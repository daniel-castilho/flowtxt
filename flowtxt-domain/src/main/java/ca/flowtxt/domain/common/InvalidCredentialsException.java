package ca.flowtxt.domain.common;

/**
 * Raised when authentication fails (unknown account or wrong password). The
 * message is deliberately generic so the API does not reveal whether an email
 * is registered. The API edge maps this to HTTP 401.
 */
public class InvalidCredentialsException extends RuntimeException {

    public InvalidCredentialsException() {
        super("Invalid credentials");
    }

    public InvalidCredentialsException(final String message) {
        super(message);
    }
}
