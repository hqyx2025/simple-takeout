package com.example.takeout.service.thirdparty;

import com.example.takeout.common.BizException;
import jakarta.mail.Session;
import jakarta.mail.internet.MimeMessage;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.Properties;

import static org.junit.jupiter.api.Assertions.*;

class QQEmailSenderTest {
    private final QQEmailSender sender = new QQEmailSender("smtp.qq.com", 465,
            "sender@qq.com", "test-authorization-code", "简单外卖", 900);

    @Test
    void bothRecoveryEmailsExplainPurposeTargetExpiryAndNextStepsWithoutExposingPhone() throws Exception {
        for (String purpose : new String[]{"login", "payment"}) {
            String label = purpose.equals("login") ? "登录密码" : "支付密码";
            MimeMessage message = sender.createMessage("user@example.com", "123456",
                    "recovery:12:" + purpose + ":13800138000:user@example.com");
            ByteArrayOutputStream wire = new ByteArrayOutputStream();
            message.writeTo(wire);
            MimeMessage received = new MimeMessage(Session.getInstance(new Properties()),
                    new ByteArrayInputStream(wire.toByteArray()));
            assertEquals("【简单外卖】找回" + label + "验证码", received.getSubject());
            String text = (String) received.getContent();
            assertTrue(text.contains("138****8000"));
            assertFalse(text.contains("13800138000"));
            assertTrue(text.contains("验证码：123456"));
            assertTrue(text.contains("15 分钟，仅可使用一次"));
            assertTrue(text.contains("找回" + label));
            assertTrue(text.contains("确认重置"));
            assertTrue(text.contains("同一邮箱可绑定多个账户"));
            assertTrue(text.contains("最新一封邮件"));
            assertTrue(text.contains("如果不是您本人操作"));
            assertTrue(text.contains("仅收到本邮件不会修改您的密码"));
            assertTrue(text.contains("不会向您索要验证码"));
        }
    }

    @Test
    void invalidPurposeOrDifferentRecipientIsRejectedBeforeTransport() {
        assertThrows(BizException.class, () -> sender.createMessage("user@example.com", "123456",
                "recovery:12:other:13800138000:user@example.com"));
        assertThrows(BizException.class, () -> sender.createMessage("other@example.com", "123456",
                "recovery:12:login:13800138000:user@example.com"));
    }

    @Test
    void registrationMailExplainsVerificationWithoutPasswordRecoveryInstructions() throws Exception {
        MimeMessage message = sender.createMessage("user@example.com", "123456",
                "registration:13800138000:user@example.com");
        assertEquals("【简单外卖】注册邮箱验证码", message.getSubject());
        String text = (String) message.getContent();
        assertTrue(text.contains("注册简单外卖账户并验证绑定邮箱"));
        assertTrue(text.contains("138****8000"));
        assertTrue(text.contains("邮箱验证通过后才会创建账户"));
        assertTrue(text.contains("不可用于找回密码"));
        assertTrue(text.contains("仅收到本邮件不会创建账户或绑定邮箱"));
        assertFalse(text.contains("找回登录密码"));
    }
}
