package ca.flowtxt.application.port.out;

public interface SmsService {
    void sendMessage(final String fromNumber, final String toPhoneNumber, final String message);
    void receiveMessage(final String payload);
}
