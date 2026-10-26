# 红队审计报告 — 上传 / 基建 / 密钥 / 前端静态页（infra 范围）

- 审计对象：`D:\work\jiandanwaimai`（entry/ HarmonyOS 客户端、server/ Spring Boot 25 后端、docker-compose 部署）
- 审计视角：进攻方红队，只读审计；未修改项目源码、未改动数据、未 commit/push
- 时间：2026-10-25
- 环境事实（已验证）：
  - `Get-NetTCPConnection` 显示 8087 / 3310 / 6387 / 9100 均无监听 → 后端未运行，无真实 HTTP 侧验证
  - `docker version` 报 `failed to connect to the docker API ... dockerDesktopLinuxEngine` → Docker 守护进程未启动，无法起容器做真机验证
  - 可用工具链：javac/java 25.0.2、node v24.14.0、`docker compose v5.5.1`（CLI 可用，可做配置解析验证）
- 结论口径：每条发现标注 **已验证**（有命令输出/配置解析结果）或 **静态推断**（仅代码/配置阅读）

---

## 概述

本范围共 11 条发现：**High 3 / Medium 3 / Low 4 / Info 1**。

被重点怀疑、但审计后**判否**的两项（结论与常见预期相反，已写明依据）：

| 议题 | 结论 | 依据 |
| --- | --- | --- |
| 上传任意文件写 / 路径穿越 | **未发现** | 文件名校验白名单 + 魔数校验 + 落盘名完全由 UUID 生成 + `normalize()` 后 `startsWith(root)` 二次校验 |
| 网关静态页 DOM XSS | **未发现可利用的 DOM XSS** | `app.js` 全部用户可控字符串均过 `esc()`；未加 `esc` 的插值均为数值型 id/计数（逐条列举在 F-INFRA-07） |

真正的风险集中在**部署形态**：数据库/缓存默认以 `0.0.0.0` 发布且 Redis 无口令、应用以 root 连库、开发档默认种子口令 `123456` 与公开测试账号、以及反向代理链路上 `X-Forwarded-For` 被网关覆写导致全局限流桶塌陷。

---

## 发现列表

### F-INFRA-01　MySQL 以 root 账号 + 明文 TLS 对外发布到 0.0.0.0:3310

- **级别**：High
- **证据**
  - `docker-compose.yml:27-29` `ports: - "${TAKEOUT_MYSQL_PORT:-3310}:3306"`（未绑定 `127.0.0.1`）
  - `docker-compose.yml:87` `TAKEOUT_DB_USERNAME: ${TAKEOUT_DB_USERNAME:-root}`，`.env:20` `TAKEOUT_DB_USERNAME=root` → 应用以 MySQL **root** 身份运行
  - `server/takeout-app/src/main/resources/application.yml:12` JDBC URL 含 `useSSL=false&allowPublicKeyRetrieval=true` → 数据库流量无加密
  - `.env:1` `TAKEOUT_DB_PASSWORD`：15 字符、纯小写人类可读口令，前缀即项目名（值不落文档）
- **已验证**：`docker compose config` 解析结果
  ```
  mysql | ports=0.0.0.0:3310->3306
  redis | ports=0.0.0.0:6387->6379
  gateway | ports=0.0.0.0:8087->8087
  ```
- **攻击链**：同网段/VPN 内任意主机 → 直连 3310（docker 发布端口绕过宿主 iptables 之外的任何本地限制）→ 以 root 爆破/撞库（口令强度低 + 无 fail2ban/无连接限速）→ 直接读写 `takeout` 库：改订单状态、改余额、改 `users.role` 提权。即便拿不到口令，`allowPublicKeyRetrieval=true` + 明文传输也让中间人可在宿主网络内截获 root 凭据。
- **修复建议**：`ports: - "127.0.0.1:${TAKEOUT_MYSQL_PORT:-3310}:3306"`（`docker-compose.demo.yml:6` 的 `ports: !reset []` 已是正确做法，主 compose 未对齐）；建立独立应用库账号并授予最小权限，root 只留运维；JDBC 打开 `useSSL=true` 或走 unix socket/内网；口令换成 32 字节随机值。

