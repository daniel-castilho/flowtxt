package ca.flowtxt.infrastructure.persistence.document;

import ca.flowtxt.domain.model.MessageStatus;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;
import java.util.UUID;

/**
 * MongoDB representation of a {@code ca.flowtxt.domain.model.Message}.
 */
@Document(collection = "messages")
public record MessageDocument(
        @Id UUID id,
        UUID contactId,
        String content,
        MessageStatus status,
        Instant timestamp,
        @Indexed String sid) {
}
