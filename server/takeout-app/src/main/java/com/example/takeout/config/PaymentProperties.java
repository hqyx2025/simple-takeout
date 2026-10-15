package com.example.takeout.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "takeout.payment")
public class PaymentProperties {

    private boolean realEnabled;
    private boolean mockEnabled;
    private boolean sandbox = true;
    private final Wechat wechat = new Wechat();
    private final Alipay alipay = new Alipay();

    public boolean isRealEnabled() { return realEnabled; }
    public void setRealEnabled(boolean realEnabled) { this.realEnabled = realEnabled; }
    public boolean isMockEnabled() { return mockEnabled; }
    public void setMockEnabled(boolean mockEnabled) { this.mockEnabled = mockEnabled; }
    public boolean isSandbox() { return sandbox; }
    public void setSandbox(boolean value) { sandbox = value; }
    public Wechat getWechat() { return wechat; }
    public Alipay getAlipay() { return alipay; }

    public static class Wechat {
        private String mchId = "";
        private String appId = "";
        private String privateKeyPath = "";
        private String merchantSerialNumber = "";
        private String apiV3Key = "";
        private String notifyUrl = "";

        public String getMchId() { return mchId; }
        public void setMchId(String value) { mchId = value; }
        public String getAppId() { return appId; }
        public void setAppId(String value) { appId = value; }
        public String getPrivateKeyPath() { return privateKeyPath; }
        public void setPrivateKeyPath(String value) { privateKeyPath = value; }
        public String getMerchantSerialNumber() { return merchantSerialNumber; }
        public void setMerchantSerialNumber(String value) { merchantSerialNumber = value; }
        public String getApiV3Key() { return apiV3Key; }
        public void setApiV3Key(String value) { apiV3Key = value; }
        public String getNotifyUrl() { return notifyUrl; }
        public void setNotifyUrl(String value) { notifyUrl = value; }
    }

    public static class Alipay {
        private String appId = "9021000169644800";
        private String sellerId = "2088721115957570";
        private String gatewayUrl = "https://openapi-sandbox.dl.alipaydev.com/gateway.do";
        private String appPrivateKey = "";
        private String publicKey = "";
        private String notifyUrl = "";

        public String getAppId() { return appId; }
        public void setAppId(String value) { appId = value; }
        public String getSellerId() { return sellerId; }
        public void setSellerId(String value) { sellerId = value; }
        public String getGatewayUrl() { return gatewayUrl; }
        public void setGatewayUrl(String value) { gatewayUrl = value; }
        public String getAppPrivateKey() { return appPrivateKey; }
        public void setAppPrivateKey(String value) { appPrivateKey = value; }
        public String getPublicKey() { return publicKey; }
        public void setPublicKey(String value) { publicKey = value; }
        public String getNotifyUrl() { return notifyUrl; }
        public void setNotifyUrl(String value) { notifyUrl = value; }
    }
}
