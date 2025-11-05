package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface SpringDataMessageRepository extends MongoRepository<MessageDocument, UUID> {
    List<MessageDocument> findByContactId(UUID contactId);
    Optional<MessageDocument> findById(UUID id);
}
