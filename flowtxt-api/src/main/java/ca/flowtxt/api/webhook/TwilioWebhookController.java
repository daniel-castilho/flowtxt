package ca.flowtxt.api.webhook;

import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.domain.model.MessageStatus;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Slf4j
@RestController
@RequestMapping("/webhook/twilio")
@RequiredArgsConstructor
public class TwilioWebhookController {

    private final UpdateMessageStatusUseCase updateMessageStatusUseCase;

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
            log.warn("Status desconhecido recebido do Twilio: {}", twilioStatus);
            return MessageStatus.UNKNOWN;
        }
    }
}
