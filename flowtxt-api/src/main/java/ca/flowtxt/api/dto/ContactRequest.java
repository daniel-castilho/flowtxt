package ca.flowtxt.api.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record ContactRequest(
        @NotBlank(message = "Name is required")
        String name,

        @NotBlank(message = "Phone number is required")
        // Edge-level mirror of the authoritative domain rule (PhoneNumber):
        // strict E.164, leading plus required.
        @Pattern(regexp = "^\\+[1-9]\\d{1,14}$", message = "Invalid phone number format")
        String phoneNumber
) {}
