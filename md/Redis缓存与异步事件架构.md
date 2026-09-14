# Redis 缓存与领域事件（异步）架构说明

> 本文记录「Redis 热点缓存 + 事务性 Outbox + Redis Stream 异步事件」的落地设计与验证结果。
> 涉及代码：`HotDataCacheService`、`RedisConfig`、`DomainEventPublisher`、
> `DomainEventConsumer`、`OutboxRelayJob`、`OutboxEventDao`。

## 1. 为什么要做，以及边界在哪

毕设目标里常提「缓存热点数据、分布式锁防超卖、Redis Stream 异步下单、MQ 解耦」。
这些能力并不都适合直接落到本工程，落地前先明确边界：

| 目标 | 本工程做法 | 原因 |
| --- | --- | --- |
| 缓存热点数据 | **已落地**（读多写少的浏览类数据） | 收益直接、风险低，失败可回源 |
| 分布式锁防秒杀超卖 | **不引入**，沿用数据库条件更新 | 现有 `UPDATE ... WHERE sold + ? <= quota` / `WHERE stock >= ?` 在本地事务内已保证不超卖；Redis 锁无法覆盖数据库写入，Redis 故障时反而更弱 |
| Redis Stream 异步下单 | **部分落地**：下单仍同步，事件异步 | 见下节「为什么下单本身不异步」 |
| RabbitMQ/RocketMQ 解耦 | **以 Redis Stream 承载**，未引入外部 Broker | 复用已有 Redis，零新增中间件；接口已抽象，后续可替换 |

### 为什么下单本身不异步

`OrderService.createOrder` 在**一个本地事务**里完成：校验 → 占秒杀名额 → 扣库存
→ 核销优惠券 → 写订单。这四步的原子性是防超卖与防重复扣券的根基。

把「下单」改成异步需要引入 saga + 补偿事务（每一步都要有反向操作），
复杂度和出错面远大于收益；而毕设场景的瓶颈并不在下单本身。
因此异步化只覆盖**可延迟、可不参与金额与状态机写入**的下游动作：
商户提醒、运营统计、对账记录等。

## 2. 热点缓存设计（HotDataCacheService）

### 缓存范围

只缓存读多写少、可容忍短暂延迟一致的浏览类数据：

- `/api/categories`（分类导航）
- `/api/stores`、`/api/stores/recommended`（店铺列表/推荐）
- `/api/stores/{id}`、`/api/stores/{id}/goods`、`/api/stores/{id}/categories`
- `/api/goods/special`、`/api/rankings/stores`、`/api/rankings/goods`
- `/api/seckills`（秒杀专区）
- `/api/banners`、`/api/announcements`

**不入缓存**：订单、购物车、余额、库存扣减、退款等强一致数据，全部直连数据库。

### 三类故障防护

| 故障 | 防护手段 | 参数 |
| --- | --- | --- |
| **缓存穿透**（查不存在的数据，请求全打到库） | 不存在的对象写入「空值占位」短 TTL；key 均为封闭集合，不含用户原始输入 | `null-ttl-seconds=60` |
| **缓存击穿**（热点 key 过期瞬间高并发回源） | 回源前 `SET NX` 抢互斥锁，只有 1 个请求查库；未抢到者短自旋复用回填结果，等不到则降级回源（绝不被锁阻塞） | `rebuild-lock-ms=3000`、`rebuild-wait-ms=500` |
| **缓存雪崩**（大批 key 同时过期 / Redis 整体不可用） | ① TTL 叠加随机抖动：`base + [0, jitter)`；② 任何 Redis 异常只记日志并回源数据库 | `ttl-seconds=300`、`jitter-seconds=120` |

坐标类 key 按约 100m 粒度取整（`Keys.coord`），避免每个用户坐标都产生独立 key 造成 key 爆炸。

### 失效策略

写操作后**显式失效**（不用 Spring Cache 注解，因为失效范围需按业务语义精确控制）：

- 店铺/商品/分类/Banner/公告变更 → `STORE_GOODS_PATTERNS`
  （`stores:*`、`store:*`、`goods:*`、`rank:*`、`seckills:*`、`categories`）
- 下单扣库存、取消回滚、退款、超时取消 → `STOCK_DEPENDENT_PATTERNS`
  （库存与秒杀名额参与列表/榜单/秒杀的展示筛选，必须让这些视图重算）

批量失效用 `SCAN` 游标而非 `KEYS`，避免大 key 空间下阻塞 Redis。

## 3. 领域事件设计（事务性 Outbox + Redis Stream）

### 为什么用 Outbox

「下单后直接发消息」有两种失败模式：

- 事务内直接写 Redis：Redis 成功但数据库回滚 → **幽灵事件**；
- 提交后再写 Redis：两者之间进程崩溃 → **丢事件**。

因此事件先以**同一事务**写入数据库 `outbox_events` 表
（要么和订单一起提交，要么一起回滚），再由 `OutboxRelayJob` 异步搬运到
Redis Stream `takeout:stream:domain-events`。

