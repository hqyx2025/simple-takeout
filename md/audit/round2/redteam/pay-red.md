# 支付与资金二次攻击线（pay-red）

- 日期：2026-10-25（Asia/Shanghai）；攻击者：pay-red（支付 / 订单 / 退款 / 结算专项）。
- 目标：找出第一轮修复未生效、修错、或修复本身引入的新问题。防守方自述见 md/audit/defense/防御结果.md（V-01..V-20）。
- 方法：以静态读码为主，所有结论给出 文件:行号。**未改动生产源码与既有测试**；PoC 未落盘运行（原因见“未覆盖”节）。线上只做了 3 次低频只读探测，未注册、未下单、未支付、未发验证码、未占用封禁桶。

## 环境与验证边界

| 项目 | 说明 |
| --- | --- |
| 本地运行时 | 本轮**未启动** Spring Boot / MySQL / Redis，**未运行**任何 Maven 用例；Lead 指定“单回合落盘、不跑全量测试”，故证据全部为源码级，需运行时确认的条目一律标注“未测”。 |
| 线上可达性 | 见下表；未做任何写操作。 |
| 证据强度 | P-01/P-02/P-03/P-05 为纯代码路径推导，可 100% 由行号复核；P-04 为配置+代码联合推断，需沙箱账号才能实测。 |

| 项目 | 请求 | 结果 |
| --- | --- | --- |
| 体验站首页 | GET https://hqyx.website/takeout/ | 200，15107 字节（服务存活） |
| 匿名读 /api/auth/me | GET https://hqyx.website/takeout/api/auth/me | 401（认证拦截生效） |
| 匿名读 /api/orders/1 | GET https://hqyx.website/takeout/api/orders/1 | 401（订单接口不可匿名枚举） |

## 发现总览

| 编号 | 级别 | 标题 | 线上状态 |
| --- | --- | --- | --- |
| P-01 | Medium | 支付密码预算桶与“设置支付密码”共用同一账号级键，且预算在业务校验前占用：未设密码或连错 5 次即把“余额支付”和“设置支付密码”一起锁死 600 秒 | 未测（会占用线上封禁桶） |
| P-02 | Low | 支付密码可被“登录密码”单向改写：设置/邮箱重置都不校验旧 PIN，V-07 宣称的第二因子可被第一因子静默覆盖 | 未测（写操作） |
| P-03 | Low（对账口径） | aggregateMerchantStats 收入列是 pay_amount - delivery_fee，缺 max(0,·)，与 settleMerchant 实际入账下限不一致；V-14 只改了骑手侧 | 未测（禁止下单） |
| P-04 | Medium | 线上仍装配支付宝沙箱且 providerPaymentsEnabled()=true：沙箱买家账号即可把订单推进“已支付”并进入真实结算口径 | 未测（无沙箱账号、禁支付） |
| P-05 | Low | 退款申请接口无限流，“驳回→重新申请”可无限循环把订单钉在 status=6，商户托管款无限期不结算 | 未测（需订单+管理员操作） |

**本轮没有发现 Critical / High。** 资金闭环（扣款 → 托管 → 结算/退款）在修复后依然是本轮最难打的部分，详见末节否定结论；以下 5 条集中在“修复面漏压点”和“清晰可复现的可用性回归”。

---

### P-01 ｜【Medium】支付密码限流桶与“设置支付密码”共用同一账号级键，且预算在业务校验之前占用

