package ca.flowtxt;

import ca.flowtxt.application.port.out.CacheService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class RedisCacheAdapterIT extends AbstractIntegrationTest {

    @Autowired
    private CacheService cacheService;

    @Test
    void putsGetsAndRemovesAValue() {
        cacheService.put("it:key", "it-value");
        assertEquals("it-value", cacheService.get("it:key"));

        cacheService.remove("it:key");
        assertNull(cacheService.get("it:key"));
    }
}
