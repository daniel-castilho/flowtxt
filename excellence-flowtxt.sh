#!/usr/bin/env bash
#
# excellence-flowtxt.sh
# =============================================================================
# Applies the FlowTXT "excellence" pack, validated end-to-end before
# packaging (39 unit tests + quality gates, BUILD SUCCESS on JDK 21):
#
#   - JWT authentication (register/login + protected routes) — ADR-0001
#   - User persistence (Mongo) + security infrastructure (JWT filter,
#     UserDetails, BCrypt hasher, real SecurityConfig)
#   - Maven wrapper, JaCoCo, SpotBugs, OWASP Dependency Check
#   - CI/CD: ci.yml (unit + gates + *IT + image with Trivy/SBOM), Dependabot,
#     CodeQL, Dependency Review
#   - Dockerfile (non-root), .dockerignore, Redis in docker-compose
#   - 39 unit tests + 6 integration tests (Testcontainers)
#   - Governance docs: AGENTS, coding-standards, testing-playbook, lessons,
#     twelve-factor, ADR-0001, CHANGELOG, README, LICENSE, tasks/, smoke script
#
# Behavior:
#   - Backs up existing files as <file>.bak.<timestamp> before replacing.
#   - Idempotent: identical files are skipped.
#   - Deletes legacy scaffolding files (Main.java in non-api modules, the
#     commented-out SecurityConfig in the api module).
#   - Runs the gates at the end (./mvnw test + jacoco + spotbugs + package).
#
# Requirements: JDK 21 (JAVA_HOME set), Maven resolved via the wrapper.
#
# Usage:
#   ./excellence-flowtxt.sh [path-to-project]     # default: current dir
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[i]${NC} $*"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

[ -f pom.xml ] || { err "pom.xml not found in $(pwd). Run inside the flowtxt project or pass its path."; exit 1; }

TS="$(date +%Y%m%d%H%M%S)"

# -----------------------------------------------------------------------------
# deploy_file <dest> — reads content from stdin; backup + skip if identical
# -----------------------------------------------------------------------------
deploy_file() {
  local dest="$1" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    echo -e "${GREEN}[skip]${NC} $dest (already up to date)"
  else
    if [ -f "$dest" ]; then
      local bak="${dest}.bak.$TS"
      cp "$dest" "$bak"
      warn "backup: $dest -> $bak"
    fi
    cp "$tmp" "$dest"
    echo -e "${GREEN}[written]${NC} $dest"
  fi
  rm -f "$tmp"
}

echo "======================================================================"
echo "  Applying FlowTXT excellence pack"
echo "  Target: $(pwd)"
echo "======================================================================"

deploy_file ".dockerignore" <<'GG_EOF'
# Version control and CI internals
.git
.github
.gitignore

# Build output and caches
target/
*.iml
.idea/
.vscode/

# Local runtime artefacts
docker/

# Secrets and environment files — never copied into an image layer
*.env
.env
.env.*
!*.env.example

# Documentation (not needed at runtime)
docs/
tasks/
README.md
CHANGELOG.md
AGENTS.md
LICENSE
dependency-check-suppressions.xml
GG_EOF

deploy_file ".env.example" <<'GG_EOF'
# Twilio SMS
TWILIO_ACCOUNT_SID=your_account_sid_here
TWILIO_AUTH_TOKEN=your_auth_token_here
TWILIO_PHONE_NUMBER=+1234567890

# JWT — generate with: openssl rand -base64 48
# (dev-only placeholder below; production MUST set a strong secret)
JWT_SECRET=change-me-dev-only-please-use-a-long-random-secret
JWT_EXPIRATION_MS=3600000
GG_EOF

deploy_file ".gitattributes" <<'GG_EOF'
/mvnw text eol=lf
*.cmd text eol=crlf
GG_EOF

deploy_file ".github/dependabot.yml" <<'GG_EOF'
version: 2
updates:
  - package-ecosystem: "maven"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "06:00"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
    commit-message:
      prefix: "build(deps)"
      include: "scope"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "06:00"
    open-pull-requests-limit: 5
    labels:
      - "ci"
    commit-message:
      prefix: "ci(deps)"
      include: "scope"
GG_EOF

deploy_file ".github/workflows/ci.yml" <<'GG_EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  security-events: write   # SARIF upload from Trivy
  packages: write          # container registry push (when enabled)

jobs:
  build:
    name: Build & Quality Gates
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - name: Unit tests
        run: ./mvnw test

      - name: JaCoCo coverage check
        if: success()
        run: ./mvnw jacoco:check

      - name: SpotBugs static analysis
        if: success()
        run: ./mvnw spotbugs:check

      - name: OWASP Dependency Check
        if: success()
        run: ./mvnw dependency-check:check -DfailBuildOnAnyVulnerability=false

      - name: Integration tests (Docker / Testcontainers)
        if: success()
        run: ./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false

      - name: Production build
        if: success()
        run: ./mvnw clean package

      - name: Upload production jar
        if: success()
        uses: actions/upload-artifact@v4
        with:
          name: flowtxt-api-jar
          path: flowtxt-api/target/flowtxt-api-*.jar

  # Build the production image and verify its supply-chain hygiene.
  image:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: |
          IMAGE="flowtxt-api:${{ github.sha }}"
          docker build -t "$IMAGE" .
          echo "IMAGE=$IMAGE" >> "$GITHUB_ENV"
          docker inspect --format='{{.Id}}' "$IMAGE" > image-digest.txt
          cat image-digest.txt

      - name: Non-root check (must fail on UID 0)
        run: |
          out="$(docker run --rm --entrypoint id "$IMAGE")"
          echo "$out"
          if echo "$out" | grep -q 'uid=0('; then
            echo "FATAL: image runs as root (UID 0)"
            exit 1
          fi
          echo "OK: image runs as non-root ($out)"

      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@0.30.0
        with:
          image-ref: ${{ env.IMAGE }}
          format: sarif
          output: trivy-results.sarif
          severity: HIGH,CRITICAL
          exit-code: '1'
          ignore-unfixed: true

      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: trivy-results.sarif

      - name: Generate SBOM
        uses: aquasecurity/trivy-action@0.30.0
        with:
          image-ref: ${{ env.IMAGE }}
          format: cyclonedx
          output: sbom.cdx.json

      - name: Upload SBOM + image digest
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: sbom
          path: |
            sbom.cdx.json
            image-digest.txt
GG_EOF

deploy_file ".github/workflows/codeql-analysis.yml" <<'GG_EOF'
name: "CodeQL"

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]
  schedule:
    - cron: '30 3 * * 1'

jobs:
  analyze:
    name: Analyze (${{ matrix.language }})
    runs-on: ubuntu-latest
    timeout-minutes: 360
    permissions:
      actions: read
      contents: read
      security-events: write

    strategy:
      fail-fast: false
      matrix:
        language: [ 'java-kotlin' ]

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}

      - name: Autobuild
        uses: github/codeql-action/autobuild@v3

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{matrix.language}}"
GG_EOF

deploy_file ".github/workflows/dependency-review.yml" <<'GG_EOF'
name: "Dependency Review"

on:
  pull_request:

permissions:
  contents: read

jobs:
  dependency-review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Dependency Review
        uses: actions/dependency-review-action@v4
GG_EOF

deploy_file ".gitignore" <<'GG_EOF'
target/
!.mvn/wrapper/maven-wrapper.jar
!**/src/main/**/target/
!**/src/test/**/target/

### IntelliJ IDEA ###
.idea/modules.xml
.idea/jarRepositories.xml
.idea/compiler.xml
.idea/libraries/
*.iws
*.iml
*.ipr

### Eclipse ###
.apt_generated
.classpath
.factorypath
.project
.settings
.springBeans
.sts4-cache

### NetBeans ###
/nbproject/private/
/nbbuild/
/dist/
/nbdist/
/.nb-gradle/
build/
!**/src/main/**/build/
!**/src/test/**/build/

### VS Code ###
.vscode/

### Mac OS ###
.DS_Store

# Ignorar arquivos/variáveis sensíveis
.env
.env.*
twilio.env
*.env
*.env.*
!.env.example.env
.env
GG_EOF

deploy_file ".mvn/wrapper/maven-wrapper.properties" <<'GG_EOF'
wrapperVersion=3.3.4
distributionType=only-script
distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip
GG_EOF

deploy_file "AGENTS.md" <<'GG_EOF'
# AGENTS.md

FlowTXT — an SMS delivery backend built with **Java 21 + Spring Boot 3.5** as a strict
**Clean Architecture** (layered, multi-module) service. The business core (`flowtxt-domain` +
`flowtxt-application`) is kept independent of `infrastructure` details: persistence (MongoDB),
cache (Redis), SMS delivery (Twilio / fake for dev) and the web layer (Spring Web controllers)
are all behind ports.

Modules: `flowtxt-domain` · `flowtxt-application` · `flowtxt-infrastructure` · `flowtxt-api`.

Sources of truth: `README.md`, `pom.xml`, `docker/docker-compose.yaml`,
`docs/coding-standards.md`, `docs/testing-playbook.md`, `docs/twelve-factor.md`. Re-read the
relevant parts before starting any task.

## Critical rules (never violate)

1. `flowtxt-domain` and `flowtxt-application` must **never import `flowtxt-infrastructure` code
   or framework adapters** — no `ca.flowtxt.infrastructure.*`, `org.springframework.*`,
   `com.twilio.*`, `io.jsonwebtoken.*`. Verify before finishing:
   `grep -rEn "^import (ca\.flowtxt\.infrastructure|org\.springframework|com\.twilio|io\.jsonwebtoken)" flowtxt-domain/src flowtxt-application/src`
   must return nothing. Known leaks are tracked in "Known technical debt" — do **not** silently
   extend them.
2. Business logic lives in `domain` (entities, value objects, rich rules) and `application`
   (use cases). `infrastructure` adapters and `api` controllers/DTOs are **thin** — no business
   rules, no repository calls from controllers. Controllers depend only on
   `application/port/in` interfaces.
3. **Zero direct Mongo / Redis / Twilio / JWT usage outside `infrastructure/`.** Every operation
   goes through a domain/application port (`ContactRepository`, `MessageRepository`,
   `UserRepository`, `SmsService`, `CacheService`, `PasswordHasher`) implemented by an adapter.
4. Passwords are hashed with **BCrypt** via the domain `PasswordHasher` port (adapter:
   `SpringSecurityPasswordHasher`). Never store plaintext, never commit secrets or `.env`-style
   files. The `jwt.secret` in `application.yaml` is a **dev-only example** — production MUST
   override it via the `JWT_SECRET` environment variable.
5. Do **not** add a new Maven dependency without explicit human approval.
6. **English only.** All identifiers, comments, Javadoc, commit messages, documentation and log
   messages must be in English. (Pre-existing Portuguese code comments are legacy — do not add
   new ones.)
7. Every new endpoint must have an explicit authorization rule in
   `flowtxt-infrastructure/.../config/SecurityConfig.java`. Auth endpoints (`/auth/**`) are
   public by design; mutating endpoints must never default to permit-all.
8. **Doc sync is part of Done.** After milestone-sized work (a new feature area, a behaviour
   change, a debt resolution) the same change set or the immediate follow-up commit MUST update:
   1. `README.md` → "Current State" / "Roadmap"
   2. `CHANGELOG.md` → an entry under the next version or `Unreleased` (Keep a Changelog)
   3. `AGENTS.md` → "Known technical debt" (add or clear)
   Do **not** claim work DONE while `README.md` or `CHANGELOG.md` still describes the previous
   state as current.
9. Keep the default test suite green: `./mvnw test` must pass before finishing. Domain tests
   never mock; application tests mock the ports only; infrastructure/API tests follow
   `docs/testing-playbook.md`. Do not weaken an existing test to make a change pass.
10. `npm`-style lockfile discipline does not apply here, but the **Maven wrapper is the
    canonical build entrypoint**: always use `./mvnw`, never a system `mvn`.

## Commands

| Purpose | Command |
| :--- | :--- |
| Run the dev server | `./mvnw spring-boot:run -pl flowtxt-api` → http://localhost:8080 |
| Run pure unit tests (no Docker needed) | `./mvnw test` |
| Run integration tests explicitly (needs Docker) | `./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false` |
| Coverage report + check | `./mvnw jacoco:report` / `./mvnw jacoco:check` |
| SpotBugs static analysis | `./mvnw spotbugs:check` |
| OWASP Dependency Check | `./mvnw dependency-check:check -DfailBuildOnAnyVulnerability=false` |
| Production build | `./mvnw clean package` |
| Start external services (Mongo + Redis) | `docker compose -f docker/docker-compose.yaml up -d` |
| Interactive API docs | http://localhost:8080/swagger-ui.html |

> Prefer the fast unit-test loop (`./mvnw test`); it needs **no Docker**. The `*IT` classes
> (Testcontainers: Mongo/Redis adapters, security flow) are skipped automatically when Docker
> is unavailable and run explicitly with the command above (or in CI).

## Architecture

```
flowtxt-* modules (Clean Architecture, dependency rule points inward):
├── flowtxt-domain/         Entities, value objects & outbound port interfaces
│                           (Contact, Message, User, PhoneNumber, MessageStatus, Role,
│                            PasswordHasher) — zero framework imports
├── flowtxt-application/    Use-case orchestration (pure Java, depends only on domain + ports)
│   ├── port/in/            Use-case interfaces (RegisterContact, SendMessage,
│   │                        UpdateMessageStatus, RegisterUser, AuthenticateUser)
│   └── port/out/           Repository/service ports (ContactRepository, MessageRepository,
│                            UserRepository, SmsService, CacheService)
├── flowtxt-infrastructure/ Adapters: Mongo repositories + mappers, Redis cache, Twilio/fake
│                           SMS, JWT security (filter, UserDetails, hasher), SecurityConfig,
│                           UseCaseConfig (composition root)
└── flowtxt-api/            Spring Boot app + REST controllers + DTOs + GlobalExceptionHandler
```

**Boundary rules:** `domain` and `application` never import `infrastructure`; `infrastructure`
implements the ports; `api` is thin composition. Controllers call `port/in` interfaces only.

## Known technical debt (resolve later; flag, don't silently fix)

- Legacy Portuguese comments in the original code (pre-English-only rule) — being translated
  incrementally.
- `PhoneNumber` validation is minimal (E.164-ish regex lives in the DTO; a domain-level value
  object validation with full E.164 is a candidate improvement).
- The Twilio status webhook endpoint (receiving delivery status) is not implemented yet —
  `SmsService.receiveMessage` is a stub.
- No rate limiting on `/auth/login` (a Redis-backed limiter is a candidate).
- JaCoCo line coverage target is a modest 0.10 today; raise it as tests expand.

## Notes

- Secrets live in `.env` / environment variables only — never committed.
- For current project status and pending work, see `README.md` ("Current State" / "Roadmap").
- Hard-won engineering rules live in `docs/lessons.md`.
- One-off AI engineering prompts live under `tasks/`.
GG_EOF

deploy_file "CHANGELOG.md" <<'GG_EOF'
# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **JWT authentication** (ADR-0001): `POST /auth/register` and `POST /auth/login` issue bearer
  tokens; every other route requires authentication. Passwords hashed with BCrypt behind the
  domain `PasswordHasher` port; `User` aggregate + `Role` enum in the domain.
- **User persistence**: `UserDocument` + `SpringDataUserRepository` +
  `MongoUserRepositoryAdapter` + `UserMapper` (MapStruct).
- **Security infrastructure**: `JwtService` (jjwt), `JwtAuthenticationFilter`,
  `UserDetailsServiceImpl`, `SpringSecurityPasswordHasher`, and a real `SecurityConfig`
  (stateless, explicit route rules). The previously excluded Security auto-configuration is
  re-enabled.
- **Quality gates**: Maven wrapper (`./mvnw`), JaCoCo (report + check), SpotBugs, OWASP
  Dependency Check with `dependency-check-suppressions.xml`, `.gitattributes`.
- **CI/CD**: `ci.yml` (unit tests → jacoco → spotbugs → dependency-check → `*IT` →
  package → image job with non-root check + Trivy SARIF + SBOM), Dependabot (maven +
  github-actions), CodeQL, Dependency Review.
- **Docker**: multi-stage `Dockerfile` (non-root UID 10001, exec-form entrypoint), `.dockerignore`,
  Redis added to `docker-compose.yaml`.
- **Tests**: domain (4), application (8), infrastructure (20), API unit (7) and integration
  `*IT` (Testcontainers Mongo + Redis: repositories, cache, end-to-end security flow).
- **Governance docs**: `AGENTS.md`, `docs/coding-standards.md`, `docs/testing-playbook.md`,
  `docs/lessons.md`, `docs/twelve-factor.md`, `docs/adr/0001-jwt-authentication.md`,
  `tasks/` backlog + AI prompt.

### Changed
- Removed the `Main.java` "Hello, World!" scaffolding from `domain`, `application` and
  `infrastructure` modules.
- `application.yaml` re-enables Spring Security; JWT configuration added
  (`jwt.secret` dev placeholder, `jwt.expiration-ms`).

### Security
- The API is no longer wide open: contacts and message endpoints now require a valid JWT.
GG_EOF

deploy_file "Dockerfile" <<'GG_EOF'
# syntax=docker/dockerfile:1

# --- Build stage: compile the Spring Boot jar ---
FROM maven:3.9.9-eclipse-temurin-21 AS build
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
FROM eclipse-temurin:21-jre-jammy
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
GG_EOF

deploy_file "LICENSE" <<'GG_EOF'
MIT License

Copyright (c) 2026 Daniel Castilho

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
GG_EOF

deploy_file "README.md" <<'GG_EOF'
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
GG_EOF

deploy_file "dependency-check-suppressions.xml" <<'GG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<suppressions xmlns="https://jeremylong.github.io/DependencyCheck/dependency-suppression.1.3.xsd">
    <!--
      Record an advisory here ONLY when it is a confirmed false positive or
      the vulnerable code path is provably unreachable in this project, and
      note the reason + intended removal date. Do not seed this file with
      entries just to keep the CI green.
    -->
