package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.entity.UserEntity;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class UserMapperTest {

    private final UserMapper mapper = new UserMapperImpl();

    @Test
    void mapsUserToEntity() {
        User user = new User(
                UUID.fromString("00000000-0000-0000-0000-000000000021"),
                "user@example.com",
                "$2a$10$hash",
                Role.USER,
                Instant.parse("2026-08-21T10:00:00Z"));

        UserEntity entity = mapper.toEntity(user);

        assertEquals(user.getId(), entity.getId());
        assertEquals("user@example.com", entity.getEmail());
        assertEquals("$2a$10$hash", entity.getPasswordHash());
        assertEquals(Role.USER, entity.getRole());
    }

    @Test
    void mapsEntityBackToUser() {
        UserEntity entity = new UserEntity(
                UUID.fromString("00000000-0000-0000-0000-000000000022"),
                "admin@example.com",
                "$2a$10$hash2",
                Role.ADMIN,
                Instant.parse("2026-08-21T11:00:00Z"));

        User user = mapper.toUser(entity);

        assertEquals(entity.getId(), user.getId());
        assertEquals(entity.getEmail(), user.getEmail());
        assertEquals(entity.getRole(), user.getRole());
    }
}
