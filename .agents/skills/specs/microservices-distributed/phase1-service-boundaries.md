# Phase 1 · 服务边界与依赖矩阵（实测基线）

> **状态**：已产出。**不改任何业务代码**——本阶段只做「把边界说清楚」，为 Phase 2/3 的进程外拆提供依据。
> **证据来源**：对 `server/src/main/java/com/example/takeout/` 的实测盘点（`grep` 依赖注入 + 路由注解），不是照抄 Spec 表格。

---

## 1. 实测跨域依赖矩阵（本阶段最重要的产出）

「跨域」指：某服务的代码直接依赖了不属于它领域边界的 DAO。**这张表决定了拆分的爆炸半径**，
不是理论划分——它是从 `private final XxxDao` 依赖注入实测出来的。

| 服务类 | 注入的 DAO / 服务 | 涉及域 | 耦合度 |
| --- | --- | --- | --- |
| `OrderService` | OrderDao, StoreDao, GoodsDao, AddressDao, CouponDao, ReviewDao, UserDao, RefundDao, PaymentRecordDao, CartItemMapper, RiderDao, GoodsSpecDao, SeckillDao | trade + catalog + account + rider | **极高（13 个）** |
| `AdminService` | StoreDao, OrderDao, UserDao, GoodsDao, RefundDao, OrderService, AdminStatsDao, PaymentRecordDao | 全部四域 | **极高（BFF 性质）** |
| `UserCenterService` | CouponDao, FavoriteDao, AddressDao, ReviewDao, StoreDao, GoodsDao, BankCardDao, UserCouponDao | account + trade + catalog | 中高 |
| `CartService` | CartItemMapper, GoodsDao, StoreDao, GoodsSpecDao | trade + catalog | 中 |
| `StoreService` | StoreDao, GoodsDao, GoodsSpecDao, SeckillDao, EmployeeDao | catalog（含秒杀、员工） | 低（域内） |
| `ContentService` | BannerDao, AnnouncementDao | catalog | 低（域内） |
| `AssistantService` | OrderDao, UserDao, StoreService | trade + account + catalog | 中 |
| `RiderService` | RiderDao, UserDao | rider + account | 低 |
| `AuthService` | UserDao | account | 无（域内） |
| `FileStorageService` | （无 DAO，仅 `Path`） | 独立（上传） | 无 |

### 1.1 三个必须正视的结论

1. **`OrderService` 是超级耦合点**：13 个 DAO 依赖横跨四域。这也正是 Spec §3.2 决策 D3
   「交易域刻意合并在一个服务」的理由——但即便如此，它仍然依赖 catalog 的商品/规格/秒杀
   与 account 的地址/用户。**Phase 3 拆 catalog 时，`OrderService` 必须改为通过 catalog 接口取价/扣库存**，
   这是 Phase 3 的主要工作量，不是"把 StoreController 挪走"那么简单。

2. **`CartService` 依赖 `GoodsDao`/`StoreDao`**（购物车要展示商品名/价格/店铺信息）。
   拆 catalog 后，购物车列表要么经 catalog 接口批量取商品，要么在 trade 侧冗余商品快照。
   **本阶段只指出问题，不在 Phase 1 决定方案**（留待 Phase 3 评估）。

3. **`AdminService` 是天然 BFF**：它跨全部四域做统计与列表聚合。Spec §3.2 把它列为可选
   `admin-bff` 是准确的；在 Phase 2/3 期间**应保持它留在单体**，不要提前外拆。

---

## 2. 实测路由归属（网关路由设计的真实约束）

**关键发现**：Controller 用 `@RequestMapping("/api")` + **方法级路径**，
因此**路由前缀分散在方法注解里，不能只按类前缀切分**。更麻烦的是**同一前缀跨 Controller**：

