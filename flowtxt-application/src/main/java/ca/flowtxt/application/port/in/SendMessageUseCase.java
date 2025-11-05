package ca.flowtxt.application.port.in;

public interface SendMessageUseCase {
    void execute(final String from, final String to, final String messageText);
}
