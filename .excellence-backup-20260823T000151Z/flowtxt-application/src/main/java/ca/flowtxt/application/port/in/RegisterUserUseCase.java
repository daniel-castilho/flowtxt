package ca.flowtxt.application.port.in;

import ca.flowtxt.domain.model.User;

/**
 * Registers a new application user. Throws IllegalArgumentException when the
 * email is already registered or the password is too weak.
 */
public interface RegisterUserUseCase {

    User register(String email, String rawPassword);
}
