package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.infrastructure.persistence.mapper.ContactMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public class MongoContactRepositoryAdapter implements ContactRepository {

    private final SpringDataContactRepository repository;
    private final ContactMapper mapper;

    public MongoContactRepositoryAdapter(
            SpringDataContactRepository repository,
            ContactMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public Optional<Contact> findById(final UUID id) {
        return repository.findById(id).map(mapper::toContact);
    }

    @Override
    public Optional<Contact> findByPhoneNumber(final String phoneNumber) {
        return repository.findByPhoneNumber(phoneNumber).map(mapper::toContact);
    }

    @Override
    public void save(final Contact contact) {
        repository.save(mapper.toDocument(contact));
    }

    @Override
    public List<Contact> findAll() {
        return repository.findAll().stream()
                .map(mapper::toContact)
                .toList();
    }
}
