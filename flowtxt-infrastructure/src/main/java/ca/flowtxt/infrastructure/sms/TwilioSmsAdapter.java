package ca.flowtxt.infrastructure.sms;

import ca.flowtxt.application.port.out.SmsService;
import com.twilio.Twilio;
import com.twilio.rest.api.v2010.account.Message;
import com.twilio.type.PhoneNumber;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;

@Slf4j
public class TwilioSmsAdapter implements SmsService {

    private final String accountSid;
    private final String authToken;
    private final String fromNumber;

    public TwilioSmsAdapter(
            @Value("${twilio.account-sid}") String accountSid,
            @Value("${twilio.auth-token}") String authToken,
            @Value("${twilio.phone-number}") String fromNumber) {
        this.accountSid = accountSid;
        this.authToken = authToken;
        this.fromNumber = fromNumber;

        String maskedAuthToken = authToken != null && authToken.length() > 4
                ? "****" + authToken.substring(authToken.length() - 4)
                : "****";

        log.info("Inicializando Twilio com Account SID: {}", accountSid);
        log.info("Auth Token (mascarado): {}", maskedAuthToken);
        log.info("Número de origem configurado: {}", fromNumber);

        try {
            Twilio.init(accountSid, authToken);
            log.info("Cliente Twilio inicializado com sucesso");
        } catch (Exception e) {
            log.error("Falha ao inicializar cliente Twilio: {}", e.getMessage(), e);
            throw e;
        }
    }

    @Override
    public String sendMessage(final String fromPhoneNumber, final String toPhoneNumber, final String content) {
        log.info("Enviando SMS - De: {}, Para: {}, Conteúdo: {}", fromPhoneNumber, toPhoneNumber, content);

        try {
            log.debug("Criando mensagem Twilio...");
            Message message = Message.creator(
                    new PhoneNumber(toPhoneNumber),
                    new PhoneNumber(fromPhoneNumber),
                    content
            ).create();

            String sid = message.getSid();
            log.info("SMS enviado com sucesso. SID da mensagem: {}", sid);
            return sid;

        } catch (Exception e) {
            log.error("Falha ao enviar SMS. Detalhes:", e);
            log.error("Classe do erro: {}", e.getClass().getName());
            log.error("Mensagem do erro: {}", e.getMessage());

            if (e.getCause() != null) {
                log.error("Causa raiz: {}: {}", e.getCause().getClass().getName(), e.getCause().getMessage());
            }

            throw new RuntimeException("Falha ao enviar SMS: " + e.getMessage(), e);
        }
    }

    @Override
    public void receiveMessage(String payload) {
        throw new UnsupportedOperationException("Webhook de recebimento ainda não implementado");
    }
}