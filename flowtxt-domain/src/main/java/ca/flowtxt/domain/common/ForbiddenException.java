package ca.flowtxt.domain.common;

/**
 * Raised when an authenticated principal is not allowed to perform an
 * operation. The API edge maps this to HTTP 403. Lives in the domain so use
 * cases can express an authorization failure without depending on web or
 * infrastructure types.
 */
public class ForbiddenException extends RuntimeException {

    public ForbiddenException(final String message) {
        super(message);
    }
}
