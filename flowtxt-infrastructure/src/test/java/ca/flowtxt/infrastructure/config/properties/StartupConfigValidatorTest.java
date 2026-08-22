package ca.flowtxt.infrastructure.config.properties;

import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class StartupConfigValidatorTest {

    private static final String VALID_SECRET =
            "a-production-secret-that-is-long-enough-for-hs256-signing!!";

    @Test
    void acceptsTheDevDefaultsInDev() {
        MockEnvironment env = new MockEnvironment().withProperty("spring.profiles.active", "dev");

        assertDoesNotThrow(() -> new StartupConfigValidator(env,
                new JwtProperties(StartupConfigValidator.DEV_SECRET_PLACEHOLDER, 3600000L),
                new TwilioProperties("", "", "")));
    }

    @Test
    void treatsNoActiveProfileAsDev() {
        assertDoesNotThrow(() -> new StartupConfigValidator(new MockEnvironment(),
                new JwtProperties(StartupConfigValidator.DEV_SECRET_PLACEHOLDER, 3600000L),
                new TwilioProperties("", "", "")));
    }

    @Test
    void rejectsTheDevSecretPlaceholderOutsideDev() {
        MockEnvironment env = prod();

        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> new StartupConfigValidator(env,
                        new JwtProperties(StartupConfigValidator.DEV_SECRET_PLACEHOLDER, 3600000L),
                        new TwilioProperties("AC" + "0".repeat(32), "token", "+15005550000")));

        assertTrue(ex.getMessage().contains("dev-only placeholder"));
    }

    @Test
    void rejectsShortSecretsEvenInDev() {
        MockEnvironment env = new MockEnvironment().withProperty("spring.profiles.active", "dev");

        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> new StartupConfigValidator(env,
                        new JwtProperties("too-short", 3600000L),
                        new TwilioProperties("", "", "")));

        assertTrue(ex.getMessage().contains("at least 32 bytes"));
    }

    @Test
    void rejectsUnresolvedPlaceholdersEvenInDev() {
        MockEnvironment env = new MockEnvironment().withProperty("spring.profiles.active", "dev");

        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> new StartupConfigValidator(env,
                        new JwtProperties("${JWT_SECRET}", 3600000L),
                        new TwilioProperties("", "", "")));

        assertTrue(ex.getMessage().contains("unresolved placeholder"));
    }

    @Test
    void aggregatesEveryMissingTwilioFieldOutsideDevIntoOneReport() {
        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> new StartupConfigValidator(prod(),
                        new JwtProperties(VALID_SECRET, 3600000L),
                        new TwilioProperties("", "", "")));

        String message = ex.getMessage();
        assertTrue(message.startsWith("Refusing to start — invalid configuration"));
        assertTrue(message.contains("twilio.account-sid"));
        assertTrue(message.contains("twilio.auth-token"));
        assertTrue(message.contains("twilio.phone-number"));
    }

    @Test
    void rejectsANonE164OriginNumberOutsideDev() {
        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> new StartupConfigValidator(prod(),
                        new JwtProperties(VALID_SECRET, 3600000L),
                        new TwilioProperties("AC" + "0".repeat(32), "token", "15005550000")));

        assertTrue(ex.getMessage().contains("must be E.164"));
    }

    @Test
    void acceptsAFullyValidProductionConfiguration() {
        assertDoesNotThrow(() -> new StartupConfigValidator(prod(),
                new JwtProperties(VALID_SECRET, 3600000L),
                new TwilioProperties("AC" + "0".repeat(32), "auth-token", "+15005550000")));
    }

    private MockEnvironment prod() {
        return new MockEnvironment().withProperty("spring.profiles.active", "prod");
    }
}