- **结论**：防守方把“余额支付”和“设置支付密码”当成同一个限流动作计费（同一 action、同一 identity），于是任何一次“还没设置支付密码”的正常尝试都会吃掉支付尝试额度；5 次即封 600 秒，而封禁同时封住了“设置支付密码”这条唯一解锁路径，用户被锁在自己解不开的环里。
- **证据**
  - server/takeout-app/src/main/java/com/example/takeout/controller/OrderController.java:89-97 —— BALANCE 分支：isBlocked("payment-password", "u"+userId) → recordAttempt(...) → payOrder(...) → **只有成功才** reset。
  - server/takeout-app/src/main/java/com/example/takeout/controller/AuthController.java:195-202 —— 设置支付密码用的是**同一个** action = "payment-password"、同一个 identity = "u"+userId。
  - server/takeout-common/src/main/java/com/example/takeout/security/LoginRateLimiter.java:38 —— payment-password 策略 = 5 次 / 60 秒窗口 / 封禁 600 秒。
  - LoginRateLimiter.java:89-106 —— recordAttempt 先本地再 Redis 原子占用，第 5 次直接抛 429；:161-164 本地窗口同步置 blockedUntil。
  - LoginRateLimiter.java:109-121 —— reset 同时删除计数键与封禁键。
  - server/takeout-app/src/main/java/com/example/takeout/service/OrderService.java:524-531 —— 校验顺序：先“未设置支付密码就 403”，再“密码错误就 403”，**两次都在预算已被消费之后**。
- **攻击链**（纯代码可复现；未实跑，避免污染线上桶）
  1. 新注册用户（防御方案已强制必须先设支付密码）点“余额支付”，请求体不填密码；
  2. OrderController.java:93 已消费 1 次预算 → OrderService.java:525-526 抛 403“请先在账号安全中设置支付密码”；
  3. 重复 5 次（连点或换订单都计同一个 u<id> 键）→ LoginRateLimiter.java:161-164 触发封禁 600 秒；
  4. 用户去设置支付密码：AuthController.java:197 isBlocked 命中 → 429“密码尝试过于频繁”；
  5. 结果：10 分钟内既不能支付、也不能设置/重置支付密码，钱包入口被自己的失败计数封死。
  - 变体：已设密码者连错 5 次，同样在 10 分钟内无法通过站内路径自救（只能走邮箱验证码重置）。
- **线上状态**：未测。原因：需要真实账号发起余额支付，属写操作，且会占用线上共享封禁桶。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md:28 声明“支付和银行卡密码验证按账号限流，避免换 IP 重置尝试预算”，:33 声明“登录、支付密码设置、银行卡揭示在**验证密码前**占用对应预算”。两句本身没错，但实现把“设置”和“支付”编成同一个桶，又没给“尚未设置支付密码”这条必经引导路径留出口——**防守方只测了“错误密码被限流”，没测“合法的未设置状态也被限流”**。
- **修复建议**
  - AuthController.java:195 改用独立 action（如 "payment-password-set"），并在 LoginRateLimiter.java:27-45 补策略；
  - OrderController.java:89-93 先做只读判断“是否已设置支付密码”，未设置则直接引导设置、**不占用** payment-password 预算；或让 OrderService.java:525 抛专用错误码，控制器对该码 reset；
  - LoginRateLimiter 增加“仅对认证失败计数”的语义，不把“前置条件不满足”算成一次猜测。

---

### P-02 ｜【Low】支付密码只能被“登录密码”改写：换 PIN 不需要旧 PIN，第二因子可被第一因子静默覆盖

- **结论**：V-07 把支付密码定位成独立第二因子，但设置/重置路径只校验登录密码，等于任何拿到 token + 登录密码的人可以直接换掉受害者 PIN 再花掉余额——门槛从“无”抬到了“同等于登录密码”，并没有真的多一道因子。
- **证据**
  - server/takeout-app/src/main/java/com/example/takeout/service/AuthService.java:159-170 —— setPaymentPassword 只比 PasswordUtil.matches(loginPassword)，**不校验既有 paymentPasswordHash**，直接覆盖。
  - AuthService.java:184-192 —— resetPaymentPasswordByEmail 也只吃邮箱验证码，同样不需要旧 PIN。
  - 对照 AuthService.java:143-157 —— 改登录密码反而要求旧密码，且改完踢掉所有会话。
  - server/takeout-app/src/main/java/com/example/takeout/controller/AuthController.java:191-204 —— 登录态即可调用，无二次验证、无冷却期、无告警。
