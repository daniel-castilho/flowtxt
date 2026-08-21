package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.document.UserDocument;
import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface UserMapper {

    User toUser(UserDocument document);

    UserDocument toDocument(User user);
}
