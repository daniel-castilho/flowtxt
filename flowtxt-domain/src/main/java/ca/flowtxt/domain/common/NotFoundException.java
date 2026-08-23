package ca.flowtxt.domain.common;

/**
 * Raised when a requested aggregate cannot be found. The API edge maps this to
 * HTTP 404. Lives in the domain so application use cases can express a missing
 * entity without depending on web or infrastructure types.
 */
public class NotFoundException extends RuntimeException {

    public NotFoundException(final String message) {
        super(message);
    }
}
