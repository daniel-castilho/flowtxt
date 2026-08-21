package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.persistence.entity.ContactEntity;
import org.mapstruct.Mapper;

/**
 * Maps between the immutable domain {@link Contact} and the JPA
 * {@link ContactEntity}. The domain stays free of persistence annotations.
 */
@Mapper(componentModel = "spring")
public interface ContactMapper {

    // Domain → Entity
    ContactEntity toEntity(Contact contact);

    // Entity → Domain
    Contact toDomain(ContactEntity entity);

    // PhoneNumber → String
    default String map(PhoneNumber phoneNumber) {
        return phoneNumber != null ? phoneNumber.value() : null;
    }

    // String → PhoneNumber
    default PhoneNumber map(String phoneNumber) {
        return phoneNumber != null ? new PhoneNumber(phoneNumber) : null;
    }
}
