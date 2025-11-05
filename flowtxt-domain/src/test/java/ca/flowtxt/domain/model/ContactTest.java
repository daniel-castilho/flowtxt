package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ContactTest {

    @Test
    void shouldCreateContactWithValidPhoneNumber() {
        // Arrange
        var expectedId = UUID.randomUUID();
        var expectedName = "Daniel Castilho";
        var expectedPhoneNumber = "6477052644";
        Contact contact = Contact.builder()
                .id(expectedId)
                .name(expectedName)
                .phoneNumber(new PhoneNumber(expectedPhoneNumber))
                .build();

        // Act & Assert
        assertNotNull(contact);
        assertEquals(expectedId, contact.getId());
        assertEquals(expectedName, contact.getName());
        assertEquals(expectedPhoneNumber, contact.getPhoneNumber().getValue());
    }

    @Test
    void shouldThrowExceptionForEmptyPhoneNumber() {
        // Arrange
        var expectedPhoneNumber = "";
        var expectedErrorMessage = "Phone number cannot be null or blank";

        // Act & Assert
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber(expectedPhoneNumber), expectedErrorMessage);
    }

}