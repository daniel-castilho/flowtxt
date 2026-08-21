package ca.flowtxt.infrastructure.persistence.document;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.util.UUID;

/**
 * MongoDB representation of a {@code ca.flowtxt.domain.model.Contact}.
 */
@Document(collection = "contacts")
public record ContactDocument(
        @Id UUID id,
        String name,
        String phoneNumber) {
}
