package ca.flowtxt.api.dto;

import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class TwilioDeliveryStatusRequest {
    private String MessageSid;
    private String MessageStatus;
    private String To;
    private String From;
    private String SmsStatus;
}

