package ca.flowtxt.application.port.in;

import ca.flowtxt.domain.model.User;

/**
 * Outcome of a successful authentication or registration: the authenticated
 * {@link User} plus a freshly issued bearer token. Returning both from the use
 * case keeps token issuance inside the application boundary so controllers stay
 * thin and never reference an infrastructure token service directly.
 */
public record AuthResult(User user, String token) {
}
