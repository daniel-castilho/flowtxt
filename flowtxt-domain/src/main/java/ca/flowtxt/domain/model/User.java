package ca.flowtxt.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

/**
 * Registered application user. The password is stored ONLY as a hash produced
 * by the PasswordHasher port — never as plaintext.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class User {

    private UUID id;
    private String email;
    private String passwordHash;
    private Role role;
    private Instant createdAt;
}
