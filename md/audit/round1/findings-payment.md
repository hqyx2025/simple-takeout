# 支付 / 订单 / 资金 / 优惠券 / 库存 红队审计（findings-payment）

审计范围：server/takeout-app（controller、service）、server/takeout-common（dao、security、model）、schema.sql、application*.yml、docker-compose*.yml、.env（仅读取键名与布尔值，未复制密钥值）。
审计人：payment-red　日期：2026-10-25

---

## 1. 概述

### 1.1 环境事实（已自行确认）

| 项 | 结果 |
| --- | --- |
| 8087 / 3310 / 6387 监听 | **均未监听**（Get-NetTCPConnection -State Listen 只见 3306，为本机其它 MySQL 实例） |
| Docker | docker version 失败：failed to connect to the docker API at npipe://...dockerDesktopLinuxEngine，无法起 compose |
| Java / Maven | JDK 25.0.2、Maven 3.9.13 可用 |
| Redis | 6387 无监听；LoginRateLimiter / SmsVerificationService 依赖 Redis |

因此本轮**未做真实 HTTP 验证**（起服务成本不可控，且启动会写入项目 takeout 库）。全部结论为**静态审计**，需要运行时确认的条目显式标注「仅静态推断」。项目源码与数据未被修改，未 commit/push，未部署。

### 1.2 总体判断

资金主链路（下单金额计算 → 余额扣款 → 第三方预支付 → 验签回调 → 托管 → 结算/退款）**工程质量明显高于一般教学项目**：金额一律服务端计算；回调强制验签且校验商户身份/金额/订单号/币种/状态；全部资金状态迁移走条件更新 + 行锁；退款用稳定退款单号幂等。本轮**未能构造出可白嫖、可重复退款、可伪造回调的攻击链**（§3 否定结论与发现同等重要）。

真实问题集中在**“演示档对外部署”的配置面**与**非资金主链路的授权/状态收口**：

1. develop profile 被当作线上体验环境时，**任意登录用户可无限加余额**（演示充值 + 注册体验金）——本仓库唯一一条“凭空造钱”的真实路径；
2. **骑手自助注册零审核**，可把任意“已出餐”订单标记为已送达并触发托管款结算给商户，真实资金流向被非受信主体驱动；
3. **余额支付不校验支付密码**（支付密码只保护“查看银行卡号”）；
4. 退款审批通过后**订单状态永远停在 6（退款中）**，状态机未收口。

发现统计：High 2 / Medium 3 / Low 3；无 Critical。

---

## 2. 发现列表

### F1｜develop 档对外部署 = 任意用户无限铸币（演示充值 + 注册体验金）

- **级别**：High（资金；前置条件：SPRING_PROFILES_ACTIVE=develop 或 TAKEOUT_DEMO_RECHARGE_ENABLED=true）
- **证据**
  - server/takeout-app/src/main/java/com/example/takeout/controller/AuthController.java:201-205 —— POST /api/auth/recharge，仅需登录态，无支付密码、无频率限制、无支付流水
  - server/takeout-app/src/main/java/com/example/takeout/service/AuthService.java:326-338 —— recharge() 仅判 demoRechargeEnabled，随后 userDao.addBalance(userId, round2(amount))；金额只校验 0.01~10000，**可重复调用**
  - server/takeout-app/src/main/resources/application.yml:55-57 —— recharge-enabled 默认 false、signup-balance 默认 20
  - server/takeout-app/src/main/resources/application-develop.yml:4-6 —— develop 下 recharge-enabled 默认 **true**
  - .env:21 SPRING_PROFILES_ACTIVE=develop；.env:22 TAKEOUT_DEMO_RECHARGE_ENABLED=true（仅布尔值，不含密钥）
  - docker-compose.demo.yml:35 默认 profile=develop；:39 默认 recharge=true
  - AuthService.java:84-86 —— register() 对 role==0 赠送 Math.max(0.0, signupBalance)
  - 守卫缺口：config/ProductionHuaweiGuard.java:18-21 只在 @Profile(production) 下拒绝 demoRechargeEnabled；application-production.yml:19 把 signup-balance 置 0 —— **只有 production profile 安全，develop 档完全敞开**
