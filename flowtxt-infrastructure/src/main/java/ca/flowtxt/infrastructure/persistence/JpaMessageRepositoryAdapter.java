package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.mapper.MessageMapper;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

/**
 * PostgreSQL/JPA adapter for {@link MessageRepository}.
 */
@Repository
public class JpaMessageRepositoryAdapter implements MessageRepository {

    private final SpringDataMessageRepository repository;
    private final MessageMapper mapper;

    public JpaMessageRepositoryAdapter(
            SpringDataMessageRepository repository,
            MessageMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public void save(Message message) {
        repository.save(mapper.toEntity(message));
    }

    @Override
    public Optional<Message> findById(UUID id) {
        return repository.findById(id).map(mapper::toDomain);
    }

    @Override
    public Optional<Message> findBySid(String messageSid) {
        return repository.findBySid(messageSid).map(mapper::toDomain);
    }
}