---

### F-INFRA-02　Redis 无口令且发布到 0.0.0.0:6387（可读写全部缓存态，可升级为容器内 RCE）

- **级别**：High
- **证据**
  - `docker-compose.yml:44-62`：`command: ["redis-server", "--appendonly", "yes"]` —— 无 `--requirepass`、无 ACL 文件、`ports: "${TAKEOUT_REDIS_PORT:-6387}:6379"`
  - `docker-compose.yml:92` `TAKEOUT_REDIS_PASSWORD: ${TAKEOUT_REDIS_PASSWORD:-}` 默认空；`.env` 中无 `TAKEOUT_REDIS_PASSWORD` 键（已逐键核对，30 个键里没有）
  - `application.yml:33` `password: ${TAKEOUT_REDIS_PASSWORD:}` → 空口令
- **已验证**：`docker compose config` 输出 `redis | ports=0.0.0.0:6387->6379`，且 `redis:` 服务的 `command` 仅含 `redis-server`；解析后的环境变量为 `TAKEOUT_REDIS_PASSWORD: ""`
- **攻击链**
  1. 直连 6387（无 AUTH）→ `KEYS takeout:*` 枚举全部键：登录限流桶 `takeout:rl:*`、JWT 黑名单、热点缓存（店铺/商品/秒杀/Banner/公告）；
  2. `DEL takeout:rl:login:<ip>:blocked` 解除任何封禁；`SET` 伪造缓存条目篡改前台展示与价格型文案；读取/擦除 SMS 验证码相关键 → 注册与找回流程被绕过；
  3. 经典 Redis 逃逸：`CONFIG SET dir /app && CONFIG SET dbfilename shell.jar|ssh key && SAVE` 在容器可写目录落地文件（容器以非 root `takeout` 运行，`/app` 可写，见 `server/Dockerfile:58-70`），再配合可写挂载面进一步利用 → 至少可造成容器内持久化与数据污染。
- **修复建议**：Redis 不发布到宿主（同 F-INFRA-01，绑 `127.0.0.1` 或干脆删 `ports`）；`--requirepass` + ACL（`docker-compose.demo.yml:16-22` 已用 ACL 文件，主 compose 应照抄）；`rename-command CONFIG ""`；生产用独立 network 且不开 `appendonly` 到宿主卷以外的路径。

---

### F-INFRA-03　反向代理链路下 `X-Forwarded-For` 被网关覆写 → 全站共用一个限流桶，10 次错误登录可锁死所有用户 10 分钟

- **级别**：High（可用性 / 登录入口）
- **证据**
  - `server/takeout-gateway/src/main/resources/application.yml:33` `trusted-proxies: ".*"`；`:46` `for-append: false`（注释明确写"覆写而非追加"，目的是防伪造）
  - `server/docker/nginx-domain.conf:33` 公网 Nginx 设置 `X-Forwarded-For $remote_addr`，`:43` `proxy_pass http://127.0.0.1:9087/` → 公网流量先到宿主 Nginx，再进网关容器
  - `server/takeout-common/.../security/LoginRateLimiter.java:121-135` `clientIp()` 取 `X-Forwarded-For` 首段；`:36` `"login", new Policy(10, 60, 600)` → 60 秒内 10 次即封 600 秒
  - `docker-compose.demo.yml:66-67` 网关只发布 `127.0.0.1:${TAKEOUT_APP_PORT:-9087}:8087` → 生产/演示流量必经 Nginx
