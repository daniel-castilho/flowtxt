package ca.flowtxt.infrastructure.cache;

import ca.flowtxt.application.port.out.CacheService;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Component;

@Component
public class RedisCacheAdapter implements CacheService {

    private final RedisTemplate<String, Object> redisTemplate;

    public RedisCacheAdapter(RedisTemplate<String, Object> redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    @Override
    public void put(final String key, final Object value) {
        redisTemplate.opsForValue().set(key, value);
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
