package ca.flowtxt.infrastructure.security.ratelimit;

import ca.flowtxt.infrastructure.config.properties.RateLimitProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Fixed-window rate limiter backed by Redis.
 *
 * <p>Each hit atomically increments a per-key counter and, on the first hit
 * of a window, sets its TTL (single Lua script — no orphan keys without an
 * expiry, per coding-standards §6). A hit is allowed while the count is
 * within {@code rate-limit.limit}; the window rolls over when the key
 * expires. Because counters live in Redis, the limit holds across replicas
 * (Twelve-Factor factor 6).</p>
 *
 * <p><strong>Fail-open:</strong> if Redis is unavailable the hit is allowed
 * and the failure logged. Throttling is best-effort protection — locking all
 * logins out because of a cache outage would hurt availability more than the
 * attack it prevents.</p>
 */
@Component
public final class FixedWindowRateLimiter {

    private static final Logger log = LoggerFactory.getLogger(FixedWindowRateLimiter.class);

    /**
     * Increments the counter at KEYS[1] and expires it after ARGV[1]
     * milliseconds on the first hit of a window. Returns {hits, ttl-millis}.
     */
    private static final RedisScript<List> FIXED_WINDOW_SCRIPT = RedisScript.of("""
            local hits = redis.call('INCR', KEYS[1])
            if hits == 1 then
                redis.call('PEXPIRE', KEYS[1], ARGV[1])
            end
            return {hits, redis.call('PTTL', KEYS[1])}
            """, List.class);

    private final StringRedisTemplate redisTemplate;
    private final RateLimitProperties properties;

    public FixedWindowRateLimiter(StringRedisTemplate redisTemplate, RateLimitProperties properties) {
        this.redisTemplate = redisTemplate;
        this.properties = properties;
    }

    /**
     * Records one hit for {@code key} inside the configured fixed window.
     *
     * @param key namespaced client identity (e.g. {@code flowtxt:ratelimit:ip|method|path})
     * @return whether the hit is within the limit; rejected verdicts carry the
     *         remaining time until the window resets
     */
    public RateLimitVerdict tryAcquire(final String key) {
        try {
            List<?> reply = redisTemplate.execute(
                    FIXED_WINDOW_SCRIPT, List.of(key), String.valueOf(properties.window().toMillis()));

            if (reply == null || reply.size() < 2) {
                log.warn("Rate limiter got an unexpected Redis reply for key {}; allowing the request", key);
                return RateLimitVerdict.allow();
            }

            long hits = ((Number) reply.get(0)).longValue();
            long ttlMillis = ((Number) reply.get(1)).longValue();
            return hits <= properties.limit()
                    ? RateLimitVerdict.allow()
                    : RateLimitVerdict.reject(retryAfterSeconds(ttlMillis));
        } catch (DataAccessException ex) {
            log.warn("Rate limiter could not reach Redis ({}); allowing the request", ex.getMessage());
            return RateLimitVerdict.allow();
        }
    }

    private long retryAfterSeconds(long ttlMillis) {
        long seconds = ttlMillis > 0 ? (ttlMillis + 999) / 1000 : properties.window().toSeconds();
        return Math.max(1, seconds);
    }
}