### 投递语义与幂等

- **至少一次（at-least-once）**：投递成功即置 `status=1`；若在「投递成功、置位前」崩溃，
  事件会重复投递。
- **消费端幂等**：`DomainEventConsumer` 用 `takeout:event:consumed:<eventId>` 去重键，
  重复事件直接跳过并 ACK。
- **永不放弃投递**：事件已在数据库中，重试几乎零成本；`retry_count` **仅用于告警**，
  不再作为跳过条件。

  > 这里踩过一个真实的坑：最初把 `retry_count >= max-retry` 当作「跳过」条件，
  > 结果 Redis 短暂宕机导致 `retry_count` 触顶，Redis 恢复后该事件被永久跳过、
  > 再也不投递。**瞬时故障不应升级为数据丢失。**

- 消费组 `takeout-consumers` 保证同组内一个事件只被一个实例消费；处理失败不 ACK，留待重读。

### 事件类型

| 事件 | 触发点 |
| --- | --- |
| `ORDER_CREATED` | 下单成功（占库存/名额/券之后） |
| `ORDER_PAID` | 支付条件更新成功后 |
| `ORDER_CANCELLED` | 待付款取消、已支付取消（即时退款） |
| `ORDER_REFUNDED` | 管理端同意退款 |

事件只在**条件更新成功后**发布，因此不会产生「假支付」「假退款」事件。

## 4. 降级行为（Redis 不可用时）

缓存与事件机制都遵循同一原则：**Redis 故障不得升级为业务故障**。

| 场景 | 行为 | 实测 |
| --- | --- | --- |
| 读接口 | 抛异常吞掉、回源数据库 | 单请求约 565ms（而非默认重试下的约 10s） |
| 写订单 | 正常成功；事件留在 outbox `status=0` | 订单创建成功，事件未丢失 |
| Redis 恢复 | 缓存重新回填；outbox 事件自动补投并消费 | 事件最终 `status=1`，消费端处理一次 |

关掉 Redis 相关能力：`TAKEOUT_CACHE_ENABLED=false`、`TAKEOUT_MQ_ENABLED=false`。

> **注意**：`RedisConfig` 中刻意**保留** `autoReconnect(true)`。
> 曾为「缓存快速失败」关掉自动重连，导致 Lettuce 在 Redis 重启后永久停留在
> `Currently not connected`，Outbox 中继再也无法投递。快速失败只需靠短超时实现。

## 5. 关键配置

```yaml
spring.data.redis:
  timeout: 500ms            # 短超时，快速降级回源
  connect-timeout: 500ms
takeout.cache:
  ttl-seconds: 300          # 基础 TTL
  jitter-seconds: 120       # 抖动上限（防雪崩）
  null-ttl-seconds: 60      # 空值占位 TTL（防穿透）
  rebuild-lock-ms: 3000     # 回源互斥锁（防击穿）
takeout.mq:
  enabled: true
  relay-scan-ms: 2000       # Outbox 中继间隔
  max-retry: 10             # 仅用于告警，不作为跳过条件
  dedup-hours: 24           # 消费幂等去重键保留
```

## 6. 验证记录

单测：`HotDataCacheServiceTest`（7 个，覆盖三类防护 + 故障降级）、
`DomainEventPublisherTest`（7 个，覆盖 Outbox 写入、异常吞噬、投递失败语义）。
全量 `mvn test` 共 **64 个测试通过**。

实例验证（docker compose + 真实 Redis/MySQL）：

| 验证项 | 结果 |
| --- | --- |
| 缓存命中延迟 | 3~4ms（冷启动首请求约 178ms 建连+回源） |
| TTL 抖动 | 连续 8 次观测 8 个不同值，分布 306~389s |
| 缓存穿透 | 不存在的店铺写入占位，TTL=60s，后续不再查库 |
| 缓存击穿 | 30 并发冷 key：全部成功、数据一致、仅回填一次、锁正确释放 |
| 缓存失效 | 管理端改分类后 `categories` 缓存立即清除 |
| 事件投递 | 下单/支付/取消事件均落 outbox 并投递到 Stream，`pending=0`、`lag=0` |
| 消费幂等 | 同一 `eventId` 投递 2 次，仅处理 1 次 |
| 宕机不丢事件 | 停 Redis 下单成功，事件 `status=0`；恢复后自动补投并消费 |
| 主流程不受影响 | Redis 全程不可用时读接口仍可用（约 565ms） |

## 7. 后续可选演进（未实现）

- 引入 RabbitMQ/RocketMQ：把 `DomainEventPublisher` 的投递实现替换为 Broker，
  消费端改为对应的 `@RabbitListener`；Outbox 与幂等设计可原样复用。
- 真正的异步下单：需引入 saga + 补偿（库存/名额/券的反向操作）与订单状态中间态，
  属于架构级改造，风险较高。
- 多实例部署时，`DomainEventConsumer` 的 `consumer-1` 应改为
  基于主机名/实例 ID 的动态消费者名。