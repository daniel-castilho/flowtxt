package ca.flowtxt.application.port.in;

/**
 * Registers a new application user and issues a bearer token for the new
 * account. Throws {@link IllegalArgumentException} when the password is too
 * weak and {@link ca.flowtxt.domain.common.ConflictException} when the email is
 * already registered.
 */
public interface RegisterUserUseCase {

    AuthResult register(String email, String rawPassword);
}
