package com.example.takeout.security;

import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HexFormat;

/** Password hashing with versioned PBKDF2 and legacy SHA-256 verification. */
public final class PasswordUtil {

    private static final String ALGORITHM = "pbkdf2-sha256";
    private static final String LEGACY_SALT = "simple-takeout-2026";
    private static final int ITERATIONS = 600_000;
    private static final int MAX_ITERATIONS = 2_000_000;
    private static final int SALT_BYTES = 16;
    private static final int KEY_BYTES = 32;
    private static final SecureRandom RANDOM = new SecureRandom();

    private PasswordUtil() {
    }

    public static String hash(String rawPassword) {
        if (rawPassword == null) {
            throw new IllegalArgumentException("rawPassword cannot be null");
        }
        byte[] salt = new byte[SALT_BYTES];
        RANDOM.nextBytes(salt);
        return ALGORITHM + "$" + ITERATIONS + "$" + HexFormat.of().formatHex(salt) + "$"
                + HexFormat.of().formatHex(derive(rawPassword, salt, ITERATIONS));
    }

    public static boolean matches(String rawPassword, String encoded) {
        if (rawPassword == null || encoded == null) {
            return false;
        }
        if (isLegacy(encoded)) {
            return MessageDigest.isEqual(legacyHash(rawPassword), HexFormat.of().parseHex(encoded));
        }
        String[] fields = encoded.split("\\$", -1);
        if (fields.length != 4 || !ALGORITHM.equals(fields[0])) {
            return false;
        }
        try {
            int iterations = Integer.parseInt(fields[1]);
            if (iterations < 1 || iterations > MAX_ITERATIONS || fields[2].length() != SALT_BYTES * 2
                    || fields[3].length() != KEY_BYTES * 2) {
                return false;
            }
            byte[] salt = HexFormat.of().parseHex(fields[2]);
            byte[] expected = HexFormat.of().parseHex(fields[3]);
            return MessageDigest.isEqual(derive(rawPassword, salt, iterations), expected);
        } catch (IllegalArgumentException e) {
            return false;
        }
    }

    public static boolean needsRehash(String encoded) {
        if (isLegacy(encoded)) {
            return true;
        }
        if (encoded == null) {
            return false;
        }
        String[] fields = encoded.split("\\$", -1);
        if (fields.length != 4 || !ALGORITHM.equals(fields[0])) {
            return false;
        }
        try {
            return Integer.parseInt(fields[1]) < ITERATIONS;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    private static boolean isLegacy(String encoded) {
        return encoded != null && encoded.matches("[0-9a-f]{64}");
    }

    private static byte[] legacyHash(String rawPassword) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return digest.digest((LEGACY_SALT + rawPassword).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("SHA-256 不可用", e);
        }
    }

    private static byte[] derive(String rawPassword, byte[] salt, int iterations) {
        char[] password = rawPassword.toCharArray();
        PBEKeySpec spec = new PBEKeySpec(password, salt, iterations, KEY_BYTES * 8);
        try {
            return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("PBKDF2-HMAC-SHA256 不可用", e);
        } finally {
            spec.clearPassword();
            Arrays.fill(password, '\0');
        }
    }
}
