# Phase 3 · 决策与落地记录（方案 C：地基先行，catalog 外拆留给 Phase 5）

> **状态**：按用户拍板执行方案 C。本轮**未外拆 catalog 服务**——只落地共享契约层，
> 并把外拆所需的前置条件与已识别风险写明，移交 Phase 5。
> **验证**：`mvn -f server/pom.xml test` = **228 passed / 0 failed**（3 模块 BUILD SUCCESS）；
> 真实进程端到端（登录/浏览/下单）全部通过。

---

## 1. 为什么最终选方案 C（而不是 A/B）

Spec 原计划 Phase 3 抽 catalog-service，理由写的是「收益最大、耦合最小」。**实测后这个前提不成立**，
三条证据如下：

### 证据一：抽 catalog 会破坏下单的原子性

`OrderService` 有 **20 处** catalog 域 DAO 用法，其中 6 个是写操作，且**全部在 `@Transactional` 内**：

| 方法 | 位置 | 性质 |
| --- | --- | --- |
| `goodsDao.deductStock` / `specDao.deductStock` | `OrderService:349-352` | 下单扣库存 |
| `seckillDao.deductQuota` | `OrderService:345` | 占秒杀名额 |
| `storeDao.updateMonthlySales` | `OrderService:371` | 店铺月销 |
| `goodsDao.restoreStock` / `specDao.restoreStock` | `OrderService:633-635` | 取消回滚库存 |
| `seckillDao.releaseQuota` / `releaseOnce` | `OrderService:638-639` | 取消回滚名额 |

这些一旦改为跨进程调用，就变成分布式事务——而 Saga 补偿是 **Phase 5** 的内容。
**先拆 catalog 再补 Saga，中间会存在一段「库存已扣、后续步骤失败、但无补偿」的窗口**，
这是拿正确性换形式。方案 B 就是这种情形，因此不选。

### 证据二：共享库下外拆的收益被高估

过渡期共库时，catalog-service 与 app 共用 `takeout-common` 的 DAO —— **共享同一份数据访问**。
此时拆出去只是「多了一个进程」，数据并未隔离；而「网关能按域路由」这一点在 Phase 2 已验证过。
所以方案 A 的增量收益主要是形式上的，不足以承担上述风险。

### 证据三：Spec 设想的「前置路由修正」机制不成立

Spec 写「先把路由归属修正到正确的 Controller，再按前缀路由」。实测：`/api/stores/{id}/reviews`
由 `UserCenterController` 提供（属 trade 域），但**它的 URL 路径不会因为挪代码而改变**，
网关按 `/api/stores/**` 前缀照样会把它送进 catalog。修正只能落在**网关路由表的精确规则**上
（具体路径排在通配之前）。这一点留给 Phase 5 与真实外拆一起做。

---

## 2. 本轮实际落地：takeout-common 共享契约层

```
server/
├── takeout-common/          ← 新增：共享契约层（66 个文件）
│   └── .../takeout/
│       ├── common/          统一响应 ApiResponse、BizException、GlobalExceptionHandler
│       │                    通用工具：InstanceId、OrderIdGenerator、SnowflakeIdGenerator、
│       │                    SchedulerLock、TraceContext
│       ├── model/           领域模型（30 个，含 trade/account/rider 域）
│       ├── dao/             JdbcTemplate DAO（20 个）
│       └── security/        JwtUtil、AuthInterceptor、LoginRateLimiter、
│                            PasswordUtil、TokenRevocationService
├── takeout-app/             单体应用（config/controller/job/service + 购物车 mapper）
└── takeout-gateway/         API 网关（Phase 2）
```

### 2.1 关键手法：保持包名不变，只改物理位置

搬迁时**包名一律不动**（仍是 `com.example.takeout.*`），因为 Java 的包名与文件路径无关。
效果：**全部既有 import 零改动**——这是 225 个用例在跨模块搬迁后依然全绿的原因。
若按常规做法改包名，将产生数百处 import 变更，风险与工时都高一个量级。

### 2.2 中途纠错：DAO 按域分类而非一把抓

第一版把**全部 21 个 DAO**（含购物车 `CartItemMapper`——属 trade 域）无差别搬进 common，
`mvn compile` 失败暴露了这个错误（common 缺 MyBatis 依赖）。
已把 `CartItemMapper` 与 `CartItemEntity` 移回 `takeout-app`。

