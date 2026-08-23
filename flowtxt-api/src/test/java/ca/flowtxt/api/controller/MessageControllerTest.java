package ca.flowtxt.api.controller;

import ca.flowtxt.api.support.RateLimitSliceTestConfig;
import ca.flowtxt.application.port.in.SendMessageUseCase;
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

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(MessageController.class)
@Import({GlobalExceptionHandler.class, SecurityConfig.class, JwtAuthenticationFilter.class,
        RateLimitSliceTestConfig.class})
class MessageControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private SendMessageUseCase sendMessageUseCase;

    @MockitoBean
    private JwtService jwtService;

    @Test
    @WithMockUser
    void sendDelegatesToUseCaseAndAnswers202() throws Exception {
        mockMvc.perform(post("/messages")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"from":"+15550000001","to":"+15550000002","content":"Hello!"}
                                """))
                .andExpect(status().isAccepted());

        verify(sendMessageUseCase).execute("+15550000001", "+15550000002", "Hello!");
    }

    @Test
    @WithMockUser
    void sendRejectsBlankContentWith400() throws Exception {
        mockMvc.perform(post("/messages")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"from":"+15550000001","to":"+15550000002","content":"  "}
                                """))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(sendMessageUseCase);
    }
}
