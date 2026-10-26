# 认证 / 授权 / 会话 红队审计报告（findings-authz）

| 项 | 值 |
| --- | --- |
| 审计范围 | `server/`（Spring Boot / Java 25，`takeout-common` + `takeout-app` + `takeout-gateway`）+ 部署编排（`docker-compose*.yml`、`server/docker/*.conf`） |
| 视角 | 黑盒可达面 → 代码回溯；攻击者无凭据起步，逐步升级 |
| 审计时间 | 2026-10-25 |
| 结论 | 共 10 条：**Critical 1 / High 2 / Medium 3 / Low 4**（AZ-10 基线为 Info，按线上暴露面记 Low），其中 2 条由可执行 PoC 验证，其余为静态推断或配置链论证 |

## 0. 环境事实（先自行确认）

- 本机 `8087 / 3310 / 6387` **无监听**：`Get-NetTCPConnection -State Listen` 只返回宿主自带 MySQL 的 `3306`。
- Docker CLI 存在（`29.8.2`）但守护进程未运行（`npipe:////./pipe/dockerDesktopLinuxEngine` 连接失败），**未启动服务**。
- 项目 `.env` 中 `SPRING_PROFILES_ACTIVE=develop`，因此所有可执行验证改为 **脱离容器的类级 PoC**：直接用 `server/takeout-common/target/classes` 里已编译的真实类（`JwtUtil`、`AuthInterceptor`、`PasswordUtil`）跑，不修改任何项目源码，不写任何数据库。
- 密钥类材料只记录「类型 + 前缀 + 长度」，全文不落报告。

## 1. 发现列表

### AZ-01 JWT 签名密钥是可猜的模板短语 → 任意身份（含管理员）token 伪造 【Critical｜已验证（PoC）】

**证据**
- `server/takeout-app/src/main/resources/application.yml:61-64` — `takeout.jwt.secret: ${TAKEOUT_JWT_SECRET}`，`expire-hours: 72`。
- `.env:2`（已 gitignore，未入库）— `TAKEOUT_JWT_SECRET`：**类型=可读短语型 HMAC 密钥；前缀 `[已脱敏的数据库口令]jwt-ple`；长度 49**；字符集仅 `[a-z-]`（无大写、无随机符号），49 位里只有 22 个不同字符，7 个连字符分段，含 `takeout / jwt / please / long / secret / 2026` 等完整英文词。
- 该形态等于「模板占位值」，字典穷举面极小：审计中用 3 个候选词组合即**精确命中**（命中值不在报告中保留）。
- `server/takeout-common/src/main/java/com/example/takeout/security/JwtUtil.java:28-32`（`Keys.hmacShaKeyFor(secret.getBytes(UTF_8))`，密钥长度 49 字节 → jjwt 选 **HS384**）、`:46-57`（签发）、`:62-68`（校验只做 `verifyWith(key)`，无 issuer/audience 白名单）。

**攻击链**
1. 攻击者从公开仓库 `.env.example` / README 的占位约定猜出或字典恢复该短语（49 字符、纯小写词+连字符，属可枚举空间）。
2. 离线自建同款 `JwtUtil`（HS384）签发 `sub=<任意 userId>`、`role=2`、`pwdAt=""` 的 token。
3. 目标站 `Authorization: Bearer <forged>` → `AuthInterceptor` 验签通过 → 按其 `sub` 查库拿到真实管理员行 → `role` 一致、`status=1`、`pwdAt` 空则跳过改密校验 → 写入 `ATTR_USER_ID/ATTR_ROLE`。
4. 直接调用 `/api/admin/**`（全部只校验 `role==2`）：改任意用户状态、审批退款、看全量订单/用户/员工、改店铺与商品。

**PoC（可复现，命令与输出）**

```powershell
# 编译并运行（classpath 取仓库内已编译类 + 本地 .m2 的 jjwt 0.12.6 / spring / tomcat-embed）
javac -encoding UTF-8 -cp "<classes+jjwt+spring+tomcat>" \
      -d TemporaryCacheStorage\audit\poc\out \
      TemporaryCacheStorage\audit\poc\JwtForgeryPoC.java
java -Dfile.encoding=UTF-8 -cp "TemporaryCacheStorage\audit\poc\out;<classes+jjwt+spring+tomcat>" JwtForgeryPoC
```

