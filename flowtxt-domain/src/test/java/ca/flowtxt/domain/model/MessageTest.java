package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class MessageTest {

    @Test
    void shouldCreateMessageWithValidContact() {
        // Arrange
        var expectedId = UUID.randomUUID();
        var expectedContact = Contact.builder()
                .id(expectedId)
                .name("Daniel Castilho")
                .phoneNumber(new PhoneNumber("6477052644"))
                .build();
        var expectedContent = "Hello, how are you?";
        var expectedSentAt = Instant.now();
        Message message = Message.builder()
                .id(expectedId)
                .contact(expectedContact)
                .content(expectedContent)
                .timestamp(expectedSentAt)
                .build();

        // Act & Assert
        assertNotNull(message);
        assertEquals(expectedId, message.getId());
        assertEquals(expectedContact, message.getContact());
        assertEquals(expectedContent, message.getContent());
        assertEquals(expectedSentAt, message.getTimestamp());
    }
}
