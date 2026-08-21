package ca.flowtxt.domain.model;

import java.time.Instant;
import java.util.UUID;

/**
 * Registered application user. The password is stored ONLY as a hash produced
 * by the PasswordHasher port — never as plaintext. Immutable: role changes
 * would be modelled as a new instance. Entities are compared by identity
 * ({@code id}), not by field state.
 */
public final class User {

    private final UUID id;
    private final String email;
    private final String passwordHash;
    private final Role role;
    private final Instant createdAt;

    /**
     * Rehydration constructor used by persistence mappers and tests.
     */
    public User(
            final UUID id,
            final String email,
            final String passwordHash,
            final Role role,
            final Instant createdAt) {
        if (id == null) {
            throw new IllegalArgumentException("User id is required");
        }
        if (email == null || email.isBlank()) {
            throw new IllegalArgumentException("User email cannot be null or blank");
        }
        if (passwordHash == null || passwordHash.isBlank()) {
            throw new IllegalArgumentException("User password hash cannot be null or blank");
        }
        if (role == null) {
            throw new IllegalArgumentException("User role is required");
        }
        if (createdAt == null) {
            throw new IllegalArgumentException("User creation timestamp is required");
        }
        this.id = id;
        this.email = email;
        this.passwordHash = passwordHash;
        this.role = role;
        this.createdAt = createdAt;
    }

    /**
     * Registers a new user with the default USER role.
     */
    public static User register(final String email, final String passwordHash) {
        return new User(UUID.randomUUID(), email, passwordHash, Role.USER, Instant.now());
    }

    public UUID getId() {
        return id;
    }

    public String getEmail() {
        return email;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public Role getRole() {
        return role;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    @Override
    public boolean equals(Object obj) {
        return obj instanceof User other && id.equals(other.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }
}
