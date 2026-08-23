package ca.flowtxt.application.port.in;

/**
 * Authenticates a user by email + password. Returns an {@link AuthResult}
 * (authenticated user + bearer token) on success; throws
 * {@link ca.flowtxt.domain.common.InvalidCredentialsException} on invalid
 * credentials. Token issuance is performed through the application's
 * {@link ca.flowtxt.application.port.out.AuthenticationTokenPort}, so the web
 * layer never depends on the infrastructure token adapter directly.
 */
public interface AuthenticateUserUseCase {

    AuthResult authenticate(String email, String rawPassword);
}