```text
[1] forged admin token (truncated) = eyJhbGciOiJIUzM4NCJ9.eyJqdGkiOiI2OTg2OTBjYy1hZDMwLTQ4NT... len=233
[2] parse with the shipped template secret: sub=5 role=2 pwdAt=''
[3] AuthInterceptor.preHandle=true  -> ATTR_ROLE=2 ATTR_USER_ID=5
[4] control group (random 48-byte secret) -> rejected: 401 / 登录凭证无效或已过期
[5] alg=none token rejected: UnsupportedJwtException / Unsecured JWSs ... are disallowed by default
```

- `[3]` 是核心：**真实 `AuthInterceptor` 判定通过并把 `role=2`、`userId=5` 写进 request**（UserDao/TokenRevocationService 用内存桩，不连库，故只验证认证层判定，不产生任何写入）。
- `[4]` 是对照组：换成随机 48 字节密钥，同一 token 立刻 401 —— 证明缺陷在**密钥熵**，不在校验逻辑。
- `[5]` 是**否定结论**：`alg=none` 与算法混淆不可利用（jjwt 0.12.6 默认拒绝未签名 JWS），故本条不涉及算法降级。
- 完整日志：`md/audit/cache/round1-poc/logs/poc1-jwt-forgery.log`。

**修复建议**
1. 立刻轮换 `TAKEOUT_JWT_SECRET`：32 字节以上 `SecureRandom`/base64，禁止任何人类可读短语；轮换即让全部存量 token 失效（等同全站强制重登）。
2. 启动期加硬断言：密钥必须 ≥32 字节且字符集熵达标（例如拒绝「只含 `[a-z0-9-]` 且不同字符 <30」的值），不满足直接拒绝启动——把「配置错了」变成起不来，而不是悄悄弱化。
3. `JwtUtil.parseToken` 增加 `requireIssuer("simple-takeout")` 并显式 `sig().add(Jwts.SIG.HS384)` 锁定算法。
4. 密钥只从 secrets 管理注入；`.env.example` 与 README 里不要留「please-use-this-long-secret」这类可复用占位。

---

### AZ-02 自助注册即开通商户/骑手（无审批），骑手端可读真实订单收货人姓名+电话+地址并可推进送达 【High｜线上可达（Lead 实测）+ 静态确认】

**证据**
- `server/takeout-app/src/main/java/com/example/takeout/service/AuthService.java:76-85` — `if (role != 0 && role != 1 && role != 3) throw "角色不合法"`，随后 `userDao.insert(..., role, ...)`：**role=1（商户）与 role=3（骑手）允许自助注册**，仅 role=2（管理员）被拒。
- `server/takeout-app/src/main/java/com/example/takeout/controller/AuthController.java:54-62`（`/api/auth/register` 在 `WebConfig` 放行名单内，无鉴权）、`:65-88`（`/api/auth/email-code` 同）。
- `server/takeout-app/src/main/java/com/example/takeout/config/WebConfig.java:45-59` — `/api/auth/register`、`/api/auth/email-code` 免鉴权。
- `server/takeout-app/src/main/java/com/example/takeout/service/RiderService.java:35-47` — 骑手档案**自动建档、无审核**（`riderDao.insert` 默认 `status=1`）。
- 骑手接单池暴露面：`server/takeout-app/src/main/java/com/example/takeout/service/OrderService.java:908-917`（`riderPool`）+ `server/takeout-common/src/main/java/com/example/takeout/dao/OrderDao.java:385-389`（`WHERE status=2 AND ready_time<>'' AND rider_id=0`）+ `OrderService.java:1006-1009`（`toView` 带完整地址）+ `server/takeout-common/src/main/java/com/example/takeout/model/Order.java:90-94`（`AddressInfo(addressId,name,phone,detail)`）。
- 抢单无人工干预：`OrderService.java:946-958`（`riderGrab` 仅校验配送半径与条件更新）、`:971-984`（`riderDeliver` 写单量与收入，并在 `confirmOrder/autoConfirmOrder` 触发 `settleMerchant` 结算 `OrderService.java:1045-1052`）。
- 配送半径可自设到极限：`RiderService.java:61-69`（半径 5~50 公里）、`:72-85`（接单位置任意经纬度）。

