package ca.flowtxt.application.usecase;

import ca.flowtxt.application.port.in.SendMessageUseCase;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;

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
        var contact = contactRepository.findByPhoneNumber(to)
                .orElseThrow(() -> new IllegalArgumentException("Contact not found for phone: " + to));

        var message = Message.pending(contact.getId(), messageText);
        messageRepository.save(message);

        try {
            var sid = smsService.sendMessage(from, to, messageText);
            messageRepository.save(message.markSent(sid));
        } catch (RuntimeException e) {
            // The provider rejected the send: record the FAILED transition so
            // the message never gets stuck in PENDING, then let the caller see
            // the failure.
            messageRepository.save(message.markFailed());
            throw e;
        }
    }
}