- **攻击链**：注册/登录普通用户 → 反复 POST /api/auth/recharge {amount:10000}（余额 +10000/次、无流水无审计无总额上限）→ 余额下真实订单 → BALANCE 支付 → confirmOrder/autoConfirmOrder 结算给商户 → 商户余额成为可消费资产；叠加批量注册（每号 20 元体验金）。
- **PoC（仅静态推断，服务未运行）**
```
POST /api/auth/recharge
Authorization: Bearer <user token>
Content-Type: application/json

{ "amount": 10000 }
→ 200 { code:200, data:{ balance: 10020.0 } }
```
- **修复**：① 演示充值/体验金按 profile 反向装配（production 下 bean 不存在，而非仅标志位 false）；② 演示充值写 payment_records（channel=DEMO）+ 单账号日上限 + LoginRateLimiter 动作 recharge；③ 启动横幅升级为显式 WARN/醒目提示（现有 DemoModeWarning:17-20 只是一行 warn）；④ 线上体验环境改 production profile + signup-balance=0。

### F2｜骑手自助注册零审核，可把任意“已出餐”订单标记送达并触发托管款结算

- **级别**：High（履约完整性 / 结算被非受信主体驱动）
- **证据**
  - service/AuthService.java:76-85 —— 注册允许 role=3（骑手），无审批/邀请码/后台确认
  - service/RiderService.java:36-47 —— 首次进骑手端**自动建档**，无资质校验
  - service/RiderService.java:72-85 —— updateLocation 接受任意合法经纬度，可把接单位置设到任意门店
  - service/OrderService.java:908-958 —— riderPool / riderGrab 只按“半径内 + status=2 + ready_time 非空”，半径上限 50km
  - service/OrderService.java:960-984 —— riderPickup(2→3)、riderDeliver(3→4) 只校验 rider_id=自己，**不校验实物交付**；送达同时 riderDao.addCompleted(riderId, deliveryFee)；requireActiveRider(:936-943) 只查 riders.status
  - service/OrderService.java:1035-1052 + job/OrderAutoConfirmJob —— 24h 后 autoConfirmOrder 释放托管并把款打给商户（userDao.addBalance）
- **攻击链**：自助注册骑手 → 自动建档 → updateLocation 设到目标门店 → online=1 → 轮询 /api/rider/pool 抢单 → 商户出餐后立即 pickup+deliver → 订单变 4（真实用户没收到餐）→ 24h 自动确认结算给商户；用户只能走退款申请（需管理员审批）。
- **影响边界（不夸大）**：骑手 total_income 只是 riders 表计数器（dao/RiderDao.java:73-76），**不直接进 users.balance**，故“骑手刷配送费提现”不成立；真实损失是履约欺诈 + 商户提前结算 + 用户钱货两空。
- **修复**：① 骑手注册改“待审 riders.status=0 + 后台审核/邀请码”，riderGrab 增加 verified 校验；② 送达绑定取餐码/用户确认码或地理围栏打卡；③ 新骑手首 N 单人工抽检 + 送达异常告警；④ updateLocation 加频率与位移速度校验（防瞬移抢全城单）。

### F3｜余额支付不校验支付密码，6 位支付密码只保护“查看银行卡号”

- **级别**：Medium（授权/资产保护错配）
- **证据**
  - service/OrderService.java:487-497、511-536 —— payOrder(...,BALANCE) 全链路只有 order.userId()==userId + balance>=payAmount + 条件扣款，**无任何密码/二次确认入参**
  - controller/OrderController.java:79-84 —— POST /api/orders/{id}/pay?channel=BALANCE 参数只有 channel/mode
  - 支付密码唯一使用点：service/UserCenterService.java:136-156 revealBankCard（PaymentPasswordUtil.matches）→ 看卡号要密码、花钱不要密码
  - 设施其实完整：AuthService.java:166-177、AuthController.java:167-187（payment-password 限流动作）、LoginRateLimiter.java:44-45
