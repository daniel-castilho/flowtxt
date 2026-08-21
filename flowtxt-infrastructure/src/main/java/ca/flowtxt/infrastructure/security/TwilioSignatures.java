package ca.flowtxt.infrastructure.security;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.Map;
import java.util.TreeMap;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Twilio request signatures (X-Twilio-Signature): HMAC-SHA1 over the full
 * request URL followed by every POST parameter appended as name+value in
 * alphabetical order, Base64-encoded with the account's auth token.
 */
public final class TwilioSignatures {

    private static final String HMAC_SHA1 = "HmacSHA1";

    private TwilioSignatures() {
    }

    /**
     * Computes the signature Twilio would send for the given request.
     *
     * @param authToken the Twilio account auth token
     * @param url       the full public request URL (scheme, host, path and query)
     * @param params    POST parameters; copied into alphabetical order here
     */
    public static String sign(String authToken, String url, Map<String, String> params) {
        StringBuilder data = new StringBuilder(url);
        for (Map.Entry<String, String> entry : new TreeMap<>(params).entrySet()) {
            data.append(entry.getKey()).append(entry.getValue());
        }
        try {
            Mac mac = Mac.getInstance(HMAC_SHA1);
            mac.init(new SecretKeySpec(authToken.getBytes(StandardCharsets.UTF_8), HMAC_SHA1));
            byte[] raw = mac.doFinal(data.toString().getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(raw);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("Unable to compute Twilio signature", e);
        }
    }

    /**
     * Constant-time comparison between the expected and the received signature.
     */
    public static boolean matches(String expected, String received) {
        if (expected == null || received == null) {
            return false;
        }
        return MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                received.getBytes(StandardCharsets.UTF_8));
    }
}
