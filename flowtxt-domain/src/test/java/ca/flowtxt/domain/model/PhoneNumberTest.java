package ca.flowtxt.domain.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class PhoneNumberTest {

    @Test
    void acceptsCanonicalE164Numbers() {
        assertEquals("+5511999999999", new PhoneNumber("+5511999999999").value());
        assertEquals("+15551234567", new PhoneNumber("+15551234567").value());
        assertEquals("+442071838750", new PhoneNumber("+442071838750").value());
    }

    @Test
    void rejectsNumbersWithoutTheLeadingPlus() {
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber("5511999999999"));
    }

    @Test
    void rejectsCountryCodesWithALeadingZero() {
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber("+01199999999"));
    }

    @Test
    void rejectsLettersSpacesAndPunctuation() {
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber("+5511 9999-9999"));
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber("+55abcdefghij"));
    }

    @Test
    void rejectsMoreThanFifteenDigits() {
        // 16 digits after the plus — one past the E.164 maximum.
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber("+55119999999999999"));
    }

    @Test
    void rejectsNullBlankAndBarePlus() {
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber(null));
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber("   "));
        assertThrows(IllegalArgumentException.class, () -> new PhoneNumber("+"));
    }
}
