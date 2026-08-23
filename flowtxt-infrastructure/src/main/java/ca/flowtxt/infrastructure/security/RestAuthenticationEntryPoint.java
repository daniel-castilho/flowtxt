package ca.flowtxt.infrastructure.security;

import ca.flowtxt.infrastructure.security.handler.RestErrorResponseWriter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Emits the canonical {@link ca.flowtxt.infrastructure.web.dto.response.ErrorResponse}
 * envelope with a 401 status when a protected endpoint is reached without valid
 * authentication. Replaces Spring Security's bare {@code HttpStatusEntryPoint}
 * so 401 responses share the API's JSON shape.
 */
@Component
public class RestAuthenticationEntryPoint implements AuthenticationEntryPoint {

    private final RestErrorResponseWriter errorResponseWriter;

    public RestAuthenticationEntryPoint(RestErrorResponseWriter errorResponseWriter) {
        this.errorResponseWriter = errorResponseWriter;
    }

    @Override
    public void commence(
            final HttpServletRequest request,
            final HttpServletResponse response,
            final AuthenticationException authException) throws IOException {
        errorResponseWriter.write(
                request,
                response,
                HttpStatus.UNAUTHORIZED,
                "Unauthorized",
                "Authentication is required to access this resource");
    }
}
