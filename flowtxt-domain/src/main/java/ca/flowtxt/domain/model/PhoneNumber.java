package ca.flowtxt.domain.model;

import lombok.Value;

@Value
public class PhoneNumber {
    String value;

    public PhoneNumber(String value) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Phone number cannot be null or blank");
        }
        // TODO: Add phone number validation by regex
        this.value = value;
    }
}
