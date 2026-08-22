package ca.flowtxt.application.port.out;

import java.time.Duration;

/**
 * Simple key-value cache contract. Entries follow the
 * {@code flowtxt:<purpose>:<id>} key convention and every write MUST carry a
 * positive TTL — the signature makes an unbounded key unrepresentable
 * (coding-standards §6).
 */
public interface CacheService {

    /**
     * Stores {@code value} under {@code key}; the entry expires after
     * {@code ttl}.
     *
     * @throws IllegalArgumentException when {@code ttl} is null or not positive
     */
    void put(final String key, final Object value, final Duration ttl);

    Object get(final String key);

    void remove(final String key);
}
