package ca.flowtxt.infrastructure.config;

import ca.flowtxt.infrastructure.config.properties.JwtProperties;
import ca.flowtxt.infrastructure.config.properties.RateLimitProperties;
import ca.flowtxt.infrastructure.config.properties.StartupConfigValidator;
import ca.flowtxt.infrastructure.config.properties.TwilioProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.GenericJackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.StringRedisSerializer;

@Configuration
@EnableConfigurationProperties({RateLimitProperties.class, JwtProperties.class, TwilioProperties.class})
public class InfrastructureConfig {

    /**
     * Fail-fast configuration guard (Twelve-Factor factor 3): throwing from
     * this bean's constructor aborts the context refresh before the web
     * server ever accepts traffic.
     */
    @Bean
    public StartupConfigValidator startupConfigValidator(
            Environment environment,
            JwtProperties jwtProperties,
            TwilioProperties twilioProperties) {
        return new StartupConfigValidator(environment, jwtProperties, twilioProperties);
    }

    @Bean
    public RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory connectionFactory) {
        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(connectionFactory);

        template.setKeySerializer(new StringRedisSerializer());
        template.setValueSerializer(new GenericJackson2JsonRedisSerializer());
        template.setHashKeySerializer(new StringRedisSerializer());
        template.setHashValueSerializer(new GenericJackson2JsonRedisSerializer());

        template.afterPropertiesSet();
        return template;
    }
}
