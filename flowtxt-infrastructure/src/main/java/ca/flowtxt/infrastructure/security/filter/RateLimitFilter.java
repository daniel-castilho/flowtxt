package ca.flowtxt.infrastructure.security.filter;

import ca.flowtxt.infrastructure.config.properties.RateLimitProperties;
import ca.flowtxt.infrastructure.security.handler.RestErrorResponseWriter;
import ca.flowtxt.infrastructure.security.ratelimit.FixedWindowRateLimiter;
import ca.flowtxt.infrastructure.security.ratelimit.RateLimitVerdict;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.lang.NonNull;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Per-client rate limiting for sensitive endpoints (default: {@code /auth/login}).
 *
 * <p>The client key is the first value of the configured forwarded header
 * ({@code X-Forwarded-For}) when present — set by the proxy/ALB in production —
 * otherwise the remote address, combined with method and path. Counters live
 * behind {@link FixedWindowRateLimiter} (Redis, shared across replicas). When
 * the limit is exceeded the filter answers 429 with a {@code Retry-After}
 * header and the canonical JSON error envelope, stopping the chain so rejected
 * brute-force traffic never reaches credential checking.</p>
 */
@Component
public final class RateLimitFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(RateLimitFilter.class);

    /** Key namespace per coding-standards §6: flowtxt:&lt;purpose&gt;:&lt;id&gt;. */
    static final String KEY_PREFIX = "flowtxt:ratelimit:";
    private static final String RETRY_AFTER_HEADER = "Retry-After";
    private static final String THROTTLED_MESSAGE = "Too many requests. Please try again later.";

    private final RateLimitProperties properties;
    private final FixedWindowRateLimiter rateLimiter;
    private final RestErrorResponseWriter errorResponseWriter;

    public RateLimitFilter(
            RateLimitProperties properties,
            FixedWindowRateLimiter rateLimiter,
            RestErrorResponseWriter errorResponseWriter) {
        this.properties = properties;
        this.rateLimiter = rateLimiter;
        this.errorResponseWriter = errorResponseWriter;
    }

    @Override
    protected boolean shouldNotFilter(@NonNull HttpServletRequest request) {
        return !properties.enabled() || !properties.paths().contains(request.getRequestURI());
    }

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {

        final String key = clientKey(request) + "|" + request.getMethod() + "|" + request.getRequestURI();
        final RateLimitVerdict verdict = rateLimiter.tryAcquire(KEY_PREFIX + key);

        if (!verdict.allowed()) {
            log.warn("Rate limit exceeded on {} {} (retry after {}s)",
                    request.getMethod(), request.getRequestURI(), verdict.retryAfterSeconds());
            response.setHeader(RETRY_AFTER_HEADER, Long.toString(verdict.retryAfterSeconds()));
            errorResponseWriter.write(
                    request,
                    response,
                    HttpStatus.TOO_MANY_REQUESTS,
                    "Too Many Requests",
                    THROTTLED_MESSAGE);
            return;
        }

        filterChain.doFilter(request, response);
    }

    private String clientKey(HttpServletRequest request) {
        final String forwarded = request.getHeader(properties.clientIpHeader());
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
