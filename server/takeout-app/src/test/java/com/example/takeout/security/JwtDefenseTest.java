package com.example.takeout.security;

import com.example.takeout.config.SecuritySecretsGuard;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.Date;
import static org.junit.jupiter.api.Assertions.*;

class JwtDefenseTest {
    private String secret() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        return Base64.getEncoder().encodeToString(bytes);
    }

    @Test void templateAndRepeatedMaterialCannotStart() {
        assertThrows(IllegalStateException.class, () -> new JwtUtil("replace-with-at-least-32-random-bytes", 72));
        assertThrows(IllegalStateException.class, () -> new JwtUtil(Base64.getEncoder().encodeToString(new byte[32]), 72));
    }

    @Test void issuedTokensWorkButOtherKeysAndIssuersCannotForgeAnAdmin() {
        String secret = secret();
        JwtUtil jwt = new JwtUtil(secret, 72);
        assertEquals(7, jwt.getUserId(jwt.parseToken(jwt.generateToken(7, 0))));
        String forged = new JwtUtil(secret(), 72).generateToken(1, 2);
        assertThrows(Exception.class, () -> jwt.parseToken(forged));
        String wrongIssuer = Jwts.builder().subject("1").issuer("other-app").claim("role", 2)
                .expiration(new Date(System.currentTimeMillis() + 60_000))
                .signWith(Keys.hmacShaKeyFor(Base64.getDecoder().decode(secret)), Jwts.SIG.HS256).compact();
        assertThrows(Exception.class, () -> jwt.parseToken(wrongIssuer));
    }

    @Test void crossPurposeKeyReuseCannotStart() {
        String first = secret();
        assertThrows(IllegalStateException.class, () -> new SecuritySecretsGuard(first, first, secret(), secret()));
        assertThrows(IllegalStateException.class, () -> new SecuritySecretsGuard(first, secret(), secret(), first));
        assertDoesNotThrow(() -> new SecuritySecretsGuard(secret(), secret(), secret(), secret()));
    }
}