- **静态推断**（结论依赖 Spring Cloud Gateway `XForwardedHeadersFilter` 的覆写语义：`for-append=false` 时下游 `X-Forwarded-For` 被替换为"直连对端地址"，而不是客户端真实地址）：经 Nginx → 宿主发布端口 → 容器时，直连对端恒为 docker bridge 网关地址（同一字符串），因此 `clientIp()` 对**所有**公网用户返回同一个 IP。
- **攻击链**：攻击者用 10 个错误口令打 `/api/auth/login` → `recordAttempt` 在共享桶内累计到 10 → 封禁键 `takeout:rl:login:<同一个IP>:blocked` 写 600 秒 → **全部用户**登录返回 429「登录尝试过于频繁」。攻击者每 10 分钟重复一次即可持续压制登录入口。同一机理使 `register`(5/3600s)、`email-code`(5/60s) 等所有按 IP 的策略一起塌陷。
- **修复建议**：网关信任的真实上游只有本机 Nginx，`trusted-proxies` 应收窄为该网段（如 `"172\.1[0-9]+\.0\.1"` 或宿主 docker bridge 网段），并改用"追加 + 取最后一个可信跳"的取 IP 策略；或在 backend 侧改用 Spring 的 `ForwardedHeaderFilter` 并把 `X-Forwarded-For` 解析改为取**最右侧非可信代理段**；同时把限流 key 改为 `ip+账号` 双维度，避免单点锁死全站。

---

### F-INFRA-04　develop 档默认种子口令 `123456` 与 README 公开测试账号（含平台管理员）

- **级别**：High（若线上体验环境跑 develop 档）
- **证据**
  - `server/takeout-app/src/main/resources/application.yml:58` `admin-password: ${TAKEOUT_DEMO_ADMIN_PASSWORD:123456}`
  - `server/takeout-app/.../config/DataSeeder.java:32-33` 读取 `takeout.demo.admin-password`，默认 `"123456"`；`:204` 骑手、`:482` 商户、`:547` 管理员种子用户一律 `PasswordUtil.hash("123456")`
  - `README.md:252-263` 公开列出 6 个测试账号（用户/商户/平台管理员 `13100131000`/骑手）且注明"密码均为 `123456`"
  - `docker-compose.yml` 未传 `TAKEOUT_DEMO_ADMIN_PASSWORD`（全文件无此键）；`.env` 也无此键（30 个键已核对）→ 主 compose + develop 档启动即为默认口令
  - 兜底仅有 `config/DemoModeWarning.java:15-20` **打一条 warn 日志**，无任何阻断
  - 唯一强制点在 `config/ProductionHuaweiGuard.java:18-21` / `ProductionPaymentGuard.java:16-19`，但都带 `@Profile("production")`；`.env:21` `SPRING_PROFILES_ACTIVE=develop`
- **静态推断 / 已验证（配置项与种子代码为已验证；"线上是否 develop"属部署事实，本次无运行实例无法确认）**
- **攻击链**：直连公开体验站 `https://hqyx.website/takeout/` → README 账号 `13100131000` / `123456` → `loginType=ADMIN` → 平台总览/退款审批/用户管理/员工管理全开：可发放退款、停用任意账号、增删商品、改营销活动。若口令被改过则退化为"任意用户/商户账号可直接登录"（同样足以刷单、看他人订单与地址）。
- **修复建议**：种子口令改为启动时随机生成并只打印一次，或强制 `TAKEOUT_DEMO_ADMIN_PASSWORD` 必填（照抄 `docker-compose.demo.yml:36` 的 `:?` 语法）；README 删除具体账号口令，改为"启动日志查看一次性口令"；把 `DemoModeWarning` 升级为 fail-fast（develop 档也要求显式 `TAKEOUT_ALLOW_DEMO_ACCOUNTS=true` 才允许种子）。

---

### F-INFRA-05　上传接口无频率/配额限制（任意登录用户可写满磁盘）

- **级别**：Medium（可用性）
- **证据**
  - `server/takeout-app/.../controller/UploadController.java:25-28`：`POST /api/upload` 只做 `storageService.store(file)`，无角色校验、无频次控制
  - `server/takeout-app/.../service/FileStorageService.java:56-78`：单文件上限 5MB（`ImageUploadValidator.java:15`），但**无用户级配额、无总量上限、无去重**
  - 限流器全量策略表 `LoginRateLimiter.java:34-48` 中不存在 upload 相关 action（已 grep `429` 全仓：仅 login/register/email-code/password-forgot/order/bank-card-reveal 等）→ **上传完全未接入限流**
  - `application.yml:20-24` 仅限制 multipart 单请求 5MB/6MB，不限制次数
  - 落盘卷 `docker-compose.yml:122-124` `uploads-data:/app/uploads`
