package ca.flowtxt.domain.model;

import java.util.UUID;

/**
 * A person the application can send messages to. Immutable: contact data is
 * fixed at creation; corrections are modelled as a new contact. Entities are
 * compared by identity ({@code id}), not by field state.
 */
public final class Contact {

    private final UUID id;
    private final String name;
    private final PhoneNumber phoneNumber;

    /**
     * Rehydration constructor used by persistence mappers and tests.
     */
    public Contact(final UUID id, final String name, final PhoneNumber phoneNumber) {
        if (id == null) {
            throw new IllegalArgumentException("Contact id is required");
        }
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Contact name cannot be null or blank");
        }
        if (phoneNumber == null) {
            throw new IllegalArgumentException("Contact phone number is required");
        }
        this.id = id;
        this.name = name;
        this.phoneNumber = phoneNumber;
    }

    /**
     * Registers a new contact, generating its identity.
     */
    public static Contact create(final String name, final PhoneNumber phoneNumber) {
        return new Contact(UUID.randomUUID(), name, phoneNumber);
    }

    public UUID getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public PhoneNumber getPhoneNumber() {
        return phoneNumber;
    }

    @Override
    public boolean equals(Object obj) {
        return obj instanceof Contact other && id.equals(other.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }
}
