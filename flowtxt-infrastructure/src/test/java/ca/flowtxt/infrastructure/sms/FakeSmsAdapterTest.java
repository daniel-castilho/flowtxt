package ca.flowtxt.infrastructure.sms;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class FakeSmsAdapterTest {

    private final FakeSmsAdapter adapter = new FakeSmsAdapter();

    @Test
    void sendsAMessageAndReturnsAFakeSid() {
        String sid = adapter.sendMessage(
                "+15005550000", "+5511999999999", "Hello FlowTXT");

        assertNotNull(sid);
        assertTrue(sid.startsWith("FAKE-"));
    }
}
