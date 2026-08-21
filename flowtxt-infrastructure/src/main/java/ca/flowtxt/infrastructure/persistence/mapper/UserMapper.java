package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.entity.UserEntity;
import org.mapstruct.Mapper;

/**
 * Maps between the immutable domain {@link User} and the JPA
 * {@link UserEntity}.
 */
@Mapper(componentModel = "spring")
public interface UserMapper {

    User toUser(UserEntity entity);

    UserEntity toEntity(User user);
}