- **攻击链**：公开注册一个用户（注册需邮箱验证码，成本 1 次邮件）→ 循环 `POST /api/upload` 每次 5MB 合法 PNG → 持续写满 `uploads-data` 卷与宿主磁盘 → 应用写日志/图片失败、健康检查降级，且 S3/OBS 计费型部署下直接产生存储账单。1000 次请求即 5GB。
- **修复建议**：对 `/api/upload` 接入 `LoginRateLimiter`（如 30 次/小时/用户）；增加用户级累计配额（如 100MB）与磁盘水位熔断；对象存储模式下设置生命周期规则。

---

### F-INFRA-06　上传校验实现复核：**未发现**任意文件写 / 路径穿越（判否，附残余风险）

- **级别**：Info（判否结论）+ 残余 Low
- **证据（逐层核对）**
  - 扩展名白名单：`server/takeout-app/.../service/ImageUploadValidator.java:13` `EXTENSIONS = {jpg,jpeg,png,webp,gif}`；`:22-26` 取**最后一个点之后**的小写扩展
  - 声明型 MIME 白名单：`:14` `CONTENT_TYPES`；`:27-28` 必须命中
  - 内容魔数校验：`:29-41` 调 `detect()`；`:44-61` 用 `readNBytes(12)` 比对 JPEG/PNG/GIF/WebP 头；`:37-40` 要求 扩展名↔魔数↔声明 MIME 三者一致
  - 落盘文件名**完全由服务端生成**：`FileStorageService.java:63` `UUID.randomUUID()...replace("-","") + "." + extension` → 客户端文件名（含 `../`、`..\\`、绝对路径、`%2e%2e`、空字节）**根本不参与路径拼接**
  - 目录侧二次校验：`:65-68` `root.resolve(day).normalize()` 后 `startsWith(root)` 否则抛 `BizException("非法的上传路径")`
  - `day` 来自 `LocalDate.now()` 固定格式（`:30,62`），不可注入
  - 静态访问映射：`config/WebConfig.java:31-37` `/uploads/**` → `local.root()`，Spring `PathResourceResolver` 默认拒绝 `..` 越界；未开启目录列表（无 `enableDirectoryListing`），`/uploads/` 直访返回 404
- **结论**：文件名/扩展名/MIME/路径穿越/目录列表五个常规攻击面**均未构成可利用缺陷**（该处实现质量高于同类项目平均水平）。
- **残余风险（Low）**
  1. 只验头部，不重编码：GIF89a/JFIF 头 + 任意后续字节的"多语种文件"（GIFAR 型）可通过校验，落地为 `.gif`（`ImageUploadValidator.java:47-56` 只比对前 12 字节）。因响应 `Content-Type` 由扩展名推导为 `image/gif`，现代浏览器不执行其中 HTML/JS，故**不构成可用 XSS**，但会成为"同源托管任意字节"的载体（钓鱼载荷分发、扫描器绕过）。
  2. 全站缺 `X-Content-Type-Options: nosniff`（见 F-INFRA-08）→ 削弱上述边界的纵深防护。
  3. 无图片内容安全检测（无 AV/无像素重采样），恶意图像解析漏洞（历史 libwebp/libavif 类）无兜底。
- **修复建议**：上传后统一 `ImageIO` 重编码去元数据（同时消灭多语种文件）；响应头补 `nosniff`；对上传目录加 `Content-Disposition: attachment`（对非图片扩展不适用，此处可省）与独立子域托管。

---

### F-INFRA-07　网关静态页 XSS 复核：**未发现可利用 DOM XSS**（判否，附残余项）

