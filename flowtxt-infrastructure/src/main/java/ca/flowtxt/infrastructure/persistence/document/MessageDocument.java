package ca.flowtxt.infrastructure.persistence.document;

import ca.flowtxt.domain.model.MessageStatus;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.redis.core.index.Indexed;

import java.time.Instant;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "messages")
public class MessageDocument {

    @Id
    private UUID id;

    private UUID contactId;
    private String content;
    private MessageStatus status;
    private Instant timestamp;

    @Indexed
    private String sid;
}

