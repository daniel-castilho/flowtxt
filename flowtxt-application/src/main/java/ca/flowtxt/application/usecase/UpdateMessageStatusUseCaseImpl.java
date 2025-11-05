package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.MessageStatus;
import lombok.RequiredArgsConstructor;

@RequiredArgsConstructor
public class UpdateMessageStatusUseCaseImpl implements UpdateMessageStatusUseCase {

    private final MessageRepository messageRepository;

    @Override
    public void updateStatus(final String messageSid, final MessageStatus status) {
        messageRepository.updateStatusBySid(messageSid, status);
    }
}
