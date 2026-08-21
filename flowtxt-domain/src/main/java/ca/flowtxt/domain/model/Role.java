package ca.flowtxt.domain.model;

/**
 * Application roles. Kept minimal: a plain USER can manage contacts and send
 * messages; ADMIN is reserved for future administrative endpoints.
 */
public enum Role {
    USER,
    ADMIN
}
