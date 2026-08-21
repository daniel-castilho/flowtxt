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
