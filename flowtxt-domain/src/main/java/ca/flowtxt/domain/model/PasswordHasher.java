package ca.flowtxt.domain.model;

/**
 * Outbound port for password hashing. Lives in the domain so the application
 * layer never depends on a concrete hashing library; the adapter (e.g. Spring
 * Security's BCrypt) is wired in infrastructure.
 */
public interface PasswordHasher {

    String hash(String rawPassword);

    boolean matches(String rawPassword, String hashedPassword);
}