**可利用性前提（3 步，全部走公开接口）**
1. `POST /api/auth/email-code {purpose:"register"}` 用自己的手机号+邮箱取码（真实邮箱可收码，无需任何审批）；
2. `POST /api/auth/register {role:3,...}` → 得到 role=3 账号 + JWT；
3. `PUT /api/rider/range/location` + `PUT /api/rider/range/radius` 把自己定位到市中心、半径拉到 50 公里 → `GET /api/rider/orders/pool` 即可拿到该区域**所有已出餐订单**的收货人姓名、手机号、详细地址、商品清单。

**线上实测（Lead 提供，只读写库）**
- `POST https://hqyx.website/takeout/api/auth/register {role:3,...}` → `400 "验证码不正确或已过期"`：说明**已通过角色校验**，只差邮箱验证码。
- `{role:1,...}` → 同上；`{role:2,...}` → `400 "角色不合法"`（管理员被正确拒绝）。
- 该站在 `develop` 档运行，种子账号 `13800138000/123456`（role=0）等均可登录，`/api/auth/me` 返回 `balance=20.0`。
- **本次未创建任何账号，也未做任何写入操作。**

**判定**：这不是参数注入，而是**授权模型缺失**——`md/开发参考.md:258` 也自认「骑手为自助注册即开通，无需平台审核」。危险点在于骑手端能直接读到真实用户的姓名/手机号/地址（个人敏感信息），并能驱动「送达→结算」改变真实资金流向。

**修复建议**
1. 注册接口只接受 `role=0`；商户/骑手改为「申请单 + 管理员审批」，审批通过才写 `users.role`。
2. 审批前账号 `status=0`（`AuthInterceptor.java:57-59` 已实现禁用即拒），登录直接 403。
3. 骑手档案 `riders.status` 默认 0，管理员开通后置 1；`RiderService.profile` 的自动建档改为只对已审批用户生效。
4. 顺手收敛接单池返回字段：`riderPool` 只给「门店地址 + 距离 + 金额 + 订单号」，收货人手机号在**抢单成功后**才下发（或脱敏中间四位）。

---

### AZ-03 限流标识退化为单一 IP：10 次失败即可全站登录/注册/找回被封 10 分钟 【High｜静态推断（配置链确定，未起服务验证）】

**证据**
- `server/takeout-common/src/main/java/com/example/takeout/security/LoginRateLimiter.java:121-135` — `clientIp` 优先取 `X-Forwarded-For` 首段，其次 `X-Real-IP`，最后 `getRemoteAddr()`。
- `LoginRateLimiter.java:34-48` — `login` 策略 `(10 次 / 60 秒)` → 超限封 `600 秒`；`register (5/3600→封 3600s)`、`email-code`、`password-forgot`、`payment-password-forgot` 全部按**同一个 IP 桶**计。
- `server/takeout-gateway/src/main/resources/application.yml:33,46` — `trusted-proxies: ".*"` + `for-append: false`：网关**用自己看到的对端地址覆写** `X-Forwarded-For`。
- `docker-compose.demo.yml:66-67` + `server/docker/nginx-domain.conf:42-43` — 线上链路是 `客户端 → 宿主 Nginx(443) → 127.0.0.1:9087(gateway)`。
- `server/docker/app-upstream.conf:9` — `proxy_set_header X-Forwarded-For $http_x_forwarded_for`（原样透传）。

**推导**：在「Nginx 在最外层」的部署里，网关的眼见对端恒为 `127.0.0.1`，于是**所有真实用户共用 `takeout:rl:login:127.0.0.1` 一个桶**。
- 攻击者每分钟发 10 次错误登录 → 该桶立即进入 `blocked` 状态 600 秒 → **全站所有人**登录/注册/找回密码/支付密码重置统统 429。
- 每 10 分钟重放一次即可维持「认证面永久不可用」，成本 10 个请求。
- 反向影响同样存在：任一用户输错 10 次会把所有人踢下线 10 分钟（自然触发也成立）。

