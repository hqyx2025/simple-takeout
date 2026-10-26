# 二次红队复测 · auth-red（认证与授权攻击线）

- 日期：2026-10-25
- 目标：本地源码 `server/`（= 线上 `defense-20261025-145628` 同源）+ 线上 https://hqyx.website/takeout/
- 攻击依据：`md/audit/defense/防御结果.md`、`md/audit/round1/漏洞攻击报告.md`、`md/audit/round1/findings-{authz,payment,infra}.md`
- 判定口径：只按"校验在什么条件下不生效"定性，不采信防御自述。所有结论均有 file:line 或实测输出。

## 结论摘要

| 编号 | 级别 | 标题 | 一句话结论 | 线上状态 |
| --- | --- | --- | --- | --- |
| A-01 | **High** | 登录"账号摘要桶"与凭据查询的等值语义不一致 | 限流键用原始手机号字符串做 SHA-256，凭据查询走 MySQL `utf8mb4_0900_ai_ci`；给手机号追加 U+200B 等可忽略字符后，SQL 仍命中同一账号，但每个变体都是全新限流桶 → 任意账号（含唯一管理员）无限次密码猜测 | 未测（见条目内说明） |
| A-02 | Medium | 低权员工可增删本店员工名单 | `requireOwned()` 对"店主"和"店员"一视同仁，任一店员可添加/移除同事（含店长以外的所有员工），`roleName` 任意可控 | 未测（线上启用商户数=0） |
| A-03 | Medium | 成功登录清零 IP 桶 + 每次登录落两行黑名单 | 单账号凭正确密码可无上限调用登录：每请求 60 万次 PBKDF2 + 2 行 `token_blacklist` 写入，清理速率仅 1000 行/分钟 | 未测（需有效账号+压测，授权禁止） |
| A-04 | Low | 停用账号可被登录文案直接枚举 | `status` 在密码校验**之前**判断，"账号已停用"与"账号或密码错误"文案不同，无需密码即可确认某手机号存在且被停用 | 未测（原因见条目） |
| A-05 | Low | 验证码开发回传守卫在 production profile 下整体消失 | `DemoModeWarning` 带 `@Profile("!production")`，切到生产 profile 后"回传即拒绝启动"这条 fail-fast 不再装配，只剩运维自觉 | 未测（需读服务器 .env，本轮禁止连服务器） |

**一句话给 lead**：A-01 是唯一需要立刻修的——防守方第二轮新加的"来源＋账号摘要"桶（V-12 声称已修）被排序规则等价字符整条打穿，实测 40 次密码猜测全部进入业务校验、0 次被限流。

---

## A-01 ｜【High】登录限流"账号摘要桶"键与凭据查询的等值语义不一致，任意账号可被无限次密码猜测

### 结论

防守方第二轮新增账号维度限流桶 `takeout:rl:login-account:<ip>:<sha256(原始 phone 字符串)>`，但凭据查询用的是 `WHERE phone = ?`，参数落在 `utf8mb4_0900_ai_ci` 排序规则下。该排序规则把 U+200B/U+200C/U+200D/U+2060/U+FEFF 等"可忽略字符"按空串参与比较，且全角数字与半角数字判等。结果：同一账号有无限多个字节不同、SQL 等价的手机号表示，每个表示对应一座全新的限流桶。叠加"登录成功会 `reset("login", ip)`"这一既有逻辑，攻击者用一个自有账号的成功登录即可反复清零 IP 桶——**账号维度和 IP 维度同时失效**。

### 证据

1. 限流键取原始字符串，没有任何规范化：
   `server/takeout-app/src/main/java/com/example/takeout/controller/AuthController.java:115-119`
   ```java
   String accountKey = loginAttemptIdentity(ip, req.phone());
   if (loginRateLimiter.isBlocked("login", ip) || loginRateLimiter.isBlocked("login-account", accountKey)) { ... }
   loginRateLimiter.recordAttempt("login-account", accountKey);
   ```
   `AuthController.java:132-140`：`digest(String.valueOf(phone).getBytes(UTF_8))` —— 纯字节哈希，不做 NFKC/白名单。
   `server/takeout-common/src/main/java/com/example/takeout/security/LoginRateLimiter.java:178-180`：`KEY_PREFIX + action + ":" + ip`。

2. 凭据查询没有任何格式校验（这是关键差异：同族其它入口都锚定了）：
   `server/takeout-app/src/main/java/com/example/takeout/service/AuthService.java:114-116`
   ```java
   public LoginResult login(String phone, String password, String loginType) {
       User user = userDao.findByPhone(phone) ...
   ```
   `server/takeout-common/src/main/java/com/example/takeout/dao/UserDao.java:40-42`：`SELECT * FROM users WHERE phone = ?`。
   对照：`AuthService.java:95-97`（注册）、`AuthService.java:195-201`（找回）都有 `phone.matches("1\\d{10}")` **且** 找回还要求 `phone.equals(user.phone())`。**只有登录入口既没有格式校验也没有 equals 复核。**

