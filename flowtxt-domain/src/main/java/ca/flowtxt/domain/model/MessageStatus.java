package ca.flowtxt.domain.model;

public enum MessageStatus {
    PENDING,
    QUEUED,
    SENT,
    DELIVERED,
    UNDELIVERED,
    FAILED,
    RECEIVED, // opcional, se quiser rastrear mensagens recebidas
    UNKNOWN   // fallback seguro
}
