# 红队复测报告 — infra 范围（网关 / 部署配置 / 上传 / 安全头 / 密钥 / 日志）

- 攻击者代号：infra-red
- 时间：2026-10-25（Asia/Shanghai）
- 目标：防守方 md/audit/defense/防御结果.md（V-01..V-20）修复后的本地源码 + 线上 https://hqyx.website/takeout/
- 方法：只读源码审计 + 本地可执行 PoC（真实网关过滤器类、真实 nginx 1.24.0 临时实例、docker compose config 解析）+ 线上低频只读探测
- 环境事实：本机 MySQL 8.4.0 / Redis 5.0.14 / nginx 1.24.0（C:/Software/Application/nginx/nginx-1.24.0-qk/nginx.exe）/ JDK 25.0.2 / docker compose v5.5.1（CLI 可用，daemon 未启动，只做 config 解析）
- 证据目录：md/audit/cache/round2-redteam/infra-red/（compose-main.json、compose-demo.json、poc_log_injection.py、nginx-*/logs/*.log）
- **本轮 infra 面未发现可直达资金的 Critical**；确认 High 2 / Medium 5 / Low 5，每条都有文件行号或命令输出。

---

## 发现总表

| 编号 | 级别 | 标题 | 线上状态 |
| --- | --- | --- | --- |
| R-01 | **High** | 主 docker-compose.yml 把网关发布到 0.0.0.0:8087，与“网关只绑宿主回环”的自述矛盾 | 线上未采用该编排（用 demo 覆盖）；实测 9087/3310/6387 均不可达 → 配置面 |
| R-02 | **High** | 线上跑 develop 档：两个 @Profile("production") 生产守卫全部不装配，安全边界退化为“私有 env 写对了” | 已实测可达（站点确为沙箱/develop 形态） |
| R-03 | Medium | 网关 XFF 超过 32 跳或畸形时**回退成对端地址**（单桶），真实类实测复现 | 未测（需 ≥10 次错登，受错登纪律限制） |
| R-04 | Medium | /uploads/** 文件不存在 → **404 被吞成 500 + 匿名无限制 ERROR 堆栈日志**，可冲掉审计归档 | **已实测可达** |
| R-05 | Medium | 全链路（宿主 nginx + 网关 + 应用）**无任何 HSTS**；防守方 V-11 自述漏项 | **已实测（头缺失）** |
| R-06 | Medium | BankCardCrypto 的 AES 密钥仍从 takeout.jwt.secret 派生 → “三种用途独立密钥”实际有第 4 个消费者 | 未测（需 JWT 密钥；静态证据确凿） |
| R-07 | Medium | .env 未迁移：文档所述 docker compose up -d 现在**起不来**，4 类真实第三方凭据从未轮换 | 已实测（解析/启动前置条件） |
| R-08 | Low | 部署脚本只把 log_format 注入宿主 nginx，**仓库里的 nginx-domain.conf 从未上线** → 代理头行为不可由仓库审计 | 未测（宿主文件不可读） |
| R-09 | Low | nginx 隐私日志的 request_id 是 nginx 自身随机值，与应用 X-Request-Id 无法关联；traceId 由客户端决定 | 已实测（响应头形态） |
| R-10 | Low | demo 编排 MYSQL_ROOT_HOST 设为 %：root 可从任意容器登录，“最小权限”被抵消 | 未测（不可读宿主） |
| R-11 | Low | server_tokens 未关；公网 nginx 1.24.0 与镜像内 1.28.3 版本漂移 | **已实测** |
| R-12 | Low | /api/location/* 无任何限流，等于给登录用户开放服务端高德 key 的转发器 | 未测（会消耗 key 配额，未打） |

---

## 详情

### R-01 ｜【High】主 docker-compose.yml 把网关发布到 0.0.0.0:8087

- **结论**：防守方 V-04 写“网关仍只绑定宿主回环地址”，这句话只对 demo 覆盖文件成立；仓库主 compose 仍把**统一 API 入口发布到全部网卡**，且没有 TLS、没有宿主 nginx 前置。
- **证据**
  - docker-compose.yml:210-212 ports 段：只有 “8087:8087” 形式，**没有 127.0.0.1 前缀**；对比 docker-compose.yml:29-31（mysql）与 :53-54（redis）都已改成 127.0.0.1 前缀。
  - docker compose -f docker-compose.yml config --format json 的实际解析结果（md/audit/cache/round2-redteam/infra-red/compose-main.json）：
        MAIN
          app:     ports=[(none)]
          gateway: ports=[0.0.0.0:8087->8087]     <-- 全部网卡
          mysql:   ports=[127.0.0.1:3310->3306]   <-- 已修
          redis:   ports=[127.0.0.1:6387->6379]   <-- 已修
        DEMO（-f docker-compose.yml -f docker-compose.demo.yml）
          gateway: ports=[127.0.0.1:8087->8087]   <-- 只有这里才是回环
          mysql / redis: ports=[(none)]
  - 主 compose 是 README:164 描述的标准启动方式（docker compose up -d --build，“7 个容器”那套）。
- **攻击链**
  1. 按 README 用主 compose 起环境（开发机 / 内网演示机 / 云主机）→ 网关在 0.0.0.0:8087 明文可访问。
  2. 同网段或公网直连 http://host:8087/ → 拿到完整网页 SPA 与 /api/**，全程 HTTP 明文（前端 JWT 在 Authorization 头里）。
  3. 绕过宿主 nginx 的全部加固（TLS、client_max_body_size、隐私访问日志、server 级策略）。
  4. 主 compose 未传 TAKEOUT_GATEWAY_TRUSTED_PROXY_REGEX，取默认值 127.0.0.1|::1；而真实对端是 docker bridge（172.17.0.1）⇒ nginx 注入的 XFF 被丢弃，来源退化为 bridge 地址 ⇒ **所有客户端共享一个 IP 限流桶**。
- **线上状态**：未采用该编排。实测 hqyx.website 上 9087/9080/3310/6387/6379/3306 全部 closed，仅 8087 开放且是宿主 nginx 的 308 跳转（见 R-11）。**配置面 High、线上当前不可达。**
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-04 只写“**主 Compose** 将数据库与 Redis 的宿主发布地址改为回环……网关仍只绑定宿主回环地址”——前半句真，后半句把 demo 覆盖的结果当成了主 compose 的结果。md/audit/cache/defense-round1/check_compose.py 的检查项只覆盖“数据库/Redis 绑定、认证、非 root 用户、危险资金开关、密钥用途分离”，**没有断言 gateway 的 host_ip**。
- **修复建议**
  - docker-compose.yml:212 改成 127.0.0.1 前缀形式（与 demo 对齐），对外暴露交给宿主 nginx。
  - check_compose.py 增加硬断言：除 gateway 外任何服务不得出现 0.0.0.0；gateway 的 host_ip 必须是 127.0.0.1。
  - 主 compose 显式传 TAKEOUT_GATEWAY_TRUSTED_PROXY_REGEX，不要让默认 127.0.0.1 在 bridge 场景静默生效。

---

### R-02 ｜【High】线上运行 develop 档：两个生产守卫全部不装配

- **结论**：ProductionHuaweiGuard / ProductionPaymentGuard 都是 @Profile("production")，而线上就是 develop 档（防守方自述），因此“生产必须 QQ 邮件 + OBS + 真实支付宝 + 非沙箱”这条 fail-closed 边界**在线上从未被执行**；真正生效的只有 DemoModeWarning（@Profile("!production")，只查 expose-mock-code 与 demo.recharge-enabled 两个开关）。
- **证据**
  - server/takeout-app/src/main/java/com/example/takeout/config/ProductionHuaweiGuard.java:9-21 —— @Profile("production")，强制 sms.provider==qq-email、upload.provider==obs。
  - .../config/ProductionPaymentGuard.java:11-27 —— @Profile("production")，强制 real-enabled / sandbox=false / 生产网关地址。
  - .../config/DemoModeWarning.java:8-16 —— @Profile("!production")，**只**校验 exposeMockCode 与 demoRechargeEnabled。
  - docker-compose.demo.yml:35 —— SPRING_PROFILES_ACTIVE 的默认值是 develop（fail-open 默认）。
  - docker-compose.demo.yml:41 —— TAKEOUT_SMS_PROVIDER 默认 mock；:59 —— TAKEOUT_UPLOAD_PROVIDER 默认 local。**默认就是 mock 短信 + 本地磁盘上传。**
  - application-develop.yml:12-17 —— upload.provider: local / local-enabled: true / payment.sandbox: true 硬编码。
  - 防守方自述（md/audit/defense/防御结果.md 部署章节）：“保留原有 **develop 体验环境**与支付宝沙箱配置”。
  - 线上侧佐证：所有响应 Server: nginx/1.24.0；/takeout/actuator*、/takeout/v3/api-docs、/takeout/swagger-ui/index.html 全 404（非 production 形态）。
- **攻击链 / 影响**（不是直接拿钱，而是安全边界整体不存在）
  1. profile=develop ⇒ 两个生产 Guard Bean 不创建 ⇒ “生产必须 OBS + 真实支付宝 + 非沙箱”的启动期强制全部消失。
  2. 于是私有 .env 漏写一个键就退化：TAKEOUT_SMS_PROVIDER 缺省 = mock ⇒ MockSmsSender（MockSmsSender.java:9-26）**不发信**但 exposesCodeForDevelopment() 返回 false ⇒ 注册/找回验证码永远收不到（静默故障）。TAKEOUT_UPLOAD_PROVIDER 缺省 = local ⇒ 上传落本地磁盘。
  3. 防守方对 V-01 的“任一 profile 的危险充值/赠金配置会阻止启动”是真修（AuthService.java:36-38 无条件校验），但**只覆盖充值/赠金两项**，替代不了被关掉的两个 production 守卫。
  4. 结论：线上安全完全依赖“私有 env 写对了”——正是“守卫靠 @Profile 装配但生产不装配”这一类。
- **线上状态**：已实测可达（develop + 沙箱形态可由响应与自述确认）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-06 与“上线前必须处理”第 1 条只要求“保持充值关闭、赠金为 0、验证码回传关闭、种子关闭”，把 profile 选择当成部署细节；自己写的“不要通过取消守卫来恢复启动”没有反向约束——**生产形态压根没装配守卫**。
- **修复建议**
  - docker-compose.demo.yml:35 把默认值改成 :? 强制显式（SPRING_PROFILES_ACTIVE 必填）。
  - 去掉两个 Production Guard 的 @Profile("production")，改为无条件 Bean + 按显式环境变量取阈值，让“生产要求”不依赖 profile 名字。
  - DemoModeWarning 补：develop 下若 sms.provider==mock 或 upload.provider==local，启动横幅打醒目 WARN。
  - check_compose.py 增加断言：SPRING_PROFILES_ACTIVE 不得有默认值。

---

### R-03 ｜【Medium】网关 XFF 超过 32 跳 / 畸形 → 回退成对端地址，限流桶重新塌陷

- **结论**：ClientIpHeadersFilter 在 hops>32、forwarded 长度>2048、或没有 XFF 时，**不做“取最右可信跳”的降级，而是把 client 留在对端地址**。只要前置代理是“追加”语义（proxy_add_x_forwarded_for）或漏配覆盖，攻击者 32 个逗号就能把所有人的限流桶并成一个——即 V-12 修的洞的同构复活。
- **证据**
  - server/takeout-gateway/src/main/java/com/example/takeout/gateway/web/ClientIpHeadersFilter.java:29-46：
        第 30 行  String client = peer;
        第 32 行  if (trusted.matcher(peer).matches() && forwarded != null && forwarded.length() <= 2048)
        第 34 行  if (hops.length <= 32) { ... }      <- >32 时整段跳过
        第 43 行  result.set("X-Forwarded-For", client);   <- client 仍是 peer
  - **用真实类实测**（临时 JUnit 驱动 ClientIpHeadersFilter，-Dtest=RedTeamXffTest，跑完立即删除，git status 无残留）：
        信任对端 = 172.17.0.1（docker bridge，线上真实形态）
        A 单跳                      -> 198.51.100.10
        B 伪造前缀 1.1.1.1, 真IP    -> 198.51.100.10    （正确）
        C 31 跳 + 真IP              -> 198.51.100.10    （正确）
        D 32 跳 + 真IP              -> 172.17.0.1       <-- 回退对端
        E 63 跳                     -> 172.17.0.1       <-- 回退对端
        F 真IP, not-an-ip           -> 172.17.0.1       <-- 回退对端
        G 200 跳（>2048 字节）      -> 172.17.0.1       <-- 回退对端
        H 无 XFF                    -> 172.17.0.1       <-- 回退对端
        I 33 跳 + 公网对端           -> 203.0.113.7      （公网对端不受影响）
        J "[::1]"                   -> [::1]            （括号形态原样写入 XFF）
        K "::ffff:198.51.100.10"    -> ::ffff:198.51.100.10
        L 两个不同真 IP              -> 198.51.100.10 / 198.51.100.11（正常隔离）
  - 下游一致性：LoginRateLimiter.java:124-130 的 clientIp() 取 request.getRemoteAddr()，由 Tomcat RemoteIpValve 按 application.yml:10 的 internal-proxies（含 172.16/12）信任上游 XFF ⇒ 网关写什么，应用就用什么。“回退成 172.17.0.1”等于全站共用一个 IP 桶。
- **攻击链（需前置代理为追加语义）**
  1. 向 /api/auth/login 发 10 次错口令，每次带 ≥32 段的 X-Forwarded-For。
  2. 若宿主 nginx 用 proxy_add_x_forwarded_for：上行 XFF = “32 段伪造 + 真 IP”，网关判 hops>32 ⇒ 写 X-Forwarded-For = docker bridge 地址。
  3. 应用 clientIp() = 该 bridge 地址，10 次后写 takeout:rl:login:<bridge>:blocked（TTL 600s）⇒ **所有用户登录 429**；每 10 分钟可再来，持续压制登录入口（F-INFRA-03 原样复活）。
  4. 同一机理打击 register（5/3600s）、email-code、upload 等全部 IP 桶策略。
- **线上状态**：**未测**。原因：(a) 需 ≥10 次错登才能证实共享桶，违反“错登最多 1-2 次”的探测纪律；(b) 是否可达取决于宿主 nginx 用覆盖还是追加——仓库里是覆盖（nginx-domain.conf:34 proxy_set_header X-Forwarded-For $remote_addr），但那份文件并未真正上线（见 R-08），宿主实际行为不可读。**代码侧缺陷确凿（真实类实测），线上可利用性未证实。**
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-05 只说“公网直连忽略自带转发头，受控代理按链路从右向左解析”；ClientIpHeadersFilterTest.java:23-40 只测了单跳、伪造前缀、三跳三种正常形态，**没有 32 跳上界、2048 字节上界、空 XFF、畸形跳的用例**。降级路径被写成“回退对端”，而正确语义应是“回退到已校验的最右一跳 / 拒绝请求”。
- **修复建议**
  - ClientIpHeadersFilter.java:32-42：超界或解析失败时不要回退 peer。改为①从右往左扫最后一个有效 IP（只截断、不整段丢弃）；②完全无法解析 → 返回 400/429 或写入显式不可伪标记，并让限流走“账号维度”而不是共享常量桶。
  - LoginRateLimiter.clientIp()：识别到解析结果是内部地址（127.0.0.1 / 172.16/12）时改为账号维度限流 + WARN，不要落进共享 IP 桶。
  - 补测试：32/33 跳、2048/2049 字节、空 XFF、畸形跳、方括号 IPv6。

---

### R-04 ｜【Medium】/uploads/** 文件不存在 → 404 被吞成 500 + 匿名无限制 ERROR 堆栈日志

- **结论**：任何不存在的上传路径都返回 500（应为 404），且每条都在应用日志写完整 NoResourceFoundException 堆栈；该路径**不经过 /api/** 的任何鉴权与限流**，匿名可无限刷 → 日志被灌满并挤掉真实审计归档。
- **证据**
  - 线上实测（只读 GET）：
        GET /takeout/uploads                        -> 500 {"code":500,"message":"服务器内部错误，请稍后重试","data":null}
        GET /takeout/uploads/20261025/x.jpg         -> 500 同上
        GET /takeout/uploads/20261025/              -> 500 同上
        GET /takeout/uploads/../application.yml     -> 404（nginx 归一化，未穿越）
        GET /takeout/uploads/%2e%2e/application.yml -> 404
  - server/takeout-common/src/main/java/com/example/takeout/common/GlobalExceptionHandler.java:69-74 —— @ExceptionHandler(Exception.class) + @ResponseStatus(500) + log.error("服务器内部错误", e)。缺文件在 Spring 6.1+ 抛 NoResourceFoundException，**没有专门处理器** ⇒ 落进兜底分支。
  - server/takeout-app/src/main/java/com/example/takeout/config/WebConfig.java:31-37 把 /uploads/** 交给 Spring ResourceHttpRequestHandler；:41-42 只对 /api/** 注册 apiRequestLoggingInterceptor，AuthInterceptor 同样只覆盖 /api/** ⇒ /uploads/** 完全无鉴权、无限流。
  - 日志可被清空的机制：server/takeout-app/src/main/resources/logback-spring.xml:30-35 —— maxFileSize 2MB / maxHistory 30 / totalSizeCap 500MB；到达 totalSizeCap 后 logback **删除最旧归档**。
- **攻击链**
  1. 匿名循环 GET /takeout/uploads/<random>.jpg（无需账号、无限流、两个 app 实例都吃）。
  2. 每次写约 2–3KB ERROR 堆栈；约 20 万次即写满 500MB 配额。
  3. 轮转 + gzip 持续占 CPU/IO；totalSizeCap 触发后最旧日志被删 ⇒ **30 天保留期塌缩成几分钟，操作审计与安全事件痕迹被主动清除**（反取证）。
  4. 附带语义破坏：前端把“图没了”显示成“服务器内部错误”。
- **线上状态**：**已实测可达**（500 + 通用错误体，未触发任何限流）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-18 只处理“日志里写了什么”（去来源标识与查询串），没处理“谁能让日志无限增长”。GlobalExceptionHandler.java:39-49 的注释自己写着“原实现落到下面的兜底分支”——他们只补了 4 个参数类异常，**漏了静态资源 404 这一类**。
- **修复建议**
  - GlobalExceptionHandler 增加 @ExceptionHandler(NoResourceFoundException.class) → 404 + log.debug（不打堆栈）。
  - WebConfig 给 /uploads/** 加轻量限流（复用 LoginRateLimiter，action=uploads-static，例如 120/min/IP），或宿主 nginx 对 /takeout/uploads/ 加 limit_req。
  - logback-spring.xml：把静态资源相关 logger 降到 WARN 并去掉堆栈；审计日志单独 appender，不参与 totalSizeCap 淘汰。

---

### R-05 ｜【Medium】全链路无 HSTS，防守方 V-11 自述漏项

- **结论**：宿主 nginx、网关 SecurityHeadersFilter、应用 SecurityHeadersFilter 三处都没有 Strict-Transport-Security。纯 HTTPS 站点缺 HSTS ⇒ SSL-strip / 降级到 http:// 可静默成功，登录口令与 JWT 在第一跳就明文暴露。
- **证据**
  - 线上实测（只读 GET，两次）：
        https://hqyx.website/takeout/             -> 200
          X-Content-Type-Options: nosniff
          X-Frame-Options: DENY
          Referrer-Policy: no-referrer
          Content-Security-Policy: default-src 'self'; script-src 'self'; ...
          Permissions-Policy: geolocation=(self)
          （无 Strict-Transport-Security）
        https://hqyx.website/takeout/api/auth/me  -> 401，同上，同样无 HSTS
  - 全仓 grep（Strict-Transport-Security / hsts）只命中 md/audit/round1/findings-infra.md:149（第一轮报告）——**代码里一处都没有**。
  - 网关：server/takeout-gateway/src/main/java/com/example/takeout/gateway/web/SecurityHeadersFilter.java:14-19 —— nosniff / frame / referrer / CSP，**无 HSTS**。
  - 应用：server/takeout-app/src/main/java/com/example/takeout/config/SecurityHeadersFilter.java:16-19 —— 只 3 个头 + API 的 no-store，**无 CSP、无 HSTS**（API 响应上的 CSP 实际来自网关）。
  - 宿主 nginx：server/docker/nginx-domain.conf:29 —— 只有 add_header Permissions-Policy，**无 HSTS**。
- **攻击链**：受害者连公共 Wi-Fi → 攻击者投毒 http://hqyx.website/takeout/（无 HSTS 时浏览器允许明文 80 端口）→ 宿主 nginx 的 listen 80 虽回 301，但攻击者可先截获明文请求并注入同源假登录页 → 拿到手机号+密码；页面同源时还能用 fetch 读走后续 Authorization 头。Cache-Control: no-store 只保护响应缓存，不防降级。
- **线上状态**：**已实测（头缺失）**——漏洞条件成立；MITM 实测需要可控网络，本轮不做。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-11 逐项列了“CSP、nosniff、禁止嵌入及 Referrer-Policy”和“应用添加对应基础响应头”，**恰好漏掉 HSTS**；而第一轮 findings-infra.md F-INFRA-08 的修复建议写得很明确：“Nginx 侧补 HSTS”。他们照着补了 4 项、跳过第 5 项；自测脚本 md/audit/cache/deploy/verify_remote.py:72 只断言 X-Content-Type-Options 与 script-src 'self'，所以漏项永远不会被测出来。
- **修复建议**
  - nginx-domain.conf 增加 add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;（includeSubDomains 需确认 blog 等子域全 HTTPS）。
  - 网关与应用两个 SecurityHeadersFilter 同样补 HSTS，覆盖“直连网关 / 裸跑”场景。
  - verify_remote.py:72 的断言加上 Strict-Transport-Security 存在性，把这次漏项变成回归项。

---

### R-06 ｜【Medium】BankCardCrypto 的密钥仍复用 takeout.jwt.secret，“三种用途独立密钥”不成立

- **结论**：V-03 的成果是“JWT / 验证码 / AI 加密三把独立密钥 + 禁止复用（SecuritySecretsGuard）”，但**银行卡完整卡号的 AES-GCM 密钥仍从 JWT 签名密钥派生**——第 4 个消费者，守卫完全看不到。JWT 密钥一旦泄露，攻击者不仅能伪造 role=2 令牌，还能离线解密库里所有完整卡号；反过来轮换 JWT 密钥会让所有已存卡密文永久不可解，密钥轮换被数据绑死。
- **证据**
  - server/takeout-app/src/main/java/com/example/takeout/service/BankCardCrypto.java:20 类注释“密钥从 JWT secret 派生，数据库不保存密钥”；:28 构造函数注入 takeout.jwt.secret；:33-35 SHA-256("takeout:bank-card:v1:" + secret) 派生 AES 密钥。
  - server/takeout-app/src/main/java/com/example/takeout/config/SecuritySecretsGuard.java:10-18 —— 只校验 jwt.secret / sms.hmac-secret / assistant.encryption-secret 三者互不相同，**不包含银行卡密钥**（它没有独立配置项）。
  - 全仓 grep takeout.jwt.secret 的消费者只有两处：takeout-common/.../security/JwtUtil.java:29 与上述 BankCardCrypto.java:28。
  - 对照已改好的两处：AssistantConfigService.java:35 用 takeout.assistant.encryption-secret；PushTokenCrypto.java:24 用 takeout.push.token-encryption-key（且要求 ≥32 字符）。
- **攻击链**
  1. 前提：JWT 密钥泄露（历史 .env 就是人类可读模板口令，见 R-07；线上虽已换 32 随机字节，但该密钥同时存在于应用进程与部署脚本的私有 env 中，暴露面最大）。
  2. 拿到密钥 → 除了“按设计”伪造任意 role=2 令牌，还可离线算 SHA-256("takeout:bank-card:v1:"+secret)，对 user_bank_cards 里 v1:<base64(iv||ct)> 逐条 AES-GCM 解密 → 拿到**完整卡号**（列表接口只回后四位，此路绕过该设计）。
  3. 可用性耦合：轮换 JWT 密钥后所有卡密文不可解（decrypt 抛 503“银行卡信息无法读取”），运维因此不敢轮换。
- **线上状态**：未测（需 JWT 密钥；本地静态证据已定性）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-03 的措辞是“**三种用途**独立配置且禁止复用”——他们把“用途”定义为自列的三项，**没有穷举“还有谁在读 jwt.secret”**。SecuritySecretsGuard 的实现方式（注入 3 个变量再两两比对）天生发现了“第 4 个未登记消费者”，也不会在有人新加该 @Value 时报错。
- **修复建议**
  - 新增 takeout.bank-card.encryption-secret（独立 openssl rand -base64 32），BankCardCrypto.java:28 改为注入它；SecuritySecretsGuard 把第 4 个变量纳入互不相同校验。
  - 迁移：读时兼容 v1（旧派生）与 v2（新密钥），离线重加密后删除旧值（assistant_config 那次已验证这套流程可行）。
  - 加固：把 jwt.secret 的注入点收敛到 JwtUtil 一个 Bean，其它组件不得直接 @Value 它；加 ArchUnit/单测断言“只有 JwtUtil 引用该 key”。

---

### R-07 ｜【Medium】.env 未迁移：文档所述本地部署现在起不来，4 类真实第三方凭据从未轮换

- **结论**：防守方写“现有 .env 没有被改写”——保留的结果是：按 README 的 docker compose up -d --build 现在**必然启动失败**（3 个必填键缺失 + JWT 密钥过不了新格式校验 + 危险开关被守卫拒绝），同时 .env 里的支付宝沙箱私钥、QQ SMTP 授权码、高德 key、DB 口令**全部沿用第一轮的值，没有一个被轮换**。
- **证据**
  - .env（仓库根，.gitignore:2 已忽略，但仍是本机唯一 env 文件）共 30 键，**缺** TAKEOUT_MYSQL_ROOT_PASSWORD、TAKEOUT_REDIS_PASSWORD、TAKEOUT_VERIFICATION_HMAC_SECRET、TAKEOUT_ASSISTANT_ENCRYPTION_SECRET、TAKEOUT_DEMO_ADMIN_PASSWORD。
  - 而 compose 现在把这些写成硬必填（:? 语法）：docker-compose.yml:21（MYSQL_ROOT_PASSWORD）、:51（REDIS_PASSWORD）、:98（VERIFICATION_HMAC_SECRET）、:99（ASSISTANT_ENCRYPTION_SECRET）⇒ 解析即失败。
  - .env:2 TAKEOUT_JWT_SECRET 的值含连字符、不是规范 Base64、也不是 32 字节 ⇒ JwtUtil.decodeSecret（server/takeout-common/.../security/JwtUtil.java:78-91）直接抛 IllegalStateException（“服务密钥必须为独立生成的 32 字节随机材料的 Base64 编码”）。
  - .env:22 TAKEOUT_DEMO_RECHARGE_ENABLED=true ⇒ AuthService.java:36-38 与 DemoModeWarning.java:13-15 抛异常，进程不启动。
  - 未轮换的真实凭据（只记类型/行号）：.env:15 支付宝应用私钥（1624 字符）；.env:17 沙箱 notify URL（trycloudflare 隧道）；.env:28 QQ SMTP 授权码；.env:6/7/8 高德 REST/JS key + 安全码；.env:1/20 DB 口令 + TAKEOUT_DB_USERNAME=root。
  - 我在本机用临时注入的 3 个 secret 与 2 个口令才让 docker compose config 跑通（compose-main.json 即这样生成）；不注入直接报必填错误。
- **攻击链**：不是远程链路，是凭据卫生 + 可用性：任何一次“整目录打包 / IDE 远程同步 / 截图 / 备份”就带走支付宝私钥 + SMTP 授权码（可冒充发信，进而配合钓鱼拿验证码）+ 高德配额。而本地环境现在无法按文档启动，操作者为了跑起来极可能反手把守卫/校验改软（防守方自己警告过“不要通过取消守卫来恢复启动”）——这是把安全控制推向被绕过的现实动机。
- **线上状态**：已实测（compose 解析层面可复现；线上用服务器私有 env，不受影响）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-03/V-04 只处理**服务器**密钥轮换（“线上已分别生成三份独立随机材料”），对仓库根 .env 明确写“没有被改写”，把“没改”当成合规而不是待清理的旧凭据；同时没给本地开发一份能通过新校验的 env 生成流程（.env.example:11-15 三个密钥全空，注释只说 openssl rand -base64 32，没有脚本）。
- **修复建议**
  - 轮换 .env 里全部第三方凭据（支付宝沙箱密钥对重新生成、QQ 授权码重置、高德 key 重置），并在 README/部署脚本里清掉任何指向旧值的历史。
  - 提供 scripts/bootstrap-dev-env.ps1：生成 3 把 32 字节随机材料 + 随机 DB/Redis 口令，写出 0600 的本地 .env，让“照文档启动”不再失败。
  - 删掉 .env 里的 TAKEOUT_DEMO_RECHARGE_ENABLED=true；若确需历史演示行为，改为显式 TAKEOUT_ALLOW_DEMO=1 的独立开关，且只允许 develop + 非公网。

---

### R-08 ｜【Low】部署脚本只把 log_format 注入宿主 nginx，仓库里的 nginx-domain.conf 从未上线

- **结论**：rollout_remote.py 对宿主 nginx 的改动**只做了日志格式与 access_log 注入**；代理头、client_max_body_size、跳转规则全部沿用服务器上那份旧文件。因此“仓库里的 server/docker/nginx-domain.conf”不能代表线上网关前的真实行为，红队/审计对代理链的任何结论只能靠线上探测反推。
- **证据**
  - md/audit/cache/deploy/rollout_remote.py:106-115：
    - 第 106 行 content = nginx.read_text()（读的是 /etc/nginx/sites-enabled/blog-hqyx，**线上现有文件**）；
    - 第 107 行只从 release 的 nginx-domain.conf 里**取出一行 log_format**；
    - 第 109-110 行用正则往 location /takeout/ 与 location = /takeout 里插一行 access_log；
    - 第 111 行 atomic(nginx, content) 只回写这一个文件。
  - 全脚本**没有任何** proxy_set_header / client_max_body_size / server_tokens 的写入。
  - 后果：nginx-domain.conf:34 的 proxy_set_header X-Forwarded-For $remote_addr（覆盖语义，是 V-05 成立的前提）在线上是否生效**无法从仓库断言**；R-03 的可利用性正卡在这里。
- **攻击链**：不是直接攻击，而是审计盲区。若宿主那份旧 nginx 用 proxy_add_x_forwarded_for（常见历史写法），R-03 立刻从“未证实”变成“线上可打”；反之若有人以为仓库文件就是线上文件，会误判 V-05 已修。
- **线上状态**：**未测**（宿主 /etc/nginx/sites-enabled/blog-hqyx 不可读，无服务器权限）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-05 自己写了“宿主 Nginx → Docker 网关地址必须按实际环境填写可信代理正则，**未做线上 Nginx 联调**”——他们知道这块没对齐，却仍把仓库配置当作已完成的修复交付。
- **修复建议**
  - 把宿主 nginx 的完整 server 块纳入仓库（nginx-domain.conf 作为唯一真源），rollout 改为**整文件部署 + nginx -t 校验 + reload**，不要用正则打补丁。
  - 部署后自动断言：带 X-Forwarded-For: 9.9.9.9 的请求，其来源不得落进日志/限流标识（即覆盖语义生效），把“XFF 来自客户端”变成可回归检查。

---

### R-09 ｜【Low】nginx 隐私日志的 request_id 与应用 traceId 是两套值，且 traceId 由客户端决定

- **结论**：新加的 takeout_privacy 格式里 request_id 取 nginx 内置随机变量，而应用/网关的 traceId 来自请求头 X-Request-Id（客户端可自带，只做字符过滤）。两条日志无法 join；审计表 trace_id 列写入的是攻击者可控值。
- **证据**
  - server/docker/nginx-domain.conf:2 与 server/docker/app-upstream.conf:1 —— request_id=$request_id（nginx 内置变量，随机 16 字节，与请求头无关）。
  - server/docker/app-upstream.conf:11 —— proxy_set_header X-Request-Id $http_x_request_id（**透传客户端头**，nginx 全程不生成 X-Request-Id）。
  - server/takeout-app/src/main/java/com/example/takeout/config/ApiRequestLoggingInterceptor.java:46-53 —— 优先采用请求头 X-Request-Id，写 MDC + 响应头。
  - takeout-common/.../common/TraceContext.java:47-51 —— 只做白名单字符过滤 + 64 字符截断 ⇒ 无换行注入（这点是好的），但值完全可预测/可伪造。
  - ApiRequestLoggingInterceptor.java:111-114 —— 该 traceId 落 operation_log.trace_id。
  - 线上实测：不带头时响应 X-Request-Id: ef01922821db427cbdfefacbd69fc0b8（服务端生成），但客户端一旦带头即覆盖。
- **攻击链**：攻击者可让多个账号/多次操作共享同一 traceId（伪造“同一请求”），或用已知 traceId 让取证错误串联；nginx access log 与应用日志之间的 request_id 缺口使“一次请求全链路 grep”失效——恰是该字段被加入的目的。
- **线上状态**：已实测（响应头形态）；日志内容不可读（无服务器权限）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-18 写“仅记录路径、方法、状态、大小、耗时及**请求 ID**”——他们复用了 nginx 的 request_id，却没把两端对齐到应用读取的 X-Request-Id；md/audit/cache/defense-round2/check_nginx_privacy.py:59 只断言 “request_id=” 出现，不校验与应用侧一致。
- **修复建议**
  - 宿主 nginx 改为 proxy_set_header X-Request-Id $request_id（覆盖），并把 $request_id 写进 takeout_privacy 格式 ⇒ 两侧同值。
  - 应用侧只接受“可信来源”注入的 X-Request-Id，否则自行生成（ClientIpHeadersFilter 已有可信对端判定，可直接复用）。
  - check_nginx_privacy.py 断言升级：同一请求的 nginx 日志 request_id 与响应头 X-Request-Id 必须相等。

---

### R-10 ｜【Low】MYSQL_ROOT_HOST 设为 %：root 可从任意容器登录

- **结论**：demo 编排允许 MySQL root 从任何主机登录，与“新库使用独立应用用户 + 独立 root 口令”的最小权限叙述冲突：任何被攻陷的容器都能用 root 直连数据库。
- **证据**：docker-compose.demo.yml:9 —— MYSQL_ROOT_HOST: '%'；解析结果（compose-demo.json）中 mysql ports=[(none)]（未发布宿主，这点是对的）；root 口令必填（:8）。
- **攻击链**：容器逃逸 / 应用 RCE 之后，横向到 DB 不再是“需要 root 只允许 localhost”这一层，而是“拿到 TAKEOUT_MYSQL_ROOT_PASSWORD 即可从本容器连 root”——而该口令对同 compose 内的 app / backup 容器都可读。
- **线上状态**：未测（需宿主权限核对 mysql.user）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md 只写“保留 demo 的 ACL 与无端口发布设置”，把 MYSQL_ROOT_HOST 当既有配置继承下来，没有回头审“root 的来源限制”。
- **修复建议**：MYSQL_ROOT_HOST 收窄到 backup 容器具体地址，或改用独立备份账号（SELECT / LOCK TABLES / SHOW VIEW / TRIGGER / RELOAD / REPLICATION CLIENT）替代 root；rollout_remote.py:33-40 与 verify_remote.py:11 的 mysql -uroot 一并替换。

---

### R-11 ｜【Low】server_tokens 未关；公网 nginx 1.24.0 与镜像内 1.28.3 版本漂移

- **结论**：所有 HTTPS 响应都暴露 Server: nginx/1.24.0 (Ubuntu)；而 compose 内部负载均衡用 nginx:1.28.3-alpine ⇒ 两个收敛点版本不同，公网那个明显更旧。
- **证据**
  - 线上实测：https://hqyx.website/takeout/ → Server: nginx/1.24.0 (Ubuntu)；http://hqyx.website:8087/ → 308 + 同一 Server 头。
  - docker-compose.yml:178 —— image: nginx:1.28.3-alpine（内部 balancer）。
  - server/docker/nginx-domain.conf 全文无 server_tokens off。
  - 端口面：公网只开 8087（宿主 nginx 的 308 跳转），9087/9080/3310/6387/6379/3306 均不可达 —— V-04 的端口收敛**确实做到了**。
- **攻击链**：版本指纹 ⇒ 直接映射该版本已知 CVE 的攻击脚本；此外那个纯跳转的 listen 8087 server 是不必要的暴露面。
- **线上状态**：已实测（头 + 端口）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md V-04 只谈“端口发布/口令/权限”，没提响应头指纹与镜像版本一致性；check_compose.py 也不检查 server_tokens。
- **修复建议**：nginx-domain.conf 与 app-upstream.conf 加 server_tokens off；宿主 nginx 升级到与镜像一致的 1.28.x；对外的 listen 8087 跳转 server 若非必要可删除（域名已覆盖）。

---

### R-12 ｜【Low】/api/location/* 无任何限流，登录用户可白嫖服务端高德 key

- **结论**：LocationController 的 4 个端点没有接入 LoginRateLimiter，任何登录用户可无限调用，消耗服务端 TAKEOUT_AMAP_REST_KEY 配额；配额打满后全站定位/选址功能失效。
- **证据**：server/takeout-app/src/main/java/com/example/takeout/controller/LocationController.java:49-106（4 个 @GetMapping，均无 limiter 调用）；:108-119 proxy() 直接 ApiResponse.ok(body) 回传上游原始 JSON；LoginRateLimiter.java:27-45 的策略表里**没有 location 相关 action**；WebConfig.java:45-56 的放行清单不含 location，所以至少需要登录（这点是对的）。
- **攻击链**：注册一个账号 → 循环 GET /api/location/search?keyword=x → 高德日配额耗尽 → 全站“选择地址/定位”失效；/nearby、/search、/geocode 还回传上游完整 JSON（含 poi 明细），可当免费 POI 抓取通道。
- **线上状态**：未测（会消耗真实 key 配额，按纪律不打）。
- **为什么防守方没堵住**：第一轮 findings-infra.md 未覆盖该控制器，防守方也没有做“所有出站第三方代理是否接入限流”的清单式复核（V-15/V-16 只处理支付查单与验证码）。
- **修复建议**：4 个端点接入 LoginRateLimiter（如 location = 30/min/账号）；/nearby、/search 只回传前端需要的字段子集（name/address/location），不要整段回上游 JSON；对高德返回的 infocode 做告警。

---

## 已尝试但打不动的方向（否定结论）

| # | 尝试 | 方法与证据 | 结论 |
| --- | --- | --- | --- |
| N-01 | 公网直连网关伪造 XFF 绕过限流 | 线上只有 8087（宿主 nginx 308 跳转）可达，9087/9080/3310/6387/6379/3306 TCP connect 全 closed；真实类实测：对端为公网 IP 时一律忽略 XFF（I 33 跳 + 公网对端 -> 203.0.113.7） | **打不动**（仅“信任对端”场景有问题，见 R-03） |
| N-02 | “左端可伪造”残留 | ClientIpHeadersFilter.java:35-40 从右往左扫；实测 伪造前缀 1.1.1.1 + 真 IP -> 取真 IP；31 跳 -> 取真 IP | **打不动** |
| N-03 | 隐私日志格式的 CRLF 日志注入 | 用防守方同款 nginx 1.24.0 + 从 nginx-domain.conf / app-upstream.conf 抽出的 log_format 起临时实例，请求路径含 %0A + 伪造字段（PoC：md/audit/cache/round2-redteam/infra-red/poc_log_injection.py）。结果：**nginx 把控制字符转义为字面量（日志里出现的是反斜杠 x 0 A），仍是一物理行** | **打不动**（伪造字段只内联在真实行内，无法伪造独立记录；按 Low 残余记录，不单列条目） |
| N-04 | /uploads/** 路径穿越、目录列表 | 源码：文件名 UUID 生成、normalize() 后 startsWith(root) 二次校验（FileStorageService.java:63-71）；线上 /uploads/../application.yml 与 /uploads/%2e%2e/application.yml 均 404 | **打不动** |
| N-05 | 上传任意扩展名 / 存储型 XSS（svg html js jsp htaccess） | ImageUploadValidator.java:13-41 扩展名白名单 + 声明 MIME 白名单 + 魔数三方一致；落盘名服务端生成；响应带 nosniff，Content-Type 由扩展名推导 | **打不动** |
| N-06 | 上传配额绕过（并发 / 异常回滚 / 多账号） | UploadService.java:41-53 同一事务内“全局→账号”固定顺序 INSERT ... ON DUPLICATE KEY UPDATE 取排他锁 + 条件 UPDATE（used_bytes <= quota - bytes）；@Transactional 保证存储异常回滚。复核 SQL 语义不会超发 | **打不动**（仅余“提交失败留孤儿文件”，防守方已自述） |
| N-07 | CORS 绕过（恶意域 / 后缀匹配 / null origin） | 线上实测：Origin: https://evil.example -> 403；https://hqyx.website.evil.example -> 403；Origin: null -> 403；Origin: https://hqyx.website -> 401 且回 Access-Control-Allow-Origin: https://hqyx.website（带 Vary: Origin） | **打不动**（WebConfig.java:62 是精确白名单，不是 allowedOriginPatterns） |
| N-08 | Swagger / actuator 未授权暴露 | 线上 /takeout/actuator、/actuator/health、/actuator/env、/swagger-ui/index.html、/v3/api-docs 全 404；项目未引入 actuator；springdoc 由 TAKEOUT_OPENAPI_ENABLED（默认 false）控制 | **打不动** |
| N-09 | 网关路由旁路 | 网关只路由 /api/** 与 /uploads/**（takeout-gateway application.yml:23-33），其余路径 404；/uploads/ 公开读取是设计如此，图片名 UUID 不可枚举 | **未构成新缺陷** |
| N-10 | Redis 口令 / ACL 被 compose 参数覆盖 | compose-main.json：redis 是 sh -c 里 exec redis-server --appendonly --requirepass（取自容器内环境变量）+ rename-command CONFIG/FLUSHALL/FLUSHDB；demo 用 --aclfile；两者 ports 都是 none 或 127.0.0.1 | **打不动**（主 compose 仍是单用户口令而非 ACL，但已不可从宿主访问） |
| N-11 | 容器特权 / healthcheck 提权 | 解析结果：所有服务 user 为空（Dockerfile:70 USER takeout）、privileged=false、无 cap_add、无 network_mode | **打不动** |
| N-12 | 安全头被应用响应覆盖或丢失 | 线上 /takeout/ 与 /api/auth/me 均带完整 CSP/nosniff/DENY/no-referrer；nosniff,DENY,no-referrer 出现重复值（应用+网关各写一次），浏览器取首个，无安全影响 | **打不动**（仅冗余） |
| N-13 | 网关测试是否仍绿 | mvn -f server/pom.xml -pl takeout-gateway -am test：ClientIpHeadersFilterTest 4/4、GatewayXForwardedConfigTest 4/4，Tests run: 8, Failures: 0, Errors: 0 | **通过**（但用例覆盖不足，见 R-03） |
| N-14 | 临时 PoC 是否污染仓库 | 临时探针 RedTeamXffTest.java 跑完即删（Test-Path = False）；git status 里只剩其他红队成员新增的 server/takeout-app/src/test/java/com/example/takeout/redteam2/，我的改动为 0 | **干净** |

## 未测项与原因

1. **R-03 线上可利用性**：需 ≥10 次错登验证共享桶，违反“错登 1–2 次”纪律；且宿主 nginx 实际 proxy_set_header 不可读（见 R-08）。
2. **R-10 / R-11 的宿主侧事实**（mysql.user 的 host 列、宿主 server_tokens 配置）：无服务器权限。
3. **OBS 路径与签名 URL**：HuaweiObsStorageService.java:36-44 要求 endpoint 与 public-base-url 均 https，store() 返回“公开基址 + key”而非签名 URL，未见泄露面；线上未启用 OBS（develop 走本地），**无法做真实对象存储验证**。
4. **容器镜像 CVE / Trivy**：无 Docker daemon，未做。
5. **真实 Redis 断连下的限流降级**：本轮聚焦配置与网关，未起容器。

---

## 建议的修复优先级

1. **R-02**：profile 默认值改为必填 + 生产守卫脱离 @Profile。唯一一条“线上正在发生”的 High。
2. **R-01**：主 compose 网关端口加回环，并在 check_compose.py 里断言。
3. **R-03 + R-08**：宿主 nginx 整文件入仓部署；网关在 XFF 不可解析时降级到账号维度而不是回退对端地址。
4. **R-04**：补 NoResourceFoundException -> 404（一行 handler）+ /uploads/ 限流。
5. **R-05**：三处补 HSTS，并把断言加进 verify_remote.py。
6. **R-06 / R-07**：银行卡密钥独立化；轮换 .env 里的第三方凭据 + 提供本地 env 生成脚本。