3. 表结构不声明 COLLATE，实际落在 `utf8mb4_0900_ai_ci`：
   `server/takeout-app/src/main/resources/schema.sql:4-22` 只有 `DEFAULT CHARSET=utf8mb4`（无 COLLATE）。
   仓库内真实 mysqldump `server/database/takeout-latest.sql` 的 users 表尾：`ENGINE=InnoDB ... DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`。
   临时 MySQL 8.4（同 compose 参数 `--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci`）实测：
   ```text
   @@character_set_server  @@collation_server        @@collation_database
   utf8mb4                 utf8mb4_unicode_ci        utf8mb4_unicode_ci
   TABLE_COLLATION
   utf8mb4_0900_ai_ci        <-- 显式 CHARSET 时取字符集默认排序规则，compose 的 collation-server 不生效
   probe              hit
   exact              1
   trailing-space     0     <-- NO PAD：尾部空格不判等
   fullwidth-digits   1     <-- 全角数字判等
   superscript-2      0
   append-zwsp        1     <-- 尾部追加 U+200B 判等
   prepend-twice      1     <-- 前缀两个 U+200B 也判等
   after-insert-count       1 / after-second-insert-count 1   <-- UNIQUE(phone) 同样判等，不会产生重复行
   ```

4. 端到端 PoC（真实 `UserDao` + 真实 `AuthService` + 真实 `AuthController` + 真实 `LoginRateLimiter`，数据库为本机临时 MySQL 8.4，建表语句与 `schema.sql` 一致）：
   PoC 文件：`md/audit/cache/round2-redteam/auth-red/LoginAccountBucketSuffixBypassPocTest.java`
   运行：`mvn -o -f server/pom.xml -pl takeout-app -am test -Dtest=LoginAccountBucketSuffixBypassPocTest`
   ```text
   [PoC-B1] findByPhone(victim) -> present=true
   [PoC-B1] findByPhone(victim+U+200B) -> present=true userId=1
   [PoC-B1] 两个入参字节不同：len 11 vs 12
   [PoC-B2] login(victim+U+200B, 正确密码) -> tokenUserId=1 username=victim
   [PoC-B3] 40 次密码猜测：进入业务校验=40，被限流=0      <-- 变体组，无一被拦
   [PoC-B3] 限流命中轨迹=[]
   [PoC-B4] 固定手机号 40 次猜测：进入业务校验=10，被限流=30   <-- 对照组，第 10 次后全拦
   Tests run: 4, Failures: 0, Errors: 0
   ```
   B4 对照组同时证明：防守方线上验证过的"错误密码预算 429"（`防御结果.md` 部署验证一节）只是**固定手机号**这一种写法，与变体绕过并不冲突。

### 攻击链

前置：攻击者需要一个自有账号（`POST /api/auth/register` 允许 role=0 自助注册，这是正常业务，不是漏洞）。

1. 目标账号 T（手机号 P，如唯一启用管理员的号）。任选变体生成器：`P + "\u200B".repeat(k)`，或把任一数字替换为全角（`１３８…`），或在数字间插入 U+200B。
2. `POST /takeout/api/auth/login`，body `{"phone":"<变体_i>","password":"<猜测>"}`：
   - `AuthController:115` 用变体串算 `accountKey`，第 i 个变体 = 第 i 座新桶，`isBlocked` 永远 false；
   - `AuthController:119` 只给该变体桶记 1 次；
   - `AuthService:115` → `UserDao:41` 在 `0900_ai_ci` 下命中 T 的真实记录，于是**这次猜测校验的正是 T 的密码**。
3. 失败计数把 `login:ip` 累到第 10 次前，用自有账号成功登录一次 → `AuthController:122` `reset("login", ip)` 把 IP 桶与封禁键一起删除（`LoginRateLimiter:109-121`）。
4. 循环步骤 2-3：**猜测次数无上限**。
5. 命中密码后拿到 role=2 的 token，直接进 `/api/admin/**`（`loginType` 可省略，`AuthService:124-129` 只在传了才校验）。

本地复跑（不需要线上）：见上文 PoC 命令与输出；变体清单 `U+200B/U+200C/U+200D/U+2060/U+FEFF/U+0000/全角数字` 均已由 lead 与我各自独立在 SQL 层复核判等。

### 线上状态

