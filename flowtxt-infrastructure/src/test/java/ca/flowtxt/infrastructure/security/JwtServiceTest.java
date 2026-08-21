package ca.flowtxt.infrastructure.security;

import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JwtServiceTest {

    private static final String SECRET =
            "test-secret-that-is-at-least-32-characters-long-for-hs256";

    private final JwtService jwtService = new JwtService(SECRET, 3600000L);

    private User sampleUser() {
        return new User(
                UUID.randomUUID(),
                "user@example.com",
                "hash",
                Role.USER,
                java.time.Instant.now());
    }

    @Test
    void generatesATokenWithTheUserEmailAsSubject() {
        String token = jwtService.generateToken(sampleUser());

        assertNotNull(token);
        assertEquals("user@example.com", jwtService.extractUsername(token));
    }

    @Test
    void validatesItsOwnToken() {
        String token = jwtService.generateToken(sampleUser());
        assertTrue(jwtService.isValid(token));
    }

    @Test
    void rejectsAnInvalidToken() {
        assertFalse(jwtService.isValid("not-a-token"));
        assertFalse(jwtService.isValid(""));
        assertFalse(jwtService.isValid(null));
    }

    @Test
    void rejectsATamperedToken() {
        String token = jwtService.generateToken(sampleUser());
        String tampered = token.substring(0, token.length() - 4) + "XXXX";
        assertFalse(jwtService.isValid(tampered));
    }

    @Test
    void rejectsATokenSignedWithADifferentSecret() {
        JwtService other = new JwtService(
                "another-secret-that-is-also-long-enough-for-hs256-ok", 3600000L);
        String token = other.generateToken(sampleUser());
        assertFalse(jwtService.isValid(token));
    }
}