**为什么不是「XFF 伪造绕过」**：主 `docker-compose.yml` 里网关就是最外层（`app` 未 publish 端口，只有 `gateway` 映射 `8087`），`for-append=false` 覆写后客户端注入的 XFF 会被丢弃；`[Lead 实测] /api/auth/* preflight 403` 也印证前端只能经网关。**只有把应用端口直接暴露出去（`TAKEOUT_APP_PORT` 对外）时，AZ-03 才会退化成「限流可绕过」**——两种形态都该修。

**修复建议**
1. 网关侧：`trusted-proxies` 收窄成宿主 Nginx 的地址，并改用 `for-enabled: true` + **追加**语义，由 Nginx 用 `$remote_addr` 写入唯一可信首段（现在 `nginx-domain.conf:33` 已这么做，但被网关覆写掉了）。
2. 应用侧：只信任「来自已知代理网段」的 `X-Forwarded-For`（`server.forward-headers-strategy=NATIVE` + `RemoteIpValve` 的内置可信网段），别自己 `split(",")[0]`。
3. 限流加第二维：`(action, account)` 与 `(action, ip)` 双桶，任一超限才封，避免「单人拖垮全站」。

---

### AZ-04 演示充值接口：登录用户可无限给自己加余额，不走支付流水 【Medium｜已验证代码路径 + Lead 线上确认开关为开】

**证据**
- `server/takeout-app/src/main/java/com/example/takeout/controller/AuthController.java:201-205` — `POST /api/auth/recharge`，`userId` 取自 token，`amount` 取自请求体，**无支付单、无回调、无流水**。
- `server/takeout-app/src/main/java/com/example/takeout/service/AuthService.java:327-338` — 仅 `demoRechargeEnabled` + `0.01~10000` 区间校验，然后 `userDao.addBalance(userId, round2(amount))`；可重复调用。
- `.env:22` — `TAKEOUT_DEMO_RECHARGE_ENABLED=true`；`application-develop.yml:5` 默认 `true`。
- 生产有硬闸：`server/takeout-app/src/main/java/com/example/takeout/config/ProductionHuaweiGuard.java:18-21`（production profile 下开了就直接**启动失败**）；`DemoModeWarning.java:17-20` 仅告警。

**影响**：线上 develop 档里，任何登录用户可把自己的余额刷到任意值（每次 ≤10000），随后用 `channel=BALANCE` 支付真实订单；商户侧会按 `pay_amount - delivery_fee` 结算（`OrderService.java:1049`），即**凭空生成的余额会转成商户可提现口径的收入**。生产 profile 不可用，故定为 Medium。

**修复建议**：`recharge` 整条链路加 `@Profile("!production")` 之外的**运行时二次断言**（如要求 `X-Demo-Token` 头 + 仅内网 IP），或直接删除该接口，演示余额改由 seeder 一次性发放；并在 `/api/auth/me` 上标注 `demo=true` 让前端禁用支付。

---

### AZ-05 商户可跨店删除他人门店的员工记录（IDOR，垂直方向不成立、水平方向成立）【Medium｜静态可证（DAO 无店铺收敛）】

**证据**
- `server/takeout-app/src/main/java/com/example/takeout/service/StoreService.java:799-802` — `removeStoreEmployee(ownerId, storeId, employeeId)` 只用 **路径上的 `storeId`** 做 `requireOwned`，随后 `employeeDao.delete(employeeId)`。
- `server/takeout-common/src/main/java/com/example/takeout/dao/EmployeeDao.java:51-53` — `DELETE FROM employees WHERE id = ?`：**SQL 里没有 store_id 条件**。
- 对照正确写法：`StoreService.java:414-425`（`replyReview` 有 `store.ownerId() != merchantId` 校验）、`AddressDao.java:48-50`（`WHERE id=? AND user_id=?`）。

**攻击链**：攻击者用自己的合法商户账号（或 AZ-02 自助注册的商户账号）拿到自己门店 `storeId` → `DELETE /api/merchant/employees/{victimEmployeeId}?storeId=<自己的店>` → `requireOwned` 通过 → DAO 按 `employeeId` 删除**任意门店**的员工行 → 受害商户的店员失去该店操作权限（商品/订单/评价），且列表里直接消失。

