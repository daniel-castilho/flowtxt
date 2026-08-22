package ca.flowtxt;

import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

/**
 * Base class for integration tests: boots the full application against real
 * PostgreSQL and Redis containers, with the schema applied by Flyway (the
 * same migrations production runs). Skipped automatically when Docker is not
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

    static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>(DockerImageName.parse("postgres:16"));

    static final GenericContainer<?> REDIS =
            new GenericContainer<>(DockerImageName.parse("redis:7-alpine"))
                    .withExposedPorts(6379);

    static {
        POSTGRES.start();
        REDIS.start();
    }

    @DynamicPropertySource
    static void registerProperties(DynamicPropertyRegistry registry) {
        // Flyway runs automatically on boot and applies V1__init.sql.
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
        registry.add("jwt.secret",
                () -> "integration-test-secret-that-is-long-enough-for-hs256!!");
        registry.add("twilio.auth-token",
                () -> "integration-test-twilio-token");
    }

    @Autowired
    protected MockMvc mockMvc;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void resetDatabaseState() {
        // The containers are singletons shared by every *IT class in this JVM:
        // without a reset, fixed fixtures collide across classes (duplicate
        // keys) depending on execution order. CASCADE covers messages ->
        // contacts regardless of table order.
        jdbcTemplate.execute("TRUNCATE TABLE messages, contacts, users CASCADE");
    }
}
