package ca.flowtxt.infrastructure.sms;

import ca.flowtxt.application.port.out.SmsService;

import java.util.UUID;

public class FakeSmsAdapter implements SmsService {

    private static final org.slf4j.Logger log =
            org.slf4j.LoggerFactory.getLogger(FakeSmsAdapter.class);

    @Override
    public String sendMessage(final String fromNumber, final String toPhoneNumber, final String content) {
        var fakeSid = "FAKE-" + UUID.randomUUID();
        log.info("[FAKE SMS] Simulating send from {} to {} with content: {}", fromNumber, toPhoneNumber, content);
        log.info("[FAKE SMS] Generated SID: {}", fakeSid);
        return fakeSid;
    }


    @Override
    public void receiveMessage(final String payload) {
        log.info("[FAKE SMS] Simulating inbound message: {}", payload);
    }
}

