package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.AuthResult;
import ca.flowtxt.application.port.in.AuthenticateUserUseCase;
import ca.flowtxt.application.port.out.AuthenticationTokenPort;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.common.InvalidCredentialsException;
import ca.flowtxt.domain.model.PasswordHasher;
import ca.flowtxt.domain.model.User;

public class AuthenticateUserUseCaseImpl implements AuthenticateUserUseCase {

    private final UserRepository userRepository;
    private final PasswordHasher passwordHasher;
    private final AuthenticationTokenPort authenticationTokenPort;

    public AuthenticateUserUseCaseImpl(
            UserRepository userRepository,
            PasswordHasher passwordHasher,
            AuthenticationTokenPort authenticationTokenPort) {
        this.userRepository = userRepository;
        this.passwordHasher = passwordHasher;
        this.authenticationTokenPort = authenticationTokenPort;
    }

    @Override
    public AuthResult authenticate(String email, String rawPassword) {
        String normalizedEmail = email == null ? "" : email.trim().toLowerCase();
        User user = userRepository.findByEmail(normalizedEmail)
                .orElseThrow(InvalidCredentialsException::new);

        if (!passwordHasher.matches(rawPassword, user.getPasswordHash())) {
            throw new InvalidCredentialsException();
        }
        return new AuthResult(user, authenticationTokenPort.issueToken(user));
    }
}
