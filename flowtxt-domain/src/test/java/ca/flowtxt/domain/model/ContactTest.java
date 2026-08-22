package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ContactTest {

    @Test
    void createGeneratesAnIdentityAndKeepsTheGivenData() {
        Contact contact = Contact.create("Daniel Castilho", new PhoneNumber("+16477052644"));

        assertNotNull(contact.getId());
        assertEquals("Daniel Castilho", contact.getName());
        assertEquals("+16477052644", contact.getPhoneNumber().value());
    }

    @Test
    void rejectsABlankName() {
        assertThrows(IllegalArgumentException.class,
                () -> Contact.create("   ", new PhoneNumber("+16477052644")));
    }

    @Test
    void rejectsANullPhoneNumber() {
        assertThrows(IllegalArgumentException.class, () -> Contact.create("Daniel", null));
    }

    @Test
    void equalityIsByIdentityNotByFieldState() {
        UUID id = UUID.randomUUID();
        Contact original = new Contact(id, "Daniel Castilho", new PhoneNumber("+16477052644"));
        Contact reloaded = new Contact(id, "Different Name", new PhoneNumber("+15550001111"));

        assertEquals(original, reloaded);
        assertEquals(original.hashCode(), reloaded.hashCode());

        Contact other = Contact.create("Daniel Castilho", new PhoneNumber("+16477052644"));
        assertNotEquals(original, other);
    }

    @Test
    void shouldThrowExceptionForEmptyPhoneNumber() {
        var expectedErrorMessage = "Phone number cannot be null or blank";

        assertThrows(IllegalArgumentException.class,
                () -> new PhoneNumber(""), expectedErrorMessage);
    }
}
