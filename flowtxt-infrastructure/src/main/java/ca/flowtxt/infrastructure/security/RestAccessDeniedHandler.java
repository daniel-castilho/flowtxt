package ca.flowtxt.infrastructure.security;

import ca.flowtxt.infrastructure.security.handler.RestErrorResponseWriter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Emits the canonical {@link ca.flowtxt.infrastructure.web.dto.response.ErrorResponse}
 * envelope with a 403 status when an authenticated principal lacks the required
 * authority.
 */
@Component
public class RestAccessDeniedHandler implements AccessDeniedHandler {

    private final RestErrorResponseWriter errorResponseWriter;

    public RestAccessDeniedHandler(RestErrorResponseWriter errorResponseWriter) {
        this.errorResponseWriter = errorResponseWriter;
    }

    @Override
    public void handle(
            final HttpServletRequest request,
            final HttpServletResponse response,
            final AccessDeniedException accessDeniedException) throws IOException {
        errorResponseWriter.write(
                request,
                response,
                HttpStatus.FORBIDDEN,
                "Forbidden",
                "You do not have permission to access this resource");
    }
}