**同类可疑点（一并核过）**
- `StoreService.java:786-797` `addStoreEmployee`：`userId` 由调用方指定，未校验目标用户是否存在/是否 role=1 → 可写入悬空行；但 `requireOwned` 保证了只能写**自己**的店，不构成跨店越权。
- `StoreService.java:804-811` `requireOwned`：`store.ownerId() != ownerId && !employeeDao.isEmployee(ownerId, storeId)` → **店主或本店在职员工**均可操作该店（设计如此，属"多门店员工"）。因此「新注册商户能否操作他人店铺」的答案是**否**（Lead 的第 2 点在此否证）。

**修复建议**：`employeeDao.delete(long storeId, long employeeId)` 加 `AND store_id = ?`；`removeStoreEmployee` 先 `isEmployee/findById` 校验归属并返回 404 而非静默成功。

---

### AZ-06 账号枚举：注册/取码返回可区分的「已注册 / 不匹配」文案 【Medium｜静态确认 + Lead 线上 400 文案印证】

**证据**
- `server/takeout-app/src/main/java/com/example/takeout/service/AuthService.java:89-107` — `registrationEmail` 对已存在账号抛 `"该账号已注册"` / `"该手机号已注册"`。
- `AuthController.java:74-77` — `/api/auth/email-code` 的 register 分支**直接透传**这两个文案（未做统一化）。
- 对比正确做法：`AuthController.java:79-85` 的找回分支已把错误统一成 `"手机号或邮箱不匹配"`（说明团队知道该模式，只是注册分支漏了）。
- 限流不足以挡住：`register` 5 次/小时/IP，但 AZ-03 下该 IP 桶本身可被第三方耗尽/共享。

**影响**：批量探测「某手机号/账号是否注册过本平台」，为撞库与社工提供目标筛选；配合 AZ-10 的默认口令，可直接筛出可用账户。

**修复建议**：注册分支对「账号已存在 / 手机号已存在」返回与「验证码错误」同一条文案（例如统一 `"注册信息校验未通过"`），差异只写服务端日志；或改为「先发码、提交时再判重」并在提交阶段返回中性文案。

---

### AZ-07 CORS 通配配置与线上 preflight 403 不一致（配置是错的、线上是"意外安全"）【Low｜配置静态确认 + Lead 线上实测】

**证据**
- `server/takeout-app/src/main/java/com/example/takeout/config/WebConfig.java:62-69` — `allowedOriginPatterns("*")`、`allowedMethods(GET,POST,PUT,DELETE,OPTIONS)`、`allowedHeaders("*")`、`maxAge(3600)`，**未开 `allowCredentials`**。
- `server/takeout-gateway/src/main/resources/application.yml:5-61` — **网关没有任何 `globalcors` 配置**；Spring Cloud Gateway 无 CORS 配置时对跨域预检返回 403（与 Lead 实测 `preflight 403` 一致）。

**判定**
- 由于未开 `allowCredentials`，浏览器不会带 Cookie，`* + credentials` 那条经典漏洞**不成立**；Bearer token 在 `Authorization` 里、需脚本自己加，也不存在「自动带凭据」的 CSRF 面。
- 真正的风险在**部署形态漂移**：当前线上因网关拦下预检而"意外"拒绝跨域；一旦有人把 `/api/**` 直连到应用（例如绕过网关做调试、或在应用前换成另一台反代），通配 CORS 立刻生效 → 任意站点可用受害者 token 读取 `/api/auth/me`、订单、地址等响应。
- 判定为 Low：**不可直接利用，但配置意图与线上行为相反，属于"下一次改动就会变成洞"的定时炸弹。**

**修复建议**：把 `allowedOriginPatterns` 改成显式白名单（`https://hqyx.website`、本地 `http://localhost:*`），或直接删掉应用侧 CORS 并在网关 `globalcors` 统一收敛；同时把 preflight 403 的事实写进部署文档，避免后人误以为"跨域已配好"。

---

### AZ-08 `/api/auth/refresh`、`/api/auth/logout` 免鉴权且无限流 【Low｜静态确认】

**证据**
- `WebConfig.java:48-49` 放行 `/api/auth/refresh`、`/api/auth/logout`。
- `AuthController.java:129-132` — `refresh` 无鉴权、无 IP/账号限流，直接进 `RefreshTokenService.refresh`。
- `AuthController.java:145-155` — `logout` 无鉴权；`tokenRevocationService.revoke(token,...)` 只对**调用方已持有**的 token 生效，故**不能把他人踢下线**（否定结论，见第 3 节）。
- `RefreshTokenService.java:58-98` — 每次 `refresh` 走 `SELECT ... FOR UPDATE`（`TokenBlacklistDao.java:55-59`），并触发全表过期清理 `DELETE FROM token_blacklist WHERE expires_at < ?`（`TokenBlacklistDao.java:30,45`）。