- **级别**：Info（判否结论）+ 残余 Low
- **证据**
  - 统一转义器：`server/takeout-gateway/src/main/resources/static/app.js:30` `const esc = (v) => String(v ?? '').replace(/[&<>"']/g, ...)`；`cash()`/`btn()`/`statusTag()` 内部均过 `esc`
  - 高危字段逐个核对（评审过全部 `innerHTML` 拼接点）：店铺名/公告/评价正文/商家回复/地址/商品名/活动标题/审计日志/骑手名/银行卡掩码 → 均 `esc()`（如 `:199` 公告 `esc(a.title)/esc(a.content)`、`:205` 店铺名 `esc(s.name)`、`:232` 评价 `esc(r.userName)/esc(r.reply)`、`:273` 地址 `esc(a.detail)`）
  - 图片 URL 一律 `esc(assetURL(...))`（`:113,232`），`urls.js:4-9` 的 `localPath` 只处理以 `/` 开头且非 `//` 的相对路径，`javascript:` 不会进入可执行上下文
  - 唯一未过 `esc` 的插值为数值字段：`:205 data-id="${s.id}"`、`:232 ★ ${r.rating}`、`:238 ${x.quantity}`、`:269 ${c.threshold}`、`:330 ${v ?? '--'}`（管理台计数）、`:334 ${c.id}`、`:338 ${s.rating}/${s.monthlySales}`、`:346 ${r.id}/${r.orderId}`、`:354 ${r.totalOrders}`、`:362 ${e.role}`、`:373-374 ${u.role}/${p.stock}` —— 这些列在 DB 侧为 `INT/DECIMAL/BIGINT`，Jackson 序列化为 number，无字符串注入面
  - `esc()` 用于 `<option value="${s.id}">` 与 `data-*` 属性时对引号做了转义（`"→&quot;`），属性逃逸不可行
  - 无 `eval`/`new Function`/`document.write`/`innerHTML = location.*` 模式；跳转全部走 `navigate()` 白名单（`:157-159`）
- **结论**：**未发现可利用的 DOM XSS 或存储型 XSS**。残余风险来自"手工转义、无 CSP 兜底"（见 F-INFRA-08）与第三方依赖缺失（无 SRI，脚本全部同源）。
- **建议**：给 `index.html` 加 CSP（`default-src 'self'; img-src 'self' data: https:; script-src 'self'`）作为兜底；把 `esc` 收敛为唯一赋值入口（如 `textContent` 优先）。

---

### F-INFRA-08　全站缺安全响应头；`/swagger-ui`、`/v3/api-docs` 无条件绕过鉴权；JWT 存于 localStorage

- **级别**：Medium（组合面）+ Low（单个）
- **证据**
  - 无任何注入安全头的 Filter/配置：全仓 grep 无 `X-Content-Type-Options`/`Content-Security-Policy`/`X-Frame-Options`/`Strict-Transport-Security`；`server/docker/nginx-domain.conf:28` 只加了 `Permissions-Policy`
  - `config/WebConfig.java:56-58` 把 `/v3/api-docs/**`、`/swagger-ui/**`、`/swagger-ui.html` 列入 `excludePathPatterns`（**无条件**，与是否启用无关）
  - `application.yml:47-51` 默认 `springdoc.api-docs.enabled=${TAKEOUT_OPENAPI_ENABLED:false}`；`.env` 无该键；`docker-compose.demo.yml:60` 显式 `false` → **默认关闭，当前不暴露**
  - 客户端令牌存储：`app.js:19,126` `localStorage.getItem/setItem('takeout.demo.token')`