**未测。** 原因：(1) 证明需要在线上对某个账号连续发 10 次以上错误密码，直接违反本轮"错登最多 1-2 次且会触发封禁桶"的授权约束，且会把真实用户的登录桶打满；(2) 线上没有我可用的账号，注册账号被明令禁止；(3) 我无法读取线上数据库排序规则（禁止连服务器），只能以"同源 schema + 仓库内真实 dump + 同版本 MySQL 复现"三重证据推定。代码路径是确定的，不依赖线上环境变量。

### 为什么防守方没堵住

- `md/audit/defense/防御结果.md` V-12 行自称："**保留 IP 桶和"来源＋账号摘要"桶，自己的成功登录不能清除他人猜测预算**"。两处都站不住：
  1. "账号摘要桶"的键是**原始请求字符串**的 SHA-256，而凭据比对发生在**数据库排序规则**里，两者语义不一致——摘要桶只是"每个字符串一座桶"，不是"每个账号一座桶"。
  2. "自己的成功登录不能清除他人猜测预算"只对**账号桶**成立（`reset` 传的是自己的 accountKey），**IP 桶仍被整键删除**（`LoginRateLimiter:116-117` 连 `:blocked` 一起 `delete`）。防守方的回归测试 `server/takeout-app/src/test/java/com/example/takeout/controller/AuthControllerRateLimitTest.java:25-41` 只断言了"固定手机号"场景，因此无法发现变体键。
- V-05 行把注意力全放在"来源 IP 能否伪造"上，结论是"限流仅取解析后的 remoteAddr"——**每个请求的 remoteAddr 确实唯一可信，但桶的键空间被攻击者用字符串变体放大了**，这是同一维度里的另一个缺陷。
- 与 V-13 的"取码阶段不再查重"属于同一类思维：把"看起来不同的输入"当成"不同的主体"，而没有在**主体解析（userId）**上做归一。

### 修复建议

1. 最小改动、与同族入口对齐——登录入口先做与注册/找回完全相同的手机号校验，规范化后的值同时用于限流键与凭据查询：
   - `server/takeout-app/src/main/java/com/example/takeout/service/AuthService.java`：把 `registrationEmail:95-97` 的手机号校验抽成 `public static String requirePhone(String phone)`，并在 `login:114` 开头调用它。
   - `server/takeout-app/src/main/java/com/example/takeout/controller/AuthController.java:113-121`：
     ```java
     String phone = AuthService.requirePhone(req.phone());   // ^1\d{10}$
     String accountKey = loginAttemptIdentity(ip, phone);
     ... authService.login(phone, req.password(), req.loginType())
     ```
2. 结构性修复（推荐同时做）：限流键改用**解析后的主体**而不是请求字符串。在 `AuthController.login` 内先 `userDao.findByPhone(phone)` 拿到 id，再以 `"u" + userId` 作为 `login-account` 的键；同一账号的一切表示自然共用一座桶。
3. 纵深防御（数据库层）：把手机号列收窄为 `ascii`/`binary` 比较，使非 ASCII 变体根本无法判等：
   `ALTER TABLE users MODIFY phone VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL;`
   （`SchemaMigration` 需同步；注意 `schema.sql:8` 的 `UNIQUE` 保留。）
4. `reset("login", ip)` 改为"减一"而不是"删键"，或在键中带上"仅本人成功"的维度，避免一次成功登录把整条 IP 失败曲线清零。
5. 回归测试：断言 `login("13800138000\u200B", ...)` 返回 400，且 `loginAttemptIdentity` 对规范号与任一变体产出相同键；再用真实 MySQL 跑一遍 `findByPhone(variant)` 必须为空。

---

## A-02 ｜【Medium】任一门店员工可增删本店员工名单，角色名任意可控

### 结论

员工管理接口的归属校验与"改价/上架"共用 `requireOwned()`，而该方法把"店主"和"该店任一启用员工"视为等价。于是最低权限的店员可以添加任意 userId 为员工、可以移除任意同事，`roleName` 由调用方自由填写（写库、不再校验）。这是防守 `V-09`（跨店删员工）修好之后仍然存在的**店内横向提权**。

### 证据

- `server/takeout-app/src/main/java/com/example/takeout/service/StoreService.java:786-797`
  ```java
  public Employee addStoreEmployee(long ownerId, long storeId, long userId, String roleName) {
      Store store = requireOwned(ownerId, storeId);          // 员工也通过
      if (store.ownerId() == userId) throw ...;
      String role = roleName == null || roleName.isBlank() ? "店员" : requireMaxLength(roleName.trim(), 16, "员工角色");
      long id = employeeDao.insert(storeId, userId, role, ...);
  ```
- `StoreService.java:799-804` `removeStoreEmployee` 同样只调 `requireOwned`；`StoreService.java:806-813`：
  ```java
  if (store.ownerId() != ownerId && !employeeDao.isEmployee(ownerId, storeId)) throw new BizException(403, "无权操作该店铺");
  ```
