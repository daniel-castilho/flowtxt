package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;

class MessageTest {

    private final UUID contactId = UUID.randomUUID();

    @Test
    void pendingStartsTheLifecycleWithGeneratedIdentityAndTimestamp() {
        Message message = Message.pending(contactId, "Hello!");

        assertEquals(MessageStatus.PENDING, message.getStatus());
        assertEquals(contactId, message.getContactId());
        assertEquals("Hello!", message.getContent());
        assertNotNull(message.getId());
        assertNotNull(message.getTimestamp());
    }

    @Test
    void markSentRecordsTheProviderSid() {
        Message sent = Message.pending(contactId, "Hello!").markSent("SM-123");

        assertEquals(MessageStatus.SENT, sent.getStatus());
        assertEquals("SM-123", sent.getSid());
    }

    @Test
    void providerCallbacksAdvanceThroughTheLifecycle() {
        Message message = Message.pending(contactId, "Hello!")
                .markSent("SM-123")
                .applyProviderStatus(MessageStatus.DELIVERED, "SM-123");

        assertEquals(MessageStatus.DELIVERED, message.getStatus());
    }

    @Test
    void replayingTheCurrentStatusIsIdempotent() {
        Message delivered = Message.pending(contactId, "Hello!")
                .markSent("SM-123")
                .applyProviderStatus(MessageStatus.DELIVERED, "SM-123");

        assertSame(delivered, delivered.applyProviderStatus(MessageStatus.DELIVERED, "SM-123"));
    }

    @Test
    void rejectsATransitionBackwardsInTheLifecycle() {
        Message delivered = Message.pending(contactId, "Hello!")
                .markSent("SM-123")
                .applyProviderStatus(MessageStatus.DELIVERED, "SM-123");

        assertThrows(IllegalStateException.class,
                () -> delivered.applyProviderStatus(MessageStatus.SENT, "SM-123"));
    }

    @Test
    void unknownStatusIsAcceptedFromAnyStateAsASink() {
        Message pending = Message.pending(contactId, "Hello!");
        Message delivered = pending.markSent("SM-123")
                .applyProviderStatus(MessageStatus.DELIVERED, "SM-123");

        assertEquals(MessageStatus.UNKNOWN,
                pending.applyProviderStatus(MessageStatus.UNKNOWN, null).getStatus());
        assertEquals(MessageStatus.UNKNOWN,
                delivered.applyProviderStatus(MessageStatus.UNKNOWN, null).getStatus());
    }

    @Test
    void marksFailedWhenTheProviderRejectsTheSend() {
        Message failed = Message.pending(contactId, "Hello!").markFailed();

        assertEquals(MessageStatus.FAILED, failed.getStatus());
    }

    @Test
    void aSentMessageRequiresAProviderSid() {
        Message pending = Message.pending(contactId, "Hello!");

        assertThrows(IllegalArgumentException.class, () -> pending.markSent(null));
        assertThrows(IllegalArgumentException.class, () -> pending.markSent("  "));
    }

    @Test
    void equalityIsByIdentityNotByFieldState() {
        UUID id = UUID.randomUUID();
        Message original = new Message(id, contactId, "Hello!", MessageStatus.PENDING,
                java.time.Instant.now(), null);
        Message reloaded = new Message(id, contactId, "Changed content", MessageStatus.SENT,
                java.time.Instant.now().plusSeconds(60), "SM-999");

        assertEquals(original, reloaded);
        assertEquals(original.hashCode(), reloaded.hashCode());

        Message other = Message.pending(UUID.randomUUID(), "Hello!");
        assertNotEquals(original, other);
    }

    @Test
    void rejectsMissingEssentialState() {
        assertThrows(IllegalArgumentException.class,
                () -> new Message(null, contactId, "Hi", MessageStatus.PENDING, java.time.Instant.now(), null));
        assertThrows(IllegalArgumentException.class,
                () -> new Message(UUID.randomUUID(), null, "Hi", MessageStatus.PENDING, java.time.Instant.now(), null));
        assertThrows(IllegalArgumentException.class,
                () -> Message.pending(contactId, "   "));
    }
}
