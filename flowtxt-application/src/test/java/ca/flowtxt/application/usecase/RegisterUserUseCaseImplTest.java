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

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RegisterUserUseCaseImplTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordHasher passwordHasher;

    private RegisterUserUseCaseImpl useCase;

    @BeforeEach
    void setUp() {
        useCase = new RegisterUserUseCaseImpl(userRepository, passwordHasher);
    }

    @Test
    void registersANewUserWithHashedPasswordAndUserRole() {
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.empty());
        when(passwordHasher.hash("strongpass123")).thenReturn("hashed-value");

        User user = useCase.register("  User@Example.COM  ", "strongpass123");

        assertEquals("user@example.com", user.getEmail());
        assertEquals("hashed-value", user.getPasswordHash());
        assertEquals(Role.USER, user.getRole());
        assertNotEquals("strongpass123", user.getPasswordHash());

        verify(userRepository).save(argThat(u ->
                u.getEmail().equals("user@example.com")
                        && u.getPasswordHash().equals("hashed-value")));
    }

    @Test
    void rejectsDuplicateEmail() {
        when(userRepository.findByEmail("taken@example.com"))
                .thenReturn(Optional.of(User.builder().email("taken@example.com").build()));

        assertThrows(IllegalArgumentException.class,
                () -> useCase.register("taken@example.com", "strongpass123"));

        verify(userRepository, never()).save(any());
    }

    @Test
    void rejectsBlankEmail() {
        assertThrows(IllegalArgumentException.class,
                () -> useCase.register("   ", "strongpass123"));
    }

    @Test
    void rejectsShortPassword() {
        assertThrows(IllegalArgumentException.class,
                () -> useCase.register("user@example.com", "short"));
    }
}
