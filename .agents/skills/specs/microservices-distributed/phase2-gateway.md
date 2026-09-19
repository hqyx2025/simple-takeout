# Phase 2 · 网关与多模块骨架（落地记录）

> **状态**：已完成并实测验收。全量 `mvn -f server/pom.xml test` = **225 passed / 0 failed**（app 221 + gateway 4）。
> **外部契约零变化**：对外 `:9000`、`/api/**`、`/uploads/**` 与拆分前完全一致，前端 HAP 零改动。

---

## 1. 兼容性冒烟（Phase 2 的准入前提，先验后做）

Spec 把「Spring Boot 3.5.4 + Java 25 + Spring Cloud + Gateway 能否共存」列为最高风险假设。
**动手拆模块前先做了最小冒烟**（独立一次性工程，非本仓库代码）：

| 项 | 结果 |
| --- | --- |
| 版本组合 | Boot 3.5.4 + Java 25.0.2 + Spring Cloud **2025.0.3** + `spring-cloud-starter-gateway-server-webflux` 4.3.5 |
| 编译打包 | ✅ BUILD SUCCESS（36 MB fat jar） |
| 运行时启动 | ✅ `Netty started on port 18080` / `Started ... in 1.476 seconds` |
| 路由转发 | ✅ `GET /api/ping` → 200 `BACKEND_PONG`（经 RewritePath 到后端）；直连对照 `/backend/ping` 同为 200 |

**结论**：该组合成立，Phase 2 可做。Spec 中"需实测、有风险"的判断得到正面验证。

> 附带修正：Spec §3.3 写的版本线是 `2025.0.x（Northfields）`。实测 Maven Central 上该线最新为
> **2025.0.3**（另有 2025.1.3，但那是对应更高 Boot 版本的线）。本次采用 **2025.0.3**。

---

## 2. 多模块拆分（Maven 聚合）

```
server/
├── pom.xml                    # 聚合根（parent + modules），artifactId = takeout-parent
├── takeout-app/               # 原单体（src + docker + 原 pom 内容），artifactId = takeout-app
│   ├── pom.xml
│   ├── src/
│   └── docker/
├── takeout-gateway/           # 新增：API 网关
│   ├── pom.xml
│   └── src/
└── Dockerfile                 # 改为双 jar 镜像
```

### 2.1 一处优于 Spec 的设计调整

Spec 的冲突清单 X3 写：构建命令需从 `mvn -f server/pom.xml spring-boot:run` 改为
`-pl takeout-app`，并同步文档。

**实际实现让这条命令改动最小化**：聚合 POM 用标准 `<modules>`，因此

| 命令 | 拆分前 | 拆分后 |
| --- | --- | --- |
| `mvn -f server/pom.xml test` | 跑单体 221 用例 | **命令不变**，自动跑全部模块（221 + 4） |
| `mvn -f server/pom.xml spring-boot:run` | 启动单体 | 需加 `-pl takeout-app`（模块歧义，无法避免） |

即：**只有需要指定单一应用的命令才变**，最常用的 `test` 命令零改动。
`server/pom.xml` 这个路径本身也保持不变（AGENTS.md、README、Dockerfile、compose 都引用它）。

### 2.2 网关的职责边界（刻意克制）

- 只做**路由 + 透传**：不校验业务、不聚合响应
- **鉴权仍由各服务的 `AuthInterceptor` 独占**——网关不把鉴权变成唯一防线（Spec 决策 D7）
- 路由覆盖 `/api/**` 与 `/uploads/**`（后者不需 JWT 但必须可达，否则评价图片 404）
- 对外监听 9000，与拆分前一致

---

## 3. 实测发现的两个真实缺陷（Spec 未预见）

网关是信任边界，下面两处错误都会**静默**造成安全回归，且症状离配置很远。
两者都已修复，并各留了契约测试守护。

### 3.1 XFF 被整体剔除 → 全站共用一个限流桶

**现象**：默认配置下经网关转发后，后端收到的请求**完全没有** `X-Forwarded-For`。

**根因**：Spring Cloud Gateway 4.3.x 引入**可信代理**机制。字节码含
`"Remote address not trusted. pattern %s remote address %s"` —— 直连来源不匹配
`trusted-proxies` 时，会调用 `RemoveXForwardedHeadersFilter` **主动剔除** X-Forwarded-*。

**后果**：后端 `LoginRateLimiter.clientIp()` 读不到 XFF，退化为 `getRemoteAddr()` = 网关地址
→ **全站用户共用同一个限流桶**，一个人触发封禁会让所有人登录失败（DoS）。

**踩到的第二个坑**：`trusted-proxies` 的类型是 `java.lang.String` 且语义是**正则**（匹配远端地址字符串），
**不是 CIDR 网段**。第一版写成 `0.0.0.0/0` 匹配不上 `127.0.0.1`，配置静默失效。

**修复**：`trusted-proxies: ".*"`（见 `takeout-gateway/application.yml`，含 `ponytail:` 注释说明
生产应收窄为前置代理网段）。

