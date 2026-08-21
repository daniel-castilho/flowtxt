package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.persistence.document.ContactDocument;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ContactMapperTest {

    private final ContactMapper mapper = new ContactMapperImpl();

    @Test
    void mapsContactToDocument() {
        Contact contact = new Contact(
                UUID.fromString("00000000-0000-0000-0000-000000000001"),
                "Maria Silva",
                new PhoneNumber("+5511999999999"));

        ContactDocument doc = mapper.toDocument(contact);

        assertEquals(contact.getId(), doc.id());
        assertEquals("Maria Silva", doc.name());
        assertEquals("+5511999999999", doc.phoneNumber());
    }

    @Test
    void mapsDocumentBackToContact() {
        ContactDocument doc = new ContactDocument(
                UUID.fromString("00000000-0000-0000-0000-000000000002"),
                "John Souza",
                "+5511888888888");

        Contact contact = mapper.toContact(doc);

        assertEquals(doc.id(), contact.getId());
        assertEquals("John Souza", contact.getName());
        assertEquals("+5511888888888", contact.getPhoneNumber().value());
    }
}
