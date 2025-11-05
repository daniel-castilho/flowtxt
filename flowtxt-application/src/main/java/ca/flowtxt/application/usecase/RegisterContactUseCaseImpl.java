package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.RegisterContactUseCase;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;

import java.util.UUID;

public class RegisterContactUseCaseImpl implements RegisterContactUseCase {

    private final ContactRepository contactRepository;

    public RegisterContactUseCaseImpl(final ContactRepository contactRepository) {
        this.contactRepository = contactRepository;
    }

    @Override
    public Contact execute(final String name, final String phoneNumber) {

        var contact = Contact.builder()
                .id(UUID.randomUUID())
                .name(name)
                .phoneNumber(new PhoneNumber(phoneNumber))
                .build();

        contactRepository.save(contact);

        return contact;
    }
}