- **攻击链**：持有 token 者（设备共用/token 泄漏/恶意调试包）可直接把受害者余额刷成订单并结算到攻击者控制的商户（配合 F1 的商户自助注册），受害者无密码环节可阻断。
- **修复**：① payOrder(BALANCE) 增加 paymentPassword 服务端校验，未设置则先引导设置；失败计入 LoginRateLimiter(payment-password, userId+ip)（现成 5/60s 封 600s）；② 大额/新设备/异地强制二次验证；③ 若产品决定免密，删除“支付密码”的安全承诺文案，避免安全剧场。

### F4｜退款审批通过后订单状态永不收口（escrow=2 但 status 恒为 6）

- **级别**：Medium（状态机/对账一致性）
- **证据**
  - service/AdminService.java:458-478 approveRefund：updateStatus(REFUNDED) → refundEscrow(0→2) → 回滚库存 → refundOrderPayment，**全程没有 6→5 的状态更新**
  - 对照 OrderDao.java:199-202 提供 updateStatusOnlyFrom，AdminService.java:480-490 rejectRefund 用了（6→4），同意分支漏了
  - OrderDao.java:205-207 markRefunding 只写 4→6
  - OrderDao.java:283-329 aggregateMerchantStats 以 status<>0 统计订单数 → 退款单长期计入订单数、不计收入
- **影响**：已退款订单在用户端/商户端/管理端永久显示“退款中”，口径长期不一致；因 applyRefund 复查 escrow!=0（OrderService.java:810-812）、cancelOrder 复查 status>3，**不构成重复退款**，仅终态缺失。
- **修复**：approveRefund 内补 orderDao.updateStatusOnlyFrom(order.id(), 6, 5) 并断言返回 true（失败即回滚，与 escrow 条件更新同事务）+ 补“6→5 唯一终态”集成断言。

### F5｜限流键取自 X-Forwarded-For 首段：直连 app 端口即可绕过全部限流

- **级别**：Medium（取决于网络可达性；网关拓扑下不可利用，见结论）
- **证据**
  - takeout-common/.../security/LoginRateLimiter.java:117-135 clientIp()：先取 XFF 第一段，其次 X-Real-IP，最后 getRemoteAddr()，**不校验来源可信**
  - 依赖它的动作：LoginRateLimiter.java:34-48（login 10/60、register 5/h、email-code、password-forgot、payment-password-forgot、bank-card-reveal 5/60、payment-password 5/60、order 10/60）
  - 网关已正确覆写：server/takeout-gateway/src/main/resources/application.yml:33-50 —— trusted-proxies 为全匹配、for-enabled: true、**for-append: false**，注释明确指出追加语义会被 split(",")[0] 绕过；docker-compose.yml:64-138 中 app **不发布端口**，仅 gateway 映射 8087（:199-201）
- **确认/否定结论**：经网关访问 **不可绕**（XFF 被覆写为网关所见地址）——Lead 线索 4 在此拓扑下不成立；**直连 app:8087**（mvn spring-boot:run、把 TAKEOUT_APP_PORT 暴露公网、绕过网关的内网访问）**成立**：每请求换一个 X-Forwarded-For 即可重置限流桶，登录爆破 / bank-card-reveal 支付密码爆破（10^6 空间、6 位纯数字）/ 下单刷单全部无门槛。反向风险：若 gateway 前再加一层代理，for-append=false 会让所有用户共享同一限流键，一次误封 = 全站登录不可用。
- **修复**：① clientIp 仅在直连来源属于可信代理集合时才信任 XFF，且取最右侧（最近一跳）而非 [0]；② app 侧 server.forward-headers-strategy=NATIVE + 代理白名单，或 app 只监听 127.0.0.1/容器网络；③ bank-card-reveal / payment-password 增加按 userId 的失败计数与指数退避，IP 维度只作辅助。

### F6｜禁用渠道的非法回调返回 500 而非 4xx（可探测 + 日志噪声）

- **级别**：Low
- **证据**
  - controller/PaymentNotificationController.java:33-51 —— 只把 SecurityException 映射 400，其余 RuntimeException 映射 500
  - service/thirdparty/ExternalPaymentService.java:277-281 —— requireGateway(WECHAT) 无条件抛 BizException(503)；startPayment/acceptNotification(:145-152) 都会先走到它
