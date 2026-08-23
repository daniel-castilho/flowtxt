package ca.flowtxt.infrastructure.config;

import ca.flowtxt.infrastructure.config.properties.TwilioProperties;
import ca.flowtxt.infrastructure.security.JwtAuthenticationFilter;
import ca.flowtxt.infrastructure.security.TwilioSignatureValidationFilter;
import ca.flowtxt.infrastructure.security.filter.RateLimitFilter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;

/**
 * Stateless JWT security: auth endpoints and the API docs are public; every
 * other route requires a valid bearer token. The default Spring Security
 * auto-configuration is re-enabled (it was previously excluded in
 * application.yaml).
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public TwilioSignatureValidationFilter twilioSignatureValidationFilter(
            TwilioProperties twilioProperties) {
        return new TwilioSignatureValidationFilter(twilioProperties.authToken());
    }

    @Bean
    public SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            JwtAuthenticationFilter jwtAuthenticationFilter,
            TwilioSignatureValidationFilter twilioSignatureValidationFilter,
            RateLimitFilter rateLimitFilter)
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
                        .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
                        .anyRequest().authenticated())
                // Missing/invalid token must be 401 Unauthorized (not Spring's
                // default 403), matching REST semantics and the IT contract.
                .exceptionHandling(ex -> ex.authenticationEntryPoint(
                        new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
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
