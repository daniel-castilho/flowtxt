package ca.flowtxt.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Message {

    private UUID id;
    private Contact contact;
    private String content;
    private MessageStatus status;
    private Instant timestamp;
    private String sid;
}
