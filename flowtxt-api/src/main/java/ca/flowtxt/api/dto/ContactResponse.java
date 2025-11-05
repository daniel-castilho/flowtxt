package ca.flowtxt.api.dto;

import lombok.AllArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
public class ContactResponse {

    private final String id;
    private final String name;
    private final String phoneNumber;
}
