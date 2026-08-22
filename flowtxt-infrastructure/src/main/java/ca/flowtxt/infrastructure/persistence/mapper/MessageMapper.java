package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.entity.MessageEntity;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.MappingTarget;

/**
 * Maps between the immutable domain {@link Message} and the JPA
 * {@link MessageEntity}. Field names align one-to-one (constructor mapping on
 * the domain side, setter mapping on the entity side).
 */
@Mapper(componentModel = "spring")
public interface MessageMapper {

    MessageEntity toEntity(Message message);

    /**
     * Applies the domain state onto an existing entity. The {@code version}
     * field is JPA-managed optimistic-locking bookkeeping: the immutable
     * domain does not carry it, and overwriting it would turn every update
     * into a false concurrent-modification conflict.
     */
    @Mapping(target = "version", ignore = true)
    void apply(Message message, @MappingTarget MessageEntity entity);

    Message toDomain(MessageEntity entity);
}