| 路径 | 所在 Controller | 归属域 | 注意 |
| --- | --- | --- | --- |
| `/api/stores`、`/api/stores/{id}`、`/api/stores/{id}/goods` | StoreController | catalog | — |
| `/api/stores/{id}/reviews`、`/api/goods/{id}/reviews` | **UserCenterController** | trade（评价） | ⚠️ **`/stores/**` 前缀被两个 Controller 共用** |
| `/api/stores/{id}/activities`、`/api/stores/{id}/setmeals` | StoreController | catalog | — |
| `/api/merchant/orders`、`/api/merchant/stats` | **OrderController** | trade | ⚠️ 商户端与用户端订单同 Controller |
| `/api/merchant/reviews`、`/api/merchant/reviews/{id}/reply` | **UserCenterController** | trade | ⚠️ 商户评价不跟商户订单在一起 |
| `/api/merchant/stores**`、`/api/merchant/goods**`、`/api/merchant/categories**` | StoreController | catalog | — |
| `/api/merchant/setmeals**`、`/api/merchant/employees**` | StoreController | catalog | — |
| `/api/orders**` | OrderController | trade | — |
| `/api/cart**` | CartController | trade | — |
| `/api/coupons**`、`/api/favorites**`、`/api/addresses**`、`/api/wallet/**` | UserCenterController | account | — |
| `/api/search` | UserCenterController | catalog（搜索商品/店铺） | ⚠️ 归 catalog 但代码在 account 型 Controller |
| `/api/auth/**` | AuthController | account | — |
| `/api/assistant/**` | AssistantController | 跨域（读订单+用户+店铺） | — |
| `/api/rider/**` | RiderController | rider | — |
| `/api/admin/**` | AdminController, AdminContentController, AdminRiderController | 跨域（BFF） | — |
| `/api/upload`、`/uploads/**` | UploadController | 独立 | — |

### 2.1 对网关路由的直接影响

- **不能按 HTTP 前缀一刀切**。例如把 `/api/stores/**` 整体路由到 catalog，会连带把
  `/api/stores/{id}/reviews`（评价，属 trade）也送错服务。
- Phase 3 的可行做法（按优先级）：
  1. **先把路由归属修正到正确的 Controller**（纯代码内部调整，外部路径不变），
     再按前缀路由——这是**推荐**做法，改动可控且让边界自洽；
  2. 或网关用更长前缀精确匹配（`/api/stores/{id}/reviews` 单独路由到 trade），
     但路由表会碎片化，后续维护成本高。
- **`/api/search` 与 `/api/stores/{id}/reviews` 是两处最需要先处理的例外**（前缀与归属域不符）。

---

## 3. 边界原则（落地时的判据）

1. **一个表只属于一个服务**，其他服务只能通过接口访问，禁止跨库 JOIN（过渡期例外见 Spec §3.5）。
2. **交易域保持合并**：订单 + 支付 + 托管 + 退款 + 券核销 + 秒杀名额在 `trade-service` 内必须原子。
3. **余额归 `account-service`**：支付时用 TCC 与 trade 协作（Phase 5，本次不做）。
4. **`AdminService` 留在单体**，直到有明确的 BFF 拆分需求。
5. **Phase 2/3 过渡期共享同一个 `takeout` 库**：边界靠代码纪律约束，不靠物理隔离。

### 3.1 边界检查方式（可执行）

Phase 2 之后用一条可执行检查守住「无跨域直连 DAO」：

```bash
# 例：catalog 服务中不得出现 trade 域的 DAO 引用
grep -rn "OrderDao\|CouponDao\|SeckillDao\|ReviewDao" server/takeout-catalog-service/src/ \
  && echo "越界：catalog 直接依赖了 trade 域 DAO" || echo "OK"
```

该检查在 Phase 3 落地时接入（届时目录才存在），**Phase 1 只定义判据**。

---

## 4. Phase 1 交付边界（明确不做）

- ❌ 不改任何业务代码、不改包结构（Spec §3.2 的"包结构整理"推迟到 Phase 2 拆模块时一并做，
  避免在单模块内做一次无收益的大搬迁）
- ❌ 不引入 Spring Cloud 依赖（Phase 2）
- ❌ 不动前端
- ✅ 仅产出本文档 + 把实测结论反馈到 `spec.md`

> **为什么不做包结构整理**：在单模块内先搬迁包、再在 Phase 2 拆模块，等于同一批文件改两遍。
> 实测依赖矩阵已经足够支撑 Phase 2 的分模块决策，直接搬进新模块更省一次改动。