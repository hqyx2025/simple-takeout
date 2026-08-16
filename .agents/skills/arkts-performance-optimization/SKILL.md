---
name: arkts-performance-optimization
description: 鸿蒙ArkUI渲染与性能优化技能，覆盖LazyForEach懒加载与IDataSource实现、@Reusable组件复用、状态管理拆分、动画优化、Profiler定位耗时。当列表卡顿、页面掉帧、内存占用高或需要性能优化时使用。
---

# ArkUI 渲染性能优化

## 核心原则（先理解再动手）

1. **状态变更会触发组件树重绘（recomposition）**：状态变量变化范围越大，重绘范围越大。局部状态放组件内，全局数据才放 AppStorage
2. **ForEach 一次性全量创建子组件**：数据量 >50 项时改用 LazyForEach，否则内存与首屏时间线性增长
3. **官方实测数据**：万条数据场景，LazyForEach 相比 ForEach 内存降低约 86%、首屏加载缩短约 77%、丢帧率从 58.2% 降至接近 0

## 一、ForEach vs LazyForEach 选择

| 维度 | ForEach | LazyForEach |
|---|---|---|
| 渲染策略 | 一次性全量 | 仅可视区域 + 缓存区 |
| 数据源 | 普通数组 | 实现 `IDataSource` 接口的类 |
| 适用场景 | <50 项、固定、静态 | 长列表、动态更新 |
| key 稳定性 | 影响复用 | 键值不稳定会影响子组件刷新 |

## 二、LazyForEach 标准实现模板

```typescript
// 1. 数据源类（必须实现 IDataSource）
class StoreDataSource implements IDataSource {
  private listeners: DataChangeListener[] = []
  private items: StoreItem[] = []

  constructor(items: StoreItem[]) {
    this.items = items
  }

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): StoreItem {
    return this.items[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  // 数据变更时通知（新增/删除/更新后必须调用）
  notifyDataChanged(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }
}
```

```
// 2. 页面中使用（片段示意，需在 build() 内）
List() {
  LazyForEach(this.dataSource, (item: StoreItem) => {
    ListItem() {
      StoreCard({ store: item })
    }
  }, (item: StoreItem) => `${item.id}`)  // key 必须唯一且稳定
}
.cachedCount(3)  // 视口外缓存数量，平衡内存与滚动流畅度
```

> **坑**：数据增删改后必须调用 `notifyDataChanged()`，否则 UI 不刷新。key 变化（如 id 复用）会导致子组件不更新。

## 三、@Reusable 组件复用（配合 LazyForEach）

高频滚动列表的列表项组件加 `@Reusable`：

```
@Reusable
@Component
export struct StoreCard {
  @Prop store: StoreItem = new StoreItem()

  aboutToReuse(params: Record<string, Object>): void {
    // 复用前重置非 @Prop 状态，避免脏数据残留
  }
}
```

## 四、状态管理拆分（减少重绘范围）

```
错误示范：筛选条件、loading、列表数据全塞一个 @State 大对象
正确做法：
  - 页面局部状态（弹窗显隐、输入框内容）→ 组件内 @State / @Local
  - 跨页共享数据（用户/购物车/订单）→ AppStorage + @StorageLink
  - 深度嵌套数据 → @ObservedV2 + @Trace（深观测，避免逐层传参）
```

要点：
- 点击按钮只改局部状态时，不应把整页带进更新逻辑
- `@State` 只能监听第一层属性，复杂嵌套 Bean 用 `@ObservedV2 + @Trace`
- V2 新增 `@Local`（组件内部状态）、`@Event`（子传父回调）；新 API 推荐用 `Repeat` 统一循环渲染（内部实现懒加载）

## 五、动画优化（避免逐帧状态更新）

```
❌ 低效：@State angle 每帧 +1，状态驱动重绘 → 掉帧
✅ 正确：animateTo / transition / 显式动画，由渲染引擎插值
```

- 布局变化用 `.animation({ duration, curve })` 或 `animateTo()`
- 页面切换用系统转场或 `transition()`，不要手动 setInterval 驱动
- 循环动画才用 setInterval（如本项目的骑手配送动画），但频率 ≤4Hz（250ms 步进）且只驱动进度数值

## 六、长列表分页与预加载

- `onReachEnd` 触发加载更多，分页状态独立管理（页码/去重/合并/错误）
- 可配合 `scrollToIndex` 和 `onScrollIndex` 提前渲染即将进入视口的数据
- 图片列表场景：请求去重 + 缓存，避免重复加载

## 七、性能定位工具

| 工具 | 用途 | 位置 |
|---|---|---|
| DevEco Profiler | 录制 Trace 定位耗时点、掉帧场景 | DevEco Studio 底部 Profiler 面板 |
| HiDebug | 内存/CPU 实时监测 | 代码接入或命令行 |
| AppAnalyzer | 页面性能/兼容性/功耗体检报告 | Tools → AppAnalyzer |

## 八、本项目（简单外卖）的落地清单

- [ ] 首页店铺列表已用 LazyForEach + IDataSource + cachedCount
- [ ] 订单列表、搜索结果、优惠券列表、评价列表等长列表已懒加载
- [ ] 列表项组件（店铺卡片/订单卡片）已加 @Reusable
- [ ] 筛选条件与列表数据已拆分，未混在同一个 @State
- [ ] 收藏/选中等局部变化未扩大 UI 更新范围
- [ ] 动画使用 animateTo/transition，无逐帧 @State 驱动
- [ ] 数据增删后 LazyForEach 数据源已调用 notifyDataChanged

