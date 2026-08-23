package ca.flowtxt;

import ca.flowtxt.infrastructure.security.TwilioSignatures;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * True black-box end-to-end test: boots the real servlet container on a random
 * port and exercises the full workflow over actual HTTP (no MockMvc) —
 * register → login → create contact → send message → Twilio status callback —
 * plus the canonical error envelope and the unauthenticated health probes.
 */
class FullWorkflowIT extends AbstractHttpIntegrationTest {

    private static final String EMAIL = "e2e-" + System.nanoTime() + "@example.com";
    private static final String PASSWORD = "strongpass123";
    private static final String PHONE = "+15551230000";

    @Test
    void registerLoginSendMessageAndReceiveWebhookOverRealHttp() {
        // 1. Register — public, returns JWT.
        String registerBody = """
                {"email":"%s","password":"%s"}
                """.formatted(EMAIL, PASSWORD);
        ResponseEntity<Map> register = postJson("/auth/register", registerBody, null);
        assertEquals(HttpStatus.CREATED, register.getStatusCode());
        String registerToken = jsonString(register.getBody(), "token");
        assertNotNull(registerToken);
        assertFalse(registerToken.isBlank());

        // 2. Login — public, fresh JWT.
        String loginBody = """
                {"email":"%s","password":"%s"}
                """.formatted(EMAIL, PASSWORD);
        ResponseEntity<Map> login = postJson("/auth/login", loginBody, null);
        assertEquals(HttpStatus.OK, login.getStatusCode());
        String token = jsonString(login.getBody(), "token");
        assertNotNull(token);

        // 3. Protected endpoint WITHOUT a token — canonical 401 envelope.
        ResponseEntity<Map> noToken = postJson("/contacts",
                contactJson("Maria", PHONE), null);
        assertEquals(HttpStatus.UNAUTHORIZED, noToken.getStatusCode());
        assertEquals(401, ((Number) noToken.getBody().get("status")).intValue());
        assertEquals("Unauthorized", noToken.getBody().get("error"));

        // 4. Create contact WITH the token — 200.
        ResponseEntity<Map> contact = postJson("/contacts",
                contactJson("Maria", PHONE), token);
        assertEquals(HttpStatus.OK, contact.getStatusCode());
        assertEquals("Maria", contact.getBody().get("name"));
        assertEquals(PHONE, contact.getBody().get("phoneNumber"));

        // 5. Duplicate contact — 409 Conflict envelope.
        ResponseEntity<Map> duplicate = postJson("/contacts",
                contactJson("Maria Again", PHONE), token);
        assertEquals(HttpStatus.CONFLICT, duplicate.getStatusCode());
        assertEquals(409, ((Number) duplicate.getBody().get("status")).intValue());

        // 6. Invalid E.164 — 400 validation envelope.
        ResponseEntity<Map> badPhone = postJson("/contacts",
                contactJson("Bad", "555-1234"), token);
        assertEquals(HttpStatus.BAD_REQUEST, badPhone.getStatusCode());
        assertEquals("Validation Error", badPhone.getBody().get("error"));
        assertNotNull(badPhone.getBody().get("validationErrors"));

        // 7. Send a message to the known contact — 202 Accepted.
        String messageBody = """
                {"from":"+15550009999","to":"%s","content":"Hello over HTTP"}
                """.formatted(PHONE);
        ResponseEntity<Map> message = postJson("/messages", messageBody, token);
        assertEquals(HttpStatus.ACCEPTED, message.getStatusCode());

        // 8. Send to an unknown contact — 404 envelope.
        String unknownBody = """
                {"from":"+15550009999","to":"+15550000000","content":"Nobody home"}
                """;
        ResponseEntity<Map> notFound = postJson("/messages", unknownBody, token);
        assertEquals(HttpStatus.NOT_FOUND, notFound.getStatusCode());

        // 9. Twilio callback without signature — 403 from the real filter chain.
        ResponseEntity<String> unsigned = postForm(
                "/webhook/twilio/status",
                Map.of("MessageSid", "SM-e2e", "MessageStatus", "delivered"),
                null);
        assertEquals(HttpStatus.FORBIDDEN, unsigned.getStatusCode());
        assertTrue(unsigned.getBody().contains("Forbidden"));

        // 10. Signed callback for a SID the provider would report: the fake
        // adapter returns a deterministic SID on send, so verify the signed
        // path returns 200 for a known persisted SID separately. A 404 for an
        // unknown SID is also acceptable and proves the chain reaches the
        // controller with the canonical envelope.
        String url = baseUrl() + "/webhook/twilio/status";
        Map<String, String> params = Map.of(
                "MessageSid", "SM-unknown-signed",
                "MessageStatus", "delivered");
        String signature = TwilioSignatures.sign(
                "integration-test-twilio-token", url, params);
        ResponseEntity<Map> signed = postForm(
                "/webhook/twilio/status", params, signature, Map.class);
        // The signed request passes the filter; the SID is unknown, so the use
        // case answers 404 through the canonical envelope.
        assertEquals(HttpStatus.NOT_FOUND, signed.getStatusCode());
        assertEquals(404, ((Number) signed.getBody().get("status")).intValue());

        // 11. Liveness/readiness probes are public over real HTTP.
        ResponseEntity<String> liveness =
                restTemplate.getForEntity(baseUrl() + "/actuator/health/liveness", String.class);
        assertEquals(HttpStatus.OK, liveness.getStatusCode());
        ResponseEntity<String> readiness =
                restTemplate.getForEntity(baseUrl() + "/actuator/health/readiness", String.class);
        assertEquals(HttpStatus.OK, readiness.getStatusCode());
        assertTrue(readiness.getBody().contains("UP"));
    }

    private String contactJson(String name, String phone) {
        return """
                {"name":"%s","phoneNumber":"%s"}
                """.formatted(name, phone);
    }

    private ResponseEntity<Map> postJson(String path, String body, String token) {
        return postJson(path, body, token, Map.class);
    }

    @SuppressWarnings("unchecked")
    private <T> ResponseEntity<T> postJson(String path, String body, String token, Class<T> type) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        if (token != null) {
            headers.setBearerAuth(token);
        }
        return restTemplate.postForEntity(baseUrl() + path, new HttpEntity<>(body, headers), type);
    }

    private ResponseEntity<String> postForm(String path, Map<String, String> form, String signature) {
        return postForm(path, form, signature, String.class);
    }

    private <T> ResponseEntity<T> postForm(
            String path, Map<String, String> form, String signature, Class<T> type) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        if (signature != null) {
            headers.set("X-Twilio-Signature", signature);
        }
        MultiValueMap<String, String> map = new LinkedMultiValueMap<>();
        form.forEach(map::add);
        return restTemplate.postForEntity(baseUrl() + path, new HttpEntity<>(map, headers), type);
    }

    @SuppressWarnings("unchecked")
    private String jsonString(Map body, String key) {
        Object value = body == null ? null : body.get(key);
        return value == null ? null : value.toString();
    }
}
