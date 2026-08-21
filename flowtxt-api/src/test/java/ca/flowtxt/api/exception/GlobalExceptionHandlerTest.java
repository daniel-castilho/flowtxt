package ca.flowtxt.api.exception;

import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.BindingResult;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class GlobalExceptionHandlerTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    void mapsValidationErrorsToBadRequest() {
        BindingResult bindingResult = mock(BindingResult.class);
        when(bindingResult.getFieldErrors()).thenReturn(List.of(
                new FieldError("dto", "email", "Email must be a valid address"),
                new FieldError("dto", "password", "Password is required")));
        MethodArgumentNotValidException ex =
                new MethodArgumentNotValidException(null, bindingResult);

        ResponseEntity<Map<String, String>> response =
                handler.handleValidationExceptions(ex);

        assertEquals(400, response.getStatusCode().value());
        assertEquals("Email must be a valid address", response.getBody().get("email"));
        assertEquals("Password is required", response.getBody().get("password"));
    }

    @Test
    void mapsBusinessExceptionsToBadRequest() {
        ResponseEntity<String> response =
                handler.handleBusinessException(
                        new IllegalArgumentException("Contact not found"));

        assertEquals(400, response.getStatusCode().value());
        assertEquals("Contact not found", response.getBody());
    }

    @Test
    void mapsUnexpectedExceptionsToInternalServerError() {
        ResponseEntity<String> response =
                handler.handleException(new RuntimeException("boom"));

        assertEquals(500, response.getStatusCode().value());
        assertEquals("boom", response.getBody());
    }
}
