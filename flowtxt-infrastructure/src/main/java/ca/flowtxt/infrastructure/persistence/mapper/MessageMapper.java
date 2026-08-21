package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.document.MessageDocument;
import org.mapstruct.Mapper;

/**
 * Field names align one-to-one between the immutable domain {@link Message}
 * (constructor mapping) and the mutable {@link MessageDocument} (setter
 * mapping), so no explicit @Mapping configuration is required.
 */
@Mapper(componentModel = "spring")
public interface MessageMapper {

    MessageDocument toDocument(Message message);

    Message toDomain(MessageDocument document);
}
