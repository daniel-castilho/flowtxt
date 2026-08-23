package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.domain.common.NotFoundException;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.domain.model.PhoneNumber;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class SendMessageUseCaseImplTest {

    private static final String FROM = "6477052644";
    private static final String TO = "+16477052655";
    private static final String CONTENT = "Hello World";

    private ContactRepository contactRepository;
    private MessageRepository messageRepository;
    private SmsService smsService;
    private SendMessageUseCaseImpl sendMessageUseCase;

    @BeforeEach
    void setup() {
        contactRepository = mock(ContactRepository.class);
        messageRepository = mock(MessageRepository.class);
        smsService = mock(SmsService.class);
        sendMessageUseCase = new SendMessageUseCaseImpl(contactRepository, messageRepository, smsService);
    }

    private Contact existingContact() {
        return new Contact(UUID.randomUUID(), "Daniel Castilho", new PhoneNumber(TO));
    }

    @Test
    void shouldSendMessageToExistingContact() {
        when(contactRepository.findByPhoneNumber(TO)).thenReturn(Optional.of(existingContact()));
        when(smsService.sendMessage(FROM, TO, CONTENT)).thenReturn("SM-123");

        sendMessageUseCase.execute(FROM, TO, CONTENT);

        ArgumentCaptor<Message> saved = ArgumentCaptor.forClass(Message.class);
        verify(messageRepository, times(2)).save(saved.capture());
        assertEquals(MessageStatus.PENDING, saved.getAllValues().get(0).getStatus());
        assertEquals(MessageStatus.SENT, saved.getAllValues().get(1).getStatus());
        assertEquals("SM-123", saved.getAllValues().get(1).getSid());
        verify(smsService).sendMessage(FROM, TO, CONTENT);
    }

    @Test
    void shouldMarkTheMessageAsFailedWhenTheProviderCallFails() {
        when(contactRepository.findByPhoneNumber(TO)).thenReturn(Optional.of(existingContact()));
        when(smsService.sendMessage(FROM, TO, CONTENT)).thenThrow(new RuntimeException("provider down"));

        assertThrows(RuntimeException.class, () -> sendMessageUseCase.execute(FROM, TO, CONTENT));

        ArgumentCaptor<Message> saved = ArgumentCaptor.forClass(Message.class);
        verify(messageRepository, times(2)).save(saved.capture());
        assertEquals(MessageStatus.PENDING, saved.getAllValues().get(0).getStatus());
        assertEquals(MessageStatus.FAILED, saved.getAllValues().get(1).getStatus());
    }

    @Test
    void shouldRejectANonRegisteredContactAsNotFound() {
        when(contactRepository.findByPhoneNumber(TO)).thenReturn(Optional.empty());

        assertThrows(NotFoundException.class,
                () -> sendMessageUseCase.execute(FROM, TO, CONTENT));

        verify(messageRepository, times(0)).save(any());
    }
}
