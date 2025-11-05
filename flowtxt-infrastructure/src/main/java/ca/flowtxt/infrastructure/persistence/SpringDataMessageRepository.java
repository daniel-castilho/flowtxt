package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.data.mongodb.repository.Update;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface SpringDataMessageRepository extends MongoRepository<MessageDocument, UUID> {
    List<MessageDocument> findByContactId(UUID contactId);

    Optional<MessageDocument> findById(UUID id);

    @Query("{ 'sid': ?0 }")
    @Update("{ '$set': { 'status': ?1 } }")
    void updateStatusBySid(String messageSid, MessageStatus status);
}