- **攻击链**：窃取 token（恶意调试包 / 设备共用 / 网页 XSS）→ 配合登录密码（撞库、复用、钓鱼）→ POST /api/auth/payment-password 写新 PIN → POST /api/orders/{id}/pay?channel=BALANCE 刷余额。纯 token 场景确实被 V-07 堵住，该链条只是多要求一个登录密码，而真实泄露事件里 token 与登录密码常同源（同设备、同配置、同钓鱼页面）。
- **线上状态**：未测（写操作，且需受害者凭据）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md:28 只主张“服务层校验独立的 6 位支付密码”，把“能校验”当成“能保护”，没有处理**凭据可被改写**这个前置；同一份报告里防守方自己给登录密码实现了“改密需旧密码 + 改密即失效旧 token”，说明知道这套模式，只是没套用到支付密码。
- **修复建议**：AuthService.java:159-170 在 paymentPasswordHash 非空（=非首次设置）时强制校验旧支付密码；改绑后 24 小时内禁止余额支付并给用户发告警；resetPaymentPasswordByEmail 同样要求旧 PIN 或加 24 小时冷静期。

---

### P-03 ｜【Low】aggregateMerchantStats 收入列用 pay_amount - delivery_fee，缺 max(0,·)，与真实入账下限不一致；V-14 只改了骑手侧

- **结论**：V-14 只把“骑手统计收入”改成 min(deliveryFee, payAmount)，商户统计的收入口径仍是无下限的 pay_amount - delivery_fee，而真正给商户加余额的 settleMerchant 用的是 max(0, pay_amount - delivery_fee)。极端优惠单会出现“钱包入账 0 / 统计页收入负数”，两侧口径互相打脸。
- **证据**
  - server/takeout-common/src/main/java/com/example/takeout/dao/OrderDao.java:338-344 —— appendAmount 的表达式固定为 `pay_amount - delivery_fee`，**没有 GREATEST(..., 0)**。
  - OrderDao.java:291-324 —— today_income / week_income / month_income / total_income / day_income_0..6 全部走 appendAmount，口径一次性全中。
  - server/takeout-app/src/main/java/com/example/takeout/service/OrderService.java:1043-1045 —— merchantSettlementAmount = max(0, round2(payAmount - deliveryFee))，真实入账有下限。
  - OrderService.java:994 —— 骑手侧已改成 Math.min(order.deliveryFee(), order.payAmount())（即 V-14 的修复点）。
  - server/takeout-common/src/main/java/com/example/takeout/dao/AdminStatsDao.java:36-42 —— 平台 GMV 用 SUM(pay_amount)，第三种口径。
- **攻击链**（不需要攻击者，是口径缺陷，商户/用户可无意触发）
  1. 商户自配折扣 / 新客立减，用户再叠白名单券，把 payAmount 压到小于 deliveryFee；
  2. 下单 → 支付 → 送达 → 确认收货：settleMerchant 给商户加 0 元（OrderService.java:1043-1045）；
  3. 商户统计页 today_income / total_income 变成负数（OrderDao.java:338-344），周/月/累计同时变负；
  4. 商户拿统计页对账 → 与钱包流水不一致；平台侧 AdminStatsDao.java:36 的 GMV 又是第三个数。
  - 边界：普通用户无法单独把 payAmount 压到低于配送费，需要商户自配活动（沿用第一轮 F7 结论），因此不构成白拿，只是账不可对。
- **线上状态**：未测。原因：需要真实优惠单，禁止下单；口径缺陷为纯 SQL 推导，可由行号直接复核。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md:35 的处理是“骑手统计收入按 min(deliveryFee, payAmount) 记账”，验证只写“极端优惠订单收入上限回归通过”——它盯的是**上限**，没回头看商户侧与平台侧的**下限与一致性**。V-14 的修复点是一个函数，不是一套口径。
- **修复建议**：OrderDao.java:338-344 的 appendAmount 改为 `GREATEST(pay_amount - delivery_fee, 0)`；AdminStatsDao.java:36-42 的 GMV 保留 pay_amount，但在接口/页面注明“GMV ≠ 商户结算额”；在既有统计测试里补一条 payAmount < deliveryFee 的断言。

