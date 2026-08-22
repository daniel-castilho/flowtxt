package ca.flowtxt.infrastructure.config.properties;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Twilio credentials and origin number. Deliberately NOT validated at bind
 * time: dev/test profiles legitimately run with blanks (the real Twilio
 * adapter is {@code @Profile("prod")}); {@code StartupConfigValidator}
 * enforces the strict rules contextually, outside dev.
 */
@ConfigurationProperties(prefix = "twilio")
public record TwilioProperties(
        String accountSid,
        String authToken,
        String phoneNumber
) {
}
