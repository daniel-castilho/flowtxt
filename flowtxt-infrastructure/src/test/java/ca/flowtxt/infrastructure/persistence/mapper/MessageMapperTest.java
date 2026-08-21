package ca.flowtxt.infrastructure.persistence.mapper;

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
        Instant now = Instant.now();

        Message message = new Message(
                UUID.fromString("00000000-0000-0000-0000-000000000012"),
                contactId, "Hello!", MessageStatus.SENT, now, "SM123");

        MessageDocument doc = mapper.toDocument(message);

        assertEquals(message.getId(), doc.id());
        assertEquals(contactId, doc.contactId());
        assertEquals("Hello!", doc.content());
        assertEquals(MessageStatus.SENT, doc.status());
        assertEquals(now, doc.timestamp());
        assertEquals("SM123", doc.sid());
    }

    @Test
    void mapsDocumentBackToMessage() {
        MessageDocument doc = new MessageDocument(
                UUID.fromString("00000000-0000-0000-0000-000000000013"),
                UUID.fromString("00000000-0000-0000-0000-000000000014"),
                "Hi",
                MessageStatus.PENDING,
                Instant.parse("2026-08-21T10:00:00Z"),
                "SM456");

        Message message = mapper.toDomain(doc);

        assertEquals(doc.id(), message.getId());
        assertEquals(doc.contactId(), message.getContactId());
        assertEquals(doc.content(), message.getContent());
        assertEquals(doc.status(), message.getStatus());
        assertEquals(doc.timestamp(), message.getTimestamp());
        assertEquals(doc.sid(), message.getSid());
    }
}
