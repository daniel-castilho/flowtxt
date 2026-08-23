package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.AuthResult;
import ca.flowtxt.application.port.out.AuthenticationTokenPort;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.common.InvalidCredentialsException;
import ca.flowtxt.domain.model.PasswordHasher;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthenticateUserUseCaseImplTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordHasher passwordHasher;

    @Mock
    private AuthenticationTokenPort authenticationTokenPort;

    private AuthenticateUserUseCaseImpl useCase;

    @BeforeEach
    void setUp() {
        useCase = new AuthenticateUserUseCaseImpl(
                userRepository, passwordHasher, authenticationTokenPort);
    }

    @Test
    void authenticatesWithValidCredentialsAndIssuesToken() {
        User stored = User.register("user@example.com", "hashed-value");
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(stored));
        when(passwordHasher.matches("correct-password", "hashed-value")).thenReturn(true);
        when(authenticationTokenPort.issueToken(stored)).thenReturn("jwt-token");

        AuthResult result = useCase.authenticate("User@Example.COM", "correct-password");

        assertEquals(stored, result.user());
        assertEquals("jwt-token", result.token());
        verify(authenticationTokenPort).issueToken(stored);
    }

    @Test
    void rejectsUnknownEmailWithInvalidCredentials() {
        when(userRepository.findByEmail("ghost@example.com")).thenReturn(Optional.empty());

        assertThrows(InvalidCredentialsException.class,
                () -> useCase.authenticate("ghost@example.com", "whatever123"));
        verify(authenticationTokenPort, never()).issueToken(any());
    }

    @Test
    void rejectsWrongPasswordWithInvalidCredentials() {
        User stored = User.register("user@example.com", "hashed-value");
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(stored));
        when(passwordHasher.matches("wrong-password", "hashed-value")).thenReturn(false);

        assertThrows(InvalidCredentialsException.class,
                () -> useCase.authenticate("user@example.com", "wrong-password"));
        verify(authenticationTokenPort, never()).issueToken(any());
    }
}
