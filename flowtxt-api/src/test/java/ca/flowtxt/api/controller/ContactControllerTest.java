package ca.flowtxt.api.controller;

import ca.flowtxt.api.support.RateLimitSliceTestConfig;
import ca.flowtxt.application.port.in.RegisterContactUseCase;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.config.SecurityConfig;
import ca.flowtxt.infrastructure.security.JwtAuthenticationFilter;
import ca.flowtxt.infrastructure.security.JwtService;
import ca.flowtxt.infrastructure.web.exception.GlobalExceptionHandler;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.UUID;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(ContactController.class)
@Import({GlobalExceptionHandler.class, SecurityConfig.class, JwtAuthenticationFilter.class,
        RateLimitSliceTestConfig.class})
class ContactControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private RegisterContactUseCase registerContactUseCase;

    @MockitoBean
    private JwtService jwtService;

    @Test
    @WithMockUser
    void registerReturnsOkWithMappedDomainResponse() throws Exception {
        UUID id = UUID.randomUUID();
        when(registerContactUseCase.execute(eq("Alice"), eq("+15551234567")))
                .thenReturn(new Contact(id, "Alice", new PhoneNumber("+15551234567")));

        mockMvc.perform(post("/contacts")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Alice\",\"phoneNumber\":\"+15551234567\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(id.toString()))
                .andExpect(jsonPath("$.name").value("Alice"))
                .andExpect(jsonPath("$.phoneNumber").value("+15551234567"));
    }

    @Test
    @WithMockUser
    void registerRejectsNonE164PhoneWith400() throws Exception {
        mockMvc.perform(post("/contacts")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Alice\",\"phoneNumber\":\"5511999\"}"))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(registerContactUseCase);
    }
}
