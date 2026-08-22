package ca.flowtxt.infrastructure.security.ratelimit;

import ca.flowtxt.infrastructure.config.properties.RateLimitProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class FixedWindowRateLimiterTest {

    @Mock
    private StringRedisTemplate redisTemplate;

    private RateLimitProperties properties;

    @BeforeEach
    void setUp() {
        properties = new RateLimitProperties(
                true, 2, Duration.ofMinutes(1), List.of("/auth/login"), "X-Forwarded-For");
    }

    @Test
    void allowsHitsWithinTheLimit() {
        doReturn(List.of(1L, 60_000L)).when(redisTemplate)
                .execute(any(RedisScript.class), anyList(), any());
        FixedWindowRateLimiter limiter = new FixedWindowRateLimiter(redisTemplate, properties);

        RateLimitVerdict verdict = limiter.tryAcquire("flowtxt:ratelimit:k");

        assertTrue(verdict.allowed());
        assertEquals(0, verdict.retryAfterSeconds());
    }

    @Test
    void rejectsHitsBeyondTheLimitAndReportsTheRemainingWindow() {
        doReturn(List.of(3L, 30_000L)).when(redisTemplate)
                .execute(any(RedisScript.class), anyList(), any());
        FixedWindowRateLimiter limiter = new FixedWindowRateLimiter(redisTemplate, properties);

        RateLimitVerdict verdict = limiter.tryAcquire("flowtxt:ratelimit:k");

        assertFalse(verdict.allowed());
        assertEquals(30, verdict.retryAfterSeconds());
    }

    @Test
    void roundsTheRetryAfterUpToTheNextSecond() {
        doReturn(List.of(3L, 1_500L)).when(redisTemplate)
                .execute(any(RedisScript.class), anyList(), any());
        FixedWindowRateLimiter limiter = new FixedWindowRateLimiter(redisTemplate, properties);

        assertEquals(2, limiter.tryAcquire("flowtxt:ratelimit:k").retryAfterSeconds());
    }

    @Test
    void passesTheConfiguredWindowSizeToRedisOnEveryHit() {
        doReturn(List.of(1L, 60_000L)).when(redisTemplate)
                .execute(any(RedisScript.class), anyList(), any());
        FixedWindowRateLimiter limiter = new FixedWindowRateLimiter(redisTemplate, properties);

        limiter.tryAcquire("flowtxt:ratelimit:k");

        verify(redisTemplate).execute(
                any(RedisScript.class),
                eq(List.of("flowtxt:ratelimit:k")),
                eq(String.valueOf(Duration.ofMinutes(1).toMillis())));
    }

    @Test
    void failsOpenWhenRedisIsUnavailable() {
        doThrow(new RedisConnectionFailureException("connection refused")).when(redisTemplate)
                .execute(any(RedisScript.class), anyList(), any());
        FixedWindowRateLimiter limiter = new FixedWindowRateLimiter(redisTemplate, properties);

        RateLimitVerdict verdict = limiter.tryAcquire("flowtxt:ratelimit:k");

        assertTrue(verdict.allowed());
    }

    @Test
    void failsOpenOnAnEmptyReply() {
        doReturn(null).when(redisTemplate)
                .execute(any(RedisScript.class), anyList(), any());
        FixedWindowRateLimiter limiter = new FixedWindowRateLimiter(redisTemplate, properties);

        assertTrue(limiter.tryAcquire("flowtxt:ratelimit:k").allowed());
    }
}
