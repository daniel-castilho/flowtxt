package ca.flowtxt.infrastructure.security;

import ca.flowtxt.application.port.out.AuthenticationTokenPort;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.config.properties.JwtProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;

/**
 * Issues and validates JWT bearer tokens (jjwt). The subject is the user's
 * email; the role and user id ride along as claims. The secret comes from
 * validated configuration (environment in production).
 *
 * <p>Implements the application {@link AuthenticationTokenPort} so use cases
 * issue tokens through the port and never depend on this infrastructure class
 * directly. Token <em>validation</em> (parsing incoming requests) remains an
 * infrastructure concern handled by {@link JwtAuthenticationFilter}.</p>
 */
@Component
public final class JwtService implements AuthenticationTokenPort {

    private final SecretKey key;
    private final long expirationMs;

    public JwtService(JwtProperties properties) {
        this.key = Keys.hmacShaKeyFor(properties.secret().getBytes(StandardCharsets.UTF_8));
        this.expirationMs = properties.expirationMs();
    }

    @Override
    public String issueToken(User user) {
        return generateToken(user);
    }

    public String generateToken(User user) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(user.getEmail())
                .claim("uid", user.getId().toString())
                .claim("role", user.getRole().name())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plusMillis(expirationMs)))
                .signWith(key)
                .compact();
    }

    public String extractUsername(String token) {
        return parse(token).getSubject();
    }

    public boolean isValid(String token) {
        try {
            parse(token);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private Claims parse(String token) {
        return Jwts.parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
}
