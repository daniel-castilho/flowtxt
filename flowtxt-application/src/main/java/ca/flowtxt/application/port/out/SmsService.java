package ca.flowtxt.application.port.out;

public interface SmsService {
    String sendMessage(final String fromNumber, final String toPhoneNumber, final String content);
    void receiveMessage(final String payload);
}