- **已验证**（配置项与现有开关）；**静态推断**（"开启 OpenAPI 后接口清单可匿名拉取"属配置联动）
- **影响/攻击链**：一旦运维打开 `TAKEOUT_OPENAPI_ENABLED=true`（很常见的临时排查动作），`/v3/api-docs` 匿名可读 → 全量接口/参数/模型清单泄露，直接喂给自动化扫描；同时无 CSP/nosniff 意味着任何一次注入（含 F-INFRA-06 残余面）都能直接升格为"读 localStorage 拿 72 小时 JWT"（`application.yml:64 expire-hours: 72`）。
- **修复建议**：加统一 `SecurityHeadersFilter`（app 与 gateway 各一）输出 CSP/nosniff/frame-options/referrer-policy，Nginx 侧补 HSTS；Swagger 的放行改为 `@ConditionalOnProperty(TAKEOUT_OPENAPI_ENABLED)` 条件注册，或加到 admin 鉴权之后；评估改用 httpOnly Cookie + CSRF token 以消除 token 可读性。

---

### F-INFRA-09　CORS 对 `/api/**` 全开 `allowedOriginPatterns("*")`

- **级别**：Low
- **证据**：`config/WebConfig.java:62-69` `allowedOriginPatterns("*")` + `allowedMethods(GET,POST,PUT,DELETE,OPTIONS)` + `allowedHeaders("*")`，未开 `allowCredentials`
- **静态推断**：凭据走 `Authorization` 头而非 Cookie，浏览器不会自动携带，因此不具备"任意站点静默代发请求"的条件；但任意第三方页面可在用户浏览器内读取其响应体（一旦 token 以任何方式暴露给页面上下文），并把 API 变成公开可嵌入的后端。
- **修复建议**：收敛为实际前端域名白名单（`https://hqyx.website`、本地调试域），按环境注入。

---

### F-INFRA-10　`.env` 凭据面与 Git 历史（已确认未入库，但明文落盘、口令强度不足）

- **级别**：Medium（口令与密钥管理）
- **已验证**（只列类型/前缀/长度，不落完整值）
  | 键 | 类型 | 长度 | 备注 |
  | --- | --- | --- | --- |
  | `.env:15 TAKEOUT_ALIPAY_APP_PRIVATE_KEY` | RSA **私钥**（PKCS#8 base64，前缀 `MIIEvQIBAD`） | 1624 | 支付宝沙箱应用私钥，真实值 |
  | `.env:2 TAKEOUT_JWT_SECRET` | HS256 签名密钥（7 段小写词 + 4 位数字，人类可读口令） | 49 | 非随机字节，与 `.env.example:10`/README:238 要求的"32 随机字节"不符 |
  | `.env:1 TAKEOUT_DB_PASSWORD` | MySQL root 口令（小写可读词，前缀即项目名） | 15 | 与 F-INFRA-01 联动 |
  | `.env:28 TAKEOUT_QQ_SMTP_AUTH_CODE` | QQ 邮箱 SMTP 授权码（小写字母串） | 16 | 可直接发信冒充 |
  | `.env:6/7/8 TAKEOUT_AMAP_*` | 高德 REST/JS Key、安全码（十六进制） | 各 32 | 可被刷配额 |
  | `.env:12/13` | 支付宝 APP_ID / SELLER_ID | 16 | 沙箱值，与 `.env.example` 相同 |
- **Git 历史核查（已验证）**
  - `git ls-files --error-unmatch .env` → `error: pathspec '.env' did not match any file(s) known to git`
  - `git log --all --oneline -- .env` → **空**（818 个提交全量历史中从未出现）
  - `git rev-list --all --objects | Select-String '.env'` → 仅 `.env.example` 的 4 个历史 blob，逐个 `git cat-file -p` 检查后**均为占位符**（`replace-with-a-strong-local-password` 等）
  - `git rev-list --all --objects | grep -E '.p12|.pem|.jks|.keystore|.p7b|secret'` → **无匹配**；`signing/` 仅 `.gitignore` 白名单外的 `release-signing.template.json5`（`<STORE_PASSWORD>` 占位）
  - `logs/` 仅 4 个 `.gitkeep` 入库；`uploads/` 未入库；`.gitignore:2` `.env`、`.gitignore:20-27` 签名文件均已覆盖
