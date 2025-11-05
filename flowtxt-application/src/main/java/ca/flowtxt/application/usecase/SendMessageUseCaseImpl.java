package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.SendMessageUseCase;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public class SendMessageUseCaseImpl implements SendMessageUseCase {

    private final ContactRepository contactRepository;
    private final MessageRepository messageRepository;
    private final SmsService smsService;

    public SendMessageUseCaseImpl(
            final ContactRepository contactRepository,
            final MessageRepository messageRepository,
            final SmsService smsService) {
        this.contactRepository = contactRepository;
        this.messageRepository = messageRepository;
        this.smsService = smsService;
    }

    @Override
    public void execute(final String from, final String to, final String messageText) {
        Optional<Contact> contactOpt = contactRepository.findByPhoneNumber(to);

        var contact = contactOpt.orElseThrow(() -> new IllegalArgumentException("Contact not found for phone: " + to));

        Message message = Message.builder()
                .id(UUID.randomUUID())
                .contact(contact)
                .content(messageText)
                .timestamp(Instant.now())
                .status(MessageStatus.PENDING)
                .build();

        // Persist message
        messageRepository.save(message);

        // Send SMS via provider
        var sid = smsService.sendMessage(from, to, messageText);

        // Update status (PENDING -> SENT)
        message.setStatus(MessageStatus.SENT);
        message.setSid(sid);
        messageRepository.save(message);
    }
}
