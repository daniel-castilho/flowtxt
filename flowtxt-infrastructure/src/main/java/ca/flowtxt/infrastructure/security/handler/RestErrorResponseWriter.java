package ca.flowtxt.infrastructure.security.handler;

import ca.flowtxt.infrastructure.web.dto.response.ErrorResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;

import java.io.IOException;

/**
 * Writes the canonical {@link ErrorResponse} envelope directly to an HTTP
 * response. Shared by the security entry point/access-denied handler and the
 * servlet filters (JWT, Twilio signature) so every error path — including
 * those that never reach a controller — produces the same JSON shape as the
 * controller advice.
 */
@Component
public class RestErrorResponseWriter {

    private final ObjectMapper objectMapper;

    public RestErrorResponseWriter(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public void write(
            final HttpServletRequest request,
            final HttpServletResponse response,
            final HttpStatus status,
            final String error,
            final String message) throws IOException {

        final ErrorResponse body = ErrorResponse.of(
                status.value(), error, message, request.getRequestURI());

        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        objectMapper.writeValue(response.getOutputStream(), body);
    }
}
