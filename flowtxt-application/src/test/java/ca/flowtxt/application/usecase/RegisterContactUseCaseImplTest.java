package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.RegisterContactUseCase;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.domain.common.ConflictException;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RegisterContactUseCaseImplTest {

    @Mock
    private ContactRepository contactRepository;

    private RegisterContactUseCase useCase;

    @BeforeEach
    void setUp() {
        useCase = new RegisterContactUseCaseImpl(contactRepository);
    }

    @Test
    void registersAContactWithAnE164Number() {
        when(contactRepository.findByPhoneNumber("+5511999999999")).thenReturn(Optional.empty());

        Contact contact = useCase.execute("Maria Silva", "+5511999999999");

        assertEquals("Maria Silva", contact.getName());
        verify(contactRepository).save(any(Contact.class));
    }

    @Test
    void rejectsADuplicatePhoneNumberAsAConflict() {
        when(contactRepository.findByPhoneNumber("+5511999999999"))
                .thenReturn(Optional.of(Contact.create("Existing", new PhoneNumber("+5511999999999"))));

        assertThrows(ConflictException.class,
                () -> useCase.execute("Another Name", "+5511999999999"));

        verify(contactRepository, never()).save(any(Contact.class));
    }

    @Test
    void propagatesTheDomainRejectionForInvalidNumbers() {
        assertThrows(IllegalArgumentException.class,
                () -> useCase.execute("Bad Number", "5511999999999"));

        verify(contactRepository, never()).save(any(Contact.class));
    }
}