---

### P-04 ｜【Medium】线上仍装配支付宝沙箱渠道且 providerPaymentsEnabled()=true：沙箱钱能把订单推成“已支付”并进入真实结算口径

- **结论**：体验站保留 develop + 支付宝沙箱，而 providerPaymentsEnabled() 只看“非 mock 且（real 或 sandbox）”——sandbox 即放行。任何持有支付宝沙箱买家账号的人都能让自己的订单进入 status=1（已支付），后续 complete / autoConfirm 会用“沙箱钱”按真实比例给商户 addBalance。当前线上启用商户为 0，暂时没有收款方；一旦平台开通第一个商户，这条链立刻变成“沙箱假币 → 真实可消费余额”。
- **证据**
  - server/takeout-app/src/main/java/com/example/takeout/service/thirdparty/ExternalPaymentService.java:296-298 —— providerPaymentsEnabled() = !mock && (real || sandbox)，sandbox=true 即整体放行。
  - ExternalPaymentService.java:282-290 —— requireGateway(ALIPAY) 只校验 gatewayUrl 等于沙箱网关、密钥非空、notifyUrl 是 HTTPS；**没有“沙箱不得进入资金闭环”的判断**。
  - ExternalPaymentService.java:198-207 —— 验签通过后 markPaid → 订单进 1，写 PAY/SUCCESS 流水，发 ORDER_PAID 事件。
  - server/takeout-app/src/main/java/com/example/takeout/service/OrderService.java:1057-1064 —— settleMerchant 无条件给商户 addBalance，**不看该单是沙箱还是真实收款**。
  - md/audit/defense/防御结果.md:146 —— “保留原有 develop 体验环境与支付宝沙箱配置”；:154 —— 当前启用商户/骑手为 0。
  - md/audit/round1/findings-payment.md:143 —— 第一轮记录的 .env 即 REAL=false / MOCK=false / SANDBOX=true。
- **攻击链**：注册普通用户（role=0 允许）→ 下单 → POST /api/orders/{id}/pay?channel=ALIPAY&mode=QR 拿沙箱收银台 → 用沙箱买家账号付款 → notify 验签通过 → 订单已支付 → 完成/自动确认 → settleMerchant 把“沙箱钱”按比例打进商户余额；商户余额可直接下单消费，等同真实购买力。资金总量当前受“启用商户为 0”限制。
- **线上状态**：未测。原因：需要沙箱买家账号，且下单/支付是写操作，违反本轮只读约束。**判断依据是配置声明 + 代码闸门，不是实测。**
- **为什么防守方没堵住**：防守方把 MOCK 禁用当成“支付面已收口”（ExternalPaymentService.java:279-281 对 WECHAT 也用了“no configuration override”的硬禁思路），却对 sandbox 单开了放行；同时在防御结果.md:146 明确“保留沙箱配置”，没有任何“沙箱订单不得结算为真实余额”的处理。等于把“能造出已支付订单”的钥匙留在了公网。
- **修复建议**：① 体验环境改用明确的演示渠道（MOCK/DEMO）并在前端标注“演示支付、不产生真实资金”，同时把 providerPaymentsEnabled 中对 sandbox 的放行限定为“只可验签演示、不得 markPaid”；② 或在 OrderService.java:1057-1064 的 settleMerchant 前判定支付渠道是否 sandbox（PaymentTransaction 加 sandbox 标记），沙箱单直接 escrow=1 且不入余额；③ 开通真实商户前必须先把沙箱渠道从对外环境的可选渠道中摘掉。

---

### P-05 ｜【Low】退款申请无频率限制，“驳回→重新申请”可无限循环把订单钉在 status=6

