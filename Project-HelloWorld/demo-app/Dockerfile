# ------------------------------------------------------------------
# Runtime-only image. Assumes you already ran: mvn clean package
# Build with:  docker build -t demo-app:1.0 .
# ------------------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine

# Run as a non-root user (AWS security scanners flag root containers)
RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring

WORKDIR /app

# target/demo-app.jar comes from <finalName>demo-app</finalName> in pom.xml
COPY --chown=spring:spring target/demo-app.jar app.jar

EXPOSE 8080

# Container-aware JVM flags so the heap respects ECS/App Runner memory limits
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
