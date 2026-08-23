package ca.flowtxt.api.controller;

import ca.flowtxt.api.support.RateLimitSliceTestConfig;
import ca.flowtxt.application.port.in.AuthResult;
import ca.flowtxt.application.port.in.AuthenticateUserUseCase;
import ca.flowtxt.application.port.in.RegisterUserUseCase;
import ca.flowtxt.domain.common.InvalidCredentialsException;
import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.config.SecurityConfig;
import ca.flowtxt.infrastructure.security.JwtAuthenticationFilter;
import ca.flowtxt.infrastructure.security.JwtService;
import ca.flowtxt.infrastructure.web.exception.GlobalExceptionHandler;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(AuthController.class)
@Import({GlobalExceptionHandler.class, SecurityConfig.class, JwtAuthenticationFilter.class,
        RateLimitSliceTestConfig.class})
class AuthControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private RegisterUserUseCase registerUserUseCase;

    @MockitoBean
    private AuthenticateUserUseCase authenticateUserUseCase;

    @MockitoBean
    private UserDetailsService userDetailsService;

    @MockitoBean
    private JwtService jwtService;

    private AuthResult authResult(String email) {
        User user = new User(
                UUID.randomUUID(), email, "stored-hash", Role.USER,
                java.time.Instant.now());
        return new AuthResult(user, "jwt-token");
    }

    @Test
    void registerReturnsCreatedWithAToken() throws Exception {
        when(registerUserUseCase.register(any(), any())).thenReturn(authResult("user@example.com"));

        mockMvc.perform(post("/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.token").value("jwt-token"))
                .andExpect(jsonPath("$.email").value("user@example.com"))
                .andExpect(jsonPath("$.role").value("USER"));
    }

    @Test
    void loginReturnsOkWithAToken() throws Exception {
        when(authenticateUserUseCase.authenticate(any(), any()))
                .thenReturn(authResult("user@example.com"));

        mockMvc.perform(post("/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("jwt-token"));
    }

    @Test
    void registerRejectsInvalidEmail() throws Exception {
        mockMvc.perform(post("/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"not-an-email\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.error").value("Validation Error"));
    }

    @Test
    void loginRejectsInvalidCredentialsWith401() throws Exception {
        when(authenticateUserUseCase.authenticate(any(), any()))
                .thenThrow(new InvalidCredentialsException());

        mockMvc.perform(post("/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"user@example.com\",\"password\":\"wrong\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.status").value(401))
                .andExpect(jsonPath("$.message").value("Invalid credentials"));
    }
}
