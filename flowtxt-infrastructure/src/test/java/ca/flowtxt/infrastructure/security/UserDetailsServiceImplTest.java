package ca.flowtxt.infrastructure.security;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UsernameNotFoundException;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserDetailsServiceImplTest {

    @Mock
    private UserRepository userRepository;

    @Test
    void loadsAUserWithItsRoleAuthority() {
        User user = new User(
                UUID.randomUUID(),
                "user@example.com",
                "hashed",
                Role.USER,
                java.time.Instant.now());
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(user));

        UserDetails details =
                new UserDetailsServiceImpl(userRepository).loadUserByUsername("user@example.com");

        assertEquals("user@example.com", details.getUsername());
        assertEquals("hashed", details.getPassword());
        assertTrue(details.getAuthorities().contains(
                new SimpleGrantedAuthority("ROLE_USER")));
    }

    @Test
    void throwsWhenTheUserDoesNotExist() {
        when(userRepository.findByEmail("ghost@example.com")).thenReturn(Optional.empty());

        assertThrows(UsernameNotFoundException.class,
                () -> new UserDetailsServiceImpl(userRepository)
                        .loadUserByUsername("ghost@example.com"));
    }
}
