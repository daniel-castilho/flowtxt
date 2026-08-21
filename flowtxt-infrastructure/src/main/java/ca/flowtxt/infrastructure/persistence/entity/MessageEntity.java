package ca.flowtxt.infrastructure.persistence.entity;

import ca.flowtxt.domain.model.MessageStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity for the {@code messages} table.
 *
 * <p>The {@code contact_id} column is a plain UUID column with a foreign key
 * enforced by the Flyway DDL — the domain {@link ca.flowtxt.domain.model.Message}
 * is immutable and holds only {@code contactId}, so no JPA association is
 * mapped (a {@code @ManyToOne} would force an unnecessary fetch and muddy the
 * mapper). Referential integrity lives in the database, where it belongs.</p>
 *
 * <p>{@code @Version} provides optimistic locking: concurrent delivery-status
 * callbacks cannot silently overwrite each other's status update.</p>
 */
@Entity
@Table(name = "messages")
public class MessageEntity {

    @Id
    private UUID id;

    @Column(name = "contact_id", nullable = false)
    private UUID contactId;

    @Column(nullable = false)
    private String content;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private MessageStatus status;

    @Column(nullable = false)
    private Instant timestamp;

    @Column(unique = true)
    private String sid;

    @Version
    @Column(nullable = false)
    private long version;

    protected MessageEntity() {
        // JPA
    }

    public MessageEntity(
            UUID id,
            UUID contactId,
            String content,
            MessageStatus status,
            Instant timestamp,
            String sid) {
        this.id = id;
        this.contactId = contactId;
        this.content = content;
        this.status = status;
        this.timestamp = timestamp;
        this.sid = sid;
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

    public long getVersion() {
        return version;
    }
}
