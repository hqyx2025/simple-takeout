package com.example.takeout.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PasswordUtilTest {

    @Test
    void hashesWithRandomSaltAndFitsExistingColumn() {
        String first = PasswordUtil.hash("secret123");
        String second = PasswordUtil.hash("secret123");

        assertNotEquals(first, second);
        assertTrue(first.length() <= 128);
        assertTrue(first.startsWith("pbkdf2-sha256$600000$"));
        assertTrue(PasswordUtil.matches("secret123", first));
        assertFalse(PasswordUtil.matches("wrong-secret", first));
        assertFalse(PasswordUtil.needsRehash(first));
    }

    @Test
    void verifiesExistingFixedSaltSha256HashesForMigration() {
        String existingSeedHash = "b86af4172288a2cd465eedefe52f92400e1ae6ad620609a340505ad63b4519cd";

        assertTrue(PasswordUtil.matches("123456", existingSeedHash));
        assertFalse(PasswordUtil.matches("wrong", existingSeedHash));
        assertTrue(PasswordUtil.needsRehash(existingSeedHash));
    }

    @Test
    void rejectsNullAndMalformedValues() {
        assertFalse(PasswordUtil.matches(null, PasswordUtil.hash("secret123")));
        assertFalse(PasswordUtil.matches("secret123", null));
        assertFalse(PasswordUtil.matches("secret123", "pbkdf2-sha256$bad$salt$key"));
        assertFalse(PasswordUtil.matches("secret123", "not-a-password-hash"));
    }
}
