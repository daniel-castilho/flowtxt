package ca.flowtxt.infrastructure.web.dto.response;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;
import java.util.Map;

/**
 * Canonical error envelope returned by every error path in the API — controller
 * advice, the JWT entry point/filter and the Twilio signature filter. Keeps the
 * JSON shape identical regardless of which layer produced the error, so clients
 * can rely on one contract for status, machine-readable error code, message and
 * (for validation failures) field-level details.
 *
 * <p>{@code validationErrors} is omitted when there are no field errors.</p>
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ErrorResponse(
        Instant timestamp,
        int status,
        String error,
        String message,
        String path,
        Map<String, String> validationErrors
) {
    public static ErrorResponse of(
            final int status,
            final String error,
            final String message,
            final String path) {
        return new ErrorResponse(Instant.now(), status, error, message, path, null);
    }

    public static ErrorResponse validation(
            final int status,
            final String error,
            final String message,
            final String path,
            final Map<String, String> fieldErrors) {
        return new ErrorResponse(Instant.now(), status, error, message, path,
                fieldErrors == null || fieldErrors.isEmpty() ? null : Map.copyOf(fieldErrors));
    }
}
