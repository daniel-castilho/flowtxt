package ca.flowtxt.infrastructure.security;

import ca.flowtxt.infrastructure.security.handler.RestErrorResponseWriter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.lang.NonNull;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;

/**
 * Enforces Twilio's request signature on {@code /webhook/twilio/**}.
 *
 * <p>The route itself is permitAll in SecurityConfig (callbacks carry no
 * bearer token); this filter is what keeps it from being open to the world.
 * It fails closed: a missing or invalid signature - or an unconfigured auth
 * token - is answered with a canonical 403 envelope before the request reaches
 * any controller.</p>
 *
 * <p>Deployed behind a proxy, the application must see the same public URL
 * Twilio dialled (e.g. via forwarded-header handling); the signature is
 * computed over the full request URL.</p>
 */
public final class TwilioSignatureValidationFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(TwilioSignatureValidationFilter.class);

    private static final String SIGNATURE_HEADER = "X-Twilio-Signature";
    private static final String WEBHOOK_PATH_PREFIX = "/webhook/twilio/";

    private final String authToken;
    private final RestErrorResponseWriter errorResponseWriter;

    public TwilioSignatureValidationFilter(
            @Value("${twilio.auth-token:}") String authToken,
            RestErrorResponseWriter errorResponseWriter) {
        this.authToken = authToken == null ? "" : authToken;
        this.errorResponseWriter = errorResponseWriter;
    }

    @Override
    protected boolean shouldNotFilter(@NonNull HttpServletRequest request) {
        return !request.getRequestURI().startsWith(WEBHOOK_PATH_PREFIX);
    }

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {

        if (authToken.isBlank()) {
            log.warn("Rejecting Twilio callback: twilio.auth-token is not configured");
            reject(request, response, "Twilio auth token is not configured");
            return;
        }

        final String received = request.getHeader(SIGNATURE_HEADER);
        final String expected = TwilioSignatures.sign(
                authToken, buildFullUrl(request), singleValuedParams(request));

        if (received == null || !TwilioSignatures.matches(expected, received)) {
            log.warn("Rejected Twilio callback with missing or invalid signature");
            reject(request, response, "Invalid or missing Twilio signature");
            return;
        }

        filterChain.doFilter(request, response);
    }

    private void reject(HttpServletRequest request, HttpServletResponse response, String message)
            throws IOException {
        errorResponseWriter.write(
                request,
                response,
                HttpStatus.FORBIDDEN,
                "Forbidden",
                message);
    }

    private String buildFullUrl(HttpServletRequest request) {
        StringBuilder url = new StringBuilder(request.getRequestURL());
        String query = request.getQueryString();
        if (query != null && !query.isBlank()) {
            url.append('?').append(query);
        }
        return url.toString();
    }

    private Map<String, String> singleValuedParams(HttpServletRequest request) {
        Map<String, String> params = new HashMap<>();
        request.getParameterMap()
                .forEach((name, values) -> {
                    if (values.length > 0) {
                        params.put(name, values[0]);
                    }
                });
        return params;
    }
}
