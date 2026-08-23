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
