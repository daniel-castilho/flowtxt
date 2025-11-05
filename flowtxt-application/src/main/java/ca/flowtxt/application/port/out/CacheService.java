package ca.flowtxt.application.port.out;

public interface CacheService {
    void put(final String key, final Object value);
    Object get(final String key);
    void remove(final String key);
}
