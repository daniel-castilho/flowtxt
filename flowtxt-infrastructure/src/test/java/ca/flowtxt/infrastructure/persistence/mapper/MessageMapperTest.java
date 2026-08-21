package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class MessageMapperTest {

    private final MessageMapper mapper = new MessageMapperImpl();

    @Test
    void mapsMessageToDocument() {
        UUID contactId = UUID.fromString("00000000-0000-0000-0000-000000000011");
        Contact contact = Contact.builder().id(contactId).build();
        Instant now = Instant.now();

        Message message = Message.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000012"))
                .contact(contact)
                .content("Hello!")
                .status(MessageStatus.SENT)
                .timestamp(now)
                .sid("SM123")
                .build();

        MessageDocument doc = mapper.toDocument(message);

        assertEquals(message.getId(), doc.getId());
        assertEquals(contactId, doc.getContactId());
        assertEquals("Hello!", doc.getContent());
        assertEquals(MessageStatus.SENT, doc.getStatus());
        assertEquals(now, doc.getTimestamp());
        assertEquals("SM123", doc.getSid());
    }

    @Test
    void mapsDocumentBackToMessage() {
        MessageDocument doc = MessageDocument.builder()
                .id(UUID.fromString("00000000-0000-0000-0000-000000000013"))
                .contactId(UUID.fromString("00000000-0000-0000-0000-000000000014"))
                .content("Hi")
                .status(MessageStatus.PENDING)
                .timestamp(Instant.parse("2026-08-21T10:00:00Z"))
                .sid("SM456")
                .build();

        Message message = mapper.toDomain(doc);

        assertEquals(doc.getId(), message.getId());
        assertEquals(doc.getContactId(), message.getContact().getId());
        assertEquals("Hi", message.getContent());
        assertEquals(MessageStatus.PENDING, message.getStatus());
        assertEquals("SM456", message.getSid());
    }
}