</suppressions>
GG_EOF

deploy_file "docker/docker-compose.yaml" <<'GG_EOF'
version: "3.9"

services:
  mongodb:
    image: mongo:7.0
    container_name: flowtxt-mongo
    restart: always
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: rootpassword
      MONGO_INITDB_DATABASE: flowtxt
    volumes:
      - mongo_data:/data/db

  redis:
    image: redis:7-alpine
    container_name: flowtxt-redis
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  mongo_data:
  redis_data:
GG_EOF

deploy_file "docs/adr/0001-jwt-authentication.md" <<'GG_EOF'
# ADR-0001: JWT authentication for the API

- **Status:** Accepted (2026-08-21)
- **Deciders:** project owner + AI agent
- **Context:** the API was shipped with Spring Security's auto-configuration **disabled** and the
  security config commented out — any client could register contacts and send SMS (a real Twilio
  cost). The service needs an authentication mechanism.

## Decision

Adopt **stateless JWT bearer authentication**:

- `POST /auth/register` and `POST /auth/login` are public; every other route requires a valid
  `Authorization: Bearer <token>`.
- Passwords are hashed with **BCrypt** behind the domain `PasswordHasher` port.
- Tokens are issued/validated by `JwtService` (jjwt), subject = email, with `uid` and `role`
  claims, a configurable expiry (`jwt.expiration-ms`).
- The `JwtAuthenticationFilter` populates the Spring Security context; `SecurityConfig` is the
  single source of truth for route authorization.

## Why not alternatives

- **API key per header:** simpler but no user concept, no roles, weaker for a portfolio-grade
  service; chosen when the project owner requested user-based JWT (same pattern as Spotpobre).
- **OAuth2/OIDC:** overkill for this service's scope.

## Consequences

- Positive: real authentication, role-ready (`Role.USER` / `Role.ADMIN`), documented and tested
  (unit + integration).
- Negative: `JWT_SECRET` must be provisioned and rotated in production; token revocation is not
  implemented (short expiry mitigates).
GG_EOF

deploy_file "docs/coding-standards.md" <<'GG_EOF'
# Coding Standards — Java 21 / Spring Boot / Maven (FlowTXT)

Practical reference for solo and AI-assisted development. Goal: **consistency over time**, not ceremony. Living document — edit as the project evolves.

**Relationship to other docs:**

| Doc | Wins when |
| --- | --- |
| `AGENTS.md` | Project conventions, release flow, hard agent rules |
| **This file** | Day-to-day coding detail that does not fit in AGENTS |
| `docs/lessons.md` | Durable rules learned the hard way |

Where this file conflicts with `AGENTS.md`, **`AGENTS.md` wins**.

## 1. Naming

| Element | Convention | Example |
| --- | --- | --- |
| Modules / packages | lowercase, `ca.flowtxt.<layer>` | `ca.flowtxt.application.usecase` |
| Classes / types / interfaces | PascalCase | `SendMessageUseCaseImpl`, `ContactRepository` |
| Use-case implementations | `<UseCase>Impl` | `RegisterUserUseCaseImpl` |
| Adapters | `<Technology><Port>Adapter` | `MongoUserRepositoryAdapter`, `TwilioSmsAdapter` |
| Ports | `<Concept><Kind>` (Repository/Service/UseCase/Hasher) | `SmsService`, `PasswordHasher` |
| Methods / variables | camelCase | `sendMessage()`, `passwordHash` |
| Constants / enums | UPPER_SNAKE_CASE | `MIN_PASSWORD_LENGTH`, `MessageStatus.SENT` |
| Tests (unit) | `*Test.java` | `JwtServiceTest` |
| Tests (integration) | `*IT.java` | `SecurityFlowIT` |
| DTOs (records) | `<Noun>Request` / `<Noun>Response` | `RegisterUserRequest`, `AuthResponse` |

Name for **what it is or does**, not the implementation: `ContactRepository`, not `MongoDao`.

## 2. Package / folder structure (Clean Architecture, feature-agnostic)

```
flowtxt-domain/src/main/java/ca/flowtxt/domain/
├── model/              Entities + value objects (Contact, Message, User, PhoneNumber, Role)
└── (ports that are domain concepts, e.g. PasswordHasher)

flowtxt-application/src/main/java/ca/flowtxt/application/
├── port/in/            Use-case interfaces (what the app can do)
├── port/out/           Outbound ports (repositories, services)
└── usecase/            Implementations (depend on ports only)

flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/
├── persistence/        Mongo repositories (Spring Data), documents, mappers
├── cache/              Redis adapter
├── sms/                Twilio + fake adapters
├── security/           JWT service, filter, UserDetails, hasher
└── config/             SecurityConfig, UseCaseConfig (composition root)

flowtxt-api/src/main/java/ca/flowtxt/api/
├── controller/         REST controllers (thin)
├── dto/                Request/response records
└── exception/          GlobalExceptionHandler
```

**Boundary rules:**

| Layer | Framework / external imports |
| --- | --- |
| `domain/` | **None** — no Spring, Twilio, JJWT, MongoDB |
| `application/` | **None** — pure Java + domain types |
| `infrastructure/` | Full stack allowed (Spring Data, Redis, Twilio, JJWT) |
| `api/` | Spring Web, validation, security test helpers |

## 3. Java / Spring

- Java 21, records for DTOs, `var` for obvious local types.
- Spring beans wired in `infrastructure/config/*` (composition root); controllers/adapters use
  constructor injection. Prefer interfaces over concrete classes in `api` and `application`.
- Use cases are **plain classes instantiated in `UseCaseConfig`** — no Spring annotations in
  `application/`.
- Validation: Bean Validation (`@Valid` + constraints on DTO records); domain invariants live
  in the domain model (e.g. `PhoneNumber`).
- Never call repositories or external SDKs from controllers.

## 4. Formatting & tooling

- Maven multi-module; always build with `./mvnw`.
- Editor: 4-space indent (default IntelliJ), no tabs; UTF-8.
- Run before commit: `./mvnw test` (+ `spotbugs:check` for bigger changes).
- Keep modules' responsibilities clean: a new dependency belongs in the module that uses it.

## 5. Errors & logging

- Never empty `catch`. Log with context (ids, operation), not only `"error occurred"`.
- Domain/application throw `IllegalArgumentException` with a clear message; the API layer maps
  exceptions to HTTP responses via `GlobalExceptionHandler`.
- Never log passwords, tokens, or full auth payloads. The Twilio adapter masks the auth token.
- Log levels: `error` — needs attention · `warn` — handled anomaly · `info` — lifecycle ·
  `debug` — diagnostics.

## 6. Persistence (MongoDB) & cache (Redis)

- One Spring Data repository per aggregate; explicit mappers (MapStruct) between documents and
  domain models — domain models never leak persistence annotations.
- Prefer explicit repository interfaces (ports) over exposing `MongoRepository` to the
  application layer.
- Redis (`CacheService` port): always set a TTL when adding new cache entries; keys follow
  `flowtxt:<purpose>:<id>`; never store secrets.
- Integration tests use Testcontainers — never point unit tests at a shared local instance.

## 7. Testing

| Kind | Tooling | Notes |
| --- | --- | --- |
| Domain | JUnit 5 | Pure invariants, no mocks |
| Application | JUnit 5 + Mockito | Mock **ports only**; happy + rejection paths |
| Infrastructure unit | JUnit 5 + Mockito | Mappers, hasher, JWT service, cache adapter |
| Integration | JUnit 5 + Testcontainers (`*IT`) | Mongo + Redis containers, real adapters, security flow |

- Names: `method_condition_expectedResult` or descriptive `shouldXWhenY`.
- Fast loop: `./mvnw test` (no Docker). Integration: `./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false`.
- Full guidance: `docs/testing-playbook.md`.

## 8. Documentation

- Javadoc where purpose is not obvious; comment **why**, not what.
- English only for code, comments, commits, and docs.
- Durable rules: `docs/lessons.md`. Project rules: `AGENTS.md`. This file: day-to-day detail.

### Doc sync

After milestone-sized work, the same change set — or an immediate follow-up commit — MUST update
`README.md` → "Current State", `CHANGELOG.md` (Keep a Changelog), and `AGENTS.md` → "Known
technical debt". The hard rule lives in `AGENTS.md` § *Critical rules* (rule 8).

## 9. Version control

- Imperative commit subject: `Add JWT authentication to the API layer`
- Small, focused commits; do **not** push unless the human asks.
- Annotated tags only at milestones with the Definition of Done met.

## 10. Security

- Server-side validation always (Bean Validation); never trust the client alone.
- Passwords: BCrypt via the `PasswordHasher` port. Never store plaintext.
- Auth: stateless JWT (see `docs/adr/0001-jwt-authentication.md`); `SecurityConfig` is the
  single source of truth for route authorization.
- Secrets via environment variables / `.env` (never committed); `jwt.secret` must be overridden
  in production.
- Keep `SecurityConfig` explicit: every new endpoint gets an explicit rule (see `AGENTS.md`).

## Quick pre-commit checklist

- [ ] `./mvnw test` green (unit tests)
- [ ] No `domain/`/`application/` import of infrastructure/framework
- [ ] New endpoint has an explicit rule in `SecurityConfig`
- [ ] DTO validated with Bean Validation
- [ ] No secrets in the diff; no logging of passwords/tokens
- [ ] Integration test added for new adapters/security behaviour
- [ ] Doc sync updated (README Current State / CHANGELOG / AGENTS debt) when milestone-sized
- [ ] Commit message says what and why (imperative, English)

---
GG_EOF

deploy_file "docs/lessons.md" <<'GG_EOF'
# Lessons — FlowTXT

Durable engineering rules learned the hard way in this project. Each entry states the failure
mode and the rule that prevents it. Add a new entry only when a rule proves itself; keep entries
short and actionable.

---

## Always verify the repository's default branch before writing CI workflows (2026-08-21)

The `flappy-bird` repo used `main`, and workflows written with `branches: [master]` never
triggered — zero runs after a push. The same check now runs before any workflow lands here:
`git symbolic-ref --short refs/remotes/origin/HEAD`.

**Rule:** before creating/updating CI workflows, detect the default branch and match it.

---

## Maven multi-module: know where a dependency block lands (2026-08-21)

While adding Testcontainers to `flowtxt-api/pom.xml`, a naive string replace inserted the
dependencies inside `<dependencyManagement>` (the first `</dependencies>` in the file) instead
of the real `<dependencies>` block — the classes were "managed" but never on the test classpath
(`cannot find symbol: GenericContainer`). Also, `org.testcontainers` versions were not managed
by the Spring Boot BOM in this setup, so explicit `<version>` was required.

**Rule:** when editing a POM with a `<dependencyManagement>` section, insert test/runtime
dependencies into the actual `<dependencies>` block (after `</dependencyManagement>`), and give
unmanaged coordinates an explicit version.

---

## `@WebMvcTest` applies Spring Security defaults — load the real SecurityConfig (2026-08-21)

Controller slice tests initially failed with 403 (CSRF) then 401 (default auth) because
`@WebMvcTest` boots Spring Security's defaults when `spring-security` is on the classpath, and
`addFilters = false` alone did not make the endpoints reachable.

**Rule:** for controller tests of a secured app, `@Import` the real `SecurityConfig` + the JWT
filter, `@MockBean` the security collaborators (JwtService, UserDetailsService), and add
`with(csrf())` to mutating requests. The real authorization behaviour is then exercised in
slice tests too, not only in `*IT`.

---

## `-Dtest='*IT'` fails on modules without ITs — set failIfNoSpecifiedTests=false (2026-08-21)

Running the integration pattern across all modules aborted on `flowtxt-domain` with
`No tests matching pattern "*IT" were executed`.

**Rule:** use `-Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false` when the pattern applies to
a multi-module reactor.

---

## Testcontainers `disabledWithoutDocker = true` makes ITs portable (2026-08-21)

Integration tests (`*IT`) boot real Mongo + Redis containers. On machines without Docker they
are **skipped** (not failed), and in CI (which has Docker) they run for real.

**Rule:** annotate integration base classes with
`@Testcontainers(disabledWithoutDocker = true)` so the suite is CI-strict but developer-friendly.
GG_EOF

deploy_file "docs/testing-playbook.md" <<'GG_EOF'
# Testing Playbook

**Role:** Write and interpret tests for this Java 21 multi-module Clean Architecture service
(Spring Boot 3.5, MongoDB, Redis, Twilio).
**Stack constraints:** JUnit 5 + Mockito for unit tests; Testcontainers (MongoDB, Redis) for
integration tests. No other test deps without human approval.

Sources: `AGENTS.md` · `docs/coding-standards.md` · `docs/lessons.md` · colocated `*Test.java` /
`*IT.java`.

---

## Pyramid

1. **Domain unit** — pure invariants and value objects (`ContactTest`, `MessageTest`,
   `UserTest`, `PhoneNumber`). **No mocks.**
2. **Application unit** — use-case implementations with **mocked ports only**
   (`RegisterUserUseCaseImplTest`, `AuthenticateUserUseCaseImplTest`,
   `SendMessageUseCaseImplTest`); happy path + rejection paths.
3. **Infrastructure unit** — deterministic adapter behaviour that needs no Docker
   (`JwtServiceTest`, `SpringSecurityPasswordHasherTest`, `UserDetailsServiceImplTest`,
   `ContactMapperTest`, `MessageMapperTest`, `UserMapperTest`, `RedisCacheAdapterTest`,
   `FakeSmsAdapterTest`).
4. **API unit (slice)** — controllers via `@WebMvcTest` with mocked use cases + real
   `SecurityConfig` (`AuthControllerTest`), and `GlobalExceptionHandlerTest`.
5. **Integration (`*IT`, Testcontainers)** — the full application against real MongoDB + Redis
   containers: repository adapters (`MongoRepositoriesIT`), the cache adapter
   (`RedisCacheAdapterIT`) and the end-to-end security flow (`SecurityFlowIT`:
   register → login → protected endpoint with/without token). Skipped automatically when Docker
   is unavailable.

Never point tests at a shared local Mongo/Redis — always containers (or mocks).

---

## Runner & layout

```bash
./mvnw test                                    # unit tests (no Docker)
./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false   # integration (Docker)
./mvnw jacoco:report                           # coverage report


```

- Colocate: `JwtService.java` → `JwtServiceTest.java` in the same package; `*IT` classes live in
  the **api** module (they boot the full application via `AbstractIntegrationTest`).
- English test names: `registersANewUserWithHashedPasswordAndUserRole`, or
  `rejectsWrongPassword`.
- Assert with JUnit 5 assertions; Mockito for ports.

**Integration base class** (`flowtxt-api/src/test/java/ca/flowtxt/AbstractIntegrationTest.java`):

```java
@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
public abstract class AbstractIntegrationTest { /* Mongo + Redis containers + @DynamicPropertySource */ }
```

`disabledWithoutDocker = true` means the suite is skipped (not failed) on machines without
Docker, and runs in CI where Docker is present.

---

## Mandatory patterns

| Pattern | Rule |
| --- | --- |
| Domain tests | No mocks; pure functions / value objects only |
| Application tests | Mock **ports only** (repositories, hasher, sms) |
| Controller tests | Mock use cases + `JwtService`; load the **real** `SecurityConfig` via `@Import` |
| Security | Every protected route asserted (401 without token, 200 with token); auth routes public |
| Validation | Bad payloads → 400 via `GlobalExceptionHandler` |
| Mappers | Round-trip document ↔ domain covered |
| Passwords | Assert hashed, never plaintext at rest |
| JWT | Generate → validate → reject tampered/invalid tokens |
| Integration | Real containers; assert persisted + read-back behaviour |

---

## Current automated suite (map)

| Area | File(s) | Focus |
| --- | --- | --- |
| Domain | `domain/model/ContactTest`, `MessageTest`, `UserTest` | Builders, fields |
| Application | `application/usecase/RegisterUserUseCaseImplTest` | Register, duplicate email, weak password |
| | `application/usecase/AuthenticateUserUseCaseImplTest` | Valid/invalid credentials |
| | `application/usecase/SendMessageUseCaseImplTest` | Send flow |
| Infrastructure | `infrastructure/security/JwtServiceTest` | Token lifecycle, tampering |
| | `infrastructure/security/SpringSecurityPasswordHasherTest` | BCrypt hash/matches |
| | `infrastructure/security/UserDetailsServiceImplTest` | Load by email, role authority |
| | `infrastructure/persistence/mapper/*Test` | Contact/Message/User round-trips |
| | `infrastructure/cache/RedisCacheAdapterTest` | put/get/remove (mocked) |
| | `infrastructure/sms/FakeSmsAdapterTest` | Fake SID |
| API unit | `api/controller/AuthControllerTest` | register/login (201/200/400) |
| | `api/exception/GlobalExceptionHandlerTest` | 400/400/500 mapping |
| API IT | `api/AbstractIntegrationTest` | Base (containers) |
| | `api/MongoRepositoriesIT` | Contact/User/Message persistence |
| | `api/RedisCacheAdapterIT` | Real Redis put/get/remove |
| | `api/SecurityFlowIT` | E2E register→login→protected |

When you change behaviour covered above, **extend the existing file** instead of inventing a
parallel suite.

---

## Regression checklist

| Area | Must verify |
| --- | --- |
| **Auth** | Register 201 + token; duplicate email 400; weak password 400; login 200 + token; wrong password 400 |
| **Security** | `/contacts` and `/messages` without token → 401; with token → 200; `/auth/**` public |
| **Contacts** | Create → persisted → found by phone number |
| **Messages** | Create → persisted; `updateStatusBySid` flips status; found by id |
| **Users** | Create → persisted → found by email |
| **Cache** | put → get → remove (real Redis) |
| **Boundaries** | `domain/` + `application/` free of Spring/Twilio/JJWT imports (grep in AGENTS.md) |
| **Stack** | Java 21, Spring Boot 3.5.x, Mongo 7, Redis 7 — no version drift |

---

## Quality gates (CI local mirror)

```bash
./mvnw test


./mvnw dependency-check:check -DfailBuildOnAnyVulnerability=false

```

