package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class UserTest {

    @Test
    void buildsAUserWithAllFields() {
        UUID id = UUID.randomUUID();
        Instant now = Instant.now();

        User user = User.builder()
                .id(id)
                .email("user@example.com")
                .passwordHash("$2a$10$abcdefghijklmnopqrstuv")
                .role(Role.USER)
                .createdAt(now)
                .build();

        assertNotNull(user);
        assertEquals(id, user.getId());
        assertEquals("user@example.com", user.getEmail());
        assertEquals("$2a$10$abcdefghijklmnopqrstuv", user.getPasswordHash());
        assertEquals(Role.USER, user.getRole());
        assertEquals(now, user.getCreatedAt());
    }
}
