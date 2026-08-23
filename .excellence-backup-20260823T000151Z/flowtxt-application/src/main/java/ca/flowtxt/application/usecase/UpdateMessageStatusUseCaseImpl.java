package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.MessageStatus;

public class UpdateMessageStatusUseCaseImpl implements UpdateMessageStatusUseCase {

    private final MessageRepository messageRepository;

    public UpdateMessageStatusUseCaseImpl(final MessageRepository messageRepository) {
        this.messageRepository = messageRepository;
    }

    @Override
    public void updateStatus(final String messageSid, final MessageStatus status) {
        var message = messageRepository.findBySid(messageSid)
                .orElseThrow(() -> new IllegalArgumentException("Message not found for sid: " + messageSid));

        // The entity validates the lifecycle transition; invalid jumps surface
        // as IllegalStateException and map to HTTP 409 at the API edge.
        messageRepository.save(message.applyProviderStatus(status, messageSid));
    }
}
