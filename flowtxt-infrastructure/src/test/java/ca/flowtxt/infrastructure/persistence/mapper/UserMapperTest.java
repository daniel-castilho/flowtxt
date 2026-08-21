package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.document.UserDocument;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class UserMapperTest {

    private final UserMapper mapper = new UserMapperImpl();

    @Test
    void mapsUserToDocument() {
        User user = new User(
                UUID.fromString("00000000-0000-0000-0000-000000000021"),
                "user@example.com",
                "$2a$10$hash",
                Role.USER,
                Instant.parse("2026-08-21T10:00:00Z"));

        UserDocument doc = mapper.toDocument(user);

        assertEquals(user.getId(), doc.getId());
        assertEquals("user@example.com", doc.getEmail());
        assertEquals("$2a$10$hash", doc.getPasswordHash());
        assertEquals(Role.USER, doc.getRole());
    }

    @Test
    void mapsDocumentBackToUser() {
        UserDocument doc = UserDocument.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000022"))
                .email("admin@example.com")
                .passwordHash("$2a$10$hash2")
                .role(Role.ADMIN)
                .createdAt(Instant.parse("2026-08-21T11:00:00Z"))
                .build();

        User user = mapper.toUser(doc);

        assertEquals(doc.getId(), user.getId());
        assertEquals("admin@example.com", user.getEmail());
        assertEquals(Role.ADMIN, user.getRole());
    }
}
