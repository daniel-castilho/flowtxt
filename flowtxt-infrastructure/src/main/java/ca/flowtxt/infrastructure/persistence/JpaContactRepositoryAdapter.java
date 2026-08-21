package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.infrastructure.persistence.mapper.ContactMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * PostgreSQL/JPA adapter for {@link ContactRepository}.
 */
@Repository
public class JpaContactRepositoryAdapter implements ContactRepository {

    private final SpringDataContactRepository repository;
    private final ContactMapper mapper;

    public JpaContactRepositoryAdapter(
            SpringDataContactRepository repository,
            ContactMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public Optional<Contact> findById(UUID id) {
        return repository.findById(id).map(mapper::toDomain);
    }

    @Override
    public Optional<Contact> findByPhoneNumber(String phoneNumber) {
        return repository.findByPhoneNumber(phoneNumber).map(mapper::toDomain);
    }

    @Override
    public void save(Contact contact) {
        repository.save(mapper.toEntity(contact));
    }

    @Override
    public List<Contact> findAll() {
        return repository.findAll().stream()
                .map(mapper::toDomain)
                .toList();
    }
}
