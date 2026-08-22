package ca.flowtxt.infrastructure.security.ratelimit;

/**
 * Outcome of a single rate-limiter check.
 *
 * @param allowed           whether the hit is within the configured limit
 * @param retryAfterSeconds when rejected, how long until the window resets
 */
public record RateLimitVerdict(boolean allowed, long retryAfterSeconds) {

    public static RateLimitVerdict allow() {
        return new RateLimitVerdict(true, 0);
    }

    public static RateLimitVerdict reject(long retryAfterSeconds) {
        return new RateLimitVerdict(false, retryAfterSeconds);
    }
}
