package ca.flowtxt.infrastructure.config;

import ca.flowtxt.application.port.in.RegisterContactUseCase;
import ca.flowtxt.application.port.in.SendMessageUseCase;
import ca.flowtxt.application.port.in.UpdateMessageStatusUseCase;
import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.SmsService;
import ca.flowtxt.application.usecase.RegisterContactUseCaseImpl;
import ca.flowtxt.application.usecase.SendMessageUseCaseImpl;
import ca.flowtxt.application.usecase.UpdateMessageStatusUseCaseImpl;
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
}
