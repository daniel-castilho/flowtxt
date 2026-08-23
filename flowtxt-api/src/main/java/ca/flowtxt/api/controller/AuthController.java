package ca.flowtxt.api.controller;

import ca.flowtxt.api.dto.AuthResponse;
import ca.flowtxt.api.dto.LoginRequest;
import ca.flowtxt.api.dto.RegisterUserRequest;
import ca.flowtxt.application.port.in.AuthResult;
import ca.flowtxt.application.port.in.AuthenticateUserUseCase;
import ca.flowtxt.application.port.in.RegisterUserUseCase;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/auth")
public class AuthController {

    private final RegisterUserUseCase registerUserUseCase;
    private final AuthenticateUserUseCase authenticateUserUseCase;

    public AuthController(
            RegisterUserUseCase registerUserUseCase,
            AuthenticateUserUseCase authenticateUserUseCase) {
        this.registerUserUseCase = registerUserUseCase;
        this.authenticateUserUseCase = authenticateUserUseCase;
    }

    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(@Valid @RequestBody RegisterUserRequest request) {
        AuthResult result = registerUserUseCase.register(request.email(), request.password());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(toResponse(result));
    }

    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        AuthResult result = authenticateUserUseCase.authenticate(request.email(), request.password());
        return ResponseEntity.ok(toResponse(result));
    }

    private AuthResponse toResponse(AuthResult result) {
        return new AuthResponse(
                result.token(),
                result.user().getEmail(),
                result.user().getRole());
    }
}
