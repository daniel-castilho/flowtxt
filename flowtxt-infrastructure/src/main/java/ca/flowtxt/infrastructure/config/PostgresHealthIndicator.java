package ca.flowtxt.infrastructure.config;

import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;

/**
 * Readiness check for the PostgreSQL backing service. Performs a cheap
 * {@code SELECT 1} and reports UP/DOWN. The Spring Boot auto-configured
 * {@code db} indicator already validates the connection; this indicator
 * exists under a stable name ({@code postgres}) so the readiness group and
 * runbook can reference it explicitly.
 */
@Component("postgres")
public class PostgresHealthIndicator implements HealthIndicator {

    private final JdbcTemplate jdbcTemplate;

    public PostgresHealthIndicator(DataSource dataSource) {
        this.jdbcTemplate = new JdbcTemplate(dataSource);
    }

    @Override
    public Health health() {
        try {
            Integer result = jdbcTemplate.queryForObject("SELECT 1", Integer.class);
            if (Integer.valueOf(1).equals(result)) {
                return Health.up().withDetail("database", "postgres").build();
            }
            return Health.down().withDetail("database", "postgres")
                    .withDetail("unexpectedResult", result).build();
        } catch (Exception e) {
            return Health.down(e).withDetail("database", "postgres").build();
        }
    }
}
