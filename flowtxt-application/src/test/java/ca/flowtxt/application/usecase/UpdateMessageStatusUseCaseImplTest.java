package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.common.NotFoundException;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UpdateMessageStatusUseCaseImplTest {

    private static final String SID = "SM-123";

    @Mock
    private MessageRepository messageRepository;

    private UpdateMessageStatusUseCaseImpl useCase;

    @BeforeEach
    void setUp() {
        useCase = new UpdateMessageStatusUseCaseImpl(messageRepository);
    }

    private Message sentMessage() {
        return Message.pending(UUID.randomUUID(), "Hello!").markSent(SID);
    }

    @Test
    void appliesTheProviderStatusAndSavesTheTransition() {
        when(messageRepository.findBySid(SID)).thenReturn(Optional.of(sentMessage()));

        useCase.updateStatus(SID, MessageStatus.DELIVERED);

        ArgumentCaptor<Message> saved = ArgumentCaptor.forClass(Message.class);
        verify(messageRepository).save(saved.capture());
        assertEquals(MessageStatus.DELIVERED, saved.getValue().getStatus());
        assertEquals(SID, saved.getValue().getSid());
    }

    @Test
    void throwsNotFoundWhenNoMessageMatchesTheSid() {
        when(messageRepository.findBySid("missing")).thenReturn(Optional.empty());

        assertThrows(NotFoundException.class,
                () -> useCase.updateStatus("missing", MessageStatus.DELIVERED));
    }

    @Test
    void propagatesTheDomainRejectionForInvalidTransitions() {
        Message delivered = sentMessage().applyProviderStatus(MessageStatus.DELIVERED, SID);
        when(messageRepository.findBySid(SID)).thenReturn(Optional.of(delivered));

        assertThrows(IllegalStateException.class,
                () -> useCase.updateStatus(SID, MessageStatus.QUEUED));
    }
}
