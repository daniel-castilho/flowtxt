package ca.flowtxt.application.port.out;

import ca.flowtxt.domain.model.Message;

import java.util.Optional;
import java.util.UUID;

public interface MessageRepository {
    void save(final Message message);
    Optional<Message> findById(final UUID id);
    Optional<Message> findBySid(final String messageSid);
}
