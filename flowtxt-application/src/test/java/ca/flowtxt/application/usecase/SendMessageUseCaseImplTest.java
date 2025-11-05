package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SendMessageUseCaseImplTest {

    private ContactRepository contactRepository;
    private MessageRepository messageRepository;
    private SendMessageUseCaseImpl sendMessageUseCase;
    private SmsService smsService;

    @BeforeEach
    void setup() {
        contactRepository = mock(ContactRepository.class);
        messageRepository = mock(MessageRepository.class);
        smsService = mock(SmsService.class);
        sendMessageUseCase = new SendMessageUseCaseImpl(contactRepository, messageRepository, smsService);
    }

    @Test
    void shouldSendMessageToExistingContact() {
        // Arrange
        var expectedId = UUID.randomUUID();
        var expectedName = "Daniel Castilho";
        var expectedPhoneNumberFrom = "6477052644";
        var expectedPhoneNumberTo = "6477052644";
        var expectedMessage = "Hello World";
        Contact contact = Contact.builder()
                .id(expectedId)
                .name(expectedName)
                .phoneNumber(new PhoneNumber(expectedPhoneNumberFrom))
                .build();

        // Act
        when(contactRepository.findByPhoneNumber(expectedPhoneNumberTo))
                .thenReturn(Optional.of(contact));

        sendMessageUseCase.execute(expectedPhoneNumberFrom, expectedPhoneNumberTo, expectedMessage);
        verify(messageRepository, times(2)).save(any()); // PENDING + SENT
        verify(smsService).sendMessage(expectedPhoneNumberFrom, expectedPhoneNumberTo, expectedMessage);
    }
}