- **结论**：applyRefund 是本轮唯一既没有频率限制、又能改变资金状态机位置的用户入口；配合“驳回后订单回到 4、escrow 仍为 0”的设计，用户可把同一单在 4↔6 之间无限往返，使该单永远不满足自动确认/结算条件，商户这笔托管款被无限期挂住。
- **证据**
  - server/takeout-app/src/main/java/com/example/takeout/controller/OrderController.java:126-132 —— POST /api/orders/{id}/refund 直接调 applyRefund，**没有任何 LoginRateLimiter**（对比同文件 :46-49 下单有 "order" 限流）。
  - server/takeout-app/src/main/java/com/example/takeout/service/OrderService.java:819-835 —— 申请条件只有 status=4、escrow=0、未评价、无 PENDING；驳回后四条重新全部满足。
  - server/takeout-app/src/main/java/com/example/takeout/service/AdminService.java:482-490 —— rejectRefund 把 6 推回 4，**不消耗 escrow、无次数上限、不记用户信用**。
  - server/takeout-common/src/main/java/com/example/takeout/dao/OrderDao.java:268-272 —— 自动确认只扫 status=4 AND escrow=0，status=6 的单永远不进队列。
  - OrderDao.java:205-207 —— markRefunding 是 4→6 条件更新，天然允许“再来一次”。
- **攻击链**：用户申请退款 → 商家/平台驳回 → 用户立即再申请 → 订单回到 6 → 循环。每轮只需一次用户点击 + 一次管理员操作；订单期间既不结算也不关单，escrow=0 的商户款被长期挂起，退款记录行按轮次线性增长，对账噪声同步累积。
- **线上状态**：未测（需要真实订单与管理员操作）。
- **为什么防守方没堵住**：md/audit/defense/防御结果.md 全篇没有出现 applyRefund 的频率或次数上限；V-08 的处理是“保留 status=6、escrow=2 的合法退款终态”（:29），把“退款中”合法化的同时也就默认它可以被用户反复触发——**防守方只审了“同意”分支的幂等，没审“拒绝”分支的可重入性**。
- **修复建议**：OrderController.java:126-132 加 LoginRateLimiter("order-refund", "u"+userId)（如 3 次/小时）；OrderService.java:808-841 增加“同一订单累计申请次数”上限（如 3 次，超限转人工且禁止再申请）；第二次申请起要求补充凭证或管理员解冻，避免把结算当人质。

---

## 已尝试但打不动的方向（否定结论）

