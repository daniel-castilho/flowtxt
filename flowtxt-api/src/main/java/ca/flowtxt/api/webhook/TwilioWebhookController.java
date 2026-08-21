package ca.flowtxt.api.webhook;

import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.domain.model.MessageStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/webhook/twilio")
public class TwilioWebhookController {

    private static final Logger log = LoggerFactory.getLogger(TwilioWebhookController.class);

    private final UpdateMessageStatusUseCase updateMessageStatusUseCase;

    public TwilioWebhookController(UpdateMessageStatusUseCase updateMessageStatusUseCase) {
        this.updateMessageStatusUseCase = updateMessageStatusUseCase;
    }

    @PostMapping("/status")
    public ResponseEntity<Void> handleStatusCallback(
            @RequestParam("MessageSid") String messageSid,
            @RequestParam("MessageStatus") String messageStatus) {

        log.info("Twilio status webhook received: sid={}, status={}", messageSid, messageStatus);

        // Map the Twilio status string onto the domain enum
        MessageStatus status = mapTwilioStatus(messageStatus);

        updateMessageStatusUseCase.updateStatus(messageSid, status);

        return ResponseEntity.ok().build();
    }

    private MessageStatus mapTwilioStatus(String twilioStatus) {
        try {
            return MessageStatus.valueOf(twilioStatus.toUpperCase());
        } catch (IllegalArgumentException e) {
            log.warn("Unknown status received from Twilio: {}", twilioStatus);
            return MessageStatus.UNKNOWN;
        }
    }
}