- **影响**：匿名 POST /api/payment/wechat/notify 必得 500 并写一条 log.error（:46-50）→ 可探测微信渠道是否装配、刷错误日志；无验签绕过（渠道硬禁用）。
- **修复**：渠道未启用时返回 400/404 且只 log.debug；BizException 与 SecurityException 收敛为统一的“回调拒绝”异常类型。

### F7｜结算口径：payAmount < deliveryFee 时平台净支出（极端优惠叠加）

- **级别**：Low（需商户自行配置多活动叠加）
- **证据**
  - service/OrderService.java:1031-1033 —— merchantSettlementAmount = max(0, round2(payAmount - deliveryFee))
  - service/OrderService.java:982 —— 骑手侧记 riderDao.addCompleted(riderId, order.deliveryFee()) 全额
  - service/OrderService.java:385-425 —— 折扣/新客立减/券可叠加，唯一约束是 payAmount>=0（:416-420）与“用券后不得为 0”（:421-425）
- **说明**：正常 payAmount = 货款+配送-优惠 ≥ 配送费，商家结算+配送费=payAmount 自洽；当“优惠额 > 货款”时商家得 0 而配送费仍按原值记账 → 平台补贴差额。单笔金额小、需商户自配活动、骑手收入不可提现，故 Low。
- **修复**：按实收分摊：deliveryIncome = min(deliveryFee, payAmount)，差额进平台账，并与 payment_records 对账。

### F8｜支付查单接口无频率限制（外部 API 成本放大）

- **级别**：Low
- **证据**：service/OrderService.java:701-709 refreshPaymentStatus → ExternalPaymentService.java:90-102 → gateway.query()；controller/OrderController.java:86-90 无 LoginRateLimiter（对比 POST /api/orders 有限流 :44-47）
- **影响**：登录用户高频调用即可按次消耗支付宝查单配额/触发风控；无资金损失。
- **修复**：payment-query 限流（如 6/min/user）+ 2s 结果缓存。

---

## 3. 已核实“未发现可利用”的项（否定结论）

### N1｜伪造支付宝回调白嫖 —— 未发现可利用
- 验签：service/thirdparty/AlipayGateway.java:99-120 rsaCheckV1(parameters, publicKey, UTF-8, RSA2)，失败即 SecurityException；
- 商户身份：:105-108 校验 app_id 与 seller_id 与配置一致；
- 金额/订单号/币种/状态：ExternalPaymentService.java:154-165 要求 outTradeNo 存在、channel 一致、amountFen 精确等于 payment.amount() 且等于 order.payAmount()（:185-188）、currency==CNY、paid==true；
- 状态机：:176-195 先锁订单行，重复回调按 providerTransactionId 判 DUPLICATE；markPaid（OrderDao.java:225-230）与 markSuccess（PaymentTransactionDao.java:86-90）均为条件更新；
- 总闸：providerPaymentsEnabled()（:296-298）= !mock && (real||sandbox)，默认全 false → acceptNotification 直接 SecurityException（:146-148）；.env:9-11 也是 REAL=false / MOCK=false / SANDBOX=true，即**当前配置下回调端点完全关闭**；
- 结论：不存在不验签、客户端声明成功、金额不校验的路径；refreshPayment 也只接受网关验签后的 QueryResult（:90-102）。

### N2｜微信回调伪造 —— 不可能触发（渠道硬禁用）
ExternalPaymentService.requireGateway 对 WECHAT **无条件**抛 503（:277-281），WechatPayGateway bean 存在但不可达，rawBody + 4 个签名头路径因此不可利用（副作用见 F6）。

### N3｜0 元购 / 负数金额 / 客户端定价 —— 未发现可利用
- 金额全在服务端算：OrderService.java:256-425（单价取库、多规格取 spec.price、秒杀取 seckill.price），请求体里的 price 被忽略并重写（:317-318）；
- quantity<=0 拒绝（:263-266、:290-292）；payAmount<0 拒绝（:416-420）；用券后实付为 0 拒绝（:421-425）；
- 未用券但活动折扣把实付压到 0：只能由商户自配活动造成（用户不能创建活动，StoreService.normalizeMarketingActivity:125-171 仅 requireOwned），且 0 元单仍须过支付状态机；
- 优惠券门槛/面额走服务端白名单（UserCenterService.java:221-278 COUPON_CAMPAIGNS），客户端提交的 threshold/amount 不在白名单即拒绝 → “自定义大额券”不成立；
- 起送价只按本店菜品金额计（OrderService.java:589-620），跨店凑单不生效。

