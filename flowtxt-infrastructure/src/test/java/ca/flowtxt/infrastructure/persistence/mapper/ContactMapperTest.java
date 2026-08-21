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
        Contact contact = Contact.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000001"))
                .name("Maria Silva")
                .phoneNumber(new PhoneNumber("+5511999999999"))
                .build();

        ContactDocument doc = mapper.toDocument(contact);

        assertEquals(contact.getId(), doc.getId());
        assertEquals("Maria Silva", doc.getName());
        assertEquals("+5511999999999", doc.getPhoneNumber());
    }

    @Test
    void mapsDocumentBackToContact() {
        ContactDocument doc = ContactDocument.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000002"))
                .name("João Souza")
                .phoneNumber("+5511888888888")
                .build();

        Contact contact = mapper.toContact(doc);

        assertEquals(doc.getId(), contact.getId());
        assertEquals("João Souza", contact.getName());
        assertEquals("+5511888888888", contact.getPhoneNumber().getValue());
    }
}
