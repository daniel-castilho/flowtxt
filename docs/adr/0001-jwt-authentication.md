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
