package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.persistence.mapper.MessageMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public class MongoMessageRepositoryAdapter implements MessageRepository {

    private final SpringDataMessageRepository repository;
    private final MessageMapper mapper;

    public MongoMessageRepositoryAdapter(
            SpringDataMessageRepository repository,
            MessageMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public void save(final Message message) {
        repository.save(mapper.toDocument(message));
    }

    @Override
    public List<Message> findByContact(final Contact contact) {
        return repository.findByContactId(contact.getId()).stream()
                .map(mapper::toDomain)
                .toList();
    }

    @Override
    public Optional<Message> findById(final UUID id) {
        return repository.findById(id).map(mapper::toDomain);
    }

    @Override
    public void updateStatusBySid(String messageSid, MessageStatus status) {
        repository.updateStatusBySid(messageSid, status);
    }
}
