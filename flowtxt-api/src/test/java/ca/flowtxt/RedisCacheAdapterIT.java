package ca.flowtxt;

import ca.flowtxt.application.port.out.CacheService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.Duration;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class RedisCacheAdapterIT extends AbstractIntegrationTest {

    @Autowired
    private CacheService cacheService;

    @Test
    void putsGetsAndRemovesAValue() {
        cacheService.put("it:key", "it-value", Duration.ofMinutes(5));
        assertEquals("it-value", cacheService.get("it:key"));

        cacheService.remove("it:key");
        assertNull(cacheService.get("it:key"));
    }

    @Test
    void expiresEntriesWhenTheTtlElapses() throws InterruptedException {
        cacheService.put("it:expiring", "fleeting", Duration.ofMillis(150));

        assertEquals("fleeting", cacheService.get("it:expiring"));

        Thread.sleep(400);
        assertNull(cacheService.get("it:expiring"), "entry should have expired");
    }
}