- 入口：`server/takeout-app/src/main/java/com/example/takeout/controller/StoreController.java:194-211`（两者都只校验 `role == 1`）。
- `roleName` 下游没有任何鉴权用途：`employees` 表只在 `listStoreEmployees` 里展示，因此它**不构成**纵向提权，只是自由文案。

### 攻击链

1. 攻击者持有某店一个"店员"身份的 role=1 账号（`StoreService:809` 只查 `employees` 行 + 状态）。
2. `DELETE /takeout/api/merchant/employees/{id}?storeId=<本店>` → 逐个清掉店主之外的所有员工（`removeStoreEmployee` 只约束 `store_id` 匹配，不区分操作者层级）。
3. `POST /takeout/api/merchant/employees?storeId=<本店>` `{"userId":<攻击者同伙 id>,"roleName":"店长"}` → 把同伙加入，形成持久化的店内多数。
4. 结果：店员可以单方面改变门店的运营人员集合；店主只能事后发现（列表里人手变了，没有审计告警）。

### 线上状态

**未测。** 线上当前启用商户数为 0（`防御结果.md` 部署记录："当前启用的商户／骑手账号为 0"），没有可用的 role=1 账号；也不允许我注册/申请商户。属于纯代码可判定项。

### 为什么防守方没堵住

- V-09 行只声称："DELETE 同时约束 employeeId 与已授权 storeId，无匹配记录返回 404"。修复把**跨店**（纵向越界）堵住了，但没有回答"店内谁有权管理员工"这个问题；`requireOwned` 仍是"店主或员工即可"，员工的**粒度授权**不在本轮范围内。
- V-02 行也承认："未新增资质审批系统或实物交付证明"——员工分级授权同样没有设计。

### 修复建议

1. `server/takeout-app/src/main/java/com/example/takeout/service/StoreService.java`：为员工名单操作引入 `requireStoreOwner(ownerId, storeId)`（只允许 `store.ownerId() == ownerId`），并让 `addStoreEmployee:786`、`removeStoreEmployee:799` 改用它；`requireOwned` 保持给商品/订单/店铺信息使用。
2. 若产品确实需要"店长管员工"：在 `employees` 表加 `permission` 列（如 `OWNER_MANAGED`/`STAFF`），`addStoreEmployee` 校验调用者的 `roleName` 是否具备 `manage_staff`，并把 `roleName` 收敛为服务端白名单枚举（当前是任意 16 字符）。
3. 员工增删写操作审计：`ApiRequestLoggingInterceptor:97-98` 目前只记录 `/api/admin/` 与 `/api/merchant/` 前缀，建议把 `/api/merchant/employees` 单独打标，便于事后追责。

---

## A-03 ｜【Medium】成功登录即清零 IP 限流桶 + 每次登录写两行黑名单

### 结论

`POST /api/auth/login` 走的是"失败才计数"模型，且**成功时把整条 IP 桶（含封禁键）删除**。一个持有自有账号的攻击者可以对登录接口发起无上限请求：每个请求触发一次 60 万轮 PBKDF2 校验，并往 `token_blacklist` 写入 2 行（access jti + refresh token），而清理任务只有 1000 行/分钟。这是认证面的资源放大，和 A-01 共用同一个"reset 太宽"的根因。

### 证据

- `AuthController.java:120-129`：成功分支 `loginRateLimiter.reset("login", ip)`。
- `LoginRateLimiter.java:109-121`：`reset` 直接 `redis.delete(counterKey)` + `redis.delete(blockKey)`，没有"减一"或"只清本人维度"的语义。
- `server/takeout-common/src/main/java/com/example/takeout/security/PasswordUtil.java:16`：`ITERATIONS = 600_000`；`matches:35-58` 每次登录都跑一次完整派生。
- `server/takeout-app/src/main/java/com/example/takeout/service/RefreshTokenService.java:42-56`：登录成功后 `trackAccessToken`（`TokenBlacklistDao.java:43-46` 插入 `ac:<family>`）+ `insertRefreshToken`（`TokenBlacklistDao.java:38-41` 插入 `rf:<family>`）= 每登录 2 行。
- `server/takeout-common/src/main/java/com/example/takeout/dao/TokenBlacklistDao.java:82-84`：`DELETE ... LIMIT 1000`，`TokenCleanupJob` 每分钟一轮；refresh 行的 `expires_at` 是 30 天后（`RefreshTokenService.java:27`），即 30 天内不清理。

### 攻击链

1. 攻击者注册一个 role=0 账号，拿到正确密码。
2. 循环 `POST /takeout/api/auth/login {"phone": <自有号>, "password": <正确>}`：
   - 每次命中 `AuthController:122` 的 reset，IP 桶恒为 0，永远不会 429；
   - 每次新签发 access+refresh，落 2 行 `token_blacklist`，30 天内不被清理。