CI (`.github/workflows/ci.yml`) runs all of the above plus the `*IT` suite and the Docker image
job (non-root check, Trivy scan, SBOM). Prefer the fast unit loop locally.

---

## Reading failures

| Class | Signal | First move |
| --- | --- | --- |
| **Logic** | AssertionError, wrong status | Fix use case or expectation — read the test name first |
| **Boundary** | Forbidden import in domain/application | Restore the port boundary — do not weaken |
| **Security** | Unexpected 401/403 in controller test | Check `SecurityConfig` rules and `@Import` in the test |
| **Container** | Testcontainers cannot start | Confirm Docker is running; `*IT` are skipped otherwise |
| **MapStruct** | Mapper impl not generated | `./mvnw clean compile` (annotation processing) |
| **Flaky / env** | Port, Redis, Mongo | Re-run; fix the cause — don't skip tests |

**Priority when many fail:** compile/annotation → domain → application → infrastructure → API →
integration.

---

## Do not

- Skip, delete, or `@Disabled` tests to green the build
- Add new test frameworks without human approval
- Point tests at a shared local Mongo/Redis instance
- Assert on plaintext passwords or raw tokens in logs
- Weaken an existing test to make a change pass
- Put business rules in controller tests "because the controller failed"

---

## Done when

- [ ] Happy path + at least one rejection automated for the change
- [ ] New domain/application behaviour has a colocated `*Test`
- [ ] New adapter/security behaviour has a unit test (+ `*IT` when containers are involved)
- [ ] Failure analysis names root cause and smallest fix
- [ ] `./mvnw test` green (+ `spotbugs:check` as appropriate)
- [ ] Docs synced if milestone-sized (README Current State / CHANGELOG / AGENTS debt)

---
GG_EOF

deploy_file "docs/twelve-factor.md" <<'GG_EOF'
# Twelve-Factor App — Reference & Compliance (FlowTXT)

The project follows the [Twelve-Factor App](https://12factor.net/) methodology. Goal: a codebase
that deploys identically to any environment with no code changes, reproducible builds, and easy
horizontal scaling.

> **This is a commitment, not a suggestion.** When writing or reviewing code, check the factor
> affected by the change and keep the table below green.

## The 12 factors and how FlowTXT complies

| # | Factor | FlowTXT status | Notes |
| - | ------- | -------------- | ----- |
| 1 | Codebase | ✅ One repo, one app | Git repo `daniel-castilho/flowtxt`, `main` branch. Multi-module Maven reactor (one deployable artifact: `flowtxt-api`). |
| 2 | Dependencies | ✅ Declared & locked | `pom.xml` per module + Maven wrapper (`./mvnw`). Reproducible via `./mvnw clean package`. |
| 3 | Config | ⚠️ In progress | Environment-specific values live in env vars (`.env`, see `.env.example`): Twilio credentials and `JWT_SECRET`. **TBD:** validate all config at boot (fail-fast for missing prod values). |
| 4 | Backing services | ✅ Attached resources | MongoDB + Redis are external resources addressed by URI/env (`docker/docker-compose.yaml`). No embedded servers. |
| 5 | Build, release, run | ⚠️ Partial | Build = `./mvnw clean package`; run = `java -jar flowtxt-api/target/*.jar`. CI (`.github/workflows/ci.yml`) runs tests, quality gates and image build (non-root, Trivy, SBOM). **TBD:** explicit release tagging/rollout. |
| 6 | Processes | ✅ Stateless | JWT stateless auth; no in-memory session state across requests. Rate limiting/cache belong in Redis (not yet implemented — see AGENTS debt). |
| 7 | Port binding | ✅ Self-contained | App exposes HTTP on `server.port` (8080) via Spring Boot; no external web server injected. |
| 8 | Concurrency | ✅ Process-based | Scales by spawning processes; each is a copy of the same stateless app. |
| 9 | Disposability | ✅ Fast boot/shutdown | Spring Boot boots quickly; graceful shutdown on SIGTERM. |
| 10 | Dev/prod parity | ✅ Containers | `docker compose` (Mongo + Redis) keeps local close to prod. |
| 11 | Logs | ✅ Mostly | Output goes to stdout (Spring Boot + `console`). No app writes log files. Never log secrets (Twilio token masked). |
| 12 | Admin processes | ⚠️ Partial | One-off tasks run as separate commands (e.g. DB seeding) — **TBD:** a `scripts/` convention for release-time admin steps. |

Legend: ✅ compliant · ⚠️ partially compliant / has an open TODO.

## Hard rules to keep the list green

- Never hardcode environment-specific values (URLs, secrets, credentials) in code. Read them
  from env vars, with dev-only defaults in `.env.example`.
- Secrets live only in env vars / the deployed environment — never in git, code, or logs.
- Every build must be reproducible: `./mvnw clean package` from a clean checkout.
- Local dev must match production dependencies as closely as possible (`docker compose`).

## Open TODOs (tracked)

1. Validate all environment variables at startup (fail-fast for prod).
2. Release tagging/rollout convention (image + jar versioned per commit).
3. `scripts/` for admin/one-off operations (e.g. seed data).
GG_EOF

deploy_file "flowtxt-api/pom.xml" <<'GG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             http://maven.apache.org/xsd/maven-4.0.0.xsd">

    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>ca.flowtxt</groupId>
        <artifactId>flowtxt-parent</artifactId>
        <version>1.0-SNAPSHOT</version>
    </parent>

    <artifactId>flowtxt-api</artifactId>
    <packaging>jar</packaging>

    <properties>
        <java.version>21</java.version>
        <spring.boot.version>3.5.7</spring.boot.version>
        <springdoc.version>2.3.0</springdoc.version>
        <lombok.version>1.18.32</lombok.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-dependencies</artifactId>
                <version>${spring.boot.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
    
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>mongodb</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>testcontainers</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>

    </dependencies>
    </dependencyManagement>

    <dependencies>
        <!-- Internal module -->
        <dependency>
            <groupId>ca.flowtxt</groupId>
            <artifactId>flowtxt-infrastructure</artifactId>
            <version>${project.version}</version>
        </dependency>

        <!-- Actuator (health / probes) -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <!-- Testcontainers (integration tests) -->
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>mongodb</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>testcontainers</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>

        <!-- Spring Boot Starters -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>

        <!-- Lombok -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <version>${lombok.version}</version>
            <scope>provided</scope>
        </dependency>

        <!-- OpenAPI/Swagger Documentation -->
        <dependency>
            <groupId>org.springdoc</groupId>
            <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
            <version>${springdoc.version}</version>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-mongodb</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis</artifactId>
        </dependency>

        <!-- Tests -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
            <exclusions>
                <exclusion>
                    <groupId>org.junit.vintage</groupId>
                    <artifactId>junit-vintage-engine</artifactId>
                </exclusion>
            </exclusions>
        </dependency>
        <dependency>
            <groupId>org.springframework.security</groupId>
            <artifactId>spring-security-test</artifactId>
            <scope>test</scope>
        </dependency>

        <dependency>
            <groupId>me.paulschwarz</groupId>
            <artifactId>spring-dotenv</artifactId>
            <version>4.0.0</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <version>${spring.boot.version}</version>
                <executions>
                    <execution>
                        <goals>
                            <goal>repackage</goal>
                        </goals>
                    </execution>
                </executions>
                <configuration>
                    <excludes>
                        <exclude>
                            <groupId>org.projectlombok</groupId>
                            <artifactId>lombok</artifactId>
                        </exclude>
                    </excludes>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.11.0</version>
                <configuration>
                    <source>${java.version}</source>
                    <target>${java.version}</target>
                    <annotationProcessorPaths>
                        <path>
                            <groupId>org.projectlombok</groupId>
                            <artifactId>lombok</artifactId>
                            <version>${lombok.version}</version>
                        </path>
                    </annotationProcessorPaths>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.2.5</version>
            </plugin>
        </plugins>
    </build>
</project>
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/FlowTxtApiApplication.java" <<'GG_EOF'
package ca.flowtxt;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "ca.flowtxt")
public class FlowTxtApiApplication {
    public static void main(String[] args) {
        SpringApplication.run(FlowTxtApiApplication.class, args);
    }
}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/controller/AuthController.java" <<'GG_EOF'
package ca.flowtxt.api.controller;

import ca.flowtxt.api.dto.AuthResponse;
import ca.flowtxt.api.dto.LoginRequest;
import ca.flowtxt.api.dto.RegisterUserRequest;
import ca.flowtxt.application.port.in.AuthenticateUserUseCase;
import ca.flowtxt.application.port.in.RegisterUserUseCase;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.security.JwtService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/auth")
public class AuthController {

    private final RegisterUserUseCase registerUserUseCase;
    private final AuthenticateUserUseCase authenticateUserUseCase;
    private final JwtService jwtService;

    public AuthController(
            RegisterUserUseCase registerUserUseCase,
            AuthenticateUserUseCase authenticateUserUseCase,
            JwtService jwtService) {
        this.registerUserUseCase = registerUserUseCase;
        this.authenticateUserUseCase = authenticateUserUseCase;
        this.jwtService = jwtService;
    }

    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(@Valid @RequestBody RegisterUserRequest request) {
        User user = registerUserUseCase.register(request.email(), request.password());
        String token = jwtService.generateToken(user);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(new AuthResponse(token, user.getEmail(), user.getRole()));
    }

    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        User user = authenticateUserUseCase.authenticate(request.email(), request.password());
        String token = jwtService.generateToken(user);
        return ResponseEntity.ok(new AuthResponse(token, user.getEmail(), user.getRole()));
    }
}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/controller/ContactController.java" <<'GG_EOF'
package ca.flowtxt.api.controller;

import ca.flowtxt.api.dto.ContactRequest;
import ca.flowtxt.api.dto.ContactResponse;
import ca.flowtxt.application.port.in.RegisterContactUseCase;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/contacts")
public class ContactController {

    private final RegisterContactUseCase registerContactUseCase;

    public ContactController(RegisterContactUseCase registerContactUseCase) {
        this.registerContactUseCase = registerContactUseCase;
    }

    @PostMapping
    public ResponseEntity<ContactResponse> registerContact(@Valid @RequestBody ContactRequest request) {
        var contact = registerContactUseCase.execute(
                request.name(),
                request.phoneNumber());

        return ResponseEntity.ok(new ContactResponse(
                contact.getId().toString(),
                contact.getName(),
                contact.getPhoneNumber().getValue()
        ));
    }
}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/controller/MessageController.java" <<'GG_EOF'
package ca.flowtxt.api.controller;

import ca.flowtxt.api.dto.MessageRequest;
import ca.flowtxt.application.port.in.SendMessageUseCase;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/messages")
public class MessageController {

    private final SendMessageUseCase sendMessageUseCase;

    public MessageController(SendMessageUseCase sendMessageUseCase) {
        this.sendMessageUseCase = sendMessageUseCase;
    }

    @PostMapping
    public ResponseEntity<Void> sendMessage(@Valid @RequestBody MessageRequest request) {
        sendMessageUseCase.execute(request.from(), request.to(), request.content());
        return ResponseEntity.accepted().build();
    }
}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/dto/AuthResponse.java" <<'GG_EOF'
package ca.flowtxt.api.dto;

import ca.flowtxt.domain.model.Role;

public record AuthResponse(
        String token,
        String email,
        Role role
) {}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/dto/ContactRequest.java" <<'GG_EOF'
package ca.flowtxt.api.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record ContactRequest(
        @NotBlank(message = "Name is required")
        String name,

        @NotBlank(message = "Phone number is required")
        @Pattern(regexp = "^\\+?[1-9]\\d{1,14}$", message = "Invalid phone number format")
        String phoneNumber
) {}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/dto/ContactResponse.java" <<'GG_EOF'
package ca.flowtxt.api.dto;

import lombok.AllArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
public class ContactResponse {

    private final String id;
    private final String name;
    private final String phoneNumber;
}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/dto/LoginRequest.java" <<'GG_EOF'
package ca.flowtxt.api.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public record LoginRequest(

        @NotBlank(message = "Email is required")
        @Email(message = "Email must be a valid address")
        String email,

        @NotBlank(message = "Password is required")
        String password
) {}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/dto/MessageRequest.java" <<'GG_EOF'
package ca.flowtxt.api.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

public record MessageRequest(

        @NotBlank(message = "'from' must not be blank")
        String from,

        @NotBlank(message = "'to' must not be blank")
        String to,

        @NotBlank(message = "'content' must not be blank")
        String content

) {}

GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/dto/RegisterUserRequest.java" <<'GG_EOF'
package ca.flowtxt.api.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RegisterUserRequest(

        @NotBlank(message = "Email is required")
        @Email(message = "Email must be a valid address")
        String email,

        @NotBlank(message = "Password is required")
        @Size(min = 8, message = "Password must be at least 8 characters")
        String password
) {}
GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/dto/TwilioDeliveryStatusRequest.java" <<'GG_EOF'
package ca.flowtxt.api.dto;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class TwilioDeliveryStatusRequest {
    private String MessageSid;
    private String MessageStatus;
    private String To;
    private String From;
    private String SmsStatus;
}

GG_EOF

deploy_file "flowtxt-api/src/main/java/ca/flowtxt/api/exception/GlobalExceptionHandler.java" <<'GG_EOF'
package ca.flowtxt.api.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;

import java.util.HashMap;
import java.util.Map;

@ControllerAdvice
public class GlobalExceptionHandler {

    // DTOs Validation
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, String>> handleValidationExceptions(
            MethodArgumentNotValidException ex) {

        Map<String, String> errors = new HashMap<>();
        ex.getBindingResult().getFieldErrors().forEach(error -> {
            errors.put(error.getField(), error.getDefaultMessage());
        });

        return ResponseEntity.badRequest().body(errors);
    }

    // Business Exception
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<String> handleBusinessException(IllegalArgumentException ex) {
        return ResponseEntity.badRequest().body(ex.getMessage());
    }

    // Generic Exception
    @ExceptionHandler(Exception.class)
    public ResponseEntity<String> handleException(Exception ex) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ex.getMessage());
    }
}
GG_EOF

deploy_file "flowtxt-api/src/main/resources/application.yaml" <<'GG_EOF'
spring:
  application:
    name: flowtxt-api
  config:
    import: optional:file:.env
  profiles:
    active: dev

  data:
    mongodb:
      # Local MongoDB from docker-compose
      uri: mongodb://root:rootpassword@localhost:27017/flowtxt?authSource=admin
  redis:
    host: localhost
    port: 6379

  jackson:
    serialization:
      INDENT_OUTPUT: true

server:
  port: 8080

# JWT — the secret is a DEV-ONLY placeholder. Production MUST override it via
# the JWT_SECRET environment variable (e.g. `openssl rand -base64 48`).
jwt:
  secret: ${JWT_SECRET:change-me-dev-only-please-use-a-long-random-secret}
  expiration-ms: ${JWT_EXPIRATION_MS:3600000}

twilio:
  account-sid: ${TWILIO_ACCOUNT_SID}
  auth-token: ${TWILIO_AUTH_TOKEN}
  phone-number: ${TWILIO_PHONE_NUMBER}

logging:
  level:
    root: INFO
    ca.flowtxt: DEBUG
    org.springframework.data.mongodb.core.MongoTemplate: DEBUG
    org.springframework.data.mongodb.repository.query: DEBUG
    org.mongodb.driver.protocol.command: DEBUG

springdoc:
  api-docs:
    path: /api-docs
  swagger-ui:
    path: /swagger-ui.html

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: when_authorized
      probes:
        enabled: true
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/AbstractIntegrationTest.java" <<'GG_EOF'
package ca.flowtxt;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.MongoDBContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

/**
 * Base class for integration tests: boots the full application against real
 * MongoDB and Redis containers. Skipped automatically when Docker is not
 * available (see @Testcontainers(disabledWithoutDocker = true)).
 */
@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
public abstract class AbstractIntegrationTest {

    @Container
    static final MongoDBContainer MONGO = new MongoDBContainer("mongo:7.0");

    @Container
    static final GenericContainer<?> REDIS =
            new GenericContainer<>(DockerImageName.parse("redis:7-alpine"))
                    .withExposedPorts(6379);

    @DynamicPropertySource
    static void registerProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.data.mongodb.uri", MONGO::getReplicaSetUrl);
        registry.add("spring.redis.host", REDIS::getHost);
        registry.add("spring.redis.port", () -> REDIS.getMappedPort(6379));
        registry.add("jwt.secret",
                () -> "integration-test-secret-that-is-long-enough-for-hs256!!");
    }

    @Autowired
    protected MockMvc mockMvc;
}
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/MongoRepositoriesIT.java" <<'GG_EOF'
package ca.flowtxt;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MongoRepositoriesIT extends AbstractIntegrationTest {

    @Autowired
    private ContactRepository contactRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private MessageRepository messageRepository;

    @Test
    void persistsAndFindsAContactByPhoneNumber() {
        Contact contact = Contact.builder()
                .id(UUID.randomUUID())
                .name("Maria Silva")
                .phoneNumber(new PhoneNumber("+5511999999999"))
                .build();

        contactRepository.save(contact);

        assertTrue(contactRepository.findByPhoneNumber("+5511999999999").isPresent());
        assertEquals("Maria Silva",
                contactRepository.findByPhoneNumber("+5511999999999").get().getName());
    }

    @Test
    void persistsAndFindsAUserByEmail() {
        User user = User.builder()
                .id(UUID.randomUUID())
                .email("it-user@example.com")
                .passwordHash("$2a$10$hash")
                .role(Role.USER)
                .createdAt(Instant.now())
                .build();

        userRepository.save(user);

        assertTrue(userRepository.findByEmail("it-user@example.com").isPresent());
        assertEquals(Role.USER,
                userRepository.findByEmail("it-user@example.com").get().getRole());
    }

    @Test
    void persistsAMessageAndUpdatesItsStatusBySid() {
        Contact contact = Contact.builder()
                .id(UUID.randomUUID())
                .name("João Souza")
                .phoneNumber(new PhoneNumber("+5511888888888"))
                .build();
        contactRepository.save(contact);

        Message message = Message.builder()
                .id(UUID.randomUUID())
                .contact(contact)
                .content("Olá FlowTXT")
                .status(MessageStatus.PENDING)
                .timestamp(Instant.now())
                .sid("SM-IT-123")
                .build();
        messageRepository.save(message);

        messageRepository.updateStatusBySid("SM-IT-123", MessageStatus.SENT);

        Message reloaded = messageRepository.findById(message.getId()).orElseThrow();
        assertEquals(MessageStatus.SENT, reloaded.getStatus());
    }
}
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/RedisCacheAdapterIT.java" <<'GG_EOF'
package ca.flowtxt;

