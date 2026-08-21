# FlowTXT

![Java](https://img.shields.io/badge/Java-21-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Spring Boot](https://img.shields.io/badge/Spring_Boot-3.5-6DB33F?style=for-the-badge&logo=spring&logoColor=white)
![Maven](https://img.shields.io/badge/Maven-3.9+-C71A36?style=for-the-badge&logo=apache-maven&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-7-47A248?style=for-the-badge&logo=mongodb&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7-DC382D?style=for-the-badge&logo=redis&logoColor=white)
![JWT](https://img.shields.io/badge/JWT-000000?style=for-the-badge&logo=json-web-tokens&logoColor=white)
![CI](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white)

FlowTXT is an **SMS delivery backend** built with **Java 21**, **Spring Boot 3.5** and a strict
**Clean Architecture** (multi-module: domain / application / infrastructure / api). It manages
contacts, sends SMS through **Twilio** (with a fake adapter for dev/test), tracks delivery
status in **MongoDB**, uses **Redis** for caching, and secures every endpoint with **JWT**
authentication.

**Project docs:** [AGENTS.md](AGENTS.md) (rules for solo/AI-assisted development) ·
[docs/coding-standards.md](docs/coding-standards.md) (coding standards) ·
[docs/testing-playbook.md](docs/testing-playbook.md) (testing guide) ·
[docs/twelve-factor.md](docs/twelve-factor.md) (12-factor compliance) ·
[docs/lessons.md](docs/lessons.md) (engineering lessons) · [CHANGELOG.md](CHANGELOG.md).

## Table of Contents

- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Commands](#commands)
- [Authentication](#authentication)
- [API & Documentation](#api--documentation)
- [Testing](#testing)
- [Security](#security)
- [Current State](#current-state)
- [Roadmap](#roadmap)

## Tech Stack

| Category | Technology |
| :--- | :--- |
| **Language & Runtime** | Java 21 (Temurin), Spring Boot 3.5.7 |
| **Build** | Maven 3.9 (with `./mvnw` wrapper), multi-module reactor |
| **Persistence** | MongoDB 7 (Spring Data) |
| **Cache** | Redis 7 (Spring Data Redis) |
| **SMS** | Twilio SDK 9 (`TwilioSmsAdapter` in `prod`, `FakeSmsAdapter` in `dev`/`test`) |
| **Auth** | Spring Security 6 + JJWT 0.12 (stateless bearer tokens) |
| **API docs** | springdoc-openapi (Swagger UI) |
| **CI / Deploy** | GitHub Actions (unit tests → quality gates → `*IT` → image with Trivy + SBOM) |
| **Testing** | JUnit 5, Mockito, Testcontainers (Mongo + Redis) |

## Architecture

Clean Architecture with a strict dependency rule that always points inward:

```
flowtxt-domain/         Entities, value objects & outbound port interfaces (Contact, Message,
│                       User, PhoneNumber, MessageStatus, Role, PasswordHasher) — zero framework
flowtxt-application/    Use-case orchestration (ports in/out) — pure Java
│                       RegisterContact, SendMessage, UpdateMessageStatus, RegisterUser, AuthenticateUser
flowtxt-infrastructure/ Adapters: Mongo repositories + mappers, Redis cache, Twilio/fake SMS,
│                       JWT (service/filter/UserDetails/hasher), SecurityConfig, UseCaseConfig
flowtxt-api/            Spring Boot app + thin REST controllers + DTOs + GlobalExceptionHandler
```

**Boundary rules:** `domain`/`application` never import `infrastructure` or frameworks; every
external concern is behind a port implemented by an adapter; controllers only call
`application/port/in` interfaces.

## Requirements

- JDK 21
- Maven 3.9+ (or use the bundled `./mvnw`)
- Docker and Docker Compose (for Mongo + Redis, and for the integration tests)

## Getting Started

### 1. Start the external services

```sh
docker compose -f docker/docker-compose.yaml up -d   # MongoDB + Redis
```

### 2. Configure environment

```sh
cp .env.example .env   # fill TWILIO_* and JWT_SECRET
```

### 3. Run the application

```sh
./mvnw spring-boot:run -pl flowtxt-api
```

The API is available at http://localhost:8080, Swagger UI at
http://localhost:8080/swagger-ui.html.

## Commands

| Purpose | Command |
| :--- | :--- |
| Run the dev server | `./mvnw spring-boot:run -pl flowtxt-api` |
| Unit tests (no Docker) | `./mvnw test` |
| Integration tests (Docker) | `./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false` |
| Coverage report / check | `./mvnw jacoco:report` / `./mvnw jacoco:check` |
| Static analysis | `./mvnw spotbugs:check` |
| Dependency check | `./mvnw dependency-check:check -DfailBuildOnAnyVulnerability=false` |
| Production build | `./mvnw clean package` → `flowtxt-api/target/flowtxt-api-1.0-SNAPSHOT.jar` |

## Authentication

All endpoints except `/auth/register` and `/auth/login` require a bearer token.

```sh
# register
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"strongpass123"}'
# → 201 {"token":"<jwt>","email":"user@example.com","role":"USER"}

# login
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"strongpass123"}'
# → 200 {"token":"<jwt>", ...}

# use the token
curl -X POST http://localhost:8080/contacts \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"name":"Maria","phoneNumber":"+5511999999999"}'
```

## API & Documentation

Interactive docs (Swagger UI): http://localhost:8080/swagger-ui.html.

| Endpoint | Method | Auth | Description |
| :--- | :--- | :--- | :--- |
| `/auth/register` | `POST` | public | Register a user, returns a JWT. |
| `/auth/login` | `POST` | public | Authenticate, returns a JWT. |
| `/contacts` | `POST` | JWT | Register a contact. |
| `/messages` | `POST` | JWT | Send an SMS to a contact. |

## Testing

Pyramid of **39 unit tests** (domain → application → infrastructure → API slice) plus
**6 integration tests** (`*IT`, Testcontainers with real MongoDB + Redis) covering repository
adapters, the cache and the end-to-end security flow. Full guidance:
[docs/testing-playbook.md](docs/testing-playbook.md).

## Security

- **JWT authentication** (see [docs/adr/0001-jwt-authentication.md](docs/adr/0001-jwt-authentication.md)) —
  stateless bearer tokens, BCrypt password hashing behind the `PasswordHasher` port.
- `SecurityConfig` is the single source of truth for route authorization; new endpoints must
  declare an explicit rule (AGENTS.md rule 7).
- Secrets (Twilio, `JWT_SECRET`) come from the environment; the `jwt.secret` in
  `application.yaml` is a dev-only placeholder that production must override.
- CI gates: SpotBugs, OWASP Dependency Check, Trivy (HIGH/CRITICAL) on the container image,
  CodeQL, Dependency Review.

## Current State

- JWT auth (register/login + protected routes), user persistence in Mongo.
- Contact + message flow with Mongo persistence and Twilio/fake SMS adapters (status model
  `MessageStatus`).
- Quality gates + full CI/CD (unit, `*IT`, image with non-root check, Trivy, SBOM) and
  governance docs (AGENTS, coding-standards, testing-playbook, lessons, twelve-factor, ADR-0001).
- 39 unit tests + 6 integration tests; Maven wrapper; Dockerfile (non-root); Redis in compose.

## Roadmap

Deliberately not implemented yet (candidate backlog — see `tasks/`):

- Twilio delivery-status webhook endpoint (`SmsService.receiveMessage` is a stub).
- Rate limiting on `/auth/login` (Redis-backed).
- `PhoneNumber` full E.164 validation in the domain value object.
- Fail-fast configuration validation at boot (12-factor factor 3).
- Raise the JaCoCo coverage target as the suite grows.
