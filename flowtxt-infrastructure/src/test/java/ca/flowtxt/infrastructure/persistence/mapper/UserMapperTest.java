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

        assertEquals(user.getId(), doc.id());
        assertEquals("user@example.com", doc.email());
        assertEquals("$2a$10$hash", doc.passwordHash());
        assertEquals(Role.USER, doc.role());
    }

    @Test
    void mapsDocumentBackToUser() {
        UserDocument doc = new UserDocument(
                UUID.fromString("00000000-0000-0000-0000-000000000022"),
                "admin@example.com",
                "$2a$10$hash2",
                Role.ADMIN,
                Instant.parse("2026-08-21T11:00:00Z"));

        User user = mapper.toUser(doc);

        assertEquals(doc.id(), user.getId());
        assertEquals(doc.email(), user.getEmail());
        assertEquals(doc.role(), user.getRole());
    }
}
