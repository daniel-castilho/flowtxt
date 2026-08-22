package ca.flowtxt.infrastructure.config;

import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.infrastructure.config.properties.TwilioProperties;
import ca.flowtxt.infrastructure.sms.FakeSmsAdapter;
import ca.flowtxt.infrastructure.sms.TwilioSmsAdapter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
public class SmsConfig {

    @Bean
    @Profile("prod")
    public SmsService twilioSmsService(TwilioProperties twilio) {
        return new TwilioSmsAdapter(twilio.accountSid(), twilio.authToken(), twilio.phoneNumber());
    }

    @Bean
    @Profile({"dev", "test"})
    public SmsService fakeSmsService() {
        return new FakeSmsAdapter();
    }
}

