#!/usr/bin/env bash
# Builds the jar, builds the image, and pushes it to ECR.
# Usage: ./deploy.sh [tag]        e.g.  ./deploy.sh 1.0
set -euo pipefail

TAG="${1:-latest}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
ECR_REPO="${ECR_REPO:-demo-app}"

echo "==> Resolving AWS account..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_URI="${REGISTRY}/${ECR_REPO}"
echo "    account=${AWS_ACCOUNT_ID} region=${AWS_REGION} repo=${ECR_REPO} tag=${TAG}"

echo "==> Building JAR..."
mvn clean package

echo "==> Building Docker image (linux/amd64)..."
docker buildx build --platform linux/amd64 -t "${ECR_REPO}:${TAG}" --load .

echo "==> Ensuring ECR repository exists..."
aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "${ECR_REPO}" --region "${AWS_REGION}" \
       --image-scanning-configuration scanOnPush=true >/dev/null

echo "==> Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

echo "==> Tagging and pushing..."
docker tag "${ECR_REPO}:${TAG}" "${ECR_URI}:${TAG}"
docker tag "${ECR_REPO}:${TAG}" "${ECR_URI}:latest"
docker push "${ECR_URI}:${TAG}"
docker push "${ECR_URI}:latest"

echo ""
echo "==> Done. Image pushed:"
echo "    ${ECR_URI}:${TAG}"
echo ""
echo "Next: create an App Runner service pointing at that image on port 8080,"
echo "or run: aws apprunner start-deployment --service-arn <arn> --region ${AWS_REGION}"