| 编号 | 尝试 | 结论与验证方式 |
| --- | --- | --- |
| N-1 | 走无密码的 payOrder 重载做余额支付 | **打不动**。OrderService.java:479-495 三个重载最终都把 paymentPassword 传成 null，落到 :528-531 一律 403；生产调用点只有 OrderController.java:87（第三方渠道，不扣余额）与 :94（带密码），grep `payOrder(` 无第三个生产调用点。 |
| N-2 | 同一订单重复退款（取消 + 审批 / 两次审批） | **打不动**。escrow 0→2 是条件更新（OrderDao.java:259-261），失败即抛异常回滚；审批侧 requirePending 用 findByIdForUpdate + PENDING 判定（AdminService.java:492-499）；取消分支要求 status≤3（OrderService.java:753），退款分支要求 status=4（:819），状态互斥。既有测试 OrderServiceFlowTest.java:619-625 用 thenReturn(true,false) 覆盖第二次退款失败。 |
| N-3 | 重复结算 / 退款后再结算 | **打不动**。releaseEscrow 要求 status=4 AND escrow=0（OrderDao.java:264-266）；confirmOrder 与 autoConfirmOrder 抢同一条件（OrderService.java:1036-1050），后者额外复查 status==4 && escrowStatus==0。审批退款把 escrow 置 2 后这条路径永远拿不到行。 |
| N-4 | 超时取消与支付回调竞态造成双份记账 | **未发现**。cancelPending 是 0→5 条件更新（OrderDao.java:248-252）；payWithBalance 先 findByIdForUpdate 锁行（OrderService.java:517-518）；applyVerifiedNotice 二次锁行复查（ExternalPaymentService.java:176-200）。未实跑并发（未启动 DB）。 |
| N-5 | 伪造支付宝/微信回调白嫖 | **未发现**。回调强制验签 + channel + 金额（分）+ 币种 + 订单四重比对（ExternalPaymentService.java:154-188）；WECHAT 被 requireGateway 硬禁（:277-281）。notify 端点确实无鉴权（PaymentNotificationController.java:33-71），但未找到不验签就让本地订单变已支付的路径。未实测（无沙箱私钥、禁支付）。 |
| N-6 | 6 位支付密码在线爆破 | **打不动**。PBKDF2-HMAC-SHA256 210k 轮（PaymentPasswordUtil.java:12）+ 账号级 5 次/60 秒即封 600 秒（LoginRateLimiter.java:38），10^6 空间约 138 天连续尝试；密码错误时事务整体回滚，不产生可观察的订单状态变化。附带说明：这是“成本可接受但仍无绝对锁定”的边界，见 P-01。 |
| N-7 | 偷 token → 改绑邮箱 → 邮件重置支付密码 → 刷余额 | **打不动**。改手机/邮箱要求当前登录密码（AuthService.java:287-291），改完 updatePassword 递增 passwordChangedAt（:297-299），旧 token 立即失效；验证码要求 phone + email 双匹配并绑定 userId + 用途（AuthService.java:194-215）。 |
| N-8 | 退款终态 escrow=2 与自动结算/统计冲突 | **未发现**。listAutoConfirmCandidates 只取 status=4 AND escrow=0（OrderDao.java:268-272），status=6 / escrow=2 不进队列；AdminStatsDao.java:36-42 的 GMV / 结算额 / 待结算额按 status+escrow 组合排除退款单（唯一冲突点就是 P-03 的负数口径）。 |
| N-9 | 禁用渠道回调刷 500 / 探测渠道是否装配 | **第一轮 F6 已修好**。PaymentNotificationController.java:43-53、62-70 把 BizException 503 映射 503、其余 400，只有真正运行时异常才 500 并 log.error——防守方这条属实。 |
| N-10 | V-15 查单限流是否“限流失败仍调下游” | **接线正确**。OrderController.java:104-112 先 isBlocked/recordAttempt，超限直接抛 429，**不调用** refreshPaymentStatus。仅静态确认，未跑控制器测试。 |
| N-11 | 优惠券并发 / 越权用别人的券 / 秒杀超卖 / stock hold 回滚 | **本轮未验证**（未写新 JUnit、未起 DB）。条件更新仍在：券 0→1 条件核销（OrderService.java:431-433）、库存 stock>=? 扣减（:436-445）、秒杀 deductQuota + joinOnce 一人一单（:457-461）。沿用第一轮 N5 判据，**标注未测**。 |
| N-12 | 员工删除的 storeId 约束是否也覆盖员工增/改/查（V-09） | **本轮未测**。预算全投到支付/退款/结算链，没有读 EmployeeDao / StoreService 的员工接口实现；建议 authz 线复核，不要当成已验证。 |

## 未覆盖 / 需其他线接手

1. **真实运行时验证**：本轮零 JUnit、零服务启动。P-01 与 P-05 都可用 3 行 Mockito 用例钉死（构造未设 paymentPassword 的 User + verify recordAttempt 已被调用；构造 status=4 订单 + 连调两次 applyRefund），建议下一轮补 `OrderServicePaymentPasswordBudgetTest` 与 `RefundReapplyBoundaryTest`。
2. **支付宝沙箱真实联调**：P-04 只能靠代码+配置推断，需要一次性沙箱联调（体验环境、可回滚）才能钉死“沙箱单是否真的进 settleMerchant”。
3. **商户结算与退款竞态**：settleMerchant 与 approveRefund 都对 orders 行做 findByIdForUpdate，静态看是同一把锁，但没有真实 MySQL 并发用例，不宣称安全。
4. **客户端是否所有余额支付入口都传 paymentPassword**：本轮只审后端；若有页面漏传，会被 OrderService.java:528-531 一律 403 打回（表现为功能损坏而非漏洞），属回归风险，交前端线确认。
