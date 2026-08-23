package ca.flowtxt;

import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.resttestclient.TestRestTemplate;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureTestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.resttestclient.TestRestTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

/**
 * Base class for black-box HTTP integration tests: boots the full application
 * on a real, random port against real PostgreSQL + Redis containers, with no
 * MockMvc. Complements {@link AbstractIntegrationTest} (which uses MockMvc) by
 * exercising the actual servlet container, filters, serialization and headers
 * end to end. Skipped automatically when Docker is unavailable.
 *
 * <p>The containers are started once per JVM in a static initializer and the
 * database is truncated before each test so classes sharing the JVM do not
 * collide on fixed fixtures regardless of execution order.</p>
 */
@Testcontainers(disabledWithoutDocker = true)
@AutoConfigureTestRestTemplate
@org.springframework.boot.test.context.SpringBootTest(
        webEnvironment = org.springframework.boot.test.context.SpringBootTest.WebEnvironment.RANDOM_PORT)
public abstract class AbstractHttpIntegrationTest {

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

    @LocalServerPort
    protected int port;

    @Autowired
    protected TestRestTemplate restTemplate;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void resetDatabaseState() {
        jdbcTemplate.execute("TRUNCATE TABLE messages, contacts, users CASCADE");
    }

    protected String baseUrl() {
        return "http://localhost:" + port;
    }
}