**教训**：共享层的边界要按「哪些是本域、哪些是跨域共享」判断，不是「能不能编译过」。

### 2.3 本轮未做的事（刻意）

- ❌ 未创建 `takeout-catalog-service` 业务实现——曾建过只含 pom + 启动类的空骨架，
  但**空骨架会误导后来者以为"拆了一半"**，已删除
- ❌ 未引入 `StoreQueryPort` 之类无调用方的接口——曾写过一个，因零引用且签名是猜的，已删除
- ❌ 未做 catalog 外拆与网关按域路由（Phase 5）

---

## 3. 本轮发现的既有缺陷（与拆分无关，但真实验证时撞到）

### 3.1 Redis 挂掉时下单直接 500，违背既有契约

**发现过程**：端到端验证时（本机 Redis 未启动）`POST /api/orders` 返回 **500**，
而 AGENTS.md §4 明确承诺「Redis 不可用时跳过防重校验——加固不能变成下单不可用」。

**根因**（`OrderService:172`）：`redisProvider.getIfAvailable()` 只判断**bean 是否存在**，
不代表**真能连上**。Redis 进程挂掉时 bean 依然在，`setIfAbsent` 直接抛
`RedisConnectionFailureException`，异常冒泡成 500。

**归属确认**：`git diff` 确认 `OrderService` 未被本轮拆分修改；该段代码来自
`141ea68 fix(security): 补齐权限与并发边界`。**是既有缺陷，不是本次改动引入的回归。**

**为什么顺手修**：① 有明确契约依据（AGENTS.md §4）；② 症状严重（Redis 一挂全站无法下单）；
③ 同模式的另外 5 处（`SchedulerLock`/`HotDataCacheService`/`DomainEventPublisher`/
`LoginRateLimiter`/`DomainEventConsumer`）**都有异常保护，只有这一处漏了**，属单点遗漏。

**修复**：包一层 try/catch——`BizException`（真·重复提交）照常抛出，
其余 `RuntimeException`（连接被拒/超时）记录告警并跳过防重、让下单继续。

**验证（先红后绿）**：
- 修复前：`POST /api/orders` → **500**，库存不变
- 修复后：同条件 → **200 success**，订单 id=58，库存 966→965
- 单测 RED 复现：把 catch 体改回 `throw e` → 2 个用例报 `RedisConnectionFailure`；恢复 → 3/3 绿

新增 `OrderServiceIdempotencyFallbackTest`（3 用例）守护：Redis 不可用/超时均放行、
但 Redis 正常时重复提交仍被拦（提示文案逐字不变，前端依赖它）。

---

## 4. 验收记录（实测）

| 验收项 | 结果 |
| --- | --- |
| 全量测试 | ✅ **228 passed / 0 failed**（225 基线 + 3 新增），3 模块 BUILD SUCCESS |
| 跨模块搬迁零测试丢失 | ✅ app 221 + gateway 4 + 新增 3 = 228，与迁移前 225 基线对齐 |
| 真实进程启动 | ✅ `Started TakeoutApplication in 2.177s`（common 拆分后 Spring 装配完好） |
| 登录（鉴权组件从 common 装配） | ✅ 200 + 真实 token |
| 浏览店铺/商品（catalog 域 DAO 从 common 装配） | ✅ 200 + 真实数据（肯德基 4.7 分、招牌套餐 60.2 元） |
| 下单（事务原子性未破） | ✅ 200 + 订单 id=58 + 库存 966→965 |
| Redis 不可用降级 | ✅ 修复后下单成功（修复前 500） |

---

## 5. 移交 Phase 5 的事项

1. **catalog 外拆 + 网关精确路由**：`/api/stores/{id}/reviews`、`/api/search` 需用精确规则
   排在 `/api/stores/**` 通配之前，否则评价请求会被送到 catalog。
2. **事务接缝**：`OrderService` 的 6 个 catalog 写方法（见 §1 证据一）必须先有 Saga/TCC 设计
   才能外拆，否则破坏下单原子性。
3. **鉴权与 account 域的耦合**：`AuthInterceptor` 依赖 `UserDao`——
   分库后需改为对 account-service 的内部调用（或把 `users` 的鉴权投影列独立出来）。
4. **共享层按域拆分**：`takeout-common` 现在是「全领域共享」，分库时需按域拆成
   `takeout-common-core` + 各域契约，此时才能真正做到「服务只访问自己的表」。