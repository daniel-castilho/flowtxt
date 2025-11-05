package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

import java.util.UUID;

@Mapper(componentModel = "spring")
public interface MessageMapper {

    @Mapping(target = "contactId", source = "contact.id")
    @Mapping(target = "sid", source = "sid")
    MessageDocument toDocument(Message message);

    @Mapping(target = "contact", expression = "java(mapContact(document.getContactId()))")
    @Mapping(target = "sid", source = "sid")
    Message toDomain(MessageDocument document);

    // Helper method to map contactId to Contact (with minimal data)
    default Contact mapContact(UUID contactId) {
        return Contact.builder()
                .id(contactId)
                .build();
    }
}

