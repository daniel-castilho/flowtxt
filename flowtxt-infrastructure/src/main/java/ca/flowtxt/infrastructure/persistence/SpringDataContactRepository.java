package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.document.ContactDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataContactRepository extends MongoRepository<ContactDocument, UUID> {
    Optional<ContactDocument> findByPhoneNumber(final String phoneNumber);
}