**风险**：免鉴权写路径 + `FOR UPDATE` 行锁 + 每请求全表 `DELETE` → 低成本资源放大（并发打 `/refresh` 制造锁等待与清理风暴），且 `refresh` 用 256bit 随机串不可猜，数据面无法爆破。定 Low。

**修复建议**：两个端点都挂 `LoginRateLimiter`（新增 `refresh`/`logout` 策略，5/60s）；把全表清理搬出热路径（登出时只删本行，清理交给已有定时任务）。

---

### AZ-09 Swagger/OpenAPI 路径在"放行名单"里，且根本不在拦截器的 `/api/**` 范围 【Low｜静态确认 + 线上 404 印证已关闭】

**证据**
- `WebConfig.java:43-59` — 拦截器只挂 `/api/**`，但放行名单里又写了 `/v3/api-docs/**`、`/swagger-ui/**`、`/swagger-ui.html`（`:56-58`）。这三条**永远不会被拦截**，写进放行名单会让人误以为"还有其他保护"。
- `server/takeout-app/src/main/resources/application.yml:47-51` — `springdoc.api-docs.enabled` 默认 `false`（`TAKEOUT_OPENAPI_ENABLED`）；`application-production.yml:1-5` 再显式关一次。
- `OpenApiConfig.java:18-27` — 定义了 `bearerAuth` 方案但**不产生任何鉴权**。

**判定**：默认/生产关闭，Lead 线上 `/v3/api-docs` 实测 404 → 当前**不可利用**。风险是：只要有人为调试打开 `TAKEOUT_OPENAPI_ENABLED=true`，整套接口文档（含管理端 `/api/admin/**` 全量路径与参数）在**无鉴权**下公开，直接省掉攻击者的信息收集阶段。
**修复建议**：从放行名单删掉这三条（它们本就不在 `/api/**`，删掉不改变行为，但消除误导）；需要在线文档时用独立 profile + Basic 认证。

---

### AZ-10 演示/默认口令 + README 公开账号表：非 production 且未注入 `TAKEOUT_DEMO_ADMIN_PASSWORD` 时得到 `admin/123456` 【Info→Low｜已验证（种子散列强度）+ Lead 线上默认口令可用】

**证据**
- `server/takeout-app/src/main/java/com/example/takeout/config/DataSeeder.java:32-33` — `@Value("${takeout.demo.admin-password:123456}")`，**默认值就是 123456**。
- `DataSeeder.java:178-187` — `ensureAdminUser` 在**任何**非空库上都会补建 `13100131000`（role=2），口令取上述配置。
- `DataSeeder.java:196-216` — 骑手 `13300133000/123456`（role=3）同样硬编码；`:535-552` 用户/商户账号全部 `PasswordUtil.hash("123456")`。
- `README.md:252-261`（"测试账号（密码均为 123456）"表）把 `13100131000` 管理员口令**公开写在仓库首页**。
- `docker-compose.yml:82-121` **没有**传 `TAKEOUT_DEMO_ADMIN_PASSWORD`（只有 `docker-compose.demo.yml:36` 用 `:?` 强制设置）→ 用主 compose 起 develop 时管理员就是 `123456`。
- `application-develop.yml:3`（`data-seed.enabled: true`）、`application-production.yml:9`（`false`）。

**PoC（旁证：散列本身是 PBKDF2，问题在口令不在算法）**

```text
[1] DataSeeder 写入的散列 = pbkdf2-sha256$600000$acea1c8... (PBKDF2 600k，不是明文/无盐)
[1] needsRehash = false   （当前强度已达标，登录不会降级）
[2] 旧库遗留散列示例 = b86af4172288a2cd465eedefe52f92400e1ae6ad620609a340505ad63b4519cd (未加盐)
[3] 离线命中：第 3 次 / 189us -> '123456'
[4] 修正结论：演示账号散列本身是 PBKDF2；真正的弱点是**已知默认口令 123456**，与散列强度无关
```

