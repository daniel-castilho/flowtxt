package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.mapper.UserMapper;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public class MongoUserRepositoryAdapter implements UserRepository {

    private final SpringDataUserRepository repository;
    private final UserMapper mapper;

    public MongoUserRepositoryAdapter(
            SpringDataUserRepository repository,
            UserMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public Optional<User> findByEmail(String email) {
        return repository.findByEmail(email).map(mapper::toUser);
    }

    @Override
    public void save(User user) {
        repository.save(mapper.toDocument(user));
    }
}
