package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.persistence.entity.MessageEntity;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class MessageMapperTest {

    private final MessageMapper mapper = new MessageMapperImpl();

    @Test
    void mapsMessageToEntity() {
        UUID contactId = UUID.fromString("00000000-0000-0000-0000-000000000011");
        Instant now = Instant.now();

        Message message = new Message(
                UUID.fromString("00000000-0000-0000-0000-000000000012"),
                contactId, "Hello!", MessageStatus.SENT, now, "SM123");

        MessageEntity entity = mapper.toEntity(message);

        assertEquals(message.getId(), entity.getId());
        assertEquals(contactId, entity.getContactId());
        assertEquals("Hello!", entity.getContent());
        assertEquals(MessageStatus.SENT, entity.getStatus());
        assertEquals(now, entity.getTimestamp());
        assertEquals("SM123", entity.getSid());
    }

    @Test
    void mapsEntityBackToMessage() {
        MessageEntity entity = new MessageEntity(
                UUID.fromString("00000000-0000-0000-0000-000000000013"),
                UUID.fromString("00000000-0000-0000-0000-000000000014"),
                "Hi",
                MessageStatus.PENDING,
                Instant.parse("2026-08-21T10:00:00Z"),
                "SM456");
        Message message = mapper.toDomain(entity);

        assertEquals(entity.getId(), message.getId());
        assertEquals(entity.getContactId(), message.getContactId());
        assertEquals(entity.getContent(), message.getContent());
        assertEquals(entity.getStatus(), message.getStatus());
        assertEquals(entity.getTimestamp(), message.getTimestamp());
        assertEquals(entity.getSid(), message.getSid());
    }

    @Test
    void applyUpdatesBusinessStateButNeverTouchesTheVersion() {
        MessageEntity entity = new MessageEntity(
                UUID.fromString("00000000-0000-0000-0000-000000000015"),
                UUID.fromString("00000000-0000-0000-0000-000000000016"),
                "Hello FlowTXT",
                MessageStatus.SENT,
                Instant.parse("2026-08-21T10:00:00Z"),
                "SM789");
        ReflectionTestUtils.setField(entity, "version", 2L);

        Message updated = new Message(
                entity.getId(), entity.getContactId(), "Hello FlowTXT",
                MessageStatus.DELIVERED, entity.getTimestamp(), "SM789");

        mapper.apply(updated, entity);

        assertEquals(MessageStatus.DELIVERED, entity.getStatus());
        assertEquals("SM789", entity.getSid());
        assertEquals(2L, entity.getVersion());
    }
}
