package ca.flowtxt.infrastructure.cache;

import ca.flowtxt.application.port.out.CacheService;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Duration;

@Component
public class RedisCacheAdapter implements CacheService {

    private final RedisTemplate<String, Object> redisTemplate;

    public RedisCacheAdapter(RedisTemplate<String, Object> redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    @Override
    public void put(final String key, final Object value, final Duration ttl) {
        if (ttl == null || ttl.isNegative() || ttl.isZero()) {
            throw new IllegalArgumentException(
                    "Cache TTL must be positive — unbounded keys are not allowed (coding-standards §6)");
        }
        redisTemplate.opsForValue().set(key, value, ttl);
    }

    @Override
    public Object get(final String key) {
        return redisTemplate.opsForValue().get(key);
    }

    @Override
    public void remove(final String key) {
        redisTemplate.delete(key);
    }
}
