package ca.flowtxt.api.dto;

import jakarta.validation.constraints.NotBlank;

public record MessageRequest(

        @NotBlank(message = "'from' must not be blank")
        String from,

        @NotBlank(message = "'to' must not be blank")
        String to,

        @NotBlank(message = "'content' must not be blank")
        String content

) {}

