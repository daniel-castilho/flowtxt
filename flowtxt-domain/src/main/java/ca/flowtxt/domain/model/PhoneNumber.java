package ca.flowtxt.domain.model;

/**
 * Phone number value object. Immutable and validated at construction;
 * full E.164 validation is tracked as a backlog improvement.
 */
public record PhoneNumber(String value) {

    public PhoneNumber {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Phone number cannot be null or blank");
        }
    }
}
