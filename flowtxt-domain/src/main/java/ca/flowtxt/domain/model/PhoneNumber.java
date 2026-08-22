package ca.flowtxt.domain.model;

import java.util.regex.Pattern;

/**
 * Phone number value object in strict ITU-T E.164 format: a leading plus,
 * a country code without a leading zero, and at most fifteen digits in total
 * (e.g. {@code +5511999999999}). Immutable and validated at construction;
 * invalid input fails fast with {@link IllegalArgumentException}, which the
 * API layer maps to HTTP 400.
 */
public record PhoneNumber(String value) {

    private static final Pattern E164 = Pattern.compile("^\\+[1-9]\\d{1,14}$");

    public PhoneNumber {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Phone number cannot be null or blank");
        }
        if (!E164.matcher(value).matches()) {
            throw new IllegalArgumentException(
                    "Phone number must be in E.164 format (leading +, up to 15 digits): " + value);
        }
    }
}
