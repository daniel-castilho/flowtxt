-- FlowTXT initial schema (PostgreSQL 16)
-- Owned by Flyway: never edit applied migrations; add V2__, V3__, ... instead.

CREATE TABLE users (
    id            uuid PRIMARY KEY,
    email         varchar(255) NOT NULL UNIQUE,
    password_hash varchar(255) NOT NULL,
    role          varchar(20)  NOT NULL CHECK (role IN ('USER', 'ADMIN')),
    created_at    timestamptz  NOT NULL
);

CREATE TABLE contacts (
    id           uuid PRIMARY KEY,
    name         varchar(255) NOT NULL,
    phone_number varchar(32)  NOT NULL UNIQUE
);

CREATE TABLE messages (
    id         uuid PRIMARY KEY,
    contact_id uuid        NOT NULL REFERENCES contacts (id),
    content    text        NOT NULL,
    status     varchar(20) NOT NULL CHECK (status IN (
        'PENDING', 'QUEUED', 'SENT', 'DELIVERED', 'UNDELIVERED',
        'FAILED', 'RECEIVED', 'UNKNOWN')),
    timestamp  timestamptz NOT NULL,
    sid        varchar(64) UNIQUE,
    version    bigint      NOT NULL DEFAULT 0
);

CREATE INDEX idx_messages_contact_id ON messages (contact_id);
CREATE INDEX idx_messages_sid ON messages (sid);
