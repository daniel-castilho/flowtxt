package ca.flowtxt.infrastructure.config;

import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.infrastructure.sms.FakeSmsAdapter;
import ca.flowtxt.infrastructure.sms.TwilioSmsAdapter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
public class SmsConfig {

    @Bean
    @Profile("prod")
    public SmsService twilioSmsService(
            @Value("${twilio.account-sid}") String accountSid,
            @Value("${twilio.auth-token}") String authToken,
            @Value("${twilio.phone-number}") String fromNumber) {
        return new TwilioSmsAdapter(accountSid, authToken, fromNumber);
    }

    @Bean
    @Profile({"dev", "test"})
    public SmsService fakeSmsService() {
        return new FakeSmsAdapter();
    }
}

