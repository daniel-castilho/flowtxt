package ca.flowtxt.infrastructure.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SpringSecurityPasswordHasherTest {

    private final SpringSecurityPasswordHasher hasher = new SpringSecurityPasswordHasher();

    @Test
    void hashesWithoutStoringPlaintext() {
        String hash = hasher.hash("s3cret-password");
        assertNotEquals("s3cret-password", hash);
        assertTrue(hash.startsWith("$2"));
    }

    @Test
    void matchesTheOriginalPassword() {
        String hash = hasher.hash("s3cret-password");
        assertTrue(hasher.matches("s3cret-password", hash));
    }

    @Test
    void rejectsAWrongPassword() {
        String hash = hasher.hash("s3cret-password");
        assertTrue(!hasher.matches("wrong-password", hash));
    }
}