- **风险/攻击链**：`.env` 就放在仓库根目录（Compose 自动读取），任何一次"打包整目录发人/截图/备份/IDE 远程同步"都会整体泄露支付宝私钥 + SMTP 授权码 + JWT 密钥；JWT 密钥为人类口令，一旦任一 JWT 泄露即可离线字典/掩码爆破（HS256），伪造任意 `userId/role=2` 的令牌；且该密钥同时被用作 AI Key 的加密派生盐：`AssistantConfigService.java:41-42` `SHA-256("takeout:assistant-api-key:v1:" + secret)` → 拿到 JWT 密钥即可解密库中已存的第三方 API Key。
- **修复建议**：轮换全部 4 类真实凭据（已进入过开发机/可能有副本）；`.env` 迁出仓库目录（`env_file: ../secrets/takeout.env`）或改用 Docker secret/系统凭据库；JWT 密钥换 `openssl rand -base64 48` 并引入 `kid` 轮换；AI Key 加密派生改用独立 `TAKEOUT_ASSISTANT_KDF_SECRET`，与 JWT 密钥解耦。

---

### F-INFRA-11　日志落盘 PII 与挂载面（查询串/来源 IP/操作者 ID）

- **级别**：Low
- **证据**：`config/ApiRequestLoggingInterceptor.java:54-57` 记录 `uri` + `query`（完整查询串）+ `getRemoteAddr()`；`:74-79` 记录 `userId/role`；`:135-138` `query()` 原样返回 `getQueryString()`；日志目录 `docker-compose.yml:126` `./logs/app:/app/logs` 绑定到项目树；`logback-spring.xml:28-35` 按天 + 2MB 轮转、保留 30 天
- **已验证（代码路径）／静态推断（实际内容，本机 `logs/app` 为空，仅有 `logs/gateway/gateway.log` 22 行启动日志，无 token/PII）**
- **说明**：`Authorization` 与请求体**未**落日志（`:20,140-143` 只记录是否携带 Bearer），未发现凭证泄露；风险是 `/api/location/search?keyword=`、`/api/search?keyword=` 之类查询串中的用户输入与 IP 进入长期日志，属隐私面而非凭据面。
- **建议**：`query` 做敏感参数脱敏（保留前 64 字符 + 白名单参数）；日志目录移出仓库树；30 天保留期按合规调整。

---

## 对 Lead 补充情报的核实结论

| # | 情报 | 我的结论 | 依据 |
| --- | --- | --- | --- |
| 1 | 演示充值可任意加余额 | **配置面确认**：`.env:22 TAKEOUT_DEMO_RECHARGE_ENABLED=true`、`application-develop.yml:5` 默认 true；`production` 档由 `ProductionHuaweiGuard.java:18-21` 强制关闭 | 业务实现（`AuthService.recharge`）归业务组，未重复验证 |
| 2 | 商户/骑手自助注册可越权 | **未验证（不在本范围）**，已转交业务组；仅记录一条基建侧佐证：`/api/auth/register` 与 `/api/merchant/**` 同处一个应用进程、无独立鉴权域 | — |
| 3 | 骑手自助注册无审核 | 同上，未验证 | — |
| 4 | XFF 伪造绕过登录限流 | **部分确认**：(a) 直连 app:8087 的场景成立——`LoginRateLimiter.java:121-135` 无条件信任 XFF 首段，而 app 在 compose 中**未发布端口**（`docker compose config` 输出 `app | ports=(none)`），仅裸跑（`application.yml:4` 默认 8087）时可达；(b) 生产链路下不成立，反而被网关**覆写**成共享桶 → 升级为 F-INFRA-03 的"全站登录 DoS" | 见 F-INFRA-03 |
| 5 | README 公开测试账号 + DataSeeder 管理员 | **确认**并升级为 High（F-INFRA-04） | `README.md:252-263`、`DataSeeder.java:32-33,204,482,547`、`application.yml:58`；主 compose 与 `.env` 均未设置 `TAKEOUT_DEMO_ADMIN_PASSWORD` |
| 6 | develop 档 `expose-mock-code` 回传验证码 | **上线路径判否**：Spring Boot 属性优先级为"OS 环境变量 > profile yml > application.yml"，而 `docker-compose.yml:102` 与 `docker-compose.demo.yml:42` 都把 `TAKEOUT_SMS_EXPOSE_MOCK_CODE` 以 `:-` 默认 **false** 显式注入容器；`.env:23` 亦为 `false` → 两条 compose 部署路径下实际生效值为 false。**仅"裸 jar + `-Dspring.profiles.active=develop` 且不设环境变量"时**生效 true（`application-develop.yml:9`） | `docker compose config` 解析后环境变量可见；分类为**静态推断（框架语义）**，因无运行实例未能抓 `/actuator/env`（且本项目未引入 actuator） |