3. 并发 N 路 → `token_blacklist` 线性增长（行数 ≈ 2 × 请求数），单行 `jti`(36) + `reason`(27) 约百字节级；同时每请求一次 PBKDF2-600k，单核每秒可被压满。
4. 额外收益：`AuthController:124` 的 `refreshTokenService.issue` 还会对 `users` 行加 `FOR UPDATE`，进一步放大行锁竞争。

### 线上状态

**未测。** 需要有效账号 + 持续压测，属本轮明确禁止的动作（"禁止创建账号、下单、支付"、"线上只做低频只读探测"）。吞吐数字属推断，未在线上或本机实测。

### 为什么防守方没堵住

- V-12 行："登录、支付密码设置、银行卡揭示在验证密码前占用对应预算；保留 IP 桶和"来源＋账号摘要"桶，自己的成功登录不能清除他人猜测预算"。实现里"成功即 `reset`"这一条从未被审视——它把 IP 桶做成"可被任何一次成功登录无条件清零"。
- V-19 行只给 refresh/logout 加了 30 次/分钟，登录本身没有"成功路径"的预算控制。

### 修复建议

1. `AuthController.java:122`：把 `reset("login", ip)` 改为"扣减一次失败计数"（`LoginRateLimiter` 新增 `decay(action, key)`，Redis `DECR` + 不低于 0，且不删封禁键）；封禁键只能靠 TTL 自然过期。
2. 登录成功路径加独立预算：`new Policy(30, 60, 300)` 的 `login-success` 桶按 `u<userId>` 计数，超限只拒绝**新建会话**（返回 429，不影响已签发 token 的校验）。
3. 给 `token_blacklist` 加每用户活跃会话上限（如每 user 最多 10 条 `rf:`/`ac:`，插入时按 `create_time` 删最旧），避免会话表成为无界写放大面。
4. `TokenCleanupJob` 的批大小可配置并调大（当前硬编码 1000，`TokenBlacklistDao.java:83`）。

---

## A-04 ｜【Low】停用账号可被登录文案直接枚举（status 校验早于密码校验）

### 结论

`login` 在**校验密码之前**就判断 `user.status()`，并对停用账号返回专属文案。任何人都可以用一个错误密码区分"该手机号从未注册/正常"与"该手机号已注册且被停用"，无需任何凭据。防守方本轮停用了 6 个演示账号，等于给出了一份可枚举的"停用账号指纹"。

### 证据

`server/takeout-app/src/main/java/com/example/takeout/service/AuthService.java:115-123`
```java
User user = userDao.findByPhone(phone).orElseThrow(() -> new BizException("账号或密码错误"));
if (user.status() != 1) {
    throw new BizException("账号已停用，请联系平台管理员");     // <-- 密码还没校验
}
if (!PasswordUtil.matches(password, user.password())) {
    throw new BizException("账号或密码错误");
}
```
请求次数上是"1 次请求 1 个比特"，不需要走验证码，也不需要正确密码。

### 攻击链

1. 对候选手机号发 `POST /takeout/api/auth/login {"phone":"<P>","password":"x"}`。
2. 返回"账号已停用，请联系平台管理员" ⇒ P 已注册且当前被停用；返回"账号或密码错误" ⇒ P 未注册或正常启用。
3. 逐个手机号扫，可复原"哪些是老演示账号/被封禁账号"。限流（10 次/10 分钟/IP + 账号桶）能拖慢，但不能消除——且配合 A-01 的变体绕过，连拖慢也不成立。

### 线上状态

**未测。** 需要针对停用账号发一次登录；我不知道 6 个停用演示账号的手机号，且该类探测会消耗真实限流名额。代码路径确定，属于"必然成立"的差集。

### 为什么防守方没堵住

- V-13 行只说"注册取码阶段不再查重和返回"账号／手机号已注册"；完成有效邮箱验证码校验后才查重，重复信息统一返回"注册信息校验未通过"…**不宣称绝对不可枚举**"。登录入口的文案差异没有被纳入这条修复，属于自认残余但未量化。
- V-06 行"线上停用 6 个确实仍匹配公开默认口令的演示账号"——恰好让这个 oracle 变得有实际意义（可反推哪些是历史演示号）。

### 修复建议

`AuthService.java:117-123`：把 `status` 判断挪到 `PasswordUtil.matches` **之后**，且停用账号也返回与"账号或密码错误"完全一致的 `code/message`（差异化提示交给"已登录后被踢下线"的 401 文案 `AuthInterceptor.java:57-59` 承担）。回归测试：对停用账号用错误密码登录，断言 message 与不存在账号完全相同。

---

