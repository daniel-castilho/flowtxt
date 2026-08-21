package ca.flowtxt;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.security.TwilioSignatures;
import tools.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end security flow against real PostgreSQL + Redis containers:
 * register -> login -> protected endpoint (with and without a token).
 */
class SecurityFlowIT extends AbstractIntegrationTest {

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private ContactRepository contactRepository;

    @Autowired
    private MessageRepository messageRepository;

    @Test
    void registerLoginAndCallProtectedEndpoint() throws Exception {
        // 1. Register — public
        mockMvc.perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"flow-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.token").isNotEmpty());

        // 2. Login — public, returns a fresh token
        String loginBody = mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"flow-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").isNotEmpty())
                .andReturn().getResponse().getContentAsString();

        String token = objectMapper.readTree(loginBody).get("token").asText();

        // 3. Protected endpoint WITHOUT a token -> 401
        mockMvc.perform(post("/contacts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Maria\",\"phoneNumber\":\"+5511999999999\"}"))
                .andExpect(status().isUnauthorized());

        // 4. Protected endpoint WITH the token -> 200
        mockMvc.perform(post("/contacts")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Maria\",\"phoneNumber\":\"+5511999999999\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Maria"));
    }

    @Test
    void rejectsLoginWithWrongPassword() throws Exception {
        mockMvc.perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"another-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isCreated());

        mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"another-user@example.com\",\"password\":\"wrong-password\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void webhookRejectsUnsignedCallbacks() throws Exception {
        // The route is permitAll in SecurityConfig; the signature filter is
        // what protects it. Without a valid X-Twilio-Signature -> 403.
        mockMvc.perform(post("/webhook/twilio/status")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM-unsigned")
                        .param("MessageStatus", "sent"))
                .andExpect(status().isForbidden());
    }

    @Test
    void webhookAcceptsASignedCallbackForAKnownSid() throws Exception {
        // Persist a message and advance it to SENT so the callback has a sid.
        contactRepository.save(Contact.create("Webhook Tester", new PhoneNumber("+15550000001")));
        Message message = Message.pending(
                contactRepository.findByPhoneNumber("+15550000001").orElseThrow().getId(),
                "Hello FlowTXT");
        messageRepository.save(message);
        messageRepository.save(message.markSent("SM-signed-it"));

        String url = "http://localhost/webhook/twilio/status";
        String signature = TwilioSignatures.sign("integration-test-twilio-token", url, Map.of(
                "MessageSid", "SM-signed-it",
                "MessageStatus", "delivered"));

        mockMvc.perform(post("/webhook/twilio/status")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM-signed-it")
                        .param("MessageStatus", "delivered")
                        .header("X-Twilio-Signature", signature))
                .andExpect(status().isOk());

        assertEquals(MessageStatus.DELIVERED,
                messageRepository.findBySid("SM-signed-it").orElseThrow().getStatus());
    }
}
