package ca.flowtxt.domain.model;

import java.time.Instant;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * An outbound SMS message. Immutable by design: every lifecycle change
 * produces a new instance, so a message can never be corrupted by stray
 * setters and is safe to share across layers and threads.
 *
 * <p>Status follows a forward-only lifecycle enforced here (not in the use
 * cases): {@code PENDING -> QUEUED -> SENT -> DELIVERED/UNDELIVERED/FAILED}.
 * Provider callbacks may always report {@link MessageStatus#UNKNOWN} without
 * breaking the flow. Replaying the current status is an idempotent no-op;
 * anything else outside the table raises {@link IllegalStateException}.</p>
 *
 * <p>Entities are compared by identity ({@code id}), not by field state.</p>
 */
public final class Message {

    private static final Map<MessageStatus, Set<MessageStatus>> ALLOWED_TRANSITIONS = buildTransitions();

    private final UUID id;
    private final UUID contactId;
    private final String content;
    private final MessageStatus status;
    private final Instant timestamp;
    private final String sid;

    /**
     * Rehydration constructor used by persistence mappers. Enforces presence
     * of essential state but never lifecycle rules — stored messages may hold
     * any persisted status.
     */
    public Message(
            final UUID id,
            final UUID contactId,
            final String content,
            final MessageStatus status,
            final Instant timestamp,
            final String sid) {
        if (id == null) {
            throw new IllegalArgumentException("Message id is required");
        }
        if (contactId == null) {
            throw new IllegalArgumentException("Message contact reference is required");
        }
        if (content == null || content.isBlank()) {
            throw new IllegalArgumentException("Message content cannot be null or blank");
        }
        if (status == null) {
            throw new IllegalArgumentException("Message status is required");
        }
        if (timestamp == null) {
            throw new IllegalArgumentException("Message timestamp is required");
        }
        this.id = id;
        this.contactId = contactId;
        this.content = content;
        this.status = status;
        this.timestamp = timestamp;
        this.sid = sid;
    }

    /**
     * Starts the lifecycle of a new outbound message in the PENDING state.
     */
    public static Message pending(final UUID contactId, final String content) {
        return new Message(UUID.randomUUID(), contactId, content, MessageStatus.PENDING, Instant.now(), null);
    }

    public Message markSent(final String providerSid) {
        if (providerSid == null || providerSid.isBlank()) {
            throw new IllegalArgumentException("A sent message requires a provider SID");
        }
        return transition(MessageStatus.SENT, providerSid);
    }

    public Message markFailed() {
        return transition(MessageStatus.FAILED, null);
    }

    /**
     * Applies a delivery-status callback reported by the SMS provider. Unknown
     * provider values must already be mapped to {@link MessageStatus#UNKNOWN}
     * at the boundary; they are accepted from any state so that odd callbacks
     * neither break the flow nor lose information.
     */
    public Message applyProviderStatus(final MessageStatus providerStatus, final String providerSid) {
        return transition(providerStatus, providerSid);
    }

    private Message transition(final MessageStatus target, final String reportedSid) {
        if (target == status) {
            return this;
        }
        if (!ALLOWED_TRANSITIONS.get(status).contains(target)) {
            throw new IllegalStateException(
                    "Invalid message status transition from %s to %s (message %s)".formatted(status, target, id));
        }
        return new Message(
                id,
                contactId,
                content,
                target,
                timestamp,
                reportedSid != null && !reportedSid.isBlank() ? reportedSid : sid);
    }

    private static Map<MessageStatus, Set<MessageStatus>> buildTransitions() {
        Map<MessageStatus, Set<MessageStatus>> transitions = new EnumMap<>(MessageStatus.class);
        transitions.put(MessageStatus.PENDING, EnumSet.of(MessageStatus.QUEUED, MessageStatus.SENT,
                MessageStatus.FAILED, MessageStatus.UNKNOWN));
        transitions.put(MessageStatus.QUEUED, EnumSet.of(MessageStatus.SENT, MessageStatus.UNDELIVERED,
                MessageStatus.FAILED, MessageStatus.UNKNOWN));
        transitions.put(MessageStatus.SENT, EnumSet.of(MessageStatus.DELIVERED, MessageStatus.UNDELIVERED,
                MessageStatus.FAILED, MessageStatus.UNKNOWN));
        transitions.put(MessageStatus.DELIVERED, EnumSet.of(MessageStatus.UNKNOWN));
        transitions.put(MessageStatus.UNDELIVERED, EnumSet.of(MessageStatus.UNKNOWN));
        transitions.put(MessageStatus.FAILED, EnumSet.of(MessageStatus.UNKNOWN));
        transitions.put(MessageStatus.RECEIVED, EnumSet.of(MessageStatus.UNKNOWN));
        transitions.put(MessageStatus.UNKNOWN, EnumSet.noneOf(MessageStatus.class));
        return Map.copyOf(transitions);
    }

    public UUID getId() {
        return id;
    }

    public UUID getContactId() {
        return contactId;
    }

    public String getContent() {
        return content;
    }

    public MessageStatus getStatus() {
        return status;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    public String getSid() {
        return sid;
    }

    @Override
    public boolean equals(Object obj) {
        return obj instanceof Message other && id.equals(other.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }
}