## A-05 ｜【Low】"验证码开发回传"的启动守卫只在非 production profile 装配

### 结论

防守方声称"开发环境验证码回传也改为启动拒绝"，但该 fail-fast 写在 `DemoModeWarning` 上，而该类带 `@Profile("!production")`。一旦按 `docker-compose.yml` 文档切到 `SPRING_PROFILES_ACTIVE=production`，这个守卫**根本不装配**；此时唯一阻止"验证码回传"的就是运维别把 `TAKEOUT_SMS_EXPOSE_MOCK_CODE` 设成 true。守卫靠 profile 装配、生产不装配，是典型的"修好了但不生效"结构。

### 证据

- `server/takeout-app/src/main/java/com/example/takeout/config/DemoModeWarning.java:7-16`
  ```java
  @Component
  @Profile("!production")            // <-- production profile 下整类不加载
  public class DemoModeWarning {
      public DemoModeWarning(@Value("${takeout.sms.expose-mock-code:false}") boolean exposeMockCode, ...) {
          if (exposeMockCode || demoRechargeEnabled) throw new IllegalStateException("验证码回传与演示充值已停用...");
  ```
- 充值/赠金那条守卫是**无条件**的（`AuthService.java:31-39`），所以 A-05 只覆盖"验证码回传"这一项。
- 回传的实际出口：`SmsVerificationService.java:97-98` `sender.exposesCodeForDevelopment() ? code : ""`；`MockSmsSender.java:14-16,24-26` 直接把配置值透出。
- 触发条件组合：`SPRING_PROFILES_ACTIVE=production` + `TAKEOUT_SMS_PROVIDER=mock`（`MockSmsSender.java:9` `matchIfMissing=true`，不设也会命中）+ `TAKEOUT_SMS_EXPOSE_MOCK_CODE=true`。此时 `DemoModeWarning` 不装配，启动不报错。若该组合生效，`email-code` 会在响应里直接返回验证码 → 只要知道"手机号+邮箱"就能完成 `password/forgot` 接管账号（`AuthService.java:174-182`）。

### 攻击链

1. 前提是部署方误用 production profile 又打开了回传/或沿用旧 .env（`defense` 记录说"现有 `.env` 没有被改写"）。
2. `POST /takeout/api/auth/email-code {"phone":"<受害者手机>","email":"<受害者邮箱>","purpose":"login"}` → 响应 `{"code":"123456","mock":true}`。
3. `POST /takeout/api/auth/password/forgot {...,"code":"123456","newPassword":"..."}` → 直接改掉受害者密码。
   限制：需要先知道受害者的 phone+email 组合（`recoveryUser` 要求两者同时匹配，`AuthService.java:194-208`）。

### 线上状态

**未测。** 需要读取服务器 `.env`/compose 的 `SPRING_PROFILES_ACTIVE` 与 `TAKEOUT_SMS_EXPOSE_MOCK_CODE`，本轮禁止连接服务器；线上 `email-code` 会真实发信，属禁止动作。当前部署的实际 profile 依 `防御结果.md` 是"保留原有 develop 体验环境"，故**当前线上大概率有守卫**；本条针对的是"切生产后守卫消失"。

### 为什么防守方没堵住

`防御结果.md` V-01 行："任一 profile 的危险充值／赠金配置会阻止 AuthService 创建；**开发环境验证码回传也改为启动拒绝**"。"开发环境"四个字是自述的边界——但它同时把守卫限定在非生产 profile，于是"生产 profile 下是否允许回传"变成没人守的空档。

### 修复建议

1. `DemoModeWarning.java:8`：删掉 `@Profile("!production")`，让它对所有 profile 生效（它只做拒绝，不会影响生产正常配置）。
2. 更稳的做法：把 `expose-mock-code` 的拒绝下沉到无条件的构造器 —— `SmsVerificationService` 已在 `58-71` 有"配置无效即抛"的写法，在那里加 `if (sender.exposesCodeForDevelopment()) throw new IllegalStateException(...)`。
3. `MockSmsSender.java:8-10` 增加 `@Profile("!production")` 或生产期直接不装配，使 `provider=mock` 在生产成为启动失败。
4. 部署检查脚本（`md/audit/cache/defense-round1/check_compose.py` 同款）增加断言：production profile 下 `TAKEOUT_SMS_EXPOSE_MOCK_CODE` 必须为 false 或缺失。

---

# 已尝试但打不动的方向（否定结论）

下面每一条我都实际读了代码/跑了验证，不是"没看"。

