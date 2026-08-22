package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.entity.MessageEntity;
import ca.flowtxt.infrastructure.persistence.mapper.MessageMapper;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

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

    /**
     * Persists the aggregate with load-then-apply: an existing row is loaded
     * as a managed entity and updated in place, so Hibernate's
     * {@code @Version} bookkeeping survives every write. Remapping the
     * immutable domain onto a fresh entity instead would reset the version to
     * 0 and make any post-insert update fail with a false
     * concurrent-modification conflict.
     */
    @Override
    @Transactional
    public void save(Message message) {
        MessageEntity entity = repository.findById(message.getId())
                .orElseGet(() -> mapper.toEntity(message));
        mapper.apply(message, entity);
        repository.save(entity);
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
