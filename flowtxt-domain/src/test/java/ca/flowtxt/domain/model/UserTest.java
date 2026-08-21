package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class UserTest {

    @Test
    void registersWithTheDefaultUserRoleAndACreationTimestamp() {
        User user = User.register("user@example.com", "$2a$10$abcdefghijklmnopqrstuv");

        assertNotNull(user.getId());
        assertEquals("user@example.com", user.getEmail());
        assertEquals("$2a$10$abcdefghijklmnopqrstuv", user.getPasswordHash());
        assertEquals(Role.USER, user.getRole());
        assertNotNull(user.getCreatedAt());
    }

    @Test
    void rehydrationKeepsEveryFieldIncludingRoleAndCreationTime() {
        UUID id = UUID.randomUUID();
        Instant createdAt = Instant.parse("2026-08-21T10:00:00Z");

        User user = new User(id, "admin@example.com", "$2a$10$hash2", Role.ADMIN, createdAt);

        assertEquals(id, user.getId());
        assertEquals("admin@example.com", user.getEmail());
        assertEquals(Role.ADMIN, user.getRole());
        assertEquals(createdAt, user.getCreatedAt());
    }

    @Test
    void rejectsMissingEssentialState() {
        assertThrows(IllegalArgumentException.class,
                () -> new User(null, "user@example.com", "hash", Role.USER, Instant.now()));
        assertThrows(IllegalArgumentException.class,
                () -> User.register("   ", "hash"));
        assertThrows(IllegalArgumentException.class,
                () -> User.register("user@example.com", null));
    }

    @Test
    void equalityIsByIdentityNotByFieldState() {
        UUID id = UUID.randomUUID();
        User original = new User(id, "user@example.com", "hash-a", Role.USER, Instant.now());
        User reloaded = new User(id, "changed@example.com", "hash-b", Role.ADMIN, Instant.now());

        assertEquals(original, reloaded);
        assertEquals(original.hashCode(), reloaded.hashCode());

        User other = User.register("user@example.com", "hash-a");
        assertNotEquals(original, other);
    }
}
