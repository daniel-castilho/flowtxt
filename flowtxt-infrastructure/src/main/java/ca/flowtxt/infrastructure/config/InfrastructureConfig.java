package ca.flowtxt.infrastructure.config;

import ca.flowtxt.application.port.out.CacheService;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.infrastructure.cache.RedisCacheAdapter;
import ca.flowtxt.infrastructure.persistence.MongoContactRepositoryAdapter;
import ca.flowtxt.infrastructure.persistence.MongoMessageRepositoryAdapter;
import ca.flowtxt.infrastructure.persistence.SpringDataContactRepository;
import ca.flowtxt.infrastructure.persistence.SpringDataMessageRepository;
import ca.flowtxt.infrastructure.persistence.mapper.ContactMapper;
import ca.flowtxt.infrastructure.persistence.mapper.MessageMapper;
import ca.flowtxt.infrastructure.sms.TwilioSmsAdapter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.GenericJackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.StringRedisSerializer;

@Configuration
public class InfrastructureConfig {

    // SMS Service
    @Bean
    public SmsService smsService(
            @Value("${twilio.account-sid}") String accountSid,
            @Value("${twilio.auth-token}") String authToken,
            @Value("${twilio.phone-number}") String fromNumber) {
        return new TwilioSmsAdapter(accountSid, authToken, fromNumber);
    }

    // Redis Configuration
    @Bean
    public RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory connectionFactory) {
        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(connectionFactory);
        
        // Configure serializers
        template.setKeySerializer(new StringRedisSerializer());
        template.setValueSerializer(new GenericJackson2JsonRedisSerializer());
        template.setHashKeySerializer(new StringRedisSerializer());
        template.setHashValueSerializer(new GenericJackson2JsonRedisSerializer());
        
        template.afterPropertiesSet();
        return template;
    }
}