| 方向 | 做了什么 | 结论 |
| --- | --- | --- |
| JWT 伪造/算法混淆 | 读 `JwtUtil.java:65-75`、`78-91`、`AuthInterceptor.java:41-49` | 打不动。`verifyWith(key)` 固定 HMAC 密钥，`requireIssuer("simple-takeout")`，解析后再断言 `alg == HS256`（jjwt 0.12 本身拒绝 `alg:none`）；不使用 `kid`，无 JWK 注入面；密钥必须规范 Base64 32 字节且至少 16 个不同字节（`decodeSecret:78-91`），模板密钥在 `SecuritySecretsGuard.java:10-19` 启动即拒。token 只从 `Authorization: Bearer` 读取（`AuthInterceptor.java:41-44`），无 query/cookie 取值点。 |
| token 用途复用 | `JwtUtil.generateToken` 只有 userId/role/jti/pwdAt/iss/exp | 打不动。无 "type=pwd-reset" 之类可被挪用的声明；`pwdAt` 只做"早于则失效"，不能反向延长。 |
| 改密后旧 token 存活（秒级碰撞） | `AuthService.java:232-245` `nextPasswordChangedAt` | 打不动。连续改密强制严格递增（`previous.plusSeconds(1)`），同一秒内的第二次改密不会产生"相等时间戳"漏洞。 |
| 拦截器路径绕过 | 逐个核对 `WebConfig.java:40-56` 与全部 17 个 controller 的 `@RequestMapping` 前缀 | 打不动。所有控制器都在 `/api/**` 下；放行名单 8 条与 `AuthController`/`PaymentNotificationController` 的公开端点一一对应，无多余项（`/v3/api-docs/**` 等已删）；网关只路由 `/api/**` 与 `/uploads/**`（`takeout-gateway/application.yml:23-33`）；宿主 nginx `location /takeout/` 用带尾斜杠的 `proxy_pass` 剥前缀（`nginx-domain.conf:46-49`），`/takeout/../api` 会被 nginx 归一化后落到博客 location。 |
| OPTIONS 预检跳过认证 | `AuthInterceptor.java:37-40` 对 OPTIONS 直接 `return true` | 打不动。Spring MVC 对未显式声明 OPTIONS 的 `@RequestMapping` 会生成内置 options handler，控制器方法体不执行，`@RequestAttribute("userId")` 也不会被解析；无端点声明 `method={POST,OPTIONS}`。 |
| 角色提权（role 0→1/2/3） | 读 `AuthService.java:67-70`、`UserDao` 全部写方法、`AdminService.java:338-376`、`StoreService.java:786-804`、`RiderService.java:35-47` | 打不动。`register` 在**消费验证码之前**就 `role != 0 → 403`；全仓没有任何 `UPDATE users SET role` 的入口（`UserDao.java:146-227` 只有 status/password/profile/payment_password）；`employees` 表不参与 JWT role；骑手自助建档要求 `user.role()==3`；管理端不能动 role=2 的账号（`AdminService.java:283-286`、`UserDao.java:147`）。 |
| JSON 直写 role | 逐个看所有 `@RequestBody` record | 打不动。`RegisterRequest(…,int role)` 是唯一带 role 的入参，走上面那条拒绝；其它 record（ProfileUpdate/EmployeeBody/…）都不落 role 列。 |
| 充值/赠金/凭空加余额 | `AuthService.java:320-322`、`register:83-84`、`31-39`；全仓 grep `addBalance` | 打不动。`recharge` 无条件 403；注册余额写死 `0.0`；构造器对 `recharge-enabled/signup-balance` fail-fast；`addBalance` 只剩 `OrderService.java:791`（退款，要求 `escrow 0→2` 条件更新成功）与 `1061`（商户结算，要求 `releaseEscrow` 成功），两条都在事务内且带幂等条件，用户侧无入口。 |
| 事件消费者加钱 | `DomainEventConsumer.java:191-214` 全量 | 打不动。消费者只写日志 + 推送，没有任何资金/余额写入。 |
| 员工变 role=1 再走商户接口 | `employees` 表与 `AuthInterceptor:51-56` | 打不动。role 只来自 users 列，且拦截器要求 token role == DB role。 |
| 骑手池 PII | `Order.java:170-176` `forRiderPool`、`OrderService.java:920-946` | 打不动。池视图把 `userId` 置 0、`items` 置空、`address` 换成"抢单后可查看收货信息"、`remark` 清空；停用骑手返回空池（`922-924`）；抢单也要过半径判定（`963-965`），不能拿订单 id 硬抢。 |
| 订单/评价/地址 IDOR | `OrderService.java:705-711`、`816-818`、`1102-1105`、`UserCenterService.java:186-194`、`331-355` | 打不动。订单详情要求 `order.userId==requester` 或 `(role==1 且 是店主)`；评价/退款/取消/确认收货逐个校验 owner；地址与银行卡的 DAO 全部带 `user_id` 条件；`orderDetail(long id)` 这个无鉴权重载只被已鉴权的内部路径调用（`512,547,720,768,784,910,969,980,995,1040`），未挂在任何 controller 上暴露。 |
| refresh token 重用/竞态 | `RefreshTokenService.java:58-98`、`TokenBlacklistDao.java:48-71` | 打不动。`SELECT … FOR UPDATE` + `consumeRefreshToken` 条件更新（`reason='rf:'+family AND user_id`），并发只有一个能成功；已用（`ru:`）再次出现即整族吊销；长度 >128 直接拒。refresh/logout 另有 30 次/分钟/IP 限流。 |
| XFF / 多跳伪造换桶 | `ClientIpHeadersFilter.java:24-47`、`nginx-domain.conf:33-38`、`app-upstream.conf:10`、`application.yml:5-10`、`docker-compose.yml:207` | 打不动。宿主 nginx 用 `X-Forwarded-For $remote_addr` **覆盖**并清空 `Forwarded`；网关白名单制 + 从右向左取第一个非信任跳、非法跳回退到 peer、>2048/>32 跳直接放弃、最后**重写**为单值并删 `X-Real-IP`/`Forwarded`；应用侧 Tomcat RemoteIpValve `internal-proxies` 可信代理。直连网关时 peer 不在信任名单 → 取 peer 本身，伪造无效。**残余**（非本轮新发现）：`TAKEOUT_INTERNAL_PROXY_REGEX` 默认信任全部 RFC1918，且 compose 的 `"${TAKEOUT_APP_PORT}:8087"` 未绑 127.0.0.1；只要网关自身不信任该对端，仍不可伪造，但建议按防守方自述收窄。 |
| 注册/找回的验证码预算被变体绕过 | 写 PoC `RegisterPhoneTailBypassPocTest` 实跑 | **打不动，并且反证了 A-01 的独特性**：`AuthService.java:95-97` 的 `phone.matches("1\\d{10}")` 在 Java 里是**全串匹配**，实测 `"13800138000\u200B".matches("1\\d{10}")` == **false**（PoC 输出 `attacker matches = false`），尾随/内嵌变体在注册与找回入口直接被 400；`recoveryUser` 还用 `phone.equals(user.phone())` 二次兜底。**同一族入口只有 `login` 没做这一步**，这就是 A-01 的成因。 |
| 账号枚举（注册/取码阶段） | `AuthController.java:74-87`、`AuthService.java:88-100`（修复后） | 打不动（就取码阶段而言）。register 目的不再查重、不复用"已注册"文案；找回目的把 `recoveryUser` 的异常统一映射成"手机号或邮箱不匹配"（`AuthController.java:79-84`），409/429 才透传。仅登录文案仍可分辨停用账号（见 A-04）。 |
| 空 body / 畸形 JSON 打 500 | `AuthController.java:272-276`、`UserCenterController.java:234-238` | 打不动。`HttpMessageNotReadableException` 被本地 `@ExceptionHandler` 收敛成 400，且注释明确不记录异常文本（避免把密码/卡号打进日志）。 |
| 验证码爆破 / 重放 | `SmsVerificationService.java:25-32,141-158` | 打不动。`CONSUME_SCRIPT` 原子比对，错误 5 次即删码删计数；验证通过即 DEL，不可重放；code key 用 HMAC 摘要而非明文。 |
| 支付密码免密 / 试错换 IP 重置 | `OrderService.java:524-531`、`UserCenterController.java:158-166`、`AuthController.java:195-203` | 打不动（本线复核）。余额支付强制 6 位独立支付密码；三处试错预算改为按账号 `u<userId>` 计数并在**验证前占用**，换 IP 不再重置预算。 |
| Swagger/调试文档暴露 | `WebConfig.java:45-56`（放行项已删）、`application.yml:53-57`（默认 false） | 打不动。网关也不路由 `/v3/api-docs`。 |
| 种子/演示账号复活 | `DataSeeder.java:29-63`、`DataSeeder.java:36-38` | 打不动。`seedEnabled` 默认 false；启用需显式 ≥16 位管理员口令，否则启动抛异常；普通种子账号口令改为每次随机 UUID。 |

## 本轮未执行的动作（限制说明）

- **未做任何线上探测**（本轮按 lead 指令只落盘结论）。上一轮线上状态的可信证据仍是 `防御结果.md` 的部署记录；本报告所有"线上状态"如实标注为未测及原因，不虚构。
- **未连接服务器**（禁止），故 A-05 依赖的 `.env` profile 组合无法证实/证伪。
- **未新增任何测试到仓库**：PoC 用完即从 `server/takeout-app/src/test/java/com/example/takeout/redteam2/` 删除，归档副本在 `md/audit/cache/round2-redteam/auth-red/`；临时 MySQL 实例（127.0.0.1:3311）已停止。
