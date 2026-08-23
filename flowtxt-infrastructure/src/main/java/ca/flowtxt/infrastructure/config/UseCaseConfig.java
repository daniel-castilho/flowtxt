package ca.flowtxt.infrastructure.config;

import ca.flowtxt.application.port.in.AuthenticateUserUseCase;
import ca.flowtxt.application.port.in.RegisterContactUseCase;
import ca.flowtxt.application.port.in.RegisterUserUseCase;
import ca.flowtxt.application.port.in.SendMessageUseCase;
import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.application.port.out.AuthenticationTokenPort;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.application.usecase.AuthenticateUserUseCaseImpl;
import ca.flowtxt.application.usecase.RegisterContactUseCaseImpl;
import ca.flowtxt.application.usecase.RegisterUserUseCaseImpl;
import ca.flowtxt.application.usecase.SendMessageUseCaseImpl;
import ca.flowtxt.application.usecase.UpdateMessageStatusUseCaseImpl;
import ca.flowtxt.domain.model.PasswordHasher;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class UseCaseConfig {

    @Bean
    public RegisterContactUseCase registerContactUseCase(final ContactRepository contactRepository) {
        return new RegisterContactUseCaseImpl(contactRepository);
    }

    @Bean
    public UpdateMessageStatusUseCase updateMessageStatusUseCase(final MessageRepository messageRepository) {
        return new UpdateMessageStatusUseCaseImpl(messageRepository);
    }

    @Bean
    public SendMessageUseCase sendMessageUseCase(
            final ContactRepository contactRepository,
            final MessageRepository messageRepository,
            final SmsService smsService) {
        return new SendMessageUseCaseImpl(contactRepository, messageRepository, smsService);
    }

    @Bean
    public RegisterUserUseCase registerUserUseCase(
            final UserRepository userRepository,
            final PasswordHasher passwordHasher,
            final AuthenticationTokenPort authenticationTokenPort) {
        return new RegisterUserUseCaseImpl(userRepository, passwordHasher, authenticationTokenPort);
    }

    @Bean
    public AuthenticateUserUseCase authenticateUserUseCase(
            final UserRepository userRepository,
            final PasswordHasher passwordHasher,
            final AuthenticationTokenPort authenticationTokenPort) {
        return new AuthenticateUserUseCaseImpl(userRepository, passwordHasher, authenticationTokenPort);
    }
}
