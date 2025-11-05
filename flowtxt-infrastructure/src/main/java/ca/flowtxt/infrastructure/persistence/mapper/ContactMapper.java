package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.persistence.document.ContactDocument;
import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface ContactMapper {

    // Domain → Document
    ContactDocument toDocument(Contact contact);

    // Document → Domain
    Contact toContact(ContactDocument document);

    // PhoneNumber → String
    default String map(PhoneNumber phoneNumber) {
        return phoneNumber != null ? phoneNumber.getValue() : null;
    }

    // String → PhoneNumber
    default PhoneNumber map(String phoneNumber) {
        return phoneNumber != null ? new PhoneNumber(phoneNumber) : null;
    }
}

