package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.AuthResult;
import ca.flowtxt.application.port.in.RegisterUserUseCase;
import ca.flowtxt.application.port.out.AuthenticationTokenPort;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.common.ConflictException;
import ca.flowtxt.domain.model.PasswordHasher;
import ca.flowtxt.domain.model.User;


public class RegisterUserUseCaseImpl implements RegisterUserUseCase {

    private static final int MIN_PASSWORD_LENGTH = 8;

    private final UserRepository userRepository;
    private final PasswordHasher passwordHasher;
    private final AuthenticationTokenPort authenticationTokenPort;

    public RegisterUserUseCaseImpl(
            UserRepository userRepository,
            PasswordHasher passwordHasher,
            AuthenticationTokenPort authenticationTokenPort) {
        this.userRepository = userRepository;
        this.passwordHasher = passwordHasher;
        this.authenticationTokenPort = authenticationTokenPort;
    }

    @Override
    public AuthResult register(String email, String rawPassword) {
        String normalizedEmail = email == null ? "" : email.trim().toLowerCase();
        if (normalizedEmail.isBlank()) {
            throw new IllegalArgumentException("Email is required");
        }
        if (rawPassword == null || rawPassword.length() < MIN_PASSWORD_LENGTH) {
            throw new IllegalArgumentException(
                    "Password must be at least " + MIN_PASSWORD_LENGTH + " characters");
        }
        if (userRepository.findByEmail(normalizedEmail).isPresent()) {
            throw new ConflictException("Email is already registered");
        }

        User user = User.register(normalizedEmail, passwordHasher.hash(rawPassword));
        userRepository.save(user);
        return new AuthResult(user, authenticationTokenPort.issueToken(user));
    }
}