### N4｜重复退款 / 退款后仍收货 / 结算重复 —— 未发现可利用
- 申请退款：4→6 且要求 escrow=0（OrderDao.markRefunding:205-207），与“确认收货”争同一条件；
- 审批同意：requirePending 用 findByIdForUpdate + status=PENDING（AdminService.java:492-499），再条件更新（RefundDao.java:85-89）；
- 资金：refundEscrow 条件 0→2（OrderDao.java:259-261），失败即抛 → 同单只能退一次；cancelOrder 走同一把锁（refundEscrow + updateStatusFrom 双条件）；
- 结算：releaseEscrow 条件 status=4 AND escrow_status=0（:263-266）；confirmOrder（OrderService.java:1015-1029）与 autoConfirmOrder（:1035-1043）竞态只有一方成功；
- 外部渠道退款：refundOriginalPayment 用稳定退款单号 R+outTradeNo（ExternalPaymentService.java:234-242、332-334），Alipay out_request_no 幂等，且校验返回 refund_fee 精确相等（AlipayGateway.java:164-182）；
- 越权退款：applyRefund 校验 order.userId()==userId（OrderService.java:803-806）；管理员路径均 role==2（AdminController.java:300-311）。

### N5｜并发下单/支付/取消导致余额凭空增加 —— 未发现可利用
- 扣款原子条件更新 balance>=amount（UserDao.deductBalance:193-196），退款/结算库内自增 ROUND(balance+?,2)（:184-186）；
- 下单先按 goodsId 升序 FOR UPDATE 锁商品（GoodsDao.lockStockRows:207-211），库存 stock>=? 条件更新（:250-253），券 status 0→1（CouponDao.markUsed:52-54），秒杀 sold+?<=quota + INSERT IGNORE 一人一单（SeckillDao.deductQuota:154-159、joinOnce:170-173）；
- 下单幂等：Redis SETNX + order_create_requests 唯一键（OrderService.java:186-229、OrderDao.reserveCreateRequest:54-56）；
- 单订单单活跃预支付由 payment_transactions.uk_payment_transactions_active_order 保证（schema.sql:219）。

### N6｜SQL 注入（$ 号拼接）—— 未发现注入点
- 全仓库**没有 Mapper XML**（只有 pom/docker/idea 下的 xml），DAO 全部 JdbcTemplate 占位符；
- 动态 SQL 逐一核对，参数一律 ?：OrderDao.java:107-117、127-146、152-178、283-329；UserDao.java:88-136；GoodsDao.java:139-187；SeckillDao.java:94-112；RefundDao.java:59-75；AdminStatsDao；
- 唯一“拼接列名”处 OrderDao.updateStatusFrom:192-197 的 timeField 由 shadowTimeColumn 白名单 switch 兜底（:62-68），非法值直接 IllegalArgumentException；
- 84 处 ${} 全为 @Value / application.yml 占位符，不进 SQL。

### N7｜JWT / 越权（资金相关部分）
- AuthInterceptor.java:36-74：签名校验 + jti 黑名单 + 库内 role 与 token role 一致 + status=1 + 改密时间比较，四道全在；
- 新注册商户**无法操作他人店铺**（否定 Lead 线索 2）：StoreService.requireOwned:804-811 = store.ownerId()==ownerId || employeeDao.isEmployee(ownerId, storeId)，EmployeeDao.isEmployee:32-37 要求 employees(user_id, store_id, status=1) 行存在，唯一插入点是店主操作 addStoreEmployee:786-797（且拒绝把店主自己加成员工）。新商户只能建自己的店（createStore:525-552 用当前 ownerId）；
- 管理员：AdminController 每个资金/退款方法入口都有 requireAdmin(role)（:154-166、:300-311）。

