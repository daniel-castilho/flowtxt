package ca.flowtxt.api.webhook;

import ca.flowtxt.api.support.RateLimitSliceTestConfig;
import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.config.SecurityConfig;
import ca.flowtxt.infrastructure.security.JwtAuthenticationFilter;
import ca.flowtxt.infrastructure.security.JwtService;
import ca.flowtxt.infrastructure.web.exception.GlobalExceptionHandler;
import ca.flowtxt.infrastructure.security.TwilioSignatures;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(TwilioWebhookController.class)
@Import({GlobalExceptionHandler.class, SecurityConfig.class, JwtAuthenticationFilter.class,
        RateLimitSliceTestConfig.class})
class TwilioWebhookControllerTest {

    private static final String WEBHOOK_URL = "/webhook/twilio/status";
    private static final String TOKEN = RateLimitSliceTestConfig.TWILIO_AUTH_TOKEN;

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private UpdateMessageStatusUseCase updateMessageStatusUseCase;

    @MockitoBean
    private JwtService jwtService;

    /** Signature exactly as Twilio computes it: HMAC over URL + sorted params. */
    private static String signatureFor(String messageSid, String messageStatus) {
        return TwilioSignatures.sign(TOKEN, "http://localhost" + WEBHOOK_URL,
                Map.of("MessageSid", messageSid, "MessageStatus", messageStatus));
    }

    @Test
    void knownStatusIsMappedAndForwardedToTheUseCase() throws Exception {
        mockMvc.perform(post(WEBHOOK_URL)
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM1234567890")
                        .param("MessageStatus", "delivered")
                        .header("X-Twilio-Signature",
                                signatureFor("SM1234567890", "delivered")))
                .andExpect(status().isOk());

        verify(updateMessageStatusUseCase).updateStatus("SM1234567890", MessageStatus.DELIVERED);
    }

    @Test
    void unknownStatusFallsBackToDomainUnknown() throws Exception {
        mockMvc.perform(post(WEBHOOK_URL)
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM9876543210")
                        .param("MessageStatus", "teleported")
                        .header("X-Twilio-Signature",
                                signatureFor("SM9876543210", "teleported")))
                .andExpect(status().isOk());

        verify(updateMessageStatusUseCase).updateStatus("SM9876543210", MessageStatus.UNKNOWN);
    }
}
