package ca.flowtxt.infrastructure.sms;

import ca.flowtxt.application.port.out.SmsService;
import lombok.extern.slf4j.Slf4j;

import java.util.UUID;

@Slf4j
public class FakeSmsAdapter implements SmsService {

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

