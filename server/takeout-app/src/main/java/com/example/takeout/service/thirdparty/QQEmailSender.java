package com.example.takeout.service.thirdparty;

import com.example.takeout.common.BizException;
import jakarta.mail.Message;
import jakarta.mail.MessagingException;
import jakarta.mail.Session;
import jakarta.mail.Transport;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.util.Properties;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** QQ SMTP transport. The generated code remains owned and validated by the server. */
@Service
@ConditionalOnProperty(name = "takeout.sms.provider", havingValue = "qq-email")
public class QQEmailSender implements SmsSender {

    private static final Logger log = LoggerFactory.getLogger(QQEmailSender.class);
    private static final Pattern VERIFICATION_IDENTITY = Pattern.compile(
            "^(?:recovery:[1-9][0-9]*:(login|payment|signin)|(registration)):(1[0-9]{10}):(.+)$");

    private final String username;
    private final String authCode;
    private final String fromName;
    private final Session session;
    private final long ttlMinutes;

    public QQEmailSender(
            @Value("${takeout.sms.qq.smtp-host:smtp.qq.com}") String host,
            @Value("${takeout.sms.qq.smtp-port:465}") int port,
            @Value("${takeout.sms.qq.username:}") String username,
            @Value("${takeout.sms.qq.auth-code:}") String authCode,
            @Value("${takeout.sms.qq.from-name:简单外卖}") String fromName,
            @Value("${takeout.sms.code-ttl-seconds:900}") long ttlSeconds) {
        if (blank(host) || blank(username) || blank(authCode) || port < 1 || port > 65535) {
            throw new IllegalStateException("QQ SMTP configuration is incomplete");
        }
        this.ttlMinutes = (ttlSeconds + 59) / 60;
        this.username = username.trim();
        this.authCode = authCode;
        this.fromName = blank(fromName) ? "简单外卖" : fromName.trim();
        Properties properties = new Properties();
        properties.put("mail.smtp.host", host.trim());
        properties.put("mail.smtp.port", Integer.toString(port));
        properties.put("mail.smtp.auth", "true");
        properties.put("mail.smtp.ssl.enable", "true");
        properties.put("mail.smtp.ssl.checkserveridentity", "true");
        properties.put("mail.smtp.connectiontimeout", "5000");
        properties.put("mail.smtp.timeout", "10000");
        properties.put("mail.smtp.writetimeout", "10000");
        this.session = Session.getInstance(properties);
    }

    @Override
    public void sendSmsCode(String email, String code) {
        throw new BizException("请通过注册或密码找回页面获取验证码");
    }

    @Override
    public void sendVerificationCode(String email, String code, String identity) {
        try {
            MimeMessage message = createMessage(email, code, identity);
            try (Transport transport = session.getTransport("smtp")) {
                transport.connect(username, authCode);
                transport.sendMessage(message, message.getAllRecipients());
            }
        } catch (MessagingException | java.io.UnsupportedEncodingException e) {
            // Provider exception text can contain recipients or authentication data.
            log.warn("QQ SMTP send failed: {}", e.getClass().getSimpleName());
            throw new BizException("验证码发送失败，请稍后重试");
        }
    }

    MimeMessage createMessage(String email, String code, String identity)
            throws MessagingException, java.io.UnsupportedEncodingException {
        if (!validEmail(email) || code == null || !code.matches("\\d{6}")) {
            throw new BizException("验证码发送失败，请稍后重试");
        }
        Matcher verification = VERIFICATION_IDENTITY.matcher(identity == null ? "" : identity);
        if (!verification.matches() || !email.equalsIgnoreCase(verification.group(4))) {
            throw new BizException("验证码发送失败，请稍后重试");
        }
        boolean registration = verification.group(2) != null;
        boolean signin = "signin".equals(verification.group(1));
        String purpose = registration ? "注册账号" : "login".equals(verification.group(1)) ? "登录密码" : "支付密码";
        String phone = verification.group(3);
        String maskedPhone = phone.substring(0, 3) + "****" + phone.substring(7);
        String operation = registration ? "注册简单外卖账户并验证绑定邮箱"
                : signin ? "使用邮箱验证码登录简单外卖账户" : "找回简单外卖账户的" + purpose;
        String instructions = registration ? """
                1. 返回简单外卖的“注册”页面。
                2. 核对账号名、手机号和邮箱，输入上方 6 位验证码。
                3. 设置登录密码并点击“注册”，邮箱验证通过后才会创建账户。
                """ : signin ? """
                1. 返回简单外卖的“验证码登录”页面。
                2. 核对手机号和绑定邮箱，输入上方 6 位验证码。
                3. 选择正确的登录端并点击“登录”。
                """ : """
                1. 返回简单外卖的“找回%s”页面。
                2. 核对手机号和绑定邮箱，输入上方 6 位验证码。
                3. 设置并确认新的%s，点击“确认重置”。
                """.formatted(purpose, purpose);
        String restriction = registration
                ? "本验证码仅用于上述手机号和邮箱的本次注册验证，不可用于找回密码。"
                : signin ? "本验证码仅用于上述账户的登录，不可用于注册或重置密码。"
                : "本验证码仅用于上述账户的本次" + purpose + "重置，不能用于其他账户或另一种密码。";
        String passiveResult = registration ? "仅收到本邮件不会创建账户或绑定邮箱。"
                : signin ? "仅收到本邮件不会登录您的账户或修改密码。" : "仅收到本邮件不会修改您的密码。";
        String body = """
                您好！

                您正在%s。
                对应手机号：%s

                验证码：%s
                有效期：%d 分钟，仅可使用一次。

                使用方法：
                %s
                温馨提示：
                · 同一邮箱可绑定多个账户，请先核对本邮件中的手机号及操作用途。
                · %s
                · 重新获取相同用途的验证码后，请使用最新一封邮件中的验证码。
                · 请勿向任何人透露验证码，简单外卖工作人员不会向您索要验证码。

                如果不是您本人操作，请忽略本邮件并留意账户安全。%s
                本邮件由系统自动发送，请勿直接回复。
                """.formatted(operation, maskedPhone, code, ttlMinutes, instructions, restriction, passiveResult);
        MimeMessage message = new MimeMessage(session);
        message.setFrom(new InternetAddress(username, fromName, StandardCharsets.UTF_8.name()));
        message.setRecipients(Message.RecipientType.TO, InternetAddress.parse(email.trim(), true));
        message.setSubject(registration ? "【简单外卖】注册邮箱验证码"
                : signin ? "【简单外卖】登录验证码" : "【简单外卖】找回" + purpose + "验证码", StandardCharsets.UTF_8.name());
        message.setText(body, StandardCharsets.UTF_8.name());
        message.saveChanges();
        return message;
    }

    private static boolean validEmail(String value) {
        return value != null && value.length() <= 254
                && value.matches("^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$");
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