---

## 未覆盖项

1. **真实 HTTP 验证全部缺失**：8087/3310/6387 无监听、Docker 守护进程未启动 → 所有接口级 PoC（上传落盘、429 触发、XFF 覆写、`/uploads/` 越权读取）未做运行验证，仅到配置/代码级。
2. **依赖 CVE 未逐条比对**：仅记录版本（spring-boot 3.5.16、spring-cloud 2025.0.3、springdoc 2.8.17、esdk-obs-java 3.26.6、wechatpay-java 0.2.17、alipay-sdk 4.40.1036.ALL、mybatis-plus 3.5.12、jjwt 0.12.6、bcprov 1.86、dom4j 2.2.0（已排除 alipay 内置旧版）、commons-lang3 3.21.0、log4j2 2.26.1、netty 4.1.139、tomcat 10.1.61、jackson 2.21.8）；未接入 CVE 数据库/未跑 `mvn dependency-check`（离线化成本高，且未获授权新增依赖）。`esdk-obs-java` 与 `alipay-sdk` 为历史高危常客，建议单独排期。
3. **Actuator**：**不适用——项目未引入 `spring-boot-starter-actuator`**（四个 pom 全量核对），故无 `/actuator/*` 暴露面，也无 `env/heapdump` 泄露。
4. **容器镜像漏洞扫描**（Trivy/Grype）未做：无 Docker daemon，且不允许部署。
5. **Nginx/网关层 TLS 细节**（`nginx-domain.conf` 之外的 `nginx-ip.conf`、`nginx-ip-bootstrap.conf`、certbot timer）只做了路径级阅读，未审计证书与 TLS 参数；`certbot` 私钥位置（`/etc/letsencrypt/live/blog-hqyx/`）在宿主，未接触。
6. **HarmonyOS 客户端**（`entry/`）的网络安全配置（明文 HTTP 白名单、证书锁定、本地存储加密）不在本次 infra 范围，仅确认 `build-profile.json5` 无内嵌签名材料、`signing/` 仅占位模板。
7. **业务逻辑越权**（商户跨店操作、骑手抢单、演示充值、注册角色自选）归业务组，本报告仅做配置侧佐证（见上表 #1-#3）。

---

## 附：本次审计的复现命令

```powershell
# 1) 环境事实
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in 8087,3310,6387,9100 }   # 空 → 无监听
docker version                                                                                # 连不上 daemon

# 2) 端口发布面（无需 daemon）
cd D:\work\jiandanwaimai
docker compose config | Select-String 'published|target: 3306|target: 6379'
docker compose config --format json   # → mysql 0.0.0.0:3310->3306, redis 0.0.0.0:6387->6379, gateway 0.0.0.0:8087

# 3) Redis 无口令
docker compose config --format json   # redis.services.command = ["redis-server","--appendonly","yes"]；TAKEOUT_REDIS_PASSWORD = ""

# 4) .env 是否入库（只输出元数据，不打印明文）
git ls-files --error-unmatch .env     # error: pathspec '.env' did not match
git log --all --oneline -- .env       # 空
git rev-list --all --objects | Select-String '\.env'   # 仅 .env.example 历史 blob

# 5) 上传校验 / 前端转义（源码级）
#    证据行号见 F-INFRA-06 / F-INFRA-07
```
