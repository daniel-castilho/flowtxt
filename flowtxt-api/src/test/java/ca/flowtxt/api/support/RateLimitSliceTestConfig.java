package ca.flowtxt.api.support;

import ca.flowtxt.infrastructure.config.properties.RateLimitProperties;
import ca.flowtxt.infrastructure.config.properties.TwilioProperties;
import ca.flowtxt.infrastructure.security.RestAccessDeniedHandler;
import ca.flowtxt.infrastructure.security.RestAuthenticationEntryPoint;
import ca.flowtxt.infrastructure.security.filter.RateLimitFilter;
import ca.flowtxt.infrastructure.security.handler.RestErrorResponseWriter;
import ca.flowtxt.infrastructure.security.ratelimit.FixedWindowRateLimiter;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.data.redis.core.StringRedisTemplate;

import java.time.Duration;
import java.util.List;

import static org.mockito.Mockito.mock;

/**
 * Slice-test wiring for the rate limiting stack. Throttling is disabled here
 * so controller slices exercise the controllers, not throttling — the
 * behaviour itself is covered by {@code RateLimitFilterTest},
 * {@code FixedWindowRateLimiterTest} and {@code LoginRateLimitIT}.
 */
@TestConfiguration(proxyBeanMethods = false)
public class RateLimitSliceTestConfig {

    @Bean
    public RateLimitProperties rateLimitProperties() {
        return new RateLimitProperties(
                false, 20, Duration.ofMinutes(1), List.of("/auth/login"), "X-Forwarded-For");
    }

    /**
     * Blank Twilio token on purpose: the signature filter fails closed per
     * request, matching dev semantics; slices never exercise real webhooks.
     */
    @Bean
    public TwilioProperties twilioProperties() {
        return new TwilioProperties("", "", "");
    }

    @Bean
    public FixedWindowRateLimiter fixedWindowRateLimiter(RateLimitProperties properties) {
        return new FixedWindowRateLimiter(mock(StringRedisTemplate.class), properties);
    }

    @Bean
    public RestErrorResponseWriter restErrorResponseWriter() {
        return mock(RestErrorResponseWriter.class);
    }

    @Bean
    public RateLimitFilter rateLimitFilter(
            RateLimitProperties properties,
            FixedWindowRateLimiter rateLimiter,
            RestErrorResponseWriter errorResponseWriter) {
        return new RateLimitFilter(properties, rateLimiter, errorResponseWriter);
    }

    @Bean
    public RestAuthenticationEntryPoint restAuthenticationEntryPoint(
            RestErrorResponseWriter errorResponseWriter) {
        return new RestAuthenticationEntryPoint(errorResponseWriter);
    }

    @Bean
    public RestAccessDeniedHandler restAccessDeniedHandler(
            RestErrorResponseWriter errorResponseWriter) {
        return new RestAccessDeniedHandler(errorResponseWriter);
    }
}
