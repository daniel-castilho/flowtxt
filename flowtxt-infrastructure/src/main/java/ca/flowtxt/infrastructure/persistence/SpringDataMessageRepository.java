package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataMessageRepository extends MongoRepository<MessageDocument, UUID> {

    Optional<MessageDocument> findBySid(String messageSid);
}
