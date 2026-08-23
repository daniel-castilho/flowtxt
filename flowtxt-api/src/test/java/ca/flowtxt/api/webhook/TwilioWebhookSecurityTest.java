package ca.flowtxt.api.webhook;

import ca.flowtxt.infrastructure.security.TwilioSignatureValidationFilter;
import ca.flowtxt.infrastructure.security.TwilioSignatures;
import ca.flowtxt.infrastructure.security.handler.RestErrorResponseWriter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.ObjectMapper;

import java.util.Map;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Filter-level contract for the Twilio webhook: valid signatures pass,
 * anything else is rejected before reaching a controller. Rejections return
 * the canonical JSON error envelope (HTTP 403), not a bare status.
 */
class TwilioWebhookSecurityTest {

    private static final String TOKEN = "test-auth-token";
    private static final String WEBHOOK_URL = "/webhook/twilio/status";

    private MockMvc mockMvc;
    private MockMvc unconfigured;

    private static String signatureFor(String url) {
        return TwilioSignatures.sign(TOKEN, url, Map.of(
                "MessageSid", "SM123",
                "MessageStatus", "sent"));
    }

    @BeforeEach
    void setUp() {
        RestErrorResponseWriter writer = new RestErrorResponseWriter(new ObjectMapper());
        mockMvc = MockMvcBuilders.standaloneSetup(new StubStatusController())
                .addFilters(new TwilioSignatureValidationFilter(TOKEN, writer))
                .build();
        unconfigured = MockMvcBuilders.standaloneSetup(new StubStatusController())
                .addFilters(new TwilioSignatureValidationFilter("", writer))
                .build();
    }

    @Test
    void acceptsACallbackWithAValidSignature() throws Exception {
        mockMvc.perform(post(WEBHOOK_URL)
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM123")
                        .param("MessageStatus", "sent")
                        .header("X-Twilio-Signature",
                                signatureFor("http://localhost" + WEBHOOK_URL)))
                .andExpect(status().isOk());
    }

    @Test
    void rejectsACallbackWithoutASignatureWithCanonicalEnvelope() throws Exception {
        mockMvc.perform(post(WEBHOOK_URL)
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM123")
                        .param("MessageStatus", "sent"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.status").value(403))
                .andExpect(jsonPath("$.error").value("Forbidden"));
    }

    @Test
    void rejectsATamperedSignature() throws Exception {
        String tampered = signatureFor("http://localhost" + WEBHOOK_URL);
        mockMvc.perform(post(WEBHOOK_URL)
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM123")
                        .param("MessageStatus", "delivered")
                        .header("X-Twilio-Signature", tampered))
                .andExpect(status().isForbidden());
    }

    @Test
    void rejectsEverythingWhenTheTokenIsNotConfigured() throws Exception {
        // Fail-closed: even a syntactically valid-looking header cannot pass
        // when the auth token is missing, because there is nothing to verify
        // it against.
        unconfigured.perform(post(WEBHOOK_URL)
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM123")
                        .param("MessageStatus", "sent")
                        .header("X-Twilio-Signature", "dGhpc0xvb2tzUmVhbEJ1dElzTm90"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message")
                        .value("Twilio auth token is not configured"));
    }

    @RestController
    static class StubStatusController {

        @PostMapping(WEBHOOK_URL)
        void accept() {
            // reached only when the filter lets the request through
        }
    }
}
