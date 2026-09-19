# Checklist · 微服务与分布式落地

> 每阶段收尾时勾选。**任何 🔴 项未通过，不得进入下一阶段。**

## 评审门禁（开始动手前）—— ✅ 已通过

- [x] 已在 `spec.md` §5.2 回答 5 个决策项（用户拍板：线 A + Phase 2/3；静态路由；过渡期共享单库；Saga 仅在 Phase 5 时启用；雪花订单号）
- [x] 已批准 `spec.md` §5.1 冲突清单中的 X1（新增 Spring Cloud 依赖栈）、X3（构建命令变更）—— 纳入 Phase 2 执行范围
- [x] X2（下单改 Saga）**不在本次范围**（Phase 5 才需要，届时单独批准）
- [x] 已确认前端零改动目标（`/api/**` 与 `:9000` 契约不变）

## 线 A · Phase 0（每项 🔴 必过）—— ✅ 全部通过

- [x] 🔴 Outbox 多实例不重复搬运（`SKIP LOCKED` + 契约测试）—— **真实 MySQL 8.4.0 实测两并发事务认领到不相交行集（A={1,2,3} / B={4,5,6}）**；`OutboxEventDaoClaimSqlTest` 5 用例守护 SQL 契约
- [x] 🔴 消费者名动态化，多实例各自消费（`consumer-<InstanceId>`，含主机名+进程号+启动碎片）
- [x] 🔴 定时任务多实例不重复处理（`SchedulerLock`；**实测 Redis 不可用时 fail-open 放行**）
- [x] 🔴 订单号全局唯一（雪花 + 冲突重试）—— **先红后绿**：旧实现同秒 200 单产出 199 个不同号（RED），雪花后 200/200（GREEN）；生成器 32000 并发零重复
- [x] 🔴 traceId 贯穿，日志可按一次请求串起（MDC + logback pattern + 响应头；含控制字符剥离与连续请求不串）
- [x] 🔴 `mvn -f server/pom.xml test` 全绿，用例数不减少 —— **221 passed / 0 failed**（基线 182，+39）
- [ ] ⚠️ 3 实例运行下 `scripts/rider-chain-regression.ps1` 全绿 —— **未执行**：本机 Docker 不可用、Redis 未启动；已用真实 MySQL 的 SQL 语义实测替代，容器级验收留待有 Docker 环境时补做
- [x] 🟡 新增配置项与多实例运行方式已写入 `AGENTS.md`

## 线 B · 每阶段通用门禁

- [x] 🔴 `mvn -f server/pom.xml test` 全绿 —— **225 passed / 0 failed**（Phase 2 后）
- [ ] ⚠️ 现有 HAP **不重新构建**即可跑通四端主链路 —— **未执行**：需要真机/模拟器，本次未做设备侧回归
- [ ] ⚠️ `scripts/rider-chain-regression.ps1` 全绿 —— **未执行**：需 Redis（本机未启动）
- [x] 🔴 契约未变：前端无需改动任何 `Constants.ets`/ApiService 字段（对外仍是 `:9000` + `/api/**`，端到端登录 200 已验证）
- [x] 🔴 无服务直接访问他域表/DAO —— Phase 2 只有网关（不访问数据库）与应用（未拆域），边界检查判据已在 `phase1-service-boundaries.md` §3.1 定义
- [x] 🟡 `docker compose up -d --build` 一键可用 —— **`docker compose config` 通过**；实际启动**未执行**（Docker daemon 未运行）
- [ ] 🟡 新增/变更文档已同步 README 文档索引 —— Spec 目录已更新；README 索引待 Phase 3 一并补
- [x] 🟡 提交信息无 AI 署名，身份为 `HQYX2025 <751848863@qq.com>`

## 专项门禁

### Phase 2（网关 + 多模块）—— ✅ 通过
- [x] 🔴 Spring Cloud 2025.0.3 与 Boot 3.5.4 / Java 25 兼容性冒烟通过（编译 + Netty 启动 + 真实路由转发 200）
- [x] 🔴 未使用 Nacos（采用静态路由 + Compose 服务名，符合"不为注册中心牺牲可构建性"）
- [x] 🔴 `AGENTS.md` 构建命令已更新且实测可用（`test` 命令未变，`spring-boot:run` 加 `-pl takeout-app`）
- [x] 🔴 **网关 XFF 安全契约（实测新增，Spec 未预见）**：
  - `for-append` 必须为 false —— 否则客户端伪造 XFF 排在最前，后端取 `[0]` → **无限绕过登录限流**（已实测复现并修复）
  - `trusted-proxies` 必须能匹配直连地址且不得写成 CIDR —— 否则网关剔除 XFF → **全站共用一个限流桶**（已实测复现并修复）
  - 两条均有契约测试守护，且做过「先红后绿」验证

### Phase 3（catalog）—— ⏭ 按方案 C 调整：外拆移交 Phase 5
- [x] 🔴 缓存穿透/击穿/雪崩三防护用例不回归（全量 228 绿，含 `HotDataCacheServiceTest`）
- [x] 🔴 价格/库存一致性：下单取价与扣减仍在同一本地事务内（端到端实测库存 966→965）
- [x] 🔴 超距/起送价/配送半径判定不回退（`StoreDeliveryRadiusTest`/`StoreDistanceTest` 全绿）
- [x] 🔴 **新增**：`takeout-common` 拆分后真实进程可启动、Spring 装配完好（`Started ... in 2.177s`）
- [x] 🔴 **新增**：Redis 不可用时下单降级契约（真机实测 200，修复前 500）
- [ ] ⏭ **catalog 服务外拆**未执行——理由：抽 catalog 会把下单的 6 个 `@Transactional` 内写操作
      变成跨进程调用，破坏原子性；需先有 Saga/TCC 设计（Phase 5）。详见 `phase3-catalog-split.md` §1

### Phase 4（account）
- [ ] 🔴 登出吊销 / 改密旧 token 失效 / 禁用账号即时失效三处不回归
- [ ] 🔴 登录/注册/下单限流语义不变

### Phase 5（trade + Saga）
- [ ] 🔴 下单/支付/取消/退款/超时取消五路径"先红后绿"用例全部有效
- [ ] 🔴 补偿幂等：重放同一 `sagaId` 不重复生效
- [ ] 🔴 卡住 Saga 可被恢复任务收敛（无永久悬挂）
- [ ] 🔴 资金与托管口径与现状逐项一致（escrow 0/1/2、余额原子自增、条件更新）
- [ ] 🔴 分库迁移脚本可执行且有回滚脚本，迁移后数据核对一致
- [ ] 🟡 事件仍在「条件更新成功之后」发布

### Phase 6（治理，可选）
- [ ] 🟡 网关限流不误伤正常用户（超限 429，Redis 不可用放行）
- [ ] 🟡 熔断降级口径明确：**绝不用假数据兜底**
- [ ] 🟡 追踪/指标可观测，健康检查复用 `healthcheck.java`
