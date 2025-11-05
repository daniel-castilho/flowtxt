package ca.flowtxt.api.controller;

import ca.flowtxt.api.dto.MessageRequest;
import ca.flowtxt.application.port.in.SendMessageUseCase;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/messages")
public class MessageController {

    private final SendMessageUseCase sendMessageUseCase;

    public MessageController(SendMessageUseCase sendMessageUseCase) {
        this.sendMessageUseCase = sendMessageUseCase;
    }

    @PostMapping
    public ResponseEntity<Void> sendMessage(@Valid @RequestBody MessageRequest request) {
        sendMessageUseCase.execute(request.from(), request.to(), request.content());
        return ResponseEntity.accepted().build();
    }
}