import ca.flowtxt.application.port.out.CacheService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class RedisCacheAdapterIT extends AbstractIntegrationTest {

    @Autowired
    private CacheService cacheService;

    @Test
    void putsGetsAndRemovesAValue() {
        cacheService.put("it:key", "it-value");
        assertEquals("it-value", cacheService.get("it:key"));

        cacheService.remove("it:key");
        assertNull(cacheService.get("it:key"));
    }
}
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/SecurityFlowIT.java" <<'GG_EOF'
package ca.flowtxt;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end security flow against real Mongo + Redis containers:
 * register -> login -> protected endpoint (with and without a token).
 */
class SecurityFlowIT extends AbstractIntegrationTest {

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void registerLoginAndCallProtectedEndpoint() throws Exception {
        // 1. Register — public
        mockMvc.perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"flow-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.token").isNotEmpty());

        // 2. Login — public, returns a fresh token
        String loginBody = mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"flow-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").isNotEmpty())
                .andReturn().getResponse().getContentAsString();

        String token = objectMapper.readTree(loginBody).get("token").asText();

        // 3. Protected endpoint WITHOUT a token -> 401
        mockMvc.perform(post("/contacts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Maria\",\"phoneNumber\":\"+5511999999999\"}"))
                .andExpect(status().isUnauthorized());

        // 4. Protected endpoint WITH the token -> 200
        mockMvc.perform(post("/contacts")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Maria\",\"phoneNumber\":\"+5511999999999\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Maria"));
    }

    @Test
    void rejectsLoginWithWrongPassword() throws Exception {
        mockMvc.perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"another-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isCreated());

        mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"another-user@example.com\",\"password\":\"wrong-password\"}"))
                .andExpect(status().isBadRequest());
    }
}
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/api/controller/AuthControllerTest.java" <<'GG_EOF'
package ca.flowtxt.api.controller;

import ca.flowtxt.api.exception.GlobalExceptionHandler;
import ca.flowtxt.application.port.in.AuthenticateUserUseCase;
import ca.flowtxt.application.port.in.RegisterUserUseCase;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.config.SecurityConfig;
import ca.flowtxt.infrastructure.security.JwtAuthenticationFilter;
import ca.flowtxt.infrastructure.security.JwtService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.test.web.servlet.MockMvc;

