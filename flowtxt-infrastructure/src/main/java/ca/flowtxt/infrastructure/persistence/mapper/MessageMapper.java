package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.entity.MessageEntity;
import org.mapstruct.Mapper;

/**
 * Maps between the immutable domain {@link Message} and the JPA
 * {@link MessageEntity}. Field names align one-to-one (constructor mapping on
 * the domain side, setter mapping on the entity side).
 */
@Mapper(componentModel = "spring")
public interface MessageMapper {

    MessageEntity toEntity(Message message);

    Message toDomain(MessageEntity entity);
}
