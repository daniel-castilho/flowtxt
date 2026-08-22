package ca.flowtxt.infrastructure.config.properties;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * JWT configuration. Binding-time constraints live in
 * {@code StartupConfigValidator} instead of Bean Validation annotations so
 * every configuration failure surfaces as one aggregated, actionable boot
 * report (and the infrastructure module needs no extra validation
 * dependency). Production must set JWT_SECRET via the environment
 * (Twelve-Factor factor 3).
 */
@ConfigurationProperties(prefix = "jwt")
public record JwtProperties(
        String secret,
        long expirationMs
) {
}