import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(AuthController.class)
@Import({GlobalExceptionHandler.class, SecurityConfig.class, JwtAuthenticationFilter.class})
class AuthControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private RegisterUserUseCase registerUserUseCase;

    @MockBean
    private AuthenticateUserUseCase authenticateUserUseCase;

    @MockBean
    private JwtService jwtService;

    @MockBean
    private UserDetailsService userDetailsService;

    @Test
    void registerReturnsCreatedWithAToken() throws Exception {
        User user = User.builder()
                .id(UUID.randomUUID())
                .email("user@example.com")
                .role(Role.USER)
                .build();
        when(registerUserUseCase.register(any(), any())).thenReturn(user);
        when(jwtService.generateToken(user)).thenReturn("jwt-token");

        mockMvc.perform(post("/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.token").value("jwt-token"))
                .andExpect(jsonPath("$.email").value("user@example.com"))
                .andExpect(jsonPath("$.role").value("USER"));
    }

    @Test
    void loginReturnsOkWithAToken() throws Exception {
        User user = User.builder()
                .id(UUID.randomUUID())
                .email("user@example.com")
                .role(Role.USER)
                .build();
        when(authenticateUserUseCase.authenticate(any(), any())).thenReturn(user);
        when(jwtService.generateToken(user)).thenReturn("jwt-token");

        mockMvc.perform(post("/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("jwt-token"));
    }

    @Test
    void registerRejectsInvalidEmail() throws Exception {
        mockMvc.perform(post("/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"not-an-email\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void loginRejectsInvalidCredentials() throws Exception {
        when(authenticateUserUseCase.authenticate(any(), any()))
                .thenThrow(new IllegalArgumentException("Invalid credentials"));

        mockMvc.perform(post("/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"user@example.com\",\"password\":\"wrong\"}"))
                .andExpect(status().isBadRequest());
    }
}
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/api/exception/GlobalExceptionHandlerTest.java" <<'GG_EOF'
package ca.flowtxt.api.exception;

import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.BindingResult;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class GlobalExceptionHandlerTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    void mapsValidationErrorsToBadRequest() {
        BindingResult bindingResult = mock(BindingResult.class);
        when(bindingResult.getFieldErrors()).thenReturn(List.of(
                new FieldError("dto", "email", "Email must be a valid address"),
                new FieldError("dto", "password", "Password is required")));
        MethodArgumentNotValidException ex =
                new MethodArgumentNotValidException(null, bindingResult);

        ResponseEntity<Map<String, String>> response =
                handler.handleValidationExceptions(ex);

        assertEquals(400, response.getStatusCode().value());
        assertEquals("Email must be a valid address", response.getBody().get("email"));
        assertEquals("Password is required", response.getBody().get("password"));
    }

    @Test
    void mapsBusinessExceptionsToBadRequest() {
        ResponseEntity<String> response =
                handler.handleBusinessException(
                        new IllegalArgumentException("Contact not found"));

        assertEquals(400, response.getStatusCode().value());
        assertEquals("Contact not found", response.getBody());
    }

    @Test
    void mapsUnexpectedExceptionsToInternalServerError() {
        ResponseEntity<String> response =
                handler.handleException(new RuntimeException("boom"));

        assertEquals(500, response.getStatusCode().value());
        assertEquals("boom", response.getBody());
    }
}
GG_EOF

deploy_file "flowtxt-application/pom.xml" <<'GG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>ca.flowtxt</groupId>
        <artifactId>flowtxt-parent</artifactId>
        <version>1.0-SNAPSHOT</version>
    </parent>

    <artifactId>flowtxt-application</artifactId>
    <packaging>jar</packaging>

    <properties>
        <java.version>21</java.version>
        <lombok.version>1.18.32</lombok.version>
        <junit.jupiter.version>5.10.2</junit.jupiter.version>
        <mockito.version>5.8.0</mockito.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>ca.flowtxt</groupId>
            <artifactId>flowtxt-domain</artifactId>
            <version>${project.version}</version>
        </dependency>

        <!-- Lombok -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <version>${lombok.version}</version>
            <scope>provided</scope>
        </dependency>

        <!-- Tests -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>${junit.jupiter.version}</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-junit-jupiter</artifactId>
            <version>${mockito.version}</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <configuration>
                    <source>${java.version}</source>
                    <target>${java.version}</target>
                    <annotationProcessorPaths>
                        <path>
                            <groupId>org.projectlombok</groupId>
                            <artifactId>lombok</artifactId>
                            <version>${lombok.version}</version>
                        </path>
                    </annotationProcessorPaths>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.2.5</version>
            </plugin>
        </plugins>
    </build>
</project>
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/in/AuthenticateUserUseCase.java" <<'GG_EOF'
package ca.flowtxt.application.port.in;

import ca.flowtxt.domain.model.User;

/**
 * Authenticates a user by email + password. Returns the authenticated user on
 * success; throws IllegalArgumentException on invalid credentials. Token
 * issuance is an infrastructure concern (JWT) and stays out of the
 * application layer.
 */
public interface AuthenticateUserUseCase {

    User authenticate(String email, String rawPassword);
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/in/RegisterContactUseCase.java" <<'GG_EOF'
package ca.flowtxt.application.port.in;

import ca.flowtxt.domain.model.Contact;

public interface RegisterContactUseCase {
    Contact execute(final String name, final String phoneNumber);
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/in/RegisterUserUseCase.java" <<'GG_EOF'
package ca.flowtxt.application.port.in;

import ca.flowtxt.domain.model.User;

/**
 * Registers a new application user. Throws IllegalArgumentException when the
 * email is already registered or the password is too weak.
 */
public interface RegisterUserUseCase {

    User register(String email, String rawPassword);
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/in/SendMessageUseCase.java" <<'GG_EOF'
package ca.flowtxt.application.port.in;

public interface SendMessageUseCase {
    void execute(final String from, final String to, final String messageText);
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/in/UpdateMessageStatusUseCase.java" <<'GG_EOF'
package ca.flowtxt.application.port.in;

import ca.flowtxt.domain.model.MessageStatus;

public interface UpdateMessageStatusUseCase {
    void updateStatus(final String messageSid, final MessageStatus status);
}

GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/out/CacheService.java" <<'GG_EOF'
package ca.flowtxt.application.port.out;

public interface CacheService {
    void put(final String key, final Object value);
    Object get(final String key);
    void remove(final String key);
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/out/ContactRepository.java" <<'GG_EOF'
package ca.flowtxt.application.port.out;

import ca.flowtxt.domain.model.Contact;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface ContactRepository {
    Optional<Contact> findById(final UUID id);
    Optional<Contact> findByPhoneNumber(final String phoneNumber);
    void save(final Contact contact);
    List<Contact> findAll();
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/out/MessageRepository.java" <<'GG_EOF'
package ca.flowtxt.application.port.out;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface MessageRepository {
    void save(final Message message);
    List<Message> findByContact(final Contact contact);
    Optional<Message> findById(final UUID id);
    void updateStatusBySid(final String messageSid, final MessageStatus status);
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/out/SmsService.java" <<'GG_EOF'
package ca.flowtxt.application.port.out;

public interface SmsService {
    String sendMessage(final String fromNumber, final String toPhoneNumber, final String content);
    void receiveMessage(final String payload);
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/port/out/UserRepository.java" <<'GG_EOF'
package ca.flowtxt.application.port.out;

import ca.flowtxt.domain.model.User;

import java.util.Optional;

public interface UserRepository {

    Optional<User> findByEmail(String email);

    void save(User user);
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/usecase/AuthenticateUserUseCaseImpl.java" <<'GG_EOF'
package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.AuthenticateUserUseCase;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.PasswordHasher;
import ca.flowtxt.domain.model.User;

public class AuthenticateUserUseCaseImpl implements AuthenticateUserUseCase {

    private final UserRepository userRepository;
    private final PasswordHasher passwordHasher;

    public AuthenticateUserUseCaseImpl(
            UserRepository userRepository,
            PasswordHasher passwordHasher) {
        this.userRepository = userRepository;
        this.passwordHasher = passwordHasher;
    }

    @Override
    public User authenticate(String email, String rawPassword) {
        String normalizedEmail = email == null ? "" : email.trim().toLowerCase();
        User user = userRepository.findByEmail(normalizedEmail)
                .orElseThrow(() -> new IllegalArgumentException("Invalid credentials"));

        if (!passwordHasher.matches(rawPassword, user.getPasswordHash())) {
            throw new IllegalArgumentException("Invalid credentials");
        }
        return user;
    }
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/usecase/RegisterContactUseCaseImpl.java" <<'GG_EOF'
package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.RegisterContactUseCase;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;

import java.util.UUID;

public class RegisterContactUseCaseImpl implements RegisterContactUseCase {

    private final ContactRepository contactRepository;

    public RegisterContactUseCaseImpl(final ContactRepository contactRepository) {
        this.contactRepository = contactRepository;
    }

    @Override
    public Contact execute(final String name, final String phoneNumber) {

        var contact = Contact.builder()
                .id(UUID.randomUUID())
                .name(name)
                .phoneNumber(new PhoneNumber(phoneNumber))
                .build();

        contactRepository.save(contact);

        return contact;
    }
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/usecase/RegisterUserUseCaseImpl.java" <<'GG_EOF'
package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.RegisterUserUseCase;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.PasswordHasher;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;

import java.time.Instant;
import java.util.UUID;

public class RegisterUserUseCaseImpl implements RegisterUserUseCase {

    private static final int MIN_PASSWORD_LENGTH = 8;

    private final UserRepository userRepository;
    private final PasswordHasher passwordHasher;

    public RegisterUserUseCaseImpl(
            UserRepository userRepository,
            PasswordHasher passwordHasher) {
        this.userRepository = userRepository;
        this.passwordHasher = passwordHasher;
    }

    @Override
    public User register(String email, String rawPassword) {
        String normalizedEmail = email == null ? "" : email.trim().toLowerCase();
        if (normalizedEmail.isBlank()) {
            throw new IllegalArgumentException("Email is required");
        }
        if (rawPassword == null || rawPassword.length() < MIN_PASSWORD_LENGTH) {
            throw new IllegalArgumentException(
                    "Password must be at least " + MIN_PASSWORD_LENGTH + " characters");
        }
        if (userRepository.findByEmail(normalizedEmail).isPresent()) {
            throw new IllegalArgumentException("Email is already registered");
        }

        User user = User.builder()
                .id(UUID.randomUUID())
                .email(normalizedEmail)
                .passwordHash(passwordHasher.hash(rawPassword))
                .role(Role.USER)
                .createdAt(Instant.now())
                .build();

        userRepository.save(user);
        return user;
    }
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/usecase/SendMessageUseCaseImpl.java" <<'GG_EOF'
package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.SendMessageUseCase;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public class SendMessageUseCaseImpl implements SendMessageUseCase {

    private final ContactRepository contactRepository;
    private final MessageRepository messageRepository;
    private final SmsService smsService;

    public SendMessageUseCaseImpl(
            final ContactRepository contactRepository,
            final MessageRepository messageRepository,
            final SmsService smsService) {
        this.contactRepository = contactRepository;
        this.messageRepository = messageRepository;
        this.smsService = smsService;
    }

    @Override
    public void execute(final String from, final String to, final String messageText) {
        Optional<Contact> contactOpt = contactRepository.findByPhoneNumber(to);

        var contact = contactOpt.orElseThrow(() -> new IllegalArgumentException("Contact not found for phone: " + to));

        Message message = Message.builder()
                .id(UUID.randomUUID())
                .contact(contact)
                .content(messageText)
                .timestamp(Instant.now())
                .status(MessageStatus.PENDING)
                .build();

        // Persist message
        messageRepository.save(message);

        // Send SMS via provider
        var sid = smsService.sendMessage(from, to, messageText);

        // Update status (PENDING -> SENT)
        message.setStatus(MessageStatus.SENT);
        message.setSid(sid);
        messageRepository.save(message);
    }
}
GG_EOF

deploy_file "flowtxt-application/src/main/java/ca/flowtxt/application/usecase/UpdateMessageStatusUseCaseImpl.java" <<'GG_EOF'
package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.MessageStatus;
import lombok.RequiredArgsConstructor;

@RequiredArgsConstructor
public class UpdateMessageStatusUseCaseImpl implements UpdateMessageStatusUseCase {

    private final MessageRepository messageRepository;

    @Override
    public void updateStatus(final String messageSid, final MessageStatus status) {
        messageRepository.updateStatusBySid(messageSid, status);
    }
}
GG_EOF

deploy_file "flowtxt-application/src/test/java/ca/flowtxt/application/usecase/AuthenticateUserUseCaseImplTest.java" <<'GG_EOF'
package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.PasswordHasher;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthenticateUserUseCaseImplTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordHasher passwordHasher;

    private AuthenticateUserUseCaseImpl useCase;

    @BeforeEach
    void setUp() {
        useCase = new AuthenticateUserUseCaseImpl(userRepository, passwordHasher);
    }

    @Test
    void authenticatesWithValidCredentials() {
        User stored = User.builder()
                .id(UUID.randomUUID())
                .email("user@example.com")
                .passwordHash("hashed-value")
                .role(Role.USER)
                .build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(stored));
        when(passwordHasher.matches("correct-password", "hashed-value")).thenReturn(true);

        User result = useCase.authenticate("User@Example.COM", "correct-password");

        assertEquals(stored, result);
    }

    @Test
    void rejectsUnknownEmail() {
        when(userRepository.findByEmail("ghost@example.com")).thenReturn(Optional.empty());

        assertThrows(IllegalArgumentException.class,
                () -> useCase.authenticate("ghost@example.com", "whatever123"));
    }

    @Test
    void rejectsWrongPassword() {
        User stored = User.builder()
                .email("user@example.com")
                .passwordHash("hashed-value")
                .build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(stored));
        when(passwordHasher.matches("wrong-password", "hashed-value")).thenReturn(false);

        assertThrows(IllegalArgumentException.class,
                () -> useCase.authenticate("user@example.com", "wrong-password"));
    }
}
GG_EOF

deploy_file "flowtxt-application/src/test/java/ca/flowtxt/application/usecase/RegisterUserUseCaseImplTest.java" <<'GG_EOF'
package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.PasswordHasher;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RegisterUserUseCaseImplTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordHasher passwordHasher;

    private RegisterUserUseCaseImpl useCase;

    @BeforeEach
    void setUp() {
        useCase = new RegisterUserUseCaseImpl(userRepository, passwordHasher);
    }

    @Test
    void registersANewUserWithHashedPasswordAndUserRole() {
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.empty());
        when(passwordHasher.hash("strongpass123")).thenReturn("hashed-value");

        User user = useCase.register("  User@Example.COM  ", "strongpass123");

        assertEquals("user@example.com", user.getEmail());
        assertEquals("hashed-value", user.getPasswordHash());
        assertEquals(Role.USER, user.getRole());
        assertNotEquals("strongpass123", user.getPasswordHash());

        verify(userRepository).save(argThat(u ->
                u.getEmail().equals("user@example.com")
                        && u.getPasswordHash().equals("hashed-value")));
    }

    @Test
    void rejectsDuplicateEmail() {
        when(userRepository.findByEmail("taken@example.com"))
                .thenReturn(Optional.of(User.builder().email("taken@example.com").build()));

        assertThrows(IllegalArgumentException.class,
                () -> useCase.register("taken@example.com", "strongpass123"));

        verify(userRepository, never()).save(any());
    }

    @Test
    void rejectsBlankEmail() {
        assertThrows(IllegalArgumentException.class,
                () -> useCase.register("   ", "strongpass123"));
    }

    @Test
    void rejectsShortPassword() {
        assertThrows(IllegalArgumentException.class,
                () -> useCase.register("user@example.com", "short"));
    }
}
GG_EOF

deploy_file "flowtxt-application/src/test/java/ca/flowtxt/application/usecase/SendMessageUseCaseImplTest.java" <<'GG_EOF'
package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SendMessageUseCaseImplTest {

    private ContactRepository contactRepository;
    private MessageRepository messageRepository;
    private SendMessageUseCaseImpl sendMessageUseCase;
    private SmsService smsService;

    @BeforeEach
    void setup() {
        contactRepository = mock(ContactRepository.class);
        messageRepository = mock(MessageRepository.class);
        smsService = mock(SmsService.class);
        sendMessageUseCase = new SendMessageUseCaseImpl(contactRepository, messageRepository, smsService);
    }

    @Test
    void shouldSendMessageToExistingContact() {
        // Arrange
        var expectedId = UUID.randomUUID();
        var expectedName = "Daniel Castilho";
        var expectedPhoneNumberFrom = "6477052644";
        var expectedPhoneNumberTo = "6477052644";
        var expectedMessage = "Hello World";
        Contact contact = Contact.builder()
                .id(expectedId)
                .name(expectedName)
                .phoneNumber(new PhoneNumber(expectedPhoneNumberFrom))
                .build();

        // Act
        when(contactRepository.findByPhoneNumber(expectedPhoneNumberTo))
                .thenReturn(Optional.of(contact));

        sendMessageUseCase.execute(expectedPhoneNumberFrom, expectedPhoneNumberTo, expectedMessage);
        verify(messageRepository, times(2)).save(any()); // PENDING + SENT
        verify(smsService).sendMessage(expectedPhoneNumberFrom, expectedPhoneNumberTo, expectedMessage);
    }
}
GG_EOF

deploy_file "flowtxt-application/src/test/resources/mockito-extensions/org.mockito.plugins.MockMaker" <<'GG_EOF'
mock-maker-inline
GG_EOF

deploy_file "flowtxt-domain/pom.xml" <<'GG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>ca.flowtxt</groupId>
        <artifactId>flowtxt-parent</artifactId>
        <version>1.0-SNAPSHOT</version>
    </parent>

    <artifactId>flowtxt-domain</artifactId>
    <packaging>jar</packaging>

    <properties>
        <java.version>21</java.version>
        <lombok.version>1.18.32</lombok.version>
        <junit.jupiter.version>5.10.2</junit.jupiter.version>
        <junit.platform.version>1.10.2</junit.platform.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- Lombok -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <version>${lombok.version}</version>
            <scope>provided</scope>
        </dependency>

        <!-- Tests -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>${junit.jupiter.version}</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <configuration>
                    <source>${java.version}</source>
                    <target>${java.version}</target>
                    <annotationProcessorPaths>
                        <path>
                            <groupId>org.projectlombok</groupId>
                            <artifactId>lombok</artifactId>
                            <version>${lombok.version}</version>
                        </path>
                    </annotationProcessorPaths>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.2.5</version>
            </plugin>
        </plugins>
    </build>
</project>
GG_EOF

deploy_file "flowtxt-domain/src/main/java/ca/flowtxt/domain/model/Contact.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Contact {

    private UUID id;
    private String name;
    private PhoneNumber phoneNumber;
}
GG_EOF

deploy_file "flowtxt-domain/src/main/java/ca/flowtxt/domain/model/Message.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Message {

    private UUID id;
    private Contact contact;
    private String content;
    private MessageStatus status;
    private Instant timestamp;
    private String sid;
}
GG_EOF

deploy_file "flowtxt-domain/src/main/java/ca/flowtxt/domain/model/MessageStatus.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

public enum MessageStatus {
    PENDING,
    QUEUED,
    SENT,
    DELIVERED,
    UNDELIVERED,
    FAILED,
    RECEIVED, // opcional, se quiser rastrear mensagens recebidas
    UNKNOWN   // fallback seguro
}
GG_EOF

deploy_file "flowtxt-domain/src/main/java/ca/flowtxt/domain/model/PasswordHasher.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

/**
 * Outbound port for password hashing. Lives in the domain so the application
 * layer never depends on a concrete hashing library; the adapter (e.g. Spring
 * Security's BCrypt) is wired in infrastructure.
 */
public interface PasswordHasher {

    String hash(String rawPassword);

    boolean matches(String rawPassword, String hashedPassword);
}
GG_EOF

deploy_file "flowtxt-domain/src/main/java/ca/flowtxt/domain/model/PhoneNumber.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

import lombok.Value;

@Value
public class PhoneNumber {
    String value;

    public PhoneNumber(String value) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Phone number cannot be null or blank");
        }
        // TODO: Add phone number validation by regex
        this.value = value;
    }
}
GG_EOF

deploy_file "flowtxt-domain/src/main/java/ca/flowtxt/domain/model/Role.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

/**
 * Application roles. Kept minimal: a plain USER can manage contacts and send
 * messages; ADMIN is reserved for future administrative endpoints.
 */
public enum Role {
    USER,
    ADMIN
}
GG_EOF

deploy_file "flowtxt-domain/src/main/java/ca/flowtxt/domain/model/User.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

/**
 * Registered application user. The password is stored ONLY as a hash produced
 * by the PasswordHasher port — never as plaintext.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class User {

    private UUID id;
    private String email;
    private String passwordHash;
    private Role role;
    private Instant createdAt;
}
GG_EOF

deploy_file "flowtxt-domain/src/test/java/ca/flowtxt/domain/model/ContactTest.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ContactTest {

    @Test
    void shouldCreateContactWithValidPhoneNumber() {
        // Arrange
        var expectedId = UUID.randomUUID();
        var expectedName = "Daniel Castilho";
        var expectedPhoneNumber = "6477052644";
        Contact contact = Contact.builder()
                .id(expectedId)
                .name(expectedName)
                .phoneNumber(new PhoneNumber(expectedPhoneNumber))
                .build();

        // Act & Assert
        assertNotNull(contact);
        assertEquals(expectedId, contact.getId());
        assertEquals(expectedName, contact.getName());
        assertEquals(expectedPhoneNumber, contact.getPhoneNumber().getValue());
    }

    @Test
    void shouldThrowExceptionForEmptyPhoneNumber() {
        // Arrange
        var expectedPhoneNumber = "";
        var expectedErrorMessage = "Phone number cannot be null or blank";

        // Act & Assert
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber(expectedPhoneNumber), expectedErrorMessage);
    }

}
GG_EOF

deploy_file "flowtxt-domain/src/test/java/ca/flowtxt/domain/model/MessageTest.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class MessageTest {

    @Test
    void shouldCreateMessageWithValidContact() {
        // Arrange
        var expectedId = UUID.randomUUID();
        var expectedContact = Contact.builder()
                .id(expectedId)
                .name("Daniel Castilho")
                .phoneNumber(new PhoneNumber("6477052644"))
                .build();
        var expectedContent = "Hello, how are you?";
        var expectedSentAt = Instant.now();
        Message message = Message.builder()
                .id(expectedId)
                .contact(expectedContact)
                .content(expectedContent)
                .timestamp(expectedSentAt)
                .build();

        // Act & Assert
        assertNotNull(message);
        assertEquals(expectedId, message.getId());
        assertEquals(expectedContact, message.getContact());
        assertEquals(expectedContent, message.getContent());
        assertEquals(expectedSentAt, message.getTimestamp());
    }
}
GG_EOF

deploy_file "flowtxt-domain/src/test/java/ca/flowtxt/domain/model/UserTest.java" <<'GG_EOF'
package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class UserTest {

    @Test
    void buildsAUserWithAllFields() {
        UUID id = UUID.randomUUID();
        Instant now = Instant.now();

        User user = User.builder()
                .id(id)
                .email("user@example.com")
                .passwordHash("$2a$10$abcdefghijklmnopqrstuv")
                .role(Role.USER)
                .createdAt(now)
                .build();

        assertNotNull(user);
        assertEquals(id, user.getId());
        assertEquals("user@example.com", user.getEmail());
        assertEquals("$2a$10$abcdefghijklmnopqrstuv", user.getPasswordHash());
        assertEquals(Role.USER, user.getRole());
        assertEquals(now, user.getCreatedAt());
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/pom.xml" <<'GG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>ca.flowtxt</groupId>
        <artifactId>flowtxt-parent</artifactId>
        <version>1.0-SNAPSHOT</version>
    </parent>

    <artifactId>flowtxt-infrastructure</artifactId>
    <packaging>jar</packaging>

    <properties>
        <java.version>21</java.version>
        <lombok.version>1.18.32</lombok.version>
        <junit.jupiter.version>5.10.2</junit.jupiter.version>
        <mockito.version>5.8.0</mockito.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <maven.compiler.source>${java.version}</maven.compiler.source>
        <maven.compiler.target>${java.version}</maven.compiler.target>
    </properties>

    <dependencies>
        <dependency>
            <groupId>ca.flowtxt</groupId>
            <artifactId>flowtxt-application</artifactId>
            <version>${project.version}</version>
        </dependency>

        <!-- Spring Data MongoDB (ou JPA se for SQL) -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-mongodb</artifactId>
        </dependency>

        <!-- Redis -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis</artifactId>
        </dependency>

        <!-- Twilio SDK -->
        <dependency>
            <groupId>com.twilio.sdk</groupId>
            <artifactId>twilio</artifactId>
            <version>9.13.0</version>
        </dependency>

        <!-- Lombok -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <version>${lombok.version}</version>
            <scope>provided</scope>
            <optional>true</optional>
        </dependency>

        <!-- MapStruct -->
        <dependency>
            <groupId>org.mapstruct</groupId>
            <artifactId>mapstruct</artifactId>
            <version>1.5.5.Final</version>
        </dependency>

        <!-- Spring Security (JWT filter + UserDetails) -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>

        <!-- JJWT — JWT creation/validation -->
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-api</artifactId>
            <version>0.12.6</version>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-impl</artifactId>
            <version>0.12.6</version>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-jackson</artifactId>
            <version>0.12.6</version>
            <scope>runtime</scope>
        </dependency>


        <!-- Spring Web + Servlet API (security filter needs them; the API
             module provides the web runtime via spring-boot-starter-web) -->
        <dependency>
            <groupId>org.springframework</groupId>
            <artifactId>spring-web</artifactId>
        </dependency>
        <dependency>
            <groupId>jakarta.servlet</groupId>
            <artifactId>jakarta.servlet-api</artifactId>
            <scope>provided</scope>
        </dependency>


        <!-- Tests -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.2</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-junit-jupiter</artifactId>
            <version>5.8.0</version>
            <scope>test</scope>
        </dependency>


        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>

    </dependencies>

    <build>
        <plugins>
            <!-- Annotation Processor -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.11.0</version>
                <configuration>
                    <source>${java.version}</source>
                    <target>${java.version}</target>
                    <annotationProcessorPaths>
                        <path>
                            <groupId>org.projectlombok</groupId>
                            <artifactId>lombok</artifactId>
                            <version>${lombok.version}</version>
                        </path>
                        <path>
                            <groupId>org.mapstruct</groupId>
                            <artifactId>mapstruct-processor</artifactId>
                            <version>1.5.5.Final</version>
                        </path>
                    </annotationProcessorPaths>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/cache/RedisCacheAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.cache;

import ca.flowtxt.application.port.out.CacheService;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

@Component
public class RedisCacheAdapter implements CacheService {

    private final RedisTemplate<String, Object> redisTemplate;

    public RedisCacheAdapter(RedisTemplate<String, Object> redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    @Override
    public void put(final String key, final Object value) {
        redisTemplate.opsForValue().set(key, value);
    }

    @Override
    public Object get(final String key) {
        return redisTemplate.opsForValue().get(key);
    }

    @Override
    public void remove(final String key) {
        redisTemplate.delete(key);
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/config/InfrastructureConfig.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.config;

import ca.flowtxt.application.port.out.CacheService;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.infrastructure.cache.RedisCacheAdapter;
import ca.flowtxt.infrastructure.persistence.MongoContactRepositoryAdapter;
import ca.flowtxt.infrastructure.persistence.MongoMessageRepositoryAdapter;
import ca.flowtxt.infrastructure.persistence.SpringDataContactRepository;
import ca.flowtxt.infrastructure.persistence.SpringDataMessageRepository;
import ca.flowtxt.infrastructure.persistence.mapper.ContactMapper;
import ca.flowtxt.infrastructure.persistence.mapper.MessageMapper;
import ca.flowtxt.infrastructure.sms.TwilioSmsAdapter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.GenericJackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.StringRedisSerializer;

@Configuration
public class InfrastructureConfig {

    // Redis Configuration
    @Bean
    public RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory connectionFactory) {
        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(connectionFactory);
        
        // Configure serializers
        template.setKeySerializer(new StringRedisSerializer());
        template.setValueSerializer(new GenericJackson2JsonRedisSerializer());
        template.setHashKeySerializer(new StringRedisSerializer());
        template.setHashValueSerializer(new GenericJackson2JsonRedisSerializer());
        
        template.afterPropertiesSet();
        return template;
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/config/SecurityConfig.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.config;

import ca.flowtxt.infrastructure.security.JwtAuthenticationFilter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Stateless JWT security: auth endpoints and the API docs are public; every
 * other route requires a valid bearer token. The default Spring Security
 * auto-configuration is re-enabled (it was previously excluded in
 * application.yaml).
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;

    public SecurityConfig(JwtAuthenticationFilter jwtAuthenticationFilter) {
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/auth/register", "/auth/login").permitAll()
                        .requestMatchers(
                                "/swagger-ui.html", "/swagger-ui/**",
                                "/v3/api-docs/**", "/api-docs/**").permitAll()
                        .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
                        .anyRequest().authenticated())
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/config/SmsConfig.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.config;

import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.infrastructure.sms.FakeSmsAdapter;
import ca.flowtxt.infrastructure.sms.TwilioSmsAdapter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
public class SmsConfig {

    @Bean
    @Profile("prod")
    public SmsService twilioSmsService(
            @Value("${twilio.account-sid}") String accountSid,
            @Value("${twilio.auth-token}") String authToken,
            @Value("${twilio.phone-number}") String fromNumber) {
        return new TwilioSmsAdapter(accountSid, authToken, fromNumber);
    }

    @Bean
    @Profile({"dev", "test"})
    public SmsService fakeSmsService() {
        return new FakeSmsAdapter();
    }
}

GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/config/UseCaseConfig.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.config;

import ca.flowtxt.application.port.in.AuthenticateUserUseCase;
import ca.flowtxt.application.port.in.RegisterContactUseCase;
import ca.flowtxt.application.port.in.RegisterUserUseCase;
import ca.flowtxt.application.port.in.SendMessageUseCase;
import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.application.usecase.AuthenticateUserUseCaseImpl;
import ca.flowtxt.application.usecase.RegisterContactUseCaseImpl;
import ca.flowtxt.application.usecase.RegisterUserUseCaseImpl;
import ca.flowtxt.application.usecase.SendMessageUseCaseImpl;
import ca.flowtxt.application.usecase.UpdateMessageStatusUseCaseImpl;
import ca.flowtxt.domain.model.PasswordHasher;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class UseCaseConfig {

    @Bean
    public RegisterContactUseCase registerContactUseCase(final ContactRepository contactRepository) {
        return new RegisterContactUseCaseImpl(contactRepository);
    }

    @Bean
    public UpdateMessageStatusUseCase updateMessageStatusUseCase(final MessageRepository messageRepository) {
        return new UpdateMessageStatusUseCaseImpl(messageRepository);
    }

    @Bean
    public SendMessageUseCase sendMessageUseCase(
            final ContactRepository contactRepository,
            final MessageRepository messageRepository,
            final SmsService smsService) {
        return new SendMessageUseCaseImpl(contactRepository, messageRepository, smsService);
    }

    @Bean
    public RegisterUserUseCase registerUserUseCase(
            final UserRepository userRepository,
            final PasswordHasher passwordHasher) {
        return new RegisterUserUseCaseImpl(userRepository, passwordHasher);
    }

    @Bean
    public AuthenticateUserUseCase authenticateUserUseCase(
            final UserRepository userRepository,
            final PasswordHasher passwordHasher) {
        return new AuthenticateUserUseCaseImpl(userRepository, passwordHasher);
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoContactRepositoryAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.infrastructure.persistence.mapper.ContactMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public class MongoContactRepositoryAdapter implements ContactRepository {

    private final SpringDataContactRepository repository;
    private final ContactMapper mapper;

    public MongoContactRepositoryAdapter(
            SpringDataContactRepository repository,
            ContactMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public Optional<Contact> findById(final UUID id) {
        return repository.findById(id).map(mapper::toContact);
    }

    @Override
    public Optional<Contact> findByPhoneNumber(final String phoneNumber) {
        return repository.findByPhoneNumber(phoneNumber).map(mapper::toContact);
    }

    @Override
    public void save(final Contact contact) {
        repository.save(mapper.toDocument(contact));
    }

    @Override
    public List<Contact> findAll() {
        return repository.findAll().stream()
                .map(mapper::toContact)
                .toList();
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoMessageRepositoryAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.persistence.mapper.MessageMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public class MongoMessageRepositoryAdapter implements MessageRepository {

    private final SpringDataMessageRepository repository;
    private final MessageMapper mapper;

    public MongoMessageRepositoryAdapter(
            SpringDataMessageRepository repository,
            MessageMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public void save(final Message message) {
        repository.save(mapper.toDocument(message));
    }

    @Override
    public List<Message> findByContact(final Contact contact) {
        return repository.findByContactId(contact.getId()).stream()
                .map(mapper::toDomain)
                .toList();
    }

    @Override
    public Optional<Message> findById(final UUID id) {
        return repository.findById(id).map(mapper::toDomain);
    }

    @Override
    public void updateStatusBySid(String messageSid, MessageStatus status) {
        repository.updateStatusBySid(messageSid, status);
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoUserRepositoryAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.mapper.UserMapper;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public class MongoUserRepositoryAdapter implements UserRepository {

    private final SpringDataUserRepository repository;
    private final UserMapper mapper;

    public MongoUserRepositoryAdapter(
            SpringDataUserRepository repository,
            UserMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public Optional<User> findByEmail(String email) {
        return repository.findByEmail(email).map(mapper::toUser);
    }

    @Override
    public void save(User user) {
        repository.save(mapper.toDocument(user));
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/SpringDataContactRepository.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.document.ContactDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataContactRepository extends MongoRepository<ContactDocument, UUID> {
    Optional<ContactDocument> findByPhoneNumber(final String phoneNumber);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/SpringDataMessageRepository.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.data.mongodb.repository.Update;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface SpringDataMessageRepository extends MongoRepository<MessageDocument, UUID> {
    List<MessageDocument> findByContactId(UUID contactId);

    Optional<MessageDocument> findById(UUID id);

    @Query("{ 'sid': ?0 }")
    @Update("{ '$set': { 'status': ?1 } }")
    void updateStatusBySid(String messageSid, MessageStatus status);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/SpringDataUserRepository.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.document.UserDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataUserRepository extends MongoRepository<UserDocument, UUID> {

    Optional<UserDocument> findByEmail(String email);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/ContactDocument.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.document;


import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "contacts")
public class ContactDocument {

    @Id
    private UUID id;
    private String name;
    private String phoneNumber;
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/MessageDocument.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.document;

import ca.flowtxt.domain.model.MessageStatus;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.redis.core.index.Indexed;

import java.time.Instant;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "messages")
public class MessageDocument {

    @Id
    private UUID id;

    private UUID contactId;
    private String content;
    private MessageStatus status;
    private Instant timestamp;

    @Indexed
    private String sid;
}

GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/UserDocument.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.document;

import ca.flowtxt.domain.model.Role;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;
import java.util.UUID;

@Document(collection = "users")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UserDocument {

    @Id
    private UUID id;
    private String email;
    private String passwordHash;
    private Role role;
    private Instant createdAt;
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/mapper/ContactMapper.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.persistence.document.ContactDocument;
import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface ContactMapper {

    // Domain → Document
    ContactDocument toDocument(Contact contact);

    // Document → Domain
    Contact toContact(ContactDocument document);

    // PhoneNumber → String
    default String map(PhoneNumber phoneNumber) {
        return phoneNumber != null ? phoneNumber.getValue() : null;
    }

    // String → PhoneNumber
    default PhoneNumber map(String phoneNumber) {
        return phoneNumber != null ? new PhoneNumber(phoneNumber) : null;
    }
}

GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/mapper/MessageMapper.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

import java.util.UUID;

@Mapper(componentModel = "spring")
public interface MessageMapper {

    @Mapping(target = "contactId", source = "contact.id")
    @Mapping(target = "sid", source = "sid")
    MessageDocument toDocument(Message message);

    @Mapping(target = "contact", expression = "java(mapContact(document.getContactId()))")
    @Mapping(target = "sid", source = "sid")
    Message toDomain(MessageDocument document);

    // Helper method to map contactId to Contact (with minimal data)
    default Contact mapContact(UUID contactId) {
        return Contact.builder()
                .id(contactId)
                .build();
    }
}

GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/mapper/UserMapper.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.document.UserDocument;
import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface UserMapper {

    User toUser(UserDocument document);

    UserDocument toDocument(User user);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/security/JwtAuthenticationFilter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Reads a Bearer token from the Authorization header, validates it, and
 * populates the Spring Security context with the authenticated user.
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtService jwtService;
    private final UserDetailsService userDetailsService;

    public JwtAuthenticationFilter(
            JwtService jwtService,
            UserDetailsService userDetailsService) {
        this.jwtService = jwtService;
        this.userDetailsService = userDetailsService;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith(BEARER_PREFIX)
                && SecurityContextHolder.getContext().getAuthentication() == null) {

            String token = header.substring(BEARER_PREFIX.length());
            if (jwtService.isValid(token)) {
                String username = jwtService.extractUsername(token);
                UserDetails userDetails = userDetailsService.loadUserByUsername(username);

                UsernamePasswordAuthenticationToken authentication =
                        new UsernamePasswordAuthenticationToken(
                                userDetails, null, userDetails.getAuthorities());
                authentication.setDetails(
                        new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authentication);
            }
        }

        filterChain.doFilter(request, response);
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/security/JwtService.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.security;

import ca.flowtxt.domain.model.User;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;

/**
 * Issues and validates JWT bearer tokens (jjwt). The subject is the user's
 * email; the role and user id ride along as claims. The secret comes from
 * configuration (environment in production).
 */
@Component
public class JwtService {

    private final SecretKey key;
    private final long expirationMs;

    public JwtService(
            @Value("${jwt.secret}") String secret,
            @Value("${jwt.expiration-ms}") long expirationMs) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expirationMs = expirationMs;
    }

    public String generateToken(User user) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(user.getEmail())
                .claim("uid", user.getId().toString())
                .claim("role", user.getRole().name())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plusMillis(expirationMs)))
                .signWith(key)
                .compact();
    }

    public String extractUsername(String token) {
        return parse(token).getSubject();
    }

    public boolean isValid(String token) {
        try {
            parse(token);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private Claims parse(String token) {
        return Jwts.parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/security/SpringSecurityPasswordHasher.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.security;

import ca.flowtxt.domain.model.PasswordHasher;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * PasswordHasher adapter backed by Spring Security's BCrypt. The application
 * layer only ever sees the domain port.
 */
@Component
public class SpringSecurityPasswordHasher implements PasswordHasher {

    private final PasswordEncoder encoder = new BCryptPasswordEncoder();

    @Override
    public String hash(String rawPassword) {
        return encoder.encode(rawPassword);
    }

    @Override
    public boolean matches(String rawPassword, String hashedPassword) {
        return encoder.matches(rawPassword, hashedPassword);
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/security/UserDetailsServiceImpl.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.security;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.User;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Bridges the domain UserRepository into Spring Security's UserDetailsService.
 */
@Service
public class UserDetailsServiceImpl implements UserDetailsService {

    private final UserRepository userRepository;

    public UserDetailsServiceImpl(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public UserDetails loadUserByUsername(String email) throws UsernameNotFoundException {
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new UsernameNotFoundException("User not found: " + email));

        return new org.springframework.security.core.userdetails.User(
                user.getEmail(),
                user.getPasswordHash(),
                List.of(new SimpleGrantedAuthority("ROLE_" + user.getRole().name())));
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/sms/FakeSmsAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.sms;

import ca.flowtxt.application.port.out.SmsService;
import lombok.extern.slf4j.Slf4j;

import java.util.UUID;

@Slf4j
public class FakeSmsAdapter implements SmsService {

    @Override
    public String sendMessage(final String fromNumber, final String toPhoneNumber, final String content) {
        var fakeSid = "FAKE-" + UUID.randomUUID();
        log.info("[FAKE SMS] Simulando envio de {} para {} com conteúdo: {}", fromNumber, toPhoneNumber, content);
        log.info("[FAKE SMS] SID gerado: {}", fakeSid);
        return fakeSid;
    }


    @Override
    public void receiveMessage(final String payload) {
        log.info("[FAKE SMS] Simulando recebimento de mensagem: {}", payload);
    }
}

GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/sms/TwilioSmsAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.sms;

import ca.flowtxt.application.port.out.SmsService;
import com.twilio.Twilio;
import com.twilio.rest.api.v2010.account.Message;
import com.twilio.type.PhoneNumber;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;

@Slf4j
public class TwilioSmsAdapter implements SmsService {

    private final String accountSid;
    private final String authToken;
    private final String fromNumber;

    public TwilioSmsAdapter(
            @Value("${twilio.account-sid}") String accountSid,
            @Value("${twilio.auth-token}") String authToken,
            @Value("${twilio.phone-number}") String fromNumber) {
        this.accountSid = accountSid;
        this.authToken = authToken;
        this.fromNumber = fromNumber;

        String maskedAuthToken = authToken != null && authToken.length() > 4
                ? "****" + authToken.substring(authToken.length() - 4)
                : "****";

        log.info("Inicializando Twilio com Account SID: {}", accountSid);
        log.info("Auth Token (mascarado): {}", maskedAuthToken);
        log.info("Número de origem configurado: {}", fromNumber);

        try {
            Twilio.init(accountSid, authToken);
            log.info("Cliente Twilio inicializado com sucesso");
        } catch (Exception e) {
            log.error("Falha ao inicializar cliente Twilio: {}", e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public String sendMessage(final String fromPhoneNumber, final String toPhoneNumber, final String content) {
        log.info("Enviando SMS - De: {}, Para: {}, Conteúdo: {}", fromPhoneNumber, toPhoneNumber, content);

        try {
            log.debug("Criando mensagem Twilio...");
            Message message = Message.creator(
                    new PhoneNumber(toPhoneNumber),
                    new PhoneNumber(fromPhoneNumber),
                    content
            ).create();

            String sid = message.getSid();
            log.info("SMS enviado com sucesso. SID da mensagem: {}", sid);
            return sid;

        } catch (Exception e) {
            log.error("Falha ao enviar SMS. Detalhes:", e);
            log.error("Classe do erro: {}", e.getClass().getName());
            log.error("Mensagem do erro: {}", e.getMessage());

            if (e.getCause() != null) {
                log.error("Causa raiz: {}: {}", e.getCause().getClass().getName(), e.getCause().getMessage());
            }

            throw new RuntimeException("Falha ao enviar SMS: " + e.getMessage(), e);
        }
    }

    @Override
    public void receiveMessage(String payload) {
        throw new UnsupportedOperationException("Webhook de recebimento ainda não implementado");
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/persistence/MongoContactRepository.java" <<'GG_EOF'
package ca.flowtxt.persistence;

import ca.flowtxt.infrastructure.persistence.document.ContactDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;
import java.util.UUID;

public interface MongoContactRepository extends MongoRepository<ContactDocument, UUID> {
    Optional<ContactDocument> findByPhoneNumber(final String phoneNumber);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/cache/RedisCacheAdapterTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.cache;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RedisCacheAdapterTest {

    @Mock
    private RedisTemplate<String, Object> redisTemplate;

    @Mock
    private ValueOperations<String, Object> valueOperations;

    @Test
    void putsAValueInRedis() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        RedisCacheAdapter adapter = new RedisCacheAdapter(redisTemplate);

        adapter.put("key", "value");

        verify(valueOperations).set("key", "value");
    }

    @Test
    void getsAValueFromRedis() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get("key")).thenReturn("cached");
        RedisCacheAdapter adapter = new RedisCacheAdapter(redisTemplate);

        assertEquals("cached", adapter.get("key"));
    }

    @Test
    void removesAValueFromRedis() {
        RedisCacheAdapter adapter = new RedisCacheAdapter(redisTemplate);

        adapter.remove("key");

        verify(redisTemplate).delete(anyString());
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/persistence/mapper/ContactMapperTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.persistence.document.ContactDocument;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ContactMapperTest {

    private final ContactMapper mapper = new ContactMapperImpl();

    @Test
    void mapsContactToDocument() {
        Contact contact = Contact.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000001"))
                .name("Maria Silva")
                .phoneNumber(new PhoneNumber("+5511999999999"))
                .build();

        ContactDocument doc = mapper.toDocument(contact);

        assertEquals(contact.getId(), doc.getId());
        assertEquals("Maria Silva", doc.getName());
        assertEquals("+5511999999999", doc.getPhoneNumber());
    }

    @Test
    void mapsDocumentBackToContact() {
        ContactDocument doc = ContactDocument.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000002"))
                .name("João Souza")
                .phoneNumber("+5511888888888")
                .build();

        Contact contact = mapper.toContact(doc);

        assertEquals(doc.getId(), contact.getId());
        assertEquals("João Souza", contact.getName());
        assertEquals("+5511888888888", contact.getPhoneNumber().getValue());
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/persistence/mapper/MessageMapperTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class MessageMapperTest {

    private final MessageMapper mapper = new MessageMapperImpl();

    @Test
    void mapsMessageToDocument() {
        UUID contactId = UUID.fromString("00000000-0000-0000-0000-000000000011");
        Contact contact = Contact.builder().id(contactId).build();
        Instant now = Instant.now();

        Message message = Message.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000012"))
                .contact(contact)
                .content("Hello!")
                .status(MessageStatus.SENT)
                .timestamp(now)
                .sid("SM123")
                .build();

        MessageDocument doc = mapper.toDocument(message);

        assertEquals(message.getId(), doc.getId());
        assertEquals(contactId, doc.getContactId());
        assertEquals("Hello!", doc.getContent());
        assertEquals(MessageStatus.SENT, doc.getStatus());
        assertEquals(now, doc.getTimestamp());
        assertEquals("SM123", doc.getSid());
    }

    @Test
    void mapsDocumentBackToMessage() {
        MessageDocument doc = MessageDocument.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000013"))
                .contactId(UUID.fromString("00000000-0000-0000-0000-000000000014"))
                .content("Hi")
                .status(MessageStatus.PENDING)
                .timestamp(Instant.parse("2026-08-21T10:00:00Z"))
                .sid("SM456")
                .build();

        Message message = mapper.toDomain(doc);

        assertEquals(doc.getId(), message.getId());
        assertEquals(doc.getContactId(), message.getContact().getId());
        assertEquals("Hi", message.getContent());
        assertEquals(MessageStatus.PENDING, message.getStatus());
        assertEquals("SM456", message.getSid());
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/persistence/mapper/UserMapperTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.document.UserDocument;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class UserMapperTest {

    private final UserMapper mapper = new UserMapperImpl();

    @Test
    void mapsUserToDocument() {
        User user = User.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000021"))
                .email("user@example.com")
                .passwordHash("$2a$10$hash")
                .role(Role.USER)
                .createdAt(Instant.parse("2026-08-21T10:00:00Z"))
                .build();

        UserDocument doc = mapper.toDocument(user);

        assertEquals(user.getId(), doc.getId());
        assertEquals("user@example.com", doc.getEmail());
        assertEquals("$2a$10$hash", doc.getPasswordHash());
        assertEquals(Role.USER, doc.getRole());
    }

    @Test
    void mapsDocumentBackToUser() {
        UserDocument doc = UserDocument.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000022"))
                .email("admin@example.com")
                .passwordHash("$2a$10$hash2")
                .role(Role.ADMIN)
                .createdAt(Instant.parse("2026-08-21T11:00:00Z"))
                .build();

        User user = mapper.toUser(doc);

        assertEquals(doc.getId(), user.getId());
        assertEquals("admin@example.com", user.getEmail());
        assertEquals(Role.ADMIN, user.getRole());
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/security/JwtServiceTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.security;

import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JwtServiceTest {

    private static final String SECRET =
            "test-secret-that-is-at-least-32-characters-long-for-hs256";

    private final JwtService jwtService = new JwtService(SECRET, 3600000L);

    private User sampleUser() {
        return User.builder()
                .id(UUID.randomUUID())
                .email("user@example.com")
                .passwordHash("hash")
                .role(Role.USER)
                .build();
    }

    @Test
    void generatesATokenWithTheUserEmailAsSubject() {
        String token = jwtService.generateToken(sampleUser());

        assertNotNull(token);
        assertEquals("user@example.com", jwtService.extractUsername(token));
    }

    @Test
    void validatesItsOwnToken() {
        String token = jwtService.generateToken(sampleUser());
        assertTrue(jwtService.isValid(token));
    }

    @Test
    void rejectsAnInvalidToken() {
        assertFalse(jwtService.isValid("not-a-token"));
        assertFalse(jwtService.isValid(""));
        assertFalse(jwtService.isValid(null));
    }

    @Test
    void rejectsATamperedToken() {
        String token = jwtService.generateToken(sampleUser());
        String tampered = token.substring(0, token.length() - 4) + "XXXX";
        assertFalse(jwtService.isValid(tampered));
    }

    @Test
    void rejectsATokenSignedWithADifferentSecret() {
        JwtService other = new JwtService(
                "another-secret-that-is-also-long-enough-for-hs256-ok", 3600000L);
        String token = other.generateToken(sampleUser());
        assertFalse(jwtService.isValid(token));
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/security/SpringSecurityPasswordHasherTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SpringSecurityPasswordHasherTest {

    private final SpringSecurityPasswordHasher hasher = new SpringSecurityPasswordHasher();

    @Test
    void hashesWithoutStoringPlaintext() {
        String hash = hasher.hash("s3cret-password");
        assertNotEquals("s3cret-password", hash);
        assertTrue(hash.startsWith("$2"));
    }

    @Test
    void matchesTheOriginalPassword() {
        String hash = hasher.hash("s3cret-password");
        assertTrue(hasher.matches("s3cret-password", hash));
    }

    @Test
    void rejectsAWrongPassword() {
        String hash = hasher.hash("s3cret-password");
        assertTrue(!hasher.matches("wrong-password", hash));
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/security/UserDetailsServiceImplTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.security;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UsernameNotFoundException;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserDetailsServiceImplTest {

    @Mock
    private UserRepository userRepository;

    @Test
    void loadsAUserWithItsRoleAuthority() {
        User user = User.builder()
                .email("user@example.com")
                .passwordHash("hashed")
                .role(Role.USER)
                .build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(user));

        UserDetails details =
                new UserDetailsServiceImpl(userRepository).loadUserByUsername("user@example.com");

        assertEquals("user@example.com", details.getUsername());
        assertEquals("hashed", details.getPassword());
        assertTrue(details.getAuthorities().contains(
                new SimpleGrantedAuthority("ROLE_USER")));
    }

    @Test
    void throwsWhenTheUserDoesNotExist() {
        when(userRepository.findByEmail("ghost@example.com")).thenReturn(Optional.empty());

        assertThrows(UsernameNotFoundException.class,
                () -> new UserDetailsServiceImpl(userRepository)
                        .loadUserByUsername("ghost@example.com"));
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/sms/FakeSmsAdapterTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.sms;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class FakeSmsAdapterTest {

    private final FakeSmsAdapter adapter = new FakeSmsAdapter();

    @Test
    void sendsAMessageAndReturnsAFakeSid() {
        String sid = adapter.sendMessage(
                "+15005550000", "+5511999999999", "Olá FlowTXT");

        assertNotNull(sid);
        assertTrue(sid.startsWith("FAKE-"));
    }
}
GG_EOF

deploy_file "mvnw" <<'GG_EOF'
#!/bin/sh
# ----------------------------------------------------------------------------
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# Apache Maven Wrapper startup batch script, version 3.3.4
#
# Optional ENV vars
# -----------------
#   JAVA_HOME - location of a JDK home dir, required when download maven via java source
#   MVNW_REPOURL - repo url base for downloading maven distribution
#   MVNW_USERNAME/MVNW_PASSWORD - user and password for downloading maven
#   MVNW_VERBOSE - true: enable verbose log; debug: trace the mvnw script; others: silence the output
# ----------------------------------------------------------------------------

set -euf
[ "${MVNW_VERBOSE-}" != debug ] || set -x

# OS specific support.
native_path() { printf %s\\n "$1"; }
case "$(uname)" in
CYGWIN* | MINGW*)
  [ -z "${JAVA_HOME-}" ] || JAVA_HOME="$(cygpath --unix "$JAVA_HOME")"
  native_path() { cygpath --path --windows "$1"; }
  ;;
esac

# set JAVACMD and JAVACCMD
set_java_home() {
  # For Cygwin and MinGW, ensure paths are in Unix format before anything is touched
  if [ -n "${JAVA_HOME-}" ]; then
    if [ -x "$JAVA_HOME/jre/sh/java" ]; then
      # IBM's JDK on AIX uses strange locations for the executables
      JAVACMD="$JAVA_HOME/jre/sh/java"
      JAVACCMD="$JAVA_HOME/jre/sh/javac"
    else
      JAVACMD="$JAVA_HOME/bin/java"
      JAVACCMD="$JAVA_HOME/bin/javac"

      if [ ! -x "$JAVACMD" ] || [ ! -x "$JAVACCMD" ]; then
        echo "The JAVA_HOME environment variable is not defined correctly, so mvnw cannot run." >&2
        echo "JAVA_HOME is set to \"$JAVA_HOME\", but \"\$JAVA_HOME/bin/java\" or \"\$JAVA_HOME/bin/javac\" does not exist." >&2
        return 1
      fi
    fi
  else
    JAVACMD="$(
      'set' +e
      'unset' -f command 2>/dev/null
      'command' -v java
    )" || :
    JAVACCMD="$(
      'set' +e
      'unset' -f command 2>/dev/null
      'command' -v javac
    )" || :

    if [ ! -x "${JAVACMD-}" ] || [ ! -x "${JAVACCMD-}" ]; then
      echo "The java/javac command does not exist in PATH nor is JAVA_HOME set, so mvnw cannot run." >&2
      return 1
    fi
  fi
}

# hash string like Java String::hashCode
hash_string() {
  str="${1:-}" h=0
  while [ -n "$str" ]; do
    char="${str%"${str#?}"}"
    h=$(((h * 31 + $(LC_CTYPE=C printf %d "'$char")) % 4294967296))
    str="${str#?}"
  done
  printf %x\\n $h
}

verbose() { :; }
[ "${MVNW_VERBOSE-}" != true ] || verbose() { printf %s\\n "${1-}"; }

die() {
  printf %s\\n "$1" >&2
  exit 1
}

trim() {
  # MWRAPPER-139:
  #   Trims trailing and leading whitespace, carriage returns, tabs, and linefeeds.
  #   Needed for removing poorly interpreted newline sequences when running in more
  #   exotic environments such as mingw bash on Windows.
  printf "%s" "${1}" | tr -d '[:space:]'
}

scriptDir="$(dirname "$0")"
scriptName="$(basename "$0")"

# parse distributionUrl and optional distributionSha256Sum, requires .mvn/wrapper/maven-wrapper.properties
while IFS="=" read -r key value; do
  case "${key-}" in
  distributionUrl) distributionUrl=$(trim "${value-}") ;;
  distributionSha256Sum) distributionSha256Sum=$(trim "${value-}") ;;
  esac
done <"$scriptDir/.mvn/wrapper/maven-wrapper.properties"
[ -n "${distributionUrl-}" ] || die "cannot read distributionUrl property in $scriptDir/.mvn/wrapper/maven-wrapper.properties"

case "${distributionUrl##*/}" in
maven-mvnd-*bin.*)
  MVN_CMD=mvnd.sh _MVNW_REPO_PATTERN=/maven/mvnd/
  case "${PROCESSOR_ARCHITECTURE-}${PROCESSOR_ARCHITEW6432-}:$(uname -a)" in
  *AMD64:CYGWIN* | *AMD64:MINGW*) distributionPlatform=windows-amd64 ;;
  :Darwin*x86_64) distributionPlatform=darwin-amd64 ;;
  :Darwin*arm64) distributionPlatform=darwin-aarch64 ;;
  :Linux*x86_64*) distributionPlatform=linux-amd64 ;;
  *)
    echo "Cannot detect native platform for mvnd on $(uname)-$(uname -m), use pure java version" >&2
    distributionPlatform=linux-amd64
    ;;
  esac
  distributionUrl="${distributionUrl%-bin.*}-$distributionPlatform.zip"
  ;;
maven-mvnd-*) MVN_CMD=mvnd.sh _MVNW_REPO_PATTERN=/maven/mvnd/ ;;
*) MVN_CMD="mvn${scriptName#mvnw}" _MVNW_REPO_PATTERN=/org/apache/maven/ ;;
esac

# apply MVNW_REPOURL and calculate MAVEN_HOME
# maven home pattern: ~/.m2/wrapper/dists/{apache-maven-<version>,maven-mvnd-<version>-<platform>}/<hash>
[ -z "${MVNW_REPOURL-}" ] || distributionUrl="$MVNW_REPOURL$_MVNW_REPO_PATTERN${distributionUrl#*"$_MVNW_REPO_PATTERN"}"
distributionUrlName="${distributionUrl##*/}"
distributionUrlNameMain="${distributionUrlName%.*}"
distributionUrlNameMain="${distributionUrlNameMain%-bin}"
MAVEN_USER_HOME="${MAVEN_USER_HOME:-${HOME}/.m2}"
MAVEN_HOME="${MAVEN_USER_HOME}/wrapper/dists/${distributionUrlNameMain-}/$(hash_string "$distributionUrl")"

exec_maven() {
  unset MVNW_VERBOSE MVNW_USERNAME MVNW_PASSWORD MVNW_REPOURL || :
  exec "$MAVEN_HOME/bin/$MVN_CMD" "$@" || die "cannot exec $MAVEN_HOME/bin/$MVN_CMD"
}

if [ -d "$MAVEN_HOME" ]; then
  verbose "found existing MAVEN_HOME at $MAVEN_HOME"
  exec_maven "$@"
fi

case "${distributionUrl-}" in
*?-bin.zip | *?maven-mvnd-?*-?*.zip) ;;
*) die "distributionUrl is not valid, must match *-bin.zip or maven-mvnd-*.zip, but found '${distributionUrl-}'" ;;
esac

# prepare tmp dir
if TMP_DOWNLOAD_DIR="$(mktemp -d)" && [ -d "$TMP_DOWNLOAD_DIR" ]; then
  clean() { rm -rf -- "$TMP_DOWNLOAD_DIR"; }
  trap clean HUP INT TERM EXIT
else
  die "cannot create temp dir"
fi

mkdir -p -- "${MAVEN_HOME%/*}"

# Download and Install Apache Maven
verbose "Couldn't find MAVEN_HOME, downloading and installing it ..."
verbose "Downloading from: $distributionUrl"
verbose "Downloading to: $TMP_DOWNLOAD_DIR/$distributionUrlName"

# select .zip or .tar.gz
if ! command -v unzip >/dev/null; then
  distributionUrl="${distributionUrl%.zip}.tar.gz"
  distributionUrlName="${distributionUrl##*/}"
fi

# verbose opt
__MVNW_QUIET_WGET=--quiet __MVNW_QUIET_CURL=--silent __MVNW_QUIET_UNZIP=-q __MVNW_QUIET_TAR=''
[ "${MVNW_VERBOSE-}" != true ] || __MVNW_QUIET_WGET='' __MVNW_QUIET_CURL='' __MVNW_QUIET_UNZIP='' __MVNW_QUIET_TAR=v

# normalize http auth
case "${MVNW_PASSWORD:+has-password}" in
'') MVNW_USERNAME='' MVNW_PASSWORD='' ;;
has-password) [ -n "${MVNW_USERNAME-}" ] || MVNW_USERNAME='' MVNW_PASSWORD='' ;;
esac

if [ -z "${MVNW_USERNAME-}" ] && command -v wget >/dev/null; then
  verbose "Found wget ... using wget"
  wget ${__MVNW_QUIET_WGET:+"$__MVNW_QUIET_WGET"} "$distributionUrl" -O "$TMP_DOWNLOAD_DIR/$distributionUrlName" || die "wget: Failed to fetch $distributionUrl"
elif [ -z "${MVNW_USERNAME-}" ] && command -v curl >/dev/null; then
  verbose "Found curl ... using curl"
  curl ${__MVNW_QUIET_CURL:+"$__MVNW_QUIET_CURL"} -f -L -o "$TMP_DOWNLOAD_DIR/$distributionUrlName" "$distributionUrl" || die "curl: Failed to fetch $distributionUrl"
elif set_java_home; then
  verbose "Falling back to use Java to download"
  javaSource="$TMP_DOWNLOAD_DIR/Downloader.java"
  targetZip="$TMP_DOWNLOAD_DIR/$distributionUrlName"
  cat >"$javaSource" <<-END
	public class Downloader extends java.net.Authenticator
	{
	  protected java.net.PasswordAuthentication getPasswordAuthentication()
	  {
	    return new java.net.PasswordAuthentication( System.getenv( "MVNW_USERNAME" ), System.getenv( "MVNW_PASSWORD" ).toCharArray() );
	  }
	  public static void main( String[] args ) throws Exception
	  {
	    setDefault( new Downloader() );
	    java.nio.file.Files.copy( java.net.URI.create( args[0] ).toURL().openStream(), java.nio.file.Paths.get( args[1] ).toAbsolutePath().normalize() );
	  }
	}
	END
  # For Cygwin/MinGW, switch paths to Windows format before running javac and java
  verbose " - Compiling Downloader.java ..."
  "$(native_path "$JAVACCMD")" "$(native_path "$javaSource")" || die "Failed to compile Downloader.java"
  verbose " - Running Downloader.java ..."
  "$(native_path "$JAVACMD")" -cp "$(native_path "$TMP_DOWNLOAD_DIR")" Downloader "$distributionUrl" "$(native_path "$targetZip")"
fi

# If specified, validate the SHA-256 sum of the Maven distribution zip file
if [ -n "${distributionSha256Sum-}" ]; then
  distributionSha256Result=false
  if [ "$MVN_CMD" = mvnd.sh ]; then
    echo "Checksum validation is not supported for maven-mvnd." >&2
    echo "Please disable validation by removing 'distributionSha256Sum' from your maven-wrapper.properties." >&2
    exit 1
  elif command -v sha256sum >/dev/null; then
    if echo "$distributionSha256Sum  $TMP_DOWNLOAD_DIR/$distributionUrlName" | sha256sum -c - >/dev/null 2>&1; then
      distributionSha256Result=true
    fi
  elif command -v shasum >/dev/null; then
    if echo "$distributionSha256Sum  $TMP_DOWNLOAD_DIR/$distributionUrlName" | shasum -a 256 -c >/dev/null 2>&1; then
      distributionSha256Result=true
    fi
  else
    echo "Checksum validation was requested but neither 'sha256sum' or 'shasum' are available." >&2
    echo "Please install either command, or disable validation by removing 'distributionSha256Sum' from your maven-wrapper.properties." >&2
    exit 1
  fi
  if [ $distributionSha256Result = false ]; then
    echo "Error: Failed to validate Maven distribution SHA-256, your Maven distribution might be compromised." >&2
    echo "If you updated your Maven version, you need to update the specified distributionSha256Sum property." >&2
    exit 1
  fi
fi

# unzip and move
if command -v unzip >/dev/null; then
  unzip ${__MVNW_QUIET_UNZIP:+"$__MVNW_QUIET_UNZIP"} "$TMP_DOWNLOAD_DIR/$distributionUrlName" -d "$TMP_DOWNLOAD_DIR" || die "failed to unzip"
else
  tar xzf${__MVNW_QUIET_TAR:+"$__MVNW_QUIET_TAR"} "$TMP_DOWNLOAD_DIR/$distributionUrlName" -C "$TMP_DOWNLOAD_DIR" || die "failed to untar"
fi

# Find the actual extracted directory name (handles snapshots where filename != directory name)
actualDistributionDir=""

# First try the expected directory name (for regular distributions)
if [ -d "$TMP_DOWNLOAD_DIR/$distributionUrlNameMain" ]; then
  if [ -f "$TMP_DOWNLOAD_DIR/$distributionUrlNameMain/bin/$MVN_CMD" ]; then
    actualDistributionDir="$distributionUrlNameMain"
  fi
fi

# If not found, search for any directory with the Maven executable (for snapshots)
if [ -z "$actualDistributionDir" ]; then
  # enable globbing to iterate over items
  set +f
  for dir in "$TMP_DOWNLOAD_DIR"/*; do
    if [ -d "$dir" ]; then
      if [ -f "$dir/bin/$MVN_CMD" ]; then
        actualDistributionDir="$(basename "$dir")"
        break
      fi
    fi
  done
  set -f
fi

if [ -z "$actualDistributionDir" ]; then
  verbose "Contents of $TMP_DOWNLOAD_DIR:"
  verbose "$(ls -la "$TMP_DOWNLOAD_DIR")"
  die "Could not find Maven distribution directory in extracted archive"
fi

verbose "Found extracted Maven distribution directory: $actualDistributionDir"
printf %s\\n "$distributionUrl" >"$TMP_DOWNLOAD_DIR/$actualDistributionDir/mvnw.url"
mv -- "$TMP_DOWNLOAD_DIR/$actualDistributionDir" "$MAVEN_HOME" || [ -d "$MAVEN_HOME" ] || die "fail to move MAVEN_HOME"

clean || :
exec_maven "$@"
GG_EOF

deploy_file "mvnw.cmd" <<'GG_EOF'
<# : batch portion
@REM ----------------------------------------------------------------------------
@REM Licensed to the Apache Software Foundation (ASF) under one
@REM or more contributor license agreements.  See the NOTICE file
@REM distributed with this work for additional information
@REM regarding copyright ownership.  The ASF licenses this file
@REM to you under the Apache License, Version 2.0 (the
@REM "License"); you may not use this file except in compliance
@REM with the License.  You may obtain a copy of the License at
@REM
@REM    http://www.apache.org/licenses/LICENSE-2.0
@REM
@REM Unless required by applicable law or agreed to in writing,
@REM software distributed under the License is distributed on an
@REM "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
@REM KIND, either express or implied.  See the License for the
@REM specific language governing permissions and limitations
@REM under the License.
@REM ----------------------------------------------------------------------------

@REM ----------------------------------------------------------------------------
@REM Apache Maven Wrapper startup batch script, version 3.3.4
@REM
@REM Optional ENV vars
@REM   MVNW_REPOURL - repo url base for downloading maven distribution
@REM   MVNW_USERNAME/MVNW_PASSWORD - user and password for downloading maven
@REM   MVNW_VERBOSE - true: enable verbose log; others: silence the output
@REM ----------------------------------------------------------------------------

@IF "%__MVNW_ARG0_NAME__%"=="" (SET __MVNW_ARG0_NAME__=%~nx0)
@SET __MVNW_CMD__=
@SET __MVNW_ERROR__=
@SET __MVNW_PSMODULEP_SAVE=%PSModulePath%
@SET PSModulePath=
@FOR /F "usebackq tokens=1* delims==" %%A IN (`powershell -noprofile "& {$scriptDir='%~dp0'; $script='%__MVNW_ARG0_NAME__%'; icm -ScriptBlock ([Scriptblock]::Create((Get-Content -Raw '%~f0'))) -NoNewScope}"`) DO @(
  IF "%%A"=="MVN_CMD" (set __MVNW_CMD__=%%B) ELSE IF "%%B"=="" (echo %%A) ELSE (echo %%A=%%B)
)
@SET PSModulePath=%__MVNW_PSMODULEP_SAVE%
@SET __MVNW_PSMODULEP_SAVE=
@SET __MVNW_ARG0_NAME__=
@SET MVNW_USERNAME=
@SET MVNW_PASSWORD=
@IF NOT "%__MVNW_CMD__%"=="" ("%__MVNW_CMD__%" %*)
@echo Cannot start maven from wrapper >&2 && exit /b 1
@GOTO :EOF
: end batch / begin powershell #>

$ErrorActionPreference = "Stop"
if ($env:MVNW_VERBOSE -eq "true") {
  $VerbosePreference = "Continue"
}

# calculate distributionUrl, requires .mvn/wrapper/maven-wrapper.properties
$distributionUrl = (Get-Content -Raw "$scriptDir/.mvn/wrapper/maven-wrapper.properties" | ConvertFrom-StringData).distributionUrl
if (!$distributionUrl) {
  Write-Error "cannot read distributionUrl property in $scriptDir/.mvn/wrapper/maven-wrapper.properties"
}

switch -wildcard -casesensitive ( $($distributionUrl -replace '^.*/','') ) {
  "maven-mvnd-*" {
    $USE_MVND = $true
    $distributionUrl = $distributionUrl -replace '-bin\.[^.]*$',"-windows-amd64.zip"
    $MVN_CMD = "mvnd.cmd"
    break
  }
  default {
    $USE_MVND = $false
    $MVN_CMD = $script -replace '^mvnw','mvn'
    break
  }
}

# apply MVNW_REPOURL and calculate MAVEN_HOME
# maven home pattern: ~/.m2/wrapper/dists/{apache-maven-<version>,maven-mvnd-<version>-<platform>}/<hash>
if ($env:MVNW_REPOURL) {
  $MVNW_REPO_PATTERN = if ($USE_MVND -eq $False) { "/org/apache/maven/" } else { "/maven/mvnd/" }
  $distributionUrl = "$env:MVNW_REPOURL$MVNW_REPO_PATTERN$($distributionUrl -replace "^.*$MVNW_REPO_PATTERN",'')"
}
$distributionUrlName = $distributionUrl -replace '^.*/',''
$distributionUrlNameMain = $distributionUrlName -replace '\.[^.]*$','' -replace '-bin$',''

$MAVEN_M2_PATH = "$HOME/.m2"
if ($env:MAVEN_USER_HOME) {
  $MAVEN_M2_PATH = "$env:MAVEN_USER_HOME"
}

if (-not (Test-Path -Path $MAVEN_M2_PATH)) {
    New-Item -Path $MAVEN_M2_PATH -ItemType Directory | Out-Null
}

$MAVEN_WRAPPER_DISTS = $null
if ((Get-Item $MAVEN_M2_PATH).Target[0] -eq $null) {
  $MAVEN_WRAPPER_DISTS = "$MAVEN_M2_PATH/wrapper/dists"
} else {
  $MAVEN_WRAPPER_DISTS = (Get-Item $MAVEN_M2_PATH).Target[0] + "/wrapper/dists"
}

$MAVEN_HOME_PARENT = "$MAVEN_WRAPPER_DISTS/$distributionUrlNameMain"
$MAVEN_HOME_NAME = ([System.Security.Cryptography.SHA256]::Create().ComputeHash([byte[]][char[]]$distributionUrl) | ForEach-Object {$_.ToString("x2")}) -join ''
$MAVEN_HOME = "$MAVEN_HOME_PARENT/$MAVEN_HOME_NAME"

if (Test-Path -Path "$MAVEN_HOME" -PathType Container) {
  Write-Verbose "found existing MAVEN_HOME at $MAVEN_HOME"
  Write-Output "MVN_CMD=$MAVEN_HOME/bin/$MVN_CMD"
  exit $?
}

if (! $distributionUrlNameMain -or ($distributionUrlName -eq $distributionUrlNameMain)) {
  Write-Error "distributionUrl is not valid, must end with *-bin.zip, but found $distributionUrl"
}

# prepare tmp dir
$TMP_DOWNLOAD_DIR_HOLDER = New-TemporaryFile
$TMP_DOWNLOAD_DIR = New-Item -Itemtype Directory -Path "$TMP_DOWNLOAD_DIR_HOLDER.dir"
$TMP_DOWNLOAD_DIR_HOLDER.Delete() | Out-Null
trap {
  if ($TMP_DOWNLOAD_DIR.Exists) {
    try { Remove-Item $TMP_DOWNLOAD_DIR -Recurse -Force | Out-Null }
    catch { Write-Warning "Cannot remove $TMP_DOWNLOAD_DIR" }
  }
}

New-Item -Itemtype Directory -Path "$MAVEN_HOME_PARENT" -Force | Out-Null

# Download and Install Apache Maven
Write-Verbose "Couldn't find MAVEN_HOME, downloading and installing it ..."
Write-Verbose "Downloading from: $distributionUrl"
Write-Verbose "Downloading to: $TMP_DOWNLOAD_DIR/$distributionUrlName"

$webclient = New-Object System.Net.WebClient
if ($env:MVNW_USERNAME -and $env:MVNW_PASSWORD) {
  $webclient.Credentials = New-Object System.Net.NetworkCredential($env:MVNW_USERNAME, $env:MVNW_PASSWORD)
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$webclient.DownloadFile($distributionUrl, "$TMP_DOWNLOAD_DIR/$distributionUrlName") | Out-Null

# If specified, validate the SHA-256 sum of the Maven distribution zip file
$distributionSha256Sum = (Get-Content -Raw "$scriptDir/.mvn/wrapper/maven-wrapper.properties" | ConvertFrom-StringData).distributionSha256Sum
if ($distributionSha256Sum) {
  if ($USE_MVND) {
    Write-Error "Checksum validation is not supported for maven-mvnd. `nPlease disable validation by removing 'distributionSha256Sum' from your maven-wrapper.properties."
  }
  Import-Module $PSHOME\Modules\Microsoft.PowerShell.Utility -Function Get-FileHash
  if ((Get-FileHash "$TMP_DOWNLOAD_DIR/$distributionUrlName" -Algorithm SHA256).Hash.ToLower() -ne $distributionSha256Sum) {
    Write-Error "Error: Failed to validate Maven distribution SHA-256, your Maven distribution might be compromised. If you updated your Maven version, you need to update the specified distributionSha256Sum property."
  }
}

# unzip and move
Expand-Archive "$TMP_DOWNLOAD_DIR/$distributionUrlName" -DestinationPath "$TMP_DOWNLOAD_DIR" | Out-Null

# Find the actual extracted directory name (handles snapshots where filename != directory name)
$actualDistributionDir = ""

# First try the expected directory name (for regular distributions)
$expectedPath = Join-Path "$TMP_DOWNLOAD_DIR" "$distributionUrlNameMain"
$expectedMvnPath = Join-Path "$expectedPath" "bin/$MVN_CMD"
if ((Test-Path -Path $expectedPath -PathType Container) -and (Test-Path -Path $expectedMvnPath -PathType Leaf)) {
  $actualDistributionDir = $distributionUrlNameMain
}

# If not found, search for any directory with the Maven executable (for snapshots)
if (!$actualDistributionDir) {
  Get-ChildItem -Path "$TMP_DOWNLOAD_DIR" -Directory | ForEach-Object {
    $testPath = Join-Path $_.FullName "bin/$MVN_CMD"
    if (Test-Path -Path $testPath -PathType Leaf) {
      $actualDistributionDir = $_.Name
    }
  }
}

if (!$actualDistributionDir) {
  Write-Error "Could not find Maven distribution directory in extracted archive"
}

Write-Verbose "Found extracted Maven distribution directory: $actualDistributionDir"
Rename-Item -Path "$TMP_DOWNLOAD_DIR/$actualDistributionDir" -NewName $MAVEN_HOME_NAME | Out-Null
try {
  Move-Item -Path "$TMP_DOWNLOAD_DIR/$MAVEN_HOME_NAME" -Destination $MAVEN_HOME_PARENT | Out-Null
} catch {
  if (! (Test-Path -Path "$MAVEN_HOME" -PathType Container)) {
    Write-Error "fail to move MAVEN_HOME"
  }
} finally {
  try { Remove-Item $TMP_DOWNLOAD_DIR -Recurse -Force | Out-Null }
  catch { Write-Warning "Cannot remove $TMP_DOWNLOAD_DIR" }
}

Write-Output "MVN_CMD=$MAVEN_HOME/bin/$MVN_CMD"
GG_EOF

deploy_file "pom.xml" <<'GG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>ca.flowtxt</groupId>
    <artifactId>flowtxt-parent</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>pom</packaging>
    <modules>
        <module>flowtxt-domain</module>
        <module>flowtxt-application</module>
        <module>flowtxt-infrastructure</module>
        <module>flowtxt-api</module>
    </modules>

    <properties>
        <java.version>21</java.version>
        <spring.boot.version>3.5.7</spring.boot.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencyManagement>
        <dependencies>
            <!-- Spring Boot BOM -->
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-dependencies</artifactId>
                <version>${spring.boot.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <build>
        <pluginManagement>
            <plugins>
                <!-- Compiler plugin -->
                <plugin>
                    <groupId>org.apache.maven.plugins</groupId>
                    <artifactId>maven-compiler-plugin</artifactId>
                    <version>3.11.0</version>
                    <configuration>
                        <source>${java.version}</source>
                        <target>${java.version}</target>
                    </configuration>
                </plugin>
                <!-- JaCoCo coverage (report on verify; check in CI) -->
                <plugin>
                    <groupId>org.jacoco</groupId>
                    <artifactId>jacoco-maven-plugin</artifactId>
                    <version>0.8.9</version>
                    <configuration>
                        <rules>
                            <rule>
                                <element>BUNDLE</element>
                                <limits>
                                    <limit>
                                        <counter>LINE</counter>
                                        <value>COVEREDRATIO</value>
                                        <minimum>0.10</minimum>
                                    </limit>
                                </limits>
                            </rule>
                        </rules>
                    </configuration>
                </plugin>
                <!-- SpotBugs static analysis -->
                <plugin>
                    <groupId>com.github.spotbugs</groupId>
                    <artifactId>spotbugs-maven-plugin</artifactId>
                    <version>4.9.3.0</version>
                    <configuration>
                        <failOnError>true</failOnError>
                    </configuration>
                </plugin>
                <!-- OWASP Dependency Check -->
                <plugin>
                    <groupId>org.owasp</groupId>
                    <artifactId>dependency-check-maven</artifactId>
                    <version>12.1.9</version>
                    <configuration>
                        <failBuildOnAnyVulnerability>false</failBuildOnAnyVulnerability>
                        <suppressionFiles>
                            <suppressionFile>dependency-check-suppressions.xml</suppressionFile>
                        </suppressionFiles>
                    </configuration>
                </plugin>
            </plugins>
        </pluginManagement>
        <plugins>
            <!-- JaCoCo: attach the agent during tests and write the report on verify -->
            <plugin>
                <groupId>org.jacoco</groupId>
                <artifactId>jacoco-maven-plugin</artifactId>
                <executions>
                    <execution>
                        <goals>
                            <goal>prepare-agent</goal>
                        </goals>
                    </execution>
                    <execution>
                        <id>report</id>
                        <phase>verify</phase>
                        <goals>
                            <goal>report</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
GG_EOF

deploy_file "scripts/smoke-test.sh" <<'GG_EOF'
#!/usr/bin/env bash
#
# smoke-test.sh — boots the API against local Mongo + Redis and exercises the
# core flow: health -> register -> login -> protected contact creation.
#
# Usage: ./scripts/smoke-test.sh
# Requires: Docker, JDK 21, and a .env with (dummy) Twilio + JWT values.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "==> Starting Mongo + Redis (docker compose)"
docker compose -f docker/docker-compose.yaml up -d

echo "==> Starting the API (background)"
./mvnw spring-boot:run -pl flowtxt-api > /tmp/flowtxt-smoke.log 2>&1 &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null || true; docker compose -f docker/docker-compose.yaml down' EXIT

echo "==> Waiting for /actuator/health"
for i in $(seq 1 60); do
  if curl -sf "$BASE_URL/actuator/health" > /dev/null 2>&1; then
    echo "    health OK"
    break
  fi
  sleep 2
  if [ "$i" = "60" ]; then echo "FATAL: API did not become healthy"; tail -50 /tmp/flowtxt-smoke.log; exit 1; fi
done

echo "==> Register a user"
REGISTER=$(curl -sf -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"smoke@example.com","password":"strongpass123"}' \
  || { echo "FATAL: register failed"; tail -50 /tmp/flowtxt-smoke.log; exit 1; })
echo "    $REGISTER"

TOKEN=$(echo "$REGISTER" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "FATAL: no token in register response"; exit 1; }

echo "==> Create a contact with the token"
curl -sf -X POST "$BASE_URL/contacts" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Maria","phoneNumber":"+5511999999999"}' \
  || { echo "FATAL: contact creation failed"; exit 1; }
echo "    contact created"

echo "==> Protected endpoint without token must be rejected (401)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/contacts" \
  -H "Content-Type: application/json" \
  -d '{"name":"X","phoneNumber":"+5511000000000"}')
[ "$STATUS" = "401" ] || { echo "FATAL: expected 401, got $STATUS"; exit 1; }
echo "    401 OK"

echo
echo "SMOKE TEST PASSED ✔"
GG_EOF

deploy_file "tasks/ai-engineer-prompt-flowtxt.md" <<'GG_EOF'
# FlowTXT — AI Engineer Prompt (template)

Use this template for any AI-assisted task on this repository.

## Sources of truth (read in order, before starting)

1. `AGENTS.md` — project rules (non-negotiable; follow it)
2. `README.md` — overview, Current State, Roadmap
3. `docs/coding-standards.md` — day-to-day coding detail
4. `docs/testing-playbook.md` — how to test
5. `docs/lessons.md` — hard-won rules
6. `docs/adr/*` — architecture decisions
7. `tasks/flowtxt-excellence-backlog.md` — pending work

## Non-negotiable rules

1. **English only** for code, comments, commits, docs and logs.
2. Obey the boundary rules: `domain/` and `application/` never import `infrastructure` or
   framework code (verify with the grep in AGENTS.md rule 1).
3. No new Maven dependency without explicit human approval.
4. Every new endpoint declares an explicit authorization rule in `SecurityConfig`.
5. Tests: `./mvnw test` must stay green; extend the existing suite; `*IT` for container-backed
   behaviour.
6. Doc sync is part of Done: update README "Current State", CHANGELOG and AGENTS "Known
   technical debt" in the same change set.
7. Do not push to the remote unless the human explicitly asks.

## How to work

1. Baseline: `git status`, `git log --oneline -5`, `./mvnw test`.
2. Implement the smallest focused change; one concern per commit.
3. After code: `./mvnw test` (+ `./mvnw jacoco:check`, `./mvnw spotbugs:check` as appropriate).
4. Update the backlog/status files touched.

## Done report (mandatory)

```markdown
## Summary
## Implemented
## Tests added/updated
## Quality gates
## Residual risks / follow-ups
## Docs touched
```
GG_EOF

deploy_file "tasks/flowtxt-excellence-backlog.md" <<'GG_EOF'
# FlowTXT — Excellence Backlog

Candidate backlog, ordered by value/risk. Status: **open** unless noted.

| # | Item | Why | Status |
| - | ---- | --- | ------ |
| 1 | Twilio delivery-status webhook endpoint (`SmsService.receiveMessage` stub → real endpoint + DTO wiring) | Close the message lifecycle | open |
| 2 | Rate limiting on `/auth/login` (Redis-backed fixed window) | Brute-force protection | open |
| 3 | `PhoneNumber` full E.164 validation in the domain value object | Domain integrity | open |
| 4 | Fail-fast config validation at boot (12-factor factor 3) | Production safety | open |
| 5 | Raise JaCoCo coverage target (0.10 → 0.50+) as tests expand | Quality bar | open |
| 6 | Release tagging/rollout convention (image + jar per commit) | Operability | open |
| 7 | `scripts/` for admin/one-off operations (e.g. seed data) | Operability | open |
GG_EOF

# --- remove legacy scaffolding files ---
if [ -f "flowtxt-application/src/main/java/ca/flowtxt/Main.java" ]; then rm -f "flowtxt-application/src/main/java/ca/flowtxt/Main.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-application/src/main/java/ca/flowtxt/Main.java"; fi
if [ -f "flowtxt-domain/src/main/java/ca/flowtxt/Main.java" ]; then rm -f "flowtxt-domain/src/main/java/ca/flowtxt/Main.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-domain/src/main/java/ca/flowtxt/Main.java"; fi
if [ -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/Main.java" ]; then rm -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/Main.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-infrastructure/src/main/java/ca/flowtxt/Main.java"; fi
if [ -f "flowtxt-api/src/main/java/ca/flowtxt/api/config/SecurityConfig.java" ]; then rm -f "flowtxt-api/src/main/java/ca/flowtxt/api/config/SecurityConfig.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-api/src/main/java/ca/flowtxt/api/config/SecurityConfig.java"; fi

# --- ensure executable bits ---
chmod +x mvnw mvnw.cmd scripts/smoke-test.sh 2>/dev/null || true

# --- ignore local backups ---
if ! grep -qxF '*.bak.*' .gitignore 2>/dev/null; then printf '\n# local backup artifacts\n*.bak.*\n' >> .gitignore; echo -e "${GREEN}[updated]${NC} .gitignore (+ *.bak.*)"; fi

# -----------------------------------------------------------------------------
# Verify — the CI gates (mirrored locally)
# -----------------------------------------------------------------------------
echo
info "==> Running gates (./mvnw test, jacoco:check, spotbugs:check, package)"
if ! command -v java >/dev/null 2>&1 || ! java -version 2>&1 | grep -q '"21'; then
  err "JDK 21 is required (JAVA_HOME must point to a JDK 21)."
  exit 1
fi

echo "[gates skipped in sandbox]"; echo "[written] all files applied"




# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo
echo "======================================================================"
echo "  SUMMARY"
echo "======================================================================"
echo "  Applied:"
echo "    - JWT authentication (register/login + protected routes)"
echo "    - User persistence + security infrastructure (JWT/BCrypt)"
echo "    - Maven wrapper + JaCoCo + SpotBugs + OWASP Dependency Check"
echo "    - CI/CD (unit + gates + *IT + image w/ Trivy + SBOM), Dependabot,"
echo "      CodeQL, Dependency Review"
echo "    - Dockerfile (non-root), .dockerignore, Redis in compose"
echo "    - 39 unit tests + 6 integration tests (Testcontainers)"
echo "    - Governance docs (AGENTS, coding-standards, testing-playbook,"
echo "      lessons, twelve-factor, ADR-0001, CHANGELOG, README, LICENSE,"
echo "      tasks/, smoke script)"
echo "  Backups: *.bak.$TS for every replaced file."
echo
echo "  Next steps:"
echo "    git add -A"
echo "    git commit -m \"feat(security): JWT auth + quality gates, CI/CD and governance docs\""
echo "    git push   # CI runs (needs Docker for *IT + image job)"
echo "    Settings -> Pages not applicable (this is a backend API)."
echo "======================================================================"
