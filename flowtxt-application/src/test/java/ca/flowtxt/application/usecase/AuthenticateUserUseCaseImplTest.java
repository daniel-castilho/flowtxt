package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.PasswordHasher;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthenticateUserUseCaseImplTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordHasher passwordHasher;

    private AuthenticateUserUseCaseImpl useCase;

    @BeforeEach
    void setUp() {
        useCase = new AuthenticateUserUseCaseImpl(userRepository, passwordHasher);
    }

    @Test
    void authenticatesWithValidCredentials() {
        User stored = User.builder()
                .id(UUID.randomUUID())
                .email("user@example.com")
                .passwordHash("hashed-value")
                .role(Role.USER)
                .build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(stored));
        when(passwordHasher.matches("correct-password", "hashed-value")).thenReturn(true);

        User result = useCase.authenticate("User@Example.COM", "correct-password");

        assertEquals(stored, result);
    }

    @Test
    void rejectsUnknownEmail() {
        when(userRepository.findByEmail("ghost@example.com")).thenReturn(Optional.empty());

        assertThrows(IllegalArgumentException.class,
                () -> useCase.authenticate("ghost@example.com", "whatever123"));
    }

    @Test
    void rejectsWrongPassword() {
        User stored = User.builder()
                .email("user@example.com")
                .passwordHash("hashed-value")
                .build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(stored));
        when(passwordHasher.matches("wrong-password", "hashed-value")).thenReturn(false);

        assertThrows(IllegalArgumentException.class,
                () -> useCase.authenticate("user@example.com", "wrong-password"));
    }
}
