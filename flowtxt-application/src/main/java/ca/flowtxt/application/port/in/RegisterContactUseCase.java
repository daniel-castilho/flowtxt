package ca.flowtxt.application.port.in;

import ca.flowtxt.domain.model.Contact;

public interface RegisterContactUseCase {
    Contact execute(final String name, final String phoneNumber);
}
