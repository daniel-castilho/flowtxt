package ca.flowtxt.infrastructure.web.exception;

import ca.flowtxt.domain.common.ConflictException;
import ca.flowtxt.domain.common.ForbiddenException;
import ca.flowtxt.domain.common.InvalidCredentialsException;
import ca.flowtxt.domain.common.NotFoundException;
import ca.flowtxt.infrastructure.web.dto.response.ErrorResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import java.util.HashMap;
import java.util.Map;

/**
 * Centralized translation of exceptions into the canonical
 * {@link ErrorResponse} envelope. The 500 handler logs method + URI + exception
 * class (so an unexpected failure is a 30-second diagnosis) and never leaks the
 * internal message back to the client.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger logger = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleMethodArgumentNotValid(
            final MethodArgumentNotValidException ex, final HttpServletRequest request) {
        final Map<String, String> fieldErrors = new HashMap<>();
        ex.getBindingResult().getFieldErrors().forEach(error ->
                fieldErrors.put(error.getField(), error.getDefaultMessage()));

        return buildResponse(
                HttpStatus.BAD_REQUEST,
                "Validation Error",
                "One or more fields have an error",
                request,
                fieldErrors);
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorResponse> handleConstraintViolation(
            final ConstraintViolationException ex, final HttpServletRequest request) {
        final Map<String, String> fieldErrors = new HashMap<>();
        ex.getConstraintViolations().forEach(violation ->
                fieldErrors.put(violation.getPropertyPath().toString(), violation.getMessage()));

        return buildResponse(
                HttpStatus.BAD_REQUEST,
                "Validation Error",
                "One or more parameters have an error",
                request,
                fieldErrors);
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ErrorResponse> handleMethodArgumentTypeMismatch(
            final MethodArgumentTypeMismatchException ex, final HttpServletRequest request) {
        return buildResponse(
                HttpStatus.BAD_REQUEST,
                "Validation Error",
                "Invalid value for parameter '" + ex.getName() + "'",
                request,
                null);
    }

    @ExceptionHandler({InvalidCredentialsException.class, BadCredentialsException.class})
    public ResponseEntity<ErrorResponse> handleInvalidCredentials(
            final RuntimeException ex, final HttpServletRequest request) {
        // Generic message: never reveal whether an account exists.
        return buildResponse(
                HttpStatus.UNAUTHORIZED,
                "Unauthorized",
                "Invalid credentials",
                request,
                null);
    }

    @ExceptionHandler(NotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(
            final NotFoundException ex, final HttpServletRequest request) {
        return buildResponse(HttpStatus.NOT_FOUND, "Not Found", ex.getMessage(), request, null);
    }

    @ExceptionHandler(ConflictException.class)
    public ResponseEntity<ErrorResponse> handleConflict(
            final ConflictException ex, final HttpServletRequest request) {
        return buildResponse(HttpStatus.CONFLICT, "Conflict", ex.getMessage(), request, null);
    }

    @ExceptionHandler(ForbiddenException.class)
    public ResponseEntity<ErrorResponse> handleForbidden(
            final ForbiddenException ex, final HttpServletRequest request) {
        return buildResponse(HttpStatus.FORBIDDEN, "Forbidden", ex.getMessage(), request, null);
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleAccessDenied(
            final AccessDeniedException ex, final HttpServletRequest request) {
        return buildResponse(
                HttpStatus.FORBIDDEN,
                "Forbidden",
                "You do not have permission to access this resource",
                request,
                null);
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<ErrorResponse> handleStateConflict(
            final IllegalStateException ex, final HttpServletRequest request) {
        // Message lifecycle conflicts and other state violations map to 409.
        return buildResponse(
                HttpStatus.CONFLICT,
                "Conflict",
                ex.getMessage(),
                request,
                null);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorResponse> handleIllegalArgument(
            final IllegalArgumentException ex, final HttpServletRequest request) {
        return buildResponse(
                HttpStatus.BAD_REQUEST,
                "Bad Request",
                ex.getMessage(),
                request,
                null);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(
            final Exception ex, final HttpServletRequest request) {
        logger.error("Unexpected error on {} {}: {} - {}",
                request.getMethod(),
                request.getRequestURI(),
                ex.getClass().getSimpleName(),
                ex.getMessage(),
                ex);
        return buildResponse(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "Internal Server Error",
                "An unexpected error occurred. Please try again later.",
                request,
                null);
    }

    private ResponseEntity<ErrorResponse> buildResponse(
            final HttpStatus status,
            final String error,
            final String message,
            final HttpServletRequest request,
            final Map<String, String> validationErrors) {
        final ErrorResponse body = validationErrors == null
                ? ErrorResponse.of(status.value(), error, message, request.getRequestURI())
                : ErrorResponse.validation(status.value(), error, message, request.getRequestURI(), validationErrors);
        return ResponseEntity.status(status).body(body);
    }
}
