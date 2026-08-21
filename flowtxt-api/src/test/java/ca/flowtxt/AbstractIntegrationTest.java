package ca.flowtxt;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.MongoDBContainer;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

/**
 * Base class for integration tests: boots the full application against real
 * MongoDB and Redis containers. Skipped automatically when Docker is not
 * available (see @Testcontainers(disabledWithoutDocker = true)).
 *
 * <p>The containers are started once per JVM in a static initializer instead
 * of being managed by {@code @Container}: the Spring application context is
 * cached across test classes, so per-class container restarts would leave the
 * cached context pointing at dead mapped ports. Containers are removed by
 * Testcontainers' Ryuk reaper when the JVM exits.</p>
 */
@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
public abstract class AbstractIntegrationTest {

    static final MongoDBContainer MONGO = new MongoDBContainer("mongo:7.0");

    static final GenericContainer<?> REDIS =
            new GenericContainer<>(DockerImageName.parse("redis:7-alpine"))
                    .withExposedPorts(6379);

    static {
        MONGO.start();
        REDIS.start();
    }

    @DynamicPropertySource
    static void registerProperties(DynamicPropertyRegistry registry) {
        // Boot 4 renamed the Mongo connection namespace to spring.mongodb.*
        registry.add("spring.mongodb.uri", MONGO::getReplicaSetUrl);
        // Boot 3 prefix (spring.redis.* no longer exists)
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
        registry.add("jwt.secret",
                () -> "integration-test-secret-that-is-long-enough-for-hs256!!");
    }

    @Autowired
    protected MockMvc mockMvc;
}
