package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.persistence.entity.ContactEntity;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ContactMapperTest {

    private final ContactMapper mapper = new ContactMapperImpl();

    @Test
    void mapsContactToEntity() {
        Contact contact = new Contact(
                UUID.fromString("00000000-0000-0000-0000-000000000001"),
                "Maria Silva",
                new PhoneNumber("+5511999999999"));

        ContactEntity entity = mapper.toEntity(contact);

        assertEquals(contact.getId(), entity.getId());
        assertEquals("Maria Silva", entity.getName());
        assertEquals("+5511999999999", entity.getPhoneNumber());
    }

    @Test
    void mapsEntityBackToContact() {
        ContactEntity entity = new ContactEntity(
                UUID.fromString("00000000-0000-0000-0000-000000000002"),
                "John Souza",
                "+5511888888888");

        Contact contact = mapper.toDomain(entity);

        assertEquals(entity.getId(), contact.getId());
        assertEquals("John Souza", contact.getName());
        assertEquals("+5511888888888", contact.getPhoneNumber().value());
    }
}
