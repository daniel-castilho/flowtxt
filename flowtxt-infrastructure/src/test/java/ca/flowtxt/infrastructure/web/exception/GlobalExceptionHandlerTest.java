package ca.flowtxt.infrastructure.web.exception;

import ca.flowtxt.domain.common.ConflictException;
import ca.flowtxt.domain.common.ForbiddenException;
import ca.flowtxt.domain.common.InvalidCredentialsException;
import ca.flowtxt.domain.common.NotFoundException;
import ca.flowtxt.infrastructure.web.dto.response.ErrorResponse;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.BeanPropertyBindingResult;
import org.springframework.validation.BindingResult;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;

import java.lang.reflect.Method;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class GlobalExceptionHandlerTest {

    private GlobalExceptionHandler handler;
    private HttpServletRequest request;

    // A real method so MethodParameter can be constructed without null.
    public void bindingTarget(String email) {
        // no-op: only the Method metadata is used by the test.
    }

    @BeforeEach
    void setUp() throws Exception {
        handler = new GlobalExceptionHandler();
        request = mock(HttpServletRequest.class);
        when(request.getRequestURI()).thenReturn("/test");
        when(request.getMethod()).thenReturn("POST");
    }

    private MethodParameter methodParameter() throws Exception {
        Method method = GlobalExceptionHandlerTest.class.getMethod("bindingTarget", String.class);
        return new MethodParameter(method, 0);
    }

    @Test
    void mapsValidationErrorsToBadRequestWithFieldErrors() throws Exception {
        BindingResult bindingResult = new BeanPropertyBindingResult(new Object(), "dto");
        bindingResult.addError(new FieldError("dto", "email", "Email must be a valid address"));
        bindingResult.addError(new FieldError("dto", "password", "Password is required"));
        MethodArgumentNotValidException ex =
                new MethodArgumentNotValidException(methodParameter(), bindingResult);

        ResponseEntity<ErrorResponse> response =
                handler.handleMethodArgumentNotValid(ex, request);

        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        ErrorResponse body = response.getBody();
        assertNotNull(body);
        assertEquals(400, body.status());
        assertEquals("Validation Error", body.error());
        assertEquals("/test", body.path());
        assertEquals("Email must be a valid address",
                body.validationErrors().get("email"));
        assertEquals("Password is required",
                body.validationErrors().get("password"));
    }

    @Test
    void mapsInvalidCredentialsToUnauthorizedWithoutLeakingExistence() {
        ResponseEntity<ErrorResponse> response =
                handler.handleInvalidCredentials(new InvalidCredentialsException(), request);

        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
        assertEquals("Invalid credentials", response.getBody().message());
    }

    @Test
    void mapsNotFoundTo404() {
        ResponseEntity<ErrorResponse> response =
                handler.handleNotFound(new NotFoundException("Message not found"), request);

        assertEquals(HttpStatus.NOT_FOUND, response.getStatusCode());
        assertEquals("Message not found", response.getBody().message());
    }

    @Test
    void mapsConflictTo409() {
        ResponseEntity<ErrorResponse> response =
                handler.handleConflict(new ConflictException("Email already registered"), request);

        assertEquals(HttpStatus.CONFLICT, response.getStatusCode());
        assertEquals("Email already registered", response.getBody().message());
    }

    @Test
    void mapsStateConflictTo409() {
        ResponseEntity<ErrorResponse> response =
                handler.handleStateConflict(
                        new IllegalStateException(
                                "Invalid message status transition from DELIVERED to SENT"),
                        request);

        assertEquals(HttpStatus.CONFLICT, response.getStatusCode());
        assertEquals("Invalid message status transition from DELIVERED to SENT",
                response.getBody().message());
    }

    @Test
    void mapsIllegalArgumentToBadRequest() {
        ResponseEntity<ErrorResponse> response =
                handler.handleIllegalArgument(
                        new IllegalArgumentException("Phone number must be in E.164 format"),
                        request);

        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertEquals("Phone number must be in E.164 format", response.getBody().message());
    }

    @Test
    void mapsForbiddenDomainExceptionTo403() {
        ResponseEntity<ErrorResponse> response =
                handler.handleForbidden(new ForbiddenException("Not allowed"), request);

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
    }

    @Test
    void mapsUnexpectedExceptionsToInternalServerErrorWithoutLeakingMessage() {
        ResponseEntity<ErrorResponse> response =
                handler.handleGeneric(new RuntimeException("boom"), request);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());
        ErrorResponse body = response.getBody();
        assertNotNull(body);
        // Internal exception message must never reach the client.
        assertEquals("An unexpected error occurred. Please try again later.", body.message());
        assertNull(body.validationErrors());
    }

    @Test
    void mapsAccessDeniedTo403() {
        ResponseEntity<ErrorResponse> response =
                handler.handleAccessDenied(
                        new org.springframework.security.access.AccessDeniedException("denied"),
                        request);

        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
    }

    @Test
    void errorResponseFactoryHelpersOmitNullOrEmptyValidationErrors() {
        ErrorResponse plain = ErrorResponse.of(404, "Not Found", "missing", "/x");
        assertNull(plain.validationErrors());

        ErrorResponse withErrors = ErrorResponse.validation(
                400, "Validation Error", "bad", "/x",
                java.util.Map.of("email", "required"));
        assertNotNull(withErrors.validationErrors());
        assertEquals("required", withErrors.validationErrors().get("email"));

        ErrorResponse fromEmpty = ErrorResponse.validation(
                400, "Validation Error", "bad", "/x", null);
        assertNull(fromEmpty.validationErrors());
    }
}
