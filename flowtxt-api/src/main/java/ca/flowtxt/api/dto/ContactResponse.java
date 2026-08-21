package ca.flowtxt.api.dto;

public record ContactResponse(
        String id,
        String name,
        String phoneNumber
) {}
