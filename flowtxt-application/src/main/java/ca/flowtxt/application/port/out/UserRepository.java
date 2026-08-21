package ca.flowtxt.application.port.out;

import ca.flowtxt.domain.model.User;

import java.util.Optional;

public interface UserRepository {

    Optional<User> findByEmail(String email);

    void save(User user);
}