**判定**：单独看是「演示数据的固有风险」（Info）；但线上 develop 公开站被 Lead 实测确认 **`admin/123456` 口径的默认口令体系在用**（`13100131000` 与 README 表一致，且 `/api/auth/me` 余额等于 `signup-balance` 默认值），等于**把管理端交给任何读过 README 的人**。故按暴露面记 Low（生产 profile 会关 seeder，且 public 库需 `TAKEOUT_DEMO_ADMIN_PASSWORD`）——但只要线上是 develop，实际就是 Critical 效果，见「修复优先级」。

**修复建议**
1. `DataSeeder` 的 `admin-password` 去掉默认值（改成 `:?` 式必需项，缺配置直接启动失败），并在 `@Profile("!production")` 外加一道「仅 localhost」的启动检查。
2. 演示站启动时随机化管理员/骑手/商户口令并打印到服务器日志（不进前端、不进 README）。
3. 把 README 的账号表删掉或改成「首次启动由 seeder 打印」。

---

## 2. 修复优先级

| 顺序 | 项 | 理由 |
| --- | --- | --- |
| P0（立即） | AZ-01 轮换 JWT 密钥；AZ-10 去掉默认管理员口令 | 两者都直接等价于管理员接管，且都可在**无凭据**下发起 |
| P1（当日） | AZ-02 关掉 role=1/3 自助注册 + 骑手审批；AZ-03 修限流标识 | 一个泄露真实用户 PII，一个能让认证面整体不可用 |
| P2（本周） | AZ-04 收敛充值；AZ-05 员工删除加店铺条件；AZ-06 统一注册文案 | 业务资金与数据完整性 |
| P3（下次迭代） | AZ-07 CORS 白名单；AZ-08 两个端点挂限流；AZ-09 删误导性放行项 | 现在是"潜在"，改动前风险会上升 |

## 3. 已核查并**否证**的方向（避免重复投入）

