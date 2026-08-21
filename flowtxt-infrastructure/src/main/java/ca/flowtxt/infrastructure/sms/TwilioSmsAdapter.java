package ca.flowtxt.infrastructure.sms;

import ca.flowtxt.application.port.out.SmsService;
import com.twilio.Twilio;
import com.twilio.rest.api.v2010.account.Message;
import com.twilio.type.PhoneNumber;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;

@Slf4j
public final class TwilioSmsAdapter implements SmsService {

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

        String maskedAuthToken = authToken != null && authToken.length() > 4
                ? "****" + authToken.substring(authToken.length() - 4)
                : "****";

        log.info("Initializing Twilio with Account SID: {}", accountSid);
        log.info("Auth Token (masked): {}", maskedAuthToken);
        log.info("Configured origin number: {}", fromNumber);

        try {
            Twilio.init(accountSid, authToken);
            log.info("Twilio client initialized successfully");
        } catch (Exception e) {
            log.error("Failed to initialize Twilio client: {}", e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public String sendMessage(final String fromPhoneNumber, final String toPhoneNumber, final String content) {
        log.info("Sending SMS - From: {}, To: {}, Content: {}", fromPhoneNumber, toPhoneNumber, content);

        try {
            log.debug("Creating Twilio message...");
            Message message = Message.creator(
                    new PhoneNumber(toPhoneNumber),
                    new PhoneNumber(fromPhoneNumber),
                    content
            ).create();

            String sid = message.getSid();
            log.info("SMS sent successfully. Message SID: {}", sid);
            return sid;

        } catch (Exception e) {
            log.error("Failed to send SMS. Details:", e);
            log.error("Error class: {}", e.getClass().getName());
            log.error("Error message: {}", e.getMessage());

            if (e.getCause() != null) {
                log.error("Root cause: {}: {}",
                        e.getCause().getClass().getName(), e.getCause().getMessage());
            }

            throw new RuntimeException("Failed to send SMS: " + e.getMessage(), e);
        }
    }

    @Override
    public void receiveMessage(String payload) {
        throw new UnsupportedOperationException("Inbound message webhook not implemented yet");
    }
}
