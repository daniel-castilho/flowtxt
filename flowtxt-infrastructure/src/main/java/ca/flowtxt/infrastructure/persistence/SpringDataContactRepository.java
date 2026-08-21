package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.entity.ContactEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataContactRepository extends JpaRepository<ContactEntity, UUID> {

    Optional<ContactEntity> findByPhoneNumber(String phoneNumber);
}
