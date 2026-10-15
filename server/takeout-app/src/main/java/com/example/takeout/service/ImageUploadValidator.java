package com.example.takeout.service;

import com.example.takeout.common.BizException;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.util.Locale;
import java.util.Set;

final class ImageUploadValidator {

    private static final Set<String> EXTENSIONS = Set.of("jpg", "jpeg", "png", "webp", "gif");
    private static final Set<String> CONTENT_TYPES = Set.of("image/jpeg", "image/png", "image/webp", "image/gif", "image/jpg");
    private static final long MAX_BYTES = 5L * 1024 * 1024;

    private ImageUploadValidator() { }

    static String validate(MultipartFile file) {
        if (file == null || file.isEmpty()) throw new BizException("请选择要上传的图片");
        if (file.getSize() > MAX_BYTES) throw new BizException("图片大小不能超过 5MB");
        String name = file.getOriginalFilename() == null ? "" : file.getOriginalFilename();
        int index = name.lastIndexOf('.');
        String extension = index < 0 || index == name.length() - 1
                ? "" : name.substring(index + 1).toLowerCase(Locale.ROOT);
        if (!EXTENSIONS.contains(extension)) throw invalidImage();
        String declared = file.getContentType() == null ? "" : file.getContentType().toLowerCase(Locale.ROOT);
        if (!CONTENT_TYPES.contains(declared)) throw invalidImage();
        String detected = detect(file);
        String expected = switch (extension) {
            case "jpg", "jpeg" -> "image/jpeg";
            case "png" -> "image/png";
            case "webp" -> "image/webp";
            case "gif" -> "image/gif";
            default -> "";
        };
        if (!expected.equals(detected) || !(declared.equals(detected)
                || (detected.equals("image/jpeg") && declared.equals("image/jpg")))) {
            throw invalidImage();
        }
        return extension;
    }

    private static String detect(MultipartFile file) {
        try (InputStream input = file.getInputStream()) {
            byte[] header = input.readNBytes(12);
            if (startsWith(header, 0xFF, 0xD8, 0xFF)) return "image/jpeg";
            if (startsWith(header, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) return "image/png";
            if (startsWith(header, 'G', 'I', 'F') && header.length >= 6
                    && header[3] == '8' && (header[4] == '7' || header[4] == '9') && header[5] == 'a') {
                return "image/gif";
            }
            if (header.length >= 12 && startsWith(header, 'R', 'I', 'F', 'F')
                    && header[8] == 'W' && header[9] == 'E' && header[10] == 'B' && header[11] == 'P') {
                return "image/webp";
            }
            return "";
        } catch (IOException e) {
            throw new BizException("图片读取失败，请稍后重试");
        }
    }

    private static boolean startsWith(byte[] bytes, int... prefix) {
        if (bytes.length < prefix.length) return false;
        for (int i = 0; i < prefix.length; i++) {
            if ((bytes[i] & 0xFF) != prefix[i]) return false;
        }
        return true;
    }

    private static BizException invalidImage() {
        return new BizException("仅支持 jpg / png / webp / gif 格式的图片");
    }
}
