package ca.flowtxt.infrastructure.config.properties;

import ca.flowtxt.domain.model.PhoneNumber;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.env.Environment;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Fail-fast configuration guard (Twelve-Factor factor 3): runs at context
 * creation and refuses to boot with an aggregated, actionable report instead
 * of failing later on the first request with a cryptic error.
 *
 * <p>Always enforced: the JWT secret must be present, must not be an
 * unresolved {@code ${...}} placeholder, and must be at least 32 bytes
 * (HS256); the expiration must be positive.</p>
 *
 * <p>Enforced outside dev: the known dev placeholder secret is rejected, and
 * Twilio credentials must be present, placeholder-free, and the origin number
 * must be valid E.164. In dev the Twilio blanks are legitimate (the real
 * adapter only exists in prod), so they only produce a WARN.</p>
 */
public final class StartupConfigValidator {

    private static final Logger log = LoggerFactory.getLogger(StartupConfigValidator.class);

    static final String DEV_SECRET_PLACEHOLDER = "change-me-dev-only-please-use-a-long-random-secret";
    private static final int MIN_SECRET_BYTES = 32;
    private static final Pattern UNRESOLVED_PLACEHOLDER = Pattern.compile("\\$\\{[^}]+}");

    private final Environment environment;
    private final JwtProperties jwt;
    private final TwilioProperties twilio;

    public StartupConfigValidator(Environment environment, JwtProperties jwt, TwilioProperties twilio) {
        this.environment = environment;
        this.jwt = jwt;
        this.twilio = twilio;
        validate();
    }

    private void validate() {
        List<String> errors = new ArrayList<>();
        boolean devMode = !runningOutsideDev();

        if (!hasText(jwt.secret())) {
            errors.add("jwt.secret is required — set the JWT_SECRET env var");
        } else {
            if (UNRESOLVED_PLACEHOLDER.matcher(jwt.secret()).find()) {
                errors.add("jwt.secret contains an unresolved placeholder — set the JWT_SECRET env var");
            }
            if (jwt.secret().getBytes(StandardCharsets.UTF_8).length < MIN_SECRET_BYTES) {
                errors.add("jwt.secret must be at least " + MIN_SECRET_BYTES + " bytes for HS256");
            }
            if (!devMode && DEV_SECRET_PLACEHOLDER.equals(jwt.secret())) {
                errors.add("jwt.secret still uses the dev-only placeholder — set JWT_SECRET "
                        + "(e.g. openssl rand -base64 48)");
            }
        }
        if (jwt.expirationMs() <= 0) {
            errors.add("jwt.expiration-ms must be positive");
        }

        boolean twilioConfigured = hasText(twilio.accountSid()) || hasText(twilio.authToken());
        if (!devMode) {
            if (!hasText(twilio.accountSid())) {
                errors.add("twilio.account-sid is required outside dev — set TWILIO_ACCOUNT_SID");
            }
            if (!hasText(twilio.authToken())) {
                errors.add("twilio.auth-token is required outside dev — set TWILIO_AUTH_TOKEN");
            }
            if (!hasText(twilio.phoneNumber())) {
                errors.add("twilio.phone-number is required outside dev — set TWILIO_PHONE_NUMBER");
            } else if (UNRESOLVED_PLACEHOLDER.matcher(twilio.phoneNumber()).find()) {
                errors.add("twilio.phone-number contains an unresolved placeholder");
            } else {
                try {
                    new PhoneNumber(twilio.phoneNumber());
                } catch (IllegalArgumentException ex) {
                    errors.add("twilio.phone-number must be E.164 (e.g. +15005550000): "
                            + ex.getMessage());
                }
            }
        } else if (twilioConfigured) {
            log.warn("Running in dev with partial Twilio configuration; the fake SMS adapter stays active");
        }

        if (!errors.isEmpty()) {
            throw new IllegalStateException(
                    "Refusing to start — invalid configuration:\n - " + String.join("\n - ", errors));
        }
    }

    /**
     * Dev-like when nothing (or only dev) is explicitly activated; any other
     * profile (prod, staging, ...) gets the strict rules.
     */
    /**
     * Dev-like only when exactly the dev profile is active (nothing active is
     * normalized to dev); any other profile (prod, staging, ...) gets the
     * strict rules.
     */
    private boolean runningOutsideDev() {
        String[] active = environment.getActiveProfiles();
        Set<String> profiles = active.length == 0 ? Set.of("dev") : Set.of(active);
        return !profiles.equals(Set.of("dev"));
    }

    private static boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}