| 方向 | 结论 | 证据 |
| --- | --- | --- |
| 未加 `/api` 前缀的接口绕过拦截器 | **不存在**。16 个 Controller 的类级映射全部是 `/api`、`/api/auth`、`/api/rider`、`/api/cart`、`/api/admin*`、`/api/location`、`/api/assistant`、`/api/payment` | `WebConfig.java:43-44` 挂 `/api/**`；逐文件核对 `@RequestMapping` |
| `/api/auth/refresh` 无鉴权却签发 token | **设计如此**，不是缺陷：refresh 凭据是 32 字节随机串（`RefreshTokenService.java:129-133`），只存 SHA-256（`:135-142`），轮换 + 重用检测（`ru:` 分支 `:73-76`）齐全 | 256bit 不可爆破；重用即焚族 |
| `/api/auth/logout` 无鉴权能否踢人 | **不能**。只能吊销「调用方已经持有」的 token；黑名单按 jti 精确匹配（`TokenBlacklistDao.java:37-42`），无批量入口 | `AuthController.java:145-155` |
| JWT `alg=none` / 算法混淆 | **不可利用**。jjwt 0.12.6 `parseSignedClaims` 默认拒绝未签名 JWS，且 `verifyWith(SecretKey)` 只接受 HMAC 族 | PoC 输出 `[5]` |
| `pwdAt` 字典序比较的时区/格式问题 | 当前**正确**。列是 `VARCHAR(32) DEFAULT ''`（`schema.sql:16`），写入与比较都用 `yyyy-MM-dd HH:mm:ss`（`AuthService.java:24,239-252`），字典序=时间序；从未改密时为空串且被 `isBlank()` 跳过（`AuthInterceptor.java:62-65`）。**脆弱点**：格式一旦被外部写入（ISO 带 `T`、带毫秒）就会全站误杀或全部放行——建议改成解析 `LocalDateTime` 后比较 | 同上 |
| 用户垂直越权（用户调商户/骑手/管理端） | **不成立**。每个方法都显式校验：`requireMerchant` `role!=1`、`requireRider` `role!=3`、`requireAdmin` `role!=2`；且 token 里的 role 与库里的 `user.role()` 再做一次比对（`AuthInterceptor.java:51-56`），改库降级/提权也会立刻 401 | `OrderController.java:162-166`、`UserCenterController.java:249-253`、`StoreController.java:440-444`、`RiderController.java:144-148`、`AdminController.java:313-317`、`AdminContentController.java:115-119`、`AdminRiderController.java:47-51`、`AdminAssistantController.java:57-61`、`AdminOperationLogController.java:25-31`、`AssistantController.java:34-37` |
| 水平越权 / IDOR：地址、银行卡、优惠券、收藏、订单 | **主要路径已收口**：地址增删改查 4 个 SQL 全带 `user_id`（`AddressDao.java:34-68`）；银行卡同（`BankCardDao.java:37-40,59-64,97-105`）；下单时地址/优惠券从 `listByUser(userId)` 里挑（`OrderService.java:247,369`）；订单 6 处操作均校验 `order.userId() != userId`（`OrderService.java:501,514,695,704,726,804,1018,1091`）；商户侧校验 `store.ownerId()`（`:871,1179-1181`） | **唯一漏点是 AZ-05 的员工删除** |
| 注册接口能否覆盖已有账号 | **不能**。`userDao.insert` 前有 `existsByUsername/existsByPhone` 双检（`AuthService.java:100-105`），且验证码要先 `consume` 才写库（`:82`）；无 `ON DUPLICATE KEY UPDATE` | — |
| 找回密码/支付密码可越权重置他人 | **不成立**。验证码 identity 是 `recovery:<userId>:<login|payment>:<phone>:<email>`（`AuthService.java:217-222`），`consume` 侧用同一 identity 才能命中（`:186,197`），且 `recoveryUser` 强制 phone+email **同时**匹配（`:201-215`）；`purpose` 只允许 `login|payment` 且两者不互通；单码 5 次尝试即焚（`SmsVerificationService.java:25-32,140-158`） | 需同时掌握受害者手机号+邮箱+邮箱收信权 |
| 验证码 mock 后门（`TAKEOUT_SMS_EXPOSE_MOCK_CODE`） | **线上未生效**。`application-develop.yml:9` 的 `expose-mock-code: true` 只是**profile 默认**，环境变量 `TAKEOUT_SMS_EXPOSE_MOCK_CODE=false`（`.env:23`）优先级更高（Spring Boot 属性优先级：OS env > profile yml > application.yml）→ 生效值 `false`；且 `.env:24` 的 `TAKEOUT_SMS_PROVIDER=qq-email` 让 `MockSmsSender`（`@ConditionalOnProperty havingValue="mock"`）**根本不会被实例化**，`exposesCodeForDevelopment()` 永远 false → `SmsVerificationService.java:97-98` 返回空码。生产另有 `ProductionHuaweiGuard.java:15-21` 双重拒绝 | 若有人只用 `-Dspring.profiles.active=develop` 而不带环境变量，则会真回传验证码——属配置风险而非代码漏洞 |
| 日志泄露 token | **不成立**。`ApiRequestLoggingInterceptor.java:54-57` 只记 `Bearer/None` 标记，不记 header 与 body；异常日志不打印凭证 | — |
| 禁用账号的存量 token | **已失效**。`AuthInterceptor.java:57-59` 每次请求查库校 `status`，不等 token 过期 | — |

## 4. 未覆盖项（后续如需继续）

1. **支付回调验签**（`/api/payment/wechat/notify`、`/api/payment/alipay/notify` 免鉴权）：`PaymentNotificationController.java:33-53` 属支付域，本次只确认「微信头存在」，未做重放/伪造验签测试——建议单独一轮。
2. **真实 Redis 下的验证码/限流行为**：`SmsVerificationService` 的 Lua 计数与 `LoginRateLimiter` 的 `INCR+EXPIRE` 需要 Redis 才能压测并发竞态；本次仅有代码级论证。
3. **多实例竞态**：`docker-compose.yml:71-76` 是 `replicas: 2`，refresh 轮换与 jti 黑名单在双实例下的时序未实测。
4. **上传面**：`md/开发参考.md:251` 自认「只校验后缀+content-type，未做魔数校验」，任意登录用户可传任意内容到公开 `/uploads/**`；属上传/存储域。
5. **Docker 实服 HTTP 验证**：守护进程未运行，未起容器；所有结论基于源码 + 已编译类的进程内 PoC + Lead 的线上只读探针。
