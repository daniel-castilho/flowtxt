package ca.flowtxt.infrastructure.config.properties;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

import java.time.Duration;
import java.util.List;

/**
 * Externalised configuration for per-client rate limiting on sensitive
 * endpoints (Twelve-Factor factor 3). Defaults are baked in so the app boots
 * safely without configuration; operators override them via the RATE_LIMIT_*
 * environment variables (see application.yaml).
 */
@ConfigurationProperties(prefix = "rate-limit")
public record RateLimitProperties(
        @DefaultValue("true") boolean enabled,
        @DefaultValue("20") int limit,
        @DefaultValue("1m") Duration window,
        @DefaultValue({"/auth/login"}) List<String> paths,
        @DefaultValue("X-Forwarded-For") String clientIpHeader
) {

    public RateLimitProperties {
        paths = paths == null ? List.of() : List.copyOf(paths);
    }

    @Override
    public List<String> paths() {
        return List.copyOf(paths);
    }
}
