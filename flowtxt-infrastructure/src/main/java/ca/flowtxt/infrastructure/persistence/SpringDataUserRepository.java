package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.document.UserDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataUserRepository extends MongoRepository<UserDocument, UUID> {

    Optional<UserDocument> findByEmail(String email);
}
