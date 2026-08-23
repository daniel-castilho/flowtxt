# syntax=docker/dockerfile:1

# --- Build stage: compile the Spring Boot jar ---
# Base images pinned by digest (supply chain). Bump deliberately: verify the
# digest, rebuild, re-scan (Trivy runs in CI), then update this file.
FROM maven:3.9.9-eclipse-temurin-21@sha256:6847cbbf21e159f97819f18336cf6bbc24a89f9eb6439317520d93f904e9a916 AS build
WORKDIR /app
COPY pom.xml .
COPY flowtxt-domain/pom.xml flowtxt-domain/
COPY flowtxt-application/pom.xml flowtxt-application/
COPY flowtxt-infrastructure/pom.xml flowtxt-infrastructure/
COPY flowtxt-api/pom.xml flowtxt-api/
RUN mvn -q -DskipTests dependency:go-offline
COPY flowtxt-domain/src flowtxt-domain/src
COPY flowtxt-application/src flowtxt-application/src
COPY flowtxt-infrastructure/src flowtxt-infrastructure/src
COPY flowtxt-api/src flowtxt-api/src
RUN mvn clean package -DskipTests

# --- Runtime stage: minimal JRE, non-root, exec-form entrypoint ---
FROM eclipse-temurin:21-jre-jammy@sha256:9af01c30e85b5a9b15fe249a84fb6dcb19e06ee84fbf23ea2d116b0e195c2ce9
LABEL org.opencontainers.image.title="flowtxt-api" \
      org.opencontainers.image.description="FlowTXT SMS backend (Clean Architecture)" \
      org.opencontainers.image.source="https://github.com/daniel-castilho/flowtxt"

# Stable, non-root runtime user (UID/GID 10001). The app must never run as UID 0.
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app app \
    && mkdir -p /tmp && chown 10001:10001 /tmp

ARG JAR_FILE=flowtxt-api/target/flowtxt-api-*.jar
COPY --from=build /app/${JAR_FILE} /app/app.jar
RUN chown 10001:10001 /app/app.jar

USER 10001:10001
WORKDIR /app

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
