package ca.flowtxt.infrastructure.cache;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RedisCacheAdapterTest {

    @Mock
    private RedisTemplate<String, Object> redisTemplate;

    @Mock
    private ValueOperations<String, Object> valueOperations;

    @Test
    void putsAValueWithItsTtlInRedis() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        RedisCacheAdapter adapter = new RedisCacheAdapter(redisTemplate);

        adapter.put("key", "value", Duration.ofMinutes(5));

        verify(valueOperations).set("key", "value", Duration.ofMinutes(5));
    }

    @Test
    void rejectsNullAndNonPositiveTtls() {
        RedisCacheAdapter adapter = new RedisCacheAdapter(redisTemplate);

        assertThrows(IllegalArgumentException.class, () -> adapter.put("k", "v", null));
        assertThrows(IllegalArgumentException.class, () -> adapter.put("k", "v", Duration.ZERO));
        assertThrows(IllegalArgumentException.class,
                () -> adapter.put("k", "v", Duration.ofSeconds(-1)));
    }

    @Test
    void getsAValueFromRedis() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.get("key")).thenReturn("cached");
        RedisCacheAdapter adapter = new RedisCacheAdapter(redisTemplate);

        assertEquals("cached", adapter.get("key"));
    }

    @Test
    void removesAValueFromRedis() {
        RedisCacheAdapter adapter = new RedisCacheAdapter(redisTemplate);

        adapter.remove("key");

        verify(redisTemplate).delete(anyString());
    }
}