### 3.2 客户端伪造 XFF 可绕过登录限流

**现象**：修复 3.1 后，用 `for-append: true`（追加语义）时，逐字节 dump 显示后端收到：

```
X-Forwarded-For: 1.2.3.4,127.0.0.1     ← 客户端伪造值排在最前
```

**根因**：网关把客户端自带的头追加在**列表最前**，而后端 `clientIp()` 取 `split(",")[0]`
—— 拿到的正是**攻击者可控的值**。

**后果**：攻击者每换一个伪造 IP 就重置一个限流桶 → **无限绕过登录限流**。

**修复**：`for-append: false`（**覆写**语义）。网关是信任边界，必须丢弃不可信输入，
只写入自己亲眼所见的地址。修复后逐字节验证：

```
X-Forwarded-For: 127.0.0.1             ← 伪造值已丢弃
```

> 这比"改后端取最后一个值"更小也更正确：后端语义与既有测试（`LoginRateLimiterTest`）
> 都不用动，信任边界的收口留在网关侧。

### 3.3 守护测试（含「先红后绿」验证）

`takeout-gateway/src/test/.../GatewayXForwardedConfigTest.java`（4 用例）直接解析
`application.yml`（不启 Spring 上下文）断言四条不变量：

1. `x-forwarded.enabled` / `for-enabled` 为 true（否则客户端 IP 传不到后端）
2. **`for-append` 必须为 false**（覆写语义，防伪造）
3. **`trusted-proxies` 必须能匹配直连地址**且不得写成 CIDR 形式
4. 路由覆盖 `/api/**` 与 `/uploads/**`；对外端口为 9000

**先红后绿已证**：把 `for-append` 改回 `true` → 用例立即失败
（`断言信息正是安全不变量`），改回 `false` → 通过。

---

## 4. 部署拓扑变更

| 项 | 变更 |
| --- | --- |
| `docker-compose.yml` | 新增 `gateway` 服务（与应用同镜像，换 jar 启动）；**对外 9000 由 gateway 暴露**；app 另映射宿主 **9100** 供直连调试 |
| `server/Dockerfile` | 改为**双 jar 镜像**（`takeout-app.jar` + `takeout-gateway.jar`）；修正多模块后的 `COPY` 路径。默认入口是应用，网关容器用 `command` 覆盖 |
| 应用端口 | 新增 `TAKEOUT_APP_PORT`（默认仍 **9000**，既有流程零影响） |
| 网关端口/目标 | `TAKEOUT_GATEWAY_PORT`（默认 9000）、`TAKEOUT_APP_URI`（默认 `http://127.0.0.1:9000`） |

---

## 5. 验收记录（实测）

| 验收项 | 结果 |
| --- | --- |
| 全量测试 | ✅ **225 passed / 0 failed**；`mvn -f server/pom.xml test` 命令不变 |
| Reactor 构建 | ✅ parent → takeout-app → takeout-gateway 全 SUCCESS |
| 网关对外端口 | ✅ Netty 在 **:9000** 就绪 |
| 经网关端到端登录 | ✅ `POST :9000/api/auth/login` → **200 + 真实 token**（余额 3828.24 与直连一致） |
| traceId 跨进程贯通 | ✅ 自定义 `X-Request-Id: final-check-888` 原样回写响应头，且 app 日志出现 `traceId=final-check-888` |
| XFF 到达后端 | ✅ 逐字节 dump 确认 `X-Forwarded-For: <客户端IP>`（非网关 IP） |
| XFF 防伪造 | ✅ 客户端伪造的 `1.2.3.4` 被丢弃，后端只收到 `127.0.0.1` |
| `docker compose config` | ✅ 解析通过 |
| **容器级 3 服务启动** | ⚠️ **未执行**——本机 Docker **daemon 未运行**（`docker version` 报 `cannot find the file specified`）；`compose config` 只做本地解析，不需要 daemon |

**未验证项（如实记录）**：容器化一键启动（`docker compose up -d --build`）与
`scripts/rider-chain-regression.ps1` 的多服务链路回归，因 Docker daemon 不可用与 Redis 未启动而**未执行**。
本阶段的多模块与网关行为以「全量单测 + 真实进程端到端（app 9100 + gateway 9000）+ 逐字节 header dump」为准。

---

## 6. Phase 3 的输入（给下一阶段的实测结论）

Phase 1 的依赖矩阵已指出，Phase 3 抽 catalog 的真实工作量集中在 `OrderService`：
它注入了 `GoodsDao`/`StoreDao`/`GoodsSpecDao`/`SeckillDao` 四个 catalog 域 DAO，
下单取价与扣库存都依赖它们。**抽走 catalog 后下单会变成跨进程调用**，
因此 Phase 3 的验收重点不是"路由切过去"，而是「下单链路的取价/扣库存正确性」。
另有两处路由归属需先修正（`/api/stores/{id}/reviews`、`/api/search` 的前缀与归属域不符），
详见 `phase1-service-boundaries.md` §2。