# demo-app — Spring Boot → JAR → Docker → AWS

A practice project that takes you all the way from source code to a public HTTPS endpoint on AWS.

## Endpoints

| Path | Returns |
|---|---|
| `/` | service status + list of endpoints |
| `/api/hello` | `{"message": "Hello, World!", ...}` |
| `/api/hello?name=Ravi` | greeting with your name |
| `/api/greet/Ravi` | path-variable example |
| `/api/info` | Java version, OS, container hostname |
| `/actuator/health` | health check used by AWS |

---

## Prerequisites

- JDK 21 (`java -version`)
- Maven 3.9+ (`mvn -version`) — or skip it and use `Dockerfile.multistage`
- Docker Desktop / Docker Engine (`docker --version`)
- AWS CLI v2, configured (`aws configure`, then `aws sts get-caller-identity`)

---

## Step 1 — Build the JAR

```bash
cd demo-app
mvn clean package
```

Output lands at `target/demo-app.jar` (a fat/executable JAR — it contains Tomcat and all dependencies).

Run it locally to confirm:

```bash
java -jar target/demo-app.jar
curl http://localhost:8080/api/hello
```

**What to notice:** `mvn package` produces `demo-app.jar` *and* `demo-app.jar.original`. The `.original` is the plain jar without dependencies — the Spring Boot Maven plugin repackages it into the executable one. Always ship the fat jar.

---

## Step 2 — Build the Docker image

```bash
docker build -t demo-app:1.0 .
```

Test the container:

```bash
docker run --rm -p 8080:8080 -e APP_ENV=docker demo-app:1.0
curl http://localhost:8080/api/hello
```

You should see `"environment": "docker"` — proof the env var reached the app.

> **On Apple Silicon (M1/M2/M3):** AWS Fargate and App Runner run on x86. Build for that architecture explicitly, or your container will crash-loop with an exec format error:
> ```bash
> docker buildx build --platform linux/amd64 -t demo-app:1.0 .
> ```

**Alternative:** skip Maven entirely with `docker build -f Dockerfile.multistage -t demo-app:1.0 .` — it builds the jar inside the image.

---

## Step 3 — Push to Amazon ECR

Set some variables (adjust region if you like; `ap-south-1` is Mumbai):

```bash
export AWS_REGION=ap-south-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REPO=demo-app
export ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO
```

**3a. Create the repository (once):**

```bash
aws ecr create-repository \
  --repository-name $ECR_REPO \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true
```

**3b. Log Docker in to ECR** (the token expires after 12 hours; rerun when pushes start failing with `no basic auth credentials`):

```bash
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

**3c. Tag and push:**

```bash
docker tag demo-app:1.0 $ECR_URI:1.0
docker tag demo-app:1.0 $ECR_URI:latest
docker push $ECR_URI:1.0
docker push $ECR_URI:latest
```

Confirm it landed:

```bash
aws ecr describe-images --repository-name $ECR_REPO --region $AWS_REGION
```

---

## Step 4 — Deploy and get a public endpoint

### Option A — AWS App Runner (recommended for a first run)

App Runner takes a container image and hands you a working HTTPS URL. No VPC, no load balancer, no security groups.

**Console route (easiest):**

1. AWS Console → **App Runner** → *Create service*
2. Source: **Container registry** → **Amazon ECR** → *Browse* → pick `demo-app:latest`
3. Deployment trigger: *Manual* (or *Automatic* to redeploy on every push)
4. ECR access role: choose **Create new service role** — App Runner needs permission to pull from ECR
5. Service name: `demo-app-service`
6. **Port: `8080`** ← the single most common mistake; the default is 8080 but verify it
7. Health check: *HTTP*, path `/actuator/health`
8. Environment variable: `APP_ENV` = `aws`
9. Create & deploy — takes about 3–5 minutes

**CLI route:**

```bash
# One-time: create the role that lets App Runner pull from ECR
aws iam create-role --role-name AppRunnerECRAccessRole \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"Service":"build.apprunner.amazonaws.com"},"Action":"sts:AssumeRole"}]
  }'

aws iam attach-role-policy --role-name AppRunnerECRAccessRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess

# Create the service
aws apprunner create-service \
  --service-name demo-app-service \
  --region $AWS_REGION \
  --source-configuration "{
    \"AuthenticationConfiguration\": {\"AccessRoleArn\": \"arn:aws:iam::$AWS_ACCOUNT_ID:role/AppRunnerECRAccessRole\"},
    \"AutoDeploymentsEnabled\": false,
    \"ImageRepository\": {
      \"ImageIdentifier\": \"$ECR_URI:latest\",
      \"ImageRepositoryType\": \"ECR\",
      \"ImageConfiguration\": {
        \"Port\": \"8080\",
        \"RuntimeEnvironmentVariables\": {\"APP_ENV\": \"aws\"}
      }
    }
  }" \
  --health-check-configuration "Protocol=HTTP,Path=/actuator/health,Interval=10,Timeout=5,HealthyThreshold=1,UnhealthyThreshold=5" \
  --instance-configuration "Cpu=1024,Memory=2048"
```

**Get your URL:**

```bash
aws apprunner list-services --region $AWS_REGION \
  --query "ServiceSummaryList[?ServiceName=='demo-app-service'].ServiceUrl" --output text
```

**Hit the endpoint:**

```bash
curl https://<your-id>.ap-south-1.awsapprunner.com/api/hello
curl https://<your-id>.ap-south-1.awsapprunner.com/api/hello?name=Ravi
```

### Option B — ECS Fargate + Application Load Balancer

More moving parts, closer to what production teams actually run. The shortest path is the Copilot CLI:

```bash
brew install aws/tap/copilot-cli      # or download the binary
copilot init \
  --app demo \
  --name api \
  --type "Load Balanced Web Service" \
  --dockerfile ./Dockerfile \
  --port 8080 \
  --deploy
```

Copilot creates the VPC, ECR repo, ECS cluster, task definition, ALB, and target group, then prints the ALB URL. `copilot svc delete` tears it all down.

Doing it by hand instead means: create cluster → register task definition (with `awslogs` driver, `awsvpc` network mode, port 8080) → create ALB + target group with health check `/actuator/health` → create service → open port 80 in the ALB security group and 8080 from the ALB to the task.

### Option C — EC2 (most manual, cheapest to reason about)

SSH into an instance, install Docker, `docker login` to ECR (attach an instance profile with `AmazonEC2ContainerRegistryReadOnly`), `docker pull`, `docker run -d -p 80:8080`, then open port 80 in the security group. Endpoint is the instance's public IP.

---

## Step 5 — Redeploy after a code change

```bash
mvn clean package
docker build -t demo-app:1.1 .
docker tag demo-app:1.1 $ECR_URI:1.1
docker tag demo-app:1.1 $ECR_URI:latest
docker push $ECR_URI:1.1
docker push $ECR_URI:latest

# App Runner
aws apprunner start-deployment --service-arn <your-service-arn> --region $AWS_REGION
```

---

## Step 6 — Clean up (so you aren't billed)

App Runner bills for provisioned memory even when idle, so don't leave it running.

```bash
# App Runner
aws apprunner delete-service --service-arn <your-service-arn> --region $AWS_REGION

# ECR
aws ecr delete-repository --repository-name $ECR_REPO --region $AWS_REGION --force

# Copilot
copilot app delete
```

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `exec /bin/sh: exec format error` | Image built on ARM Mac. Rebuild with `--platform linux/amd64`. |
| Service stuck "Operation in progress", then rolls back | Health check failing. Check the port is 8080 and the path is `/actuator/health`. |
| `no basic auth credentials` on push | ECR login token expired — rerun the `get-login-password` command. |
| Health check fails but container starts fine locally | Actuator not exposed. Verify `management.endpoints.web.exposure.include=health` is in `application.properties`. |
| 503 from the ALB | Task is unhealthy or the security group doesn't allow the ALB → task on 8080. |
| `COPY target/demo-app.jar` fails | You didn't run `mvn clean package`, or `<finalName>` in `pom.xml` doesn't match. |
| App Runner can't pull image | The ECR access role is missing or lacks `AWSAppRunnerServicePolicyForECRAccess`. |

## Cost note

App Runner has no free tier and charges roughly $5–8/month for the smallest config left running continuously. Delete the service when you're done practising. ECR gives 500 MB of free storage per month for the first year.
