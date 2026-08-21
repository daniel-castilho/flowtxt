package ca.flowtxt.infrastructure.persistence.document;

import ca.flowtxt.domain.model.Role;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;
import java.util.UUID;

/**
 * MongoDB representation of a {@code ca.flowtxt.domain.model.User}. The
 * password is stored only as a hash.
 */
@Document(collection = "users")
public record UserDocument(
        @Id UUID id,
        String email,
        String passwordHash,
        Role role,
        Instant createdAt) {
}