### N8｜配置合并优先级 / 验证码明文回传（否定 Lead 线索 6）
- Spring Boot 外部配置优先级 **OS 环境变量 > profile yml > application.yml**，故 .env:23 TAKEOUT_SMS_EXPOSE_MOCK_CODE=false 会覆盖 application-develop.yml:9 的 true（compose 经 environment 注入，docker-compose.demo.yml:42 默认 false）；
- 更关键是该开关**只影响 mock 发信器**：MockSmsSender.java:14,24-26 读 expose-mock-code 决定 exposesCodeForDevelopment()，而 SmsVerificationService.issue:97-98 只在 sender.exposesCodeForDevelopment() 为真时才回传 code；.env:24 TAKEOUT_SMS_PROVIDER=qq-email → 装配 QQEmailSender（QQEmailSender.java:23），其 exposesCodeForDevelopment() 走接口默认 false（SmsSender.java:12-15）；
- 结论：**当前配置下 /api/auth/email-code 不会回传验证码**。仅当 provider 未覆盖（默认 mock）+ expose-mock-code=true 时才明文回传，那是纯本地开发形态。

### N9｜演示账号（Lead 线索 5，资金侧结论）
- DataSeeder.java:178-187 幂等补 phone=13100131000 管理员（口令取 takeout.demo.admin-password，默认 123456，application.yml:58），README.md:252-261 公开；
- 但 application-production.yml:8-9 data-seed.enabled=false，production 下不种演示账号；**风险仅存在于 develop 档对外部署**（与 F1 同一根因），管理员接管后可任意 approveRefund / refundOrder / updateUserStatus → 资金影响 High，判 authz 线交叉引用；
- production 守卫强制 sandbox=false + 生产网关（ProductionPaymentGuard.java:26-27），故演示密钥无法在生产触发真实退款。

---

## 4. 未覆盖项

| 项 | 原因 / 建议 |
| --- | --- |
| 真实 HTTP 验证（回调伪造、并发下单、退款竞态） | 8087/3310/6387 未监听、docker daemon 不可用、Redis 缺失；未启动服务以免写入项目 takeout 库 |
| 项目自带 MySQL 并发用例（OrderConcurrencyMySqlTest、AdminRefundConcurrencyMySqlTest、PaymentNotificationConcurrencyMySqlTest、StoreServiceTransactionMySqlTest） | 均为 opt-in：TAKEOUT_MYSQL_CONCURRENCY_TEST=1 + TAKEOUT_DB_*；用例会自建并删除随机库（OrderConcurrencyMySqlTest.java:44-72）。有 MySQL 环境时可直接复跑作回归基线 |
| ArkTS 客户端支付流程（entry/） | 本轮只审后端；未确认客户端是否传 paymentPassword、是否前端模拟支付成功（F3 的产品前提） |
| 支付宝真实 SDK 行为（rsaCheckV1 对参数集/编码处理） | 依赖第三方 SDK，未做沙箱联调；已逐项核对官方必校验字段 |
| 微信支付网关实现 | 被硬禁用；放开前必须完整重审其验签/退款逻辑 |
| 多实例/Redis 宕机下的库存与券并发 | 静态核对条件更新充分，未做运行时压测；SchedulerLock/LoginRateLimiter 均 fail-open，多实例下限额事实上失效（非资金问题） |
| CORS（WebConfig.java:62-69 allowedOriginPatterns 全匹配） | 属 infra 审计线；记为支付接口可被任意源跨域调用（Bearer 头需显式添加，风险有限） |

---

## 5. 修复优先级

1. **P0** 把 develop 档从对外环境摘掉，或按 F1 做 profile 级反向守卫——唯一能凭空造钱的路径；
2. **P0** 骑手注册准入 + 送达证据（F2），否则履约与结算可被任意互联网用户驱动；
3. **P1** 余额支付接入支付密码与失败限流（F3）；
4. **P1** 退款终态收口（F4）+ 对账口径；
5. **P2** clientIp 可信代理改造（F5）、回调错误码语义（F6）、结算分摊口径（F7）、查单限流（F8）。

---

*证据行号基于审计时的工作区（未改动任何源码）。本文件不含密钥明文、口令、JWT 或私钥内容。*
