package ca.flowtxt.application.port.in;

import ca.flowtxt.domain.model.MessageStatus;

public interface UpdateMessageStatusUseCase {
    void updateStatus(final String messageSid, final MessageStatus status);
}

