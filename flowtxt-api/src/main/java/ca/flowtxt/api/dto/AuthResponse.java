package ca.flowtxt.api.dto;

import ca.flowtxt.domain.model.Role;

public record AuthResponse(
        String token,
        String email,
        Role role
) {}
