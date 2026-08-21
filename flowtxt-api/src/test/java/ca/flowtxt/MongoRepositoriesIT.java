package ca.flowtxt;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MongoRepositoriesIT extends AbstractIntegrationTest {

    @Autowired
    private ContactRepository contactRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private MessageRepository messageRepository;

    @Test
    void persistsAndFindsAContactByPhoneNumber() {
        Contact contact = Contact.create("Maria Silva", new PhoneNumber("+5511999999999"));
        contactRepository.save(contact);

        assertTrue(contactRepository.findByPhoneNumber("+5511999999999").isPresent());
        assertEquals("Maria Silva",
                contactRepository.findByPhoneNumber("+5511999999999").get().getName());
    }

    @Test
    void persistsAndFindsAUserByEmail() {
        userRepository.save(User.register("it-user@example.com", "$2a$10$hash"));

        assertTrue(userRepository.findByEmail("it-user@example.com").isPresent());
        assertEquals(ca.flowtxt.domain.model.Role.USER,
                userRepository.findByEmail("it-user@example.com").get().getRole());
    }

    @Test
    void persistsAMessageAndFindsItBySidAfterItsLifecycleAdvances() {
        Contact contact = Contact.create("John Souza", new PhoneNumber("+5511888888888"));
        contactRepository.save(contact);

        Message message = Message.pending(contact.getId(), "Hello FlowTXT");
        messageRepository.save(message);
        messageRepository.save(message.markSent("SM-IT-123"));

        Message reloaded = messageRepository.findBySid("SM-IT-123").orElseThrow();
        assertEquals(MessageStatus.SENT, reloaded.getStatus());
        assertEquals("SM-IT-123", reloaded.getSid());

        messageRepository.save(reloaded.applyProviderStatus(MessageStatus.DELIVERED, "SM-IT-123"));
        assertEquals(MessageStatus.DELIVERED,
                messageRepository.findBySid("SM-IT-123").orElseThrow().getStatus());
    }
}
