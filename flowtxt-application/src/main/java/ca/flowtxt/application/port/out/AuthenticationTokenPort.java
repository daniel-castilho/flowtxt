package ca.flowtxt.application.port.out;

import ca.flowtxt.domain.model.User;

/**
 * Outbound port for issuing an authentication token for an authenticated user.
 *
 * <p>The application layer depends only on this contract and never on a concrete
 * token provider (JWT, opaque token, external IdP...). The concrete adapter
 * lives in infrastructure and may be swapped without touching the use cases.</p>
 */
public interface AuthenticationTokenPort {

    /**
     * Issues a signed bearer token that identifies {@code user}. The token's
     * encoding, claims and expiry are the adapter's concern.
     */
    String issueToken(User user);
}
