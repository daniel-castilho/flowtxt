package ca.flowtxt.application.port.out;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface MessageRepository {
    void save(final Message message);
    List<Message> findByContact(final Contact contact);
    Optional<Message> findById(final UUID id);
}
