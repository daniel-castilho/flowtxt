package ca.flowtxt.infrastructure.persistence.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.util.UUID;

/**
 * JPA entity for the {@code contacts} table. The domain {@code Contact} is
 * immutable; this mutable entity is the persistence representation only.
 */
@Entity
@Table(name = "contacts")
public class ContactEntity {

    @Id
    private UUID id;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false, unique = true)
    private String phoneNumber;

    protected ContactEntity() {
        // JPA
    }

    public ContactEntity(UUID id, String name, String phoneNumber) {
        this.id = id;
        this.name = name;
        this.phoneNumber = phoneNumber;
    }

    public UUID getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public String getPhoneNumber() {
        return phoneNumber;
    }
}
