package ca.flowtxt.infrastructure.config;

import ca.flowtxt.infrastructure.config.properties.TwilioProperties;
import ca.flowtxt.infrastructure.security.JwtAuthenticationFilter;
import ca.flowtxt.infrastructure.security.RestAccessDeniedHandler;
import ca.flowtxt.infrastructure.security.RestAuthenticationEntryPoint;
import ca.flowtxt.infrastructure.security.TwilioSignatureValidationFilter;
import ca.flowtxt.infrastructure.security.filter.RateLimitFilter;
import ca.flowtxt.infrastructure.security.handler.RestErrorResponseWriter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Stateless JWT security: auth endpoints, Twilio callbacks, health probes and
 * the API docs are public; every other route requires a valid bearer token.
 *
 * <p>All error paths - missing token, invalid token, insufficient authority,
 * bad Twilio signature - return the canonical JSON error envelope through the
 * shared {@link RestErrorResponseWriter}.</p>
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public TwilioSignatureValidationFilter twilioSignatureValidationFilter(
            TwilioProperties twilioProperties,
            RestErrorResponseWriter errorResponseWriter) {
        return new TwilioSignatureValidationFilter(twilioProperties.authToken(), errorResponseWriter);
    }

    @Bean
    public SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            JwtAuthenticationFilter jwtAuthenticationFilter,
            TwilioSignatureValidationFilter twilioSignatureValidationFilter,
            RateLimitFilter rateLimitFilter,
            RestAuthenticationEntryPoint authenticationEntryPoint,
            RestAccessDeniedHandler accessDeniedHandler)
            throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/auth/register", "/auth/login").permitAll()
                        // Twilio callbacks carry no bearer token; authenticity is
                        // enforced by the signature filter below instead.
                        .requestMatchers("/webhook/twilio/**").permitAll()
                        .requestMatchers(
                                "/swagger-ui.html", "/swagger-ui/**",
                                "/v3/api-docs/**", "/api-docs/**").permitAll()
                        // Liveness/readiness probes are polled by the load
                        // balancer/orchestrator without credentials; every
                        // other actuator route requires authentication.
                        .requestMatchers(
                                "/actuator/health/liveness",
                                "/actuator/health/readiness").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint(authenticationEntryPoint)
                        .accessDeniedHandler(accessDeniedHandler))
                // All three custom filters anchor on a BUILT-IN filter: Security 7
                // rejects custom-filter anchors ("does not have a registered
                // order"). Registration order puts login throttling first (rejected
                // brute-force traffic costs no signature/token work), then Twilio
                // signature validation, then JWT.
                .addFilterBefore(rateLimitFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterBefore(twilioSignatureValidationFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
