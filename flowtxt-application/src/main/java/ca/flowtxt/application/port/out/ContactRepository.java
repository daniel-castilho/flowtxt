package ca.flowtxt.application.port.out;

import ca.flowtxt.domain.model.Contact;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface ContactRepository {
    Optional<Contact> findById(final UUID id);
    Optional<Contact> findByPhoneNumber(final String phoneNumber);
    void save(final Contact contact);
    List<Contact> findAll();
}
