package ca.flowtxt.infrastructure.security.filter;

import ca.flowtxt.infrastructure.config.properties.RateLimitProperties;
import ca.flowtxt.infrastructure.security.ratelimit.FixedWindowRateLimiter;
import ca.flowtxt.infrastructure.security.ratelimit.RateLimitVerdict;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Per-client rate limiting for sensitive endpoints (default: {@code /auth/login}).
 *
 * <p>The client key is the first value of the configured forwarded header
 * ({@code X-Forwarded-For}) when present — set by the proxy/ALB in
 * production — otherwise the remote address, combined with method and path.
 * Counters live behind {@link FixedWindowRateLimiter} (Redis, shared across
 * replicas). When the limit is exceeded the filter answers 429 with a
 * {@code Retry-After} header and stops the chain, so rejected brute-force
 * traffic never reaches credentials checking.</p>
 */
@Component
public final class RateLimitFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(RateLimitFilter.class);

    /** Key namespace per coding-standards §6: flowtxt:<purpose>:<id>. */
    static final String KEY_PREFIX = "flowtxt:ratelimit:";
    private static final String RETRY_AFTER_HEADER = "Retry-After";
    private static final String THROTTLED_MESSAGE = "Too many requests. Please try again later.";

    private final RateLimitProperties properties;
    private final FixedWindowRateLimiter rateLimiter;

    public RateLimitFilter(RateLimitProperties properties, FixedWindowRateLimiter rateLimiter) {
        this.properties = properties;
        this.rateLimiter = rateLimiter;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !properties.enabled() || !properties.paths().contains(request.getRequestURI());
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        String key = clientKey(request) + "|" + request.getMethod() + "|" + request.getRequestURI();
        RateLimitVerdict verdict = rateLimiter.tryAcquire(KEY_PREFIX + key);

        if (!verdict.allowed()) {
            log.warn("Rate limit exceeded on {} {} (retry after {}s)",
                    request.getMethod(), request.getRequestURI(), verdict.retryAfterSeconds());
            respondTooManyRequests(response, verdict.retryAfterSeconds());
            return;
        }

        filterChain.doFilter(request, response);
    }

    private void respondTooManyRequests(HttpServletResponse response, long retryAfterSeconds)
            throws IOException {
        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setHeader(RETRY_AFTER_HEADER, Long.toString(retryAfterSeconds));
        response.setContentType("text/plain;charset=UTF-8");
        response.getWriter().write(THROTTLED_MESSAGE);
    }

    private String clientKey(HttpServletRequest request) {
        String forwarded = request.getHeader(properties.clientIpHeader());
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
