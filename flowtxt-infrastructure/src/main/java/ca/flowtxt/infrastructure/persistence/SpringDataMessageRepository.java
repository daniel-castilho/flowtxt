package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.entity.MessageEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataMessageRepository extends JpaRepository<MessageEntity, UUID> {

    Optional<MessageEntity> findBySid(String messageSid);
}
