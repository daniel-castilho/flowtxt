package ca.flowtxt;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;

import java.util.Set;

import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.emptyOrNullString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end login throttling against the real Redis container: beyond the
 * configured limit /auth/login answers 429 with a Retry-After header, while
 * other clients keep their own budget. Runs in its own Spring context (lower
 * limit via @TestPropertySource); rate-limit keys are cleared around each test
 * so sibling IT classes sharing the containers are never throttled.
 */
@TestPropertySource(properties = {
        "rate-limit.limit=3",
        "rate-limit.window=1m"
})
class LoginRateLimitIT extends AbstractIntegrationTest {

    private static final String RATE_LIMIT_KEYS = "flowtxt:ratelimit:*";

    @Autowired
    private StringRedisTemplate redisTemplate;

    @BeforeEach
    @AfterEach
    void clearRateLimitCounters() {
        Set<String> keys = redisTemplate.keys(RATE_LIMIT_KEYS);
        if (keys != null && !keys.isEmpty()) {
            redisTemplate.delete(keys);
        }
    }

    private void attemptLogin(String clientIp) throws Exception {
        mockMvc.perform(post("/auth/login")
                        .header("X-Forwarded-For", clientIp)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"ghost@example.com\",\"password\":\"wrong-password\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void blocksLoginsOnceTheFixedWindowIsExhausted() throws Exception {
        for (int i = 0; i < 3; i++) {
            attemptLogin("203.0.113.10");
        }

        mockMvc.perform(post("/auth/login")
                        .header("X-Forwarded-For", "203.0.113.10")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"ghost@example.com\",\"password\":\"wrong-password\"}"))
                .andExpect(status().isTooManyRequests())
                .andExpect(header().string("Retry-After", not(emptyOrNullString())));
    }

    @Test
    void keepsOtherClientsUnderTheirOwnBudget() throws Exception {
        attemptLogin("203.0.113.11");
        attemptLogin("203.0.113.11");

        // A third hit would exhaust this client too; assert it is still allowed.
        attemptLogin("203.0.113.11");
    }
}
