package com.example.takeout.service;

import com.example.takeout.common.BizException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class FileStorageServiceTest {

    @TempDir
    Path tempDir;

    private FileStorageService storage;

    @Test
    void insufficientDiskReserveStopsWriting() {
        ReflectionTestUtils.setField(storage, "minFreeBytes", Long.MAX_VALUE);
        BizException error = assertThrows(BizException.class, () -> storage.store(
                new MockMultipartFile("file", "photo.jpg", "image/jpeg", bytes(0xFF, 0xD8, 0xFF))));
        org.junit.jupiter.api.Assertions.assertEquals(503, error.getCode());
    }

    @BeforeEach
    void setUp() throws IOException {
        storage = new FileStorageService(tempDir.toString());
        storage.init();
    }

    @Test
    void storesJpegPngWebpAndGifWhenExtensionAndMimeMatchTheirSignatures() throws IOException {
        assertStored("photo.jpg", "image/jpeg", bytes(0xFF, 0xD8, 0xFF, 0x00));
        assertStored("photo.png", "image/png", bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A));
        assertStored("photo.webp", "image/webp", bytes('R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'E', 'B', 'P'));
        assertStored("photo.gif", "image/gif", bytes('G', 'I', 'F', '8', '9', 'a'));
    }

    @Test
    void rejectsUnsupportedOrMismatchedFileContent() {
        assertRejected("photo.png", "image/png", bytes('n', 'o', 't', ' ', 'a', 'n', ' ', 'i', 'm', 'a', 'g', 'e'));
        assertRejected("photo.png", "image/gif", bytes('G', 'I', 'F', '8', '9', 'a'));
        assertRejected("photo.gif", "image/png", bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A));
        assertRejected("photo.jpg", "image/png", bytes(0xFF, 0xD8, 0xFF, 0x00));
        assertRejected("photo.svg", "image/svg+xml", bytes('<', 's', 'v', 'g', '>'));
    }

    @Test
    void allowsLegacyJpegMimeAliasOnlyForJpegContent() throws IOException {
        assertStored("photo.jpeg", "image/jpg", bytes(0xFF, 0xD8, 0xFF, 0x00));
    }

    @Test
    void rejectsLocalStorageWhenDisabled() throws IOException {
        Path disabledRoot = tempDir.resolve("disabled");
        FileStorageService disabledStorage = new FileStorageService(disabledRoot.toString());
        ReflectionTestUtils.setField(disabledStorage, "localStorageEnabled", false);

        disabledStorage.init();

        assertTrue(Files.notExists(disabledRoot));
        assertThrows(BizException.class, () -> disabledStorage.store(
                new MockMultipartFile("file", "photo.jpg", "image/jpeg", bytes(0xFF, 0xD8, 0xFF))));
    }

    private void assertStored(String name, String contentType, byte[] content) throws IOException {
        String url = storage.store(new MockMultipartFile("file", name, contentType, content));
        assertTrue(url.matches("/uploads/\\d{8}/[0-9a-f]{32}\\." + extension(name)));
        Path stored = tempDir.resolve(url.substring("/uploads/".length()));
        assertArrayEquals(content, Files.readAllBytes(stored));
    }

    private void assertRejected(String name, String contentType, byte[] content) {
        assertThrows(BizException.class,
                () -> storage.store(new MockMultipartFile("file", name, contentType, content)));
    }

    private String extension(String name) {
        return name.substring(name.lastIndexOf('.') + 1);
    }

    private byte[] bytes(int... values) {
        byte[] result = new byte[values.length];
        for (int i = 0; i < values.length; i++) result[i] = (byte) values[i];
        return result;
    }
}
