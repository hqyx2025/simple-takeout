# Tasks · 微服务与分布式落地

> **进度**：**线 A（Task 1/2）已完成** ✅ —— 全量 `mvn -f server/pom.xml test` = **221 passed / 0 failed**（基线 182 + 新增 39）。
> **线 B** 按用户拍板继续到 Phase 2/3（网关 + catalog），Phase 4/5/6 不在本次承诺范围。
> **纪律**：遵守 `AGENTS.md` §9/§10 —— 提交信息不得含 AI 署名、身份用 `HQYX2025 <751848863@qq.com>`、临时产物放 `TemporaryCacheStorage/`、只改文档时不改业务代码且不自动提交。
> **每阶段收尾**：`mvn -f server/pom.xml test` 全绿 → 相关链路脚本通过 → 更新本文件与 `checklist.md` → 提交。

## 线 A：分布式基线收口（✅ 已完成）

- [x] Task 1: Phase 0 多实例真·可用
  - [x] SubTask 1.1: `OutboxEventDao.claimPending` 行级认领（`FOR UPDATE SKIP LOCKED` + `owner`/`lease_until` 租约），补 SQL 契约测试（`OutboxEventDaoClaimSqlTest` 5 用例）
  - [x] SubTask 1.2: `DomainEventConsumer` 消费者名动态化（`consumer-<InstanceId>`）（G2）
  - [x] SubTask 1.3: 定时任务单实例调度锁 `SchedulerLock`（Redis；**Redis 不可用时 fail-open**）；接入 OrderTimeoutJob 与 Outbox cleanup（relay 不加锁——它已有行级认领，加锁会把多实例退化成单实例）（G3）
  - [x] SubTask 1.4: Snowflake 订单号（`SnowflakeIdGenerator` + `OrderIdGenerator`）+ `order_no` 唯一键冲突换号重试一次（G4）
  - [x] SubTask 1.5: `X-Request-Id`/traceId 生成与透传 + 日志 MDC + **补 `logback-spring.xml`**（仓库原本无此配置，pattern 含 `%X{traceId}`）
  - [x] SubTask 1.6: 多实例验收——**已在真实 MySQL 8.4.0 上实测**：并发认领行集不相交（A={1,2,3} / B={4,5,6}）、租约四场景、订单号先红后绿（旧实现同秒 200 单 → 199 个不同号）
- [x] Task 2: 线 A 文档与配置
  - [x] SubTask 2.1: `AGENTS.md` 记录多实例运行方式、新增配置项（`claim-lease-ms`/`job.lock-enabled`/各锁 TTL）、日志与 traceId；并**修正日志描述漂移**（原文声称的 logback 能力此前从未落地）

> **注**：`docker compose up -d --build --scale app=3` 与 `scripts/rider-chain-regression.ps1` 的多实例全链路回归**未执行**——本机 Docker 不可用（`docker version` 无响应）、Redis 未启动（6379 未监听）。因此多实例验收以「真实 MySQL 8.4 上的 SQL 语义实测 + 单元层的锁/ID/追踪契约」为准；容器级 3 实例链路验收留待具备 Docker 环境时补做。

## 线 B：微服务化（每个 Phase 结束后按 §5.2 决策是否继续）

- [ ] Task 3: Phase 1 逻辑边界收敛（不拆进程）
  - [ ] SubTask 3.1: 输出服务边界与依赖矩阵文档（对照 `spec.md` §3.2）
  - [ ] SubTask 3.2: 以包结构/内部接口隔离跨域直连 DAO，补边界检查脚本
- [ ] Task 4: Phase 2 网关 + 多模块骨架 + 兼容性冒烟
  - [ ] SubTask 4.1: 兼容性冒烟：Spring Cloud 2025.0.x + Boot 3.5.4 + Java 25 最小样例（网关能启动并转发）
  - [ ] SubTask 4.2: `server/pom.xml` 改聚合，新增 `takeout-common`、`takeout-gateway`、`takeout-app`
  - [ ] SubTask 4.3: 网关静态路由 `/api/**` → `takeout-app`，:9000 契约与行为不变
  - [ ] SubTask 4.4: 同步更新 `AGENTS.md`/README 的构建运行命令（`-pl takeout-app`）
  - [ ] SubTask 4.5: 全量测试 + 前端零改动回归
- [ ] Task 5: Phase 3 抽 `catalog-service`
  - [ ] SubTask 5.1: 迁移 stores/goods/goods_specs/categories/banners/announcements 及缓存与商户端相关接口
  - [ ] SubTask 5.2: 网关前缀路由切换；过渡期共享 `takeout` 库
  - [ ] SubTask 5.3: 契约测试（catalog 接口 + 缓存三防护不回归）
  - [ ] SubTask 5.4: `rider-chain-regression.ps1` 全绿 + HAP 不重建回归
- [ ] Task 6: Phase 4 抽 `account-service`
  - [ ] SubTask 6.1: 迁移 users/auth/token_blacklist/addresses/favorites
  - [ ] SubTask 6.2: 鉴权回归（登出吊销、改密失效、禁用账号即时失效）
  - [ ] SubTask 6.3: 路由切换 + 全量回归
- [ ] Task 7: Phase 5 抽 `trade-service` + Saga/TCC（最难，可放弃）
  - [ ] SubTask 7.1: 迁移 orders/cart/coupons/seckills/refunds/payment/marketing_activities/reviews
  - [ ] SubTask 7.2: `saga_transactions` 表 + 编排器 + `/internal/**` 预留接口（stock/coupon/seckill/balance）
  - [ ] SubTask 7.3: Saga 恢复任务（多实例安全）
  - [ ] SubTask 7.4: 分库迁移脚本 + 回滚脚本（account/catalog/trade/rider schema）
  - [ ] SubTask 7.5: 下单/支付/取消/退款/超时取消五路径"先红后绿"用例（含补偿/幂等/并发）
  - [ ] SubTask 7.6: 资金与托管口径对照验收（与现状逐项比对）
- [ ] Task 8: Phase 6（可选）治理收口
  - [ ] SubTask 8.1: 注册中心/配置中心（仅当 Phase 2 验证通过）
  - [ ] SubTask 8.2: 网关限流（复用 Redis）、Resilience4j 熔断降级
  - [ ] SubTask 8.3: Micrometer Tracing + Zipkin（可选）
  - [ ] SubTask 8.4: `rider-service` 外拆 + `admin-bff` 跨域统计聚合
  - [ ] SubTask 8.5: 新增 `md/微服务与分布式架构.md` 并登记 README 文档索引

# Task Dependencies
- Task 1（Phase 0）不依赖任何前置，**最先做**，且是线 B 的地基（多实例安全）
- Task 3（边界收敛）依赖 Task 1 完成；不拆进程，可单独交付
- Task 4（网关）依赖 Task 3 与兼容性冒烟（4.1）
- Task 5（catalog）依赖 Task 4
- Task 6（account）与 Task 5 可并行，但都依赖 Task 4
- Task 7（trade+Saga）依赖 Task 5 与 Task 6 完成（需要 catalog/account 的内部接口）
- Task 8 依赖 Task 4~7 中已完成的部分；每项可独立开关
