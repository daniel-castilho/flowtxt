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
