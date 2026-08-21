package ca.flowtxt;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.Instant;
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
        Contact contact = Contact.builder()
                .id(UUID.randomUUID())
                .name("Maria Silva")
                .phoneNumber(new PhoneNumber("+5511999999999"))
                .build();

        contactRepository.save(contact);

        assertTrue(contactRepository.findByPhoneNumber("+5511999999999").isPresent());
        assertEquals("Maria Silva",
                contactRepository.findByPhoneNumber("+5511999999999").get().getName());
    }

    @Test
    void persistsAndFindsAUserByEmail() {
        User user = User.builder()
                .id(UUID.randomUUID())
                .email("it-user@example.com")
                .passwordHash("$2a$10$hash")
                .role(Role.USER)
                .createdAt(Instant.now())
                .build();

        userRepository.save(user);

        assertTrue(userRepository.findByEmail("it-user@example.com").isPresent());
        assertEquals(Role.USER,
                userRepository.findByEmail("it-user@example.com").get().getRole());
    }

    @Test
    void persistsAMessageAndUpdatesItsStatusBySid() {
        Contact contact = Contact.builder()
                .id(UUID.randomUUID())
                .name("João Souza")
                .phoneNumber(new PhoneNumber("+5511888888888"))
                .build();
        contactRepository.save(contact);

        Message message = Message.builder()
                .id(UUID.randomUUID())
                .contact(contact)
                .content("Olá FlowTXT")
                .status(MessageStatus.PENDING)
                .timestamp(Instant.now())
                .sid("SM-IT-123")
                .build();
        messageRepository.save(message);

        messageRepository.updateStatusBySid("SM-IT-123", MessageStatus.SENT);

        Message reloaded = messageRepository.findById(message.getId()).orElseThrow();
        assertEquals(MessageStatus.SENT, reloaded.getStatus());
    }
}
