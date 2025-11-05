package ca.flowtxt.infrastructure.sms;

import ca.flowtxt.application.port.out.SmsService;
import com.twilio.Twilio;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Slf4j
public class TwilioSmsAdapter implements SmsService {

    private final String accountSid;
    private final String authToken;
    private final String fromNumber;

    public TwilioSmsAdapter(
            @Value("${twilio.account-sid}") String accountSid,
            @Value("${twilio.auth-token}") String authToken,
            @Value("${twilio.phone-number}") String fromNumber) {
        this.accountSid = accountSid;
        this.authToken = authToken;
        this.fromNumber = fromNumber;

        // Log the values being used (masking sensitive data)
        String maskedAuthToken = authToken != null && authToken.length() > 4 
            ? "****" + authToken.substring(authToken.length() - 4) 
            : "****";
            
        log.info("Initializing Twilio with Account SID: {}", accountSid);
        log.info("Using Auth Token: {}", maskedAuthToken);
        log.info("From number: {}", fromNumber);

        try {
            // Initialize Twilio client
            Twilio.init(accountSid, authToken);
            log.info("Twilio client initialized successfully");
        } catch (Exception e) {
            log.error("Failed to initialize Twilio client: {}", e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public void sendMessage(final String fromPhoneNumber, final String toPhoneNumber, final String content) {
        log.info("Attempting to send SMS - From: {}, To: {}, Content: {}", fromPhoneNumber, toPhoneNumber, content);
        
        try {
            log.debug("Creating Twilio message...");
            
            var message = com.twilio.rest.api.v2010.account.Message.creator(
                    new com.twilio.type.PhoneNumber(toPhoneNumber),
                    new com.twilio.type.PhoneNumber(fromPhoneNumber),
                    content
            );
            
            log.debug("Sending message through Twilio...");
            var result = message.create();
            
            log.info("SMS sent successfully. Message SID: {}", result.getSid());
            return;
            
        } catch (Exception e) {
            log.error("Failed to send SMS. Error details:", e);
            log.error("Error class: {}", e.getClass().getName());
            log.error("Error message: {}", e.getMessage());
            
            if (e.getCause() != null) {
                log.error("Root cause: {}: {}", e.getCause().getClass().getName(), e.getCause().getMessage());
            }
            
            throw new RuntimeException("Failed to send SMS: " + e.getMessage(), e);
        }
    }

    @Override
    public void receiveMessage(String payload) {
        // TODO: Needs to implement Twilio webhook endpoint -> API Controller
        throw new UnsupportedOperationException("Not implemented yet");
    }
}
