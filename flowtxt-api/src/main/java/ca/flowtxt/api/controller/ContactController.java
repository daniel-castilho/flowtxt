package ca.flowtxt.api.controller;

import ca.flowtxt.api.dto.ContactRequest;
import ca.flowtxt.api.dto.ContactResponse;
import ca.flowtxt.application.port.in.RegisterContactUseCase;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/contacts")
public class ContactController {

    private final RegisterContactUseCase registerContactUseCase;

    public ContactController(RegisterContactUseCase registerContactUseCase) {
        this.registerContactUseCase = registerContactUseCase;
    }

    @PostMapping
    public ResponseEntity<ContactResponse> registerContact(@Valid @RequestBody ContactRequest request) {
        var contact = registerContactUseCase.execute(
                request.name(),
                request.phoneNumber());

        return ResponseEntity.ok(new ContactResponse(
                contact.getId().toString(),
                contact.getName(),
                contact.getPhoneNumber().getValue()
        ));
    }
}
