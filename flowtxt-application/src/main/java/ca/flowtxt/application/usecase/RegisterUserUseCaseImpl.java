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
