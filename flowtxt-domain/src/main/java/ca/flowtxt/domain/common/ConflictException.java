package ca.flowtxt.domain.common;

/**
 * Raised when an operation conflicts with the current state of an aggregate
 * (duplicate natural key, stale optimistic-lock, etc.). The API edge maps this
 * to HTTP 409. Lives in the domain so use cases can express the conflict
 * without depending on web or infrastructure types.
 */
public class ConflictException extends RuntimeException {

    public ConflictException(final String message) {
        super(message);
    }
}
