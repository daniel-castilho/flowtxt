package ca.flowtxt.infrastructure.security.filter;

import ca.flowtxt.infrastructure.config.properties.RateLimitProperties;
import ca.flowtxt.infrastructure.security.ratelimit.FixedWindowRateLimiter;
import ca.flowtxt.infrastructure.security.ratelimit.RateLimitVerdict;
import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

import java.io.PrintWriter;
import java.time.Duration;
import java.util.List;

import static org.mockito.Mockito.anyInt;
import static org.mockito.Mockito.anyString;
import static org.mockito.Mockito.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RateLimitFilterTest {

    private static final RateLimitProperties PROPERTIES = new RateLimitProperties(
            true, 20, Duration.ofMinutes(1), List.of("/auth/login"), "X-Forwarded-For");

    @Mock
    private HttpServletRequest request;

    @Mock
    private HttpServletResponse response;

    @Mock
    private FilterChain filterChain;

    @Mock
    private PrintWriter printWriter;

    @Mock
    private FixedWindowRateLimiter rateLimiter;

    private RateLimitFilter filter;

    @BeforeEach
    void setUp() {
        filter = new RateLimitFilter(PROPERTIES, rateLimiter);
    }

    @Test
    void doFilter_withinLimit_continuesChain() throws Exception {
        when(request.getRequestURI()).thenReturn("/auth/login");
        when(request.getMethod()).thenReturn("POST");
        when(request.getRemoteAddr()).thenReturn("10.0.0.5");
        when(rateLimiter.tryAcquire(anyString())).thenReturn(RateLimitVerdict.allow());

        filter.doFilter(request, response, filterChain);

        verify(filterChain).doFilter(request, response);
        verify(response, never()).setStatus(anyInt());
    }

    @Test
    void doFilter_overLimit_writes429WithRetryAfterAndStopsChain() throws Exception {
        when(request.getRequestURI()).thenReturn("/auth/login");
        when(request.getMethod()).thenReturn("POST");
        when(request.getRemoteAddr()).thenReturn("10.0.0.5");
        when(rateLimiter.tryAcquire(anyString())).thenReturn(RateLimitVerdict.reject(42));
        when(response.getWriter()).thenReturn(printWriter);

        filter.doFilter(request, response, filterChain);

        verify(response).setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        verify(response).setHeader("Retry-After", "42");
        verify(printWriter).write("Too many requests. Please try again later.");
        verifyNoInteractions(filterChain);
    }

    @Test
    void doFilter_usesFirstForwardedValueInTheKey() throws Exception {
        when(request.getRequestURI()).thenReturn("/auth/login");
        when(request.getMethod()).thenReturn("POST");
        when(request.getHeader("X-Forwarded-For")).thenReturn("203.0.113.9, 10.0.0.1");
        when(rateLimiter.tryAcquire(anyString())).thenReturn(RateLimitVerdict.allow());

        filter.doFilter(request, response, filterChain);

        verify(rateLimiter).tryAcquire(eq("flowtxt:ratelimit:203.0.113.9|POST|/auth/login"));
    }

    @Test
    void doFilter_whenDisabled_continuesChainWithoutThrottling() throws Exception {
        RateLimitProperties disabled = new RateLimitProperties(
                false, 20, Duration.ofMinutes(1), List.of("/auth/login"), "X-Forwarded-For");
        RateLimitFilter disabledFilter = new RateLimitFilter(disabled, rateLimiter);

        disabledFilter.doFilter(request, response, filterChain);

        verify(filterChain).doFilter(request, response);
        verifyNoInteractions(rateLimiter);
    }

    @Test
    void doFilter_unprotectedPath_continuesChainWithoutThrottling() throws Exception {
        when(request.getRequestURI()).thenReturn("/contacts");

        filter.doFilter(request, response, filterChain);

        verify(filterChain).doFilter(request, response);
        verifyNoInteractions(rateLimiter);
    }
}
