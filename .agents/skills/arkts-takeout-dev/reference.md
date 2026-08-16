# ArkTS 布局与组件规范参考

## 一、布局组件属性对照(API 24 / SDK 6.1.1)

| 组件 | 内容对齐 | 交叉轴 | 说明 |
|---|---|---|---|
| `Stack` | `alignContent(Alignment.X)` | — | **无** justifyContent/alignItems |
| `Row` | `justifyContent(FlexAlign.X)` | `alignItems(VerticalAlign.X)` | 交叉轴=垂直 |
| `Column` | `justifyContent(FlexAlign.X)` | `alignItems(HorizontalAlign.X)` | 交叉轴=水平 |
| `Flex` | `justifyContent(FlexAlign.X)` | `alignItems(ItemAlign.X)` | — |

### Alignment 枚举(无 CenterStart)

`TopStart` / `Top` / `TopEnd` / `Start`(垂直居中+水平起始) / `Center` / `End` / `BottomStart` / `Bottom` / `BottomEnd`

### 常见误用（以下均为非法写法，仅作对比展示）

```
// ❌ 错误
Stack() { ... }
  .justifyContent(FlexAlign.Center)     // Stack 无此属性
  .alignItems(HorizontalAlign.Center)   // Stack 无此属性

Row() { ... }
  .alignItems(HorizontalAlign.Top)      // HorizontalAlign 无 Top

Stack({ alignContent: Alignment.CenterStart })  // 枚举不存在

// ✅ 正确
Stack() { ... }
  .alignContent(Alignment.Center)

Row() { ... }
  .alignItems(VerticalAlign.Top)
```

## 二、Length 类型处理

宽高、`Area.width`、`position` 等返回 `Length`(string | number | Resource),**不能直接 Number.parseFloat**:

```
.onAreaChange((oldValue: Area, newValue: Area) => {
  const w: Length = newValue.width
  if (typeof w === 'number') {
    this.trackWidth = w
  } else if (typeof w === 'string') {
    this.trackWidth = Number.parseFloat(w)
  }
})
```

## 三、动画模式(骑手配送动画参考)

```
@State riderProgress: number = 0
private riderTimer: number = -1

start() {
  this.riderTimer = setInterval(() => {
    if (this.riderProgress >= 0.88) { this.stop(); return }
    this.riderProgress += 0.02
  }, 250)
}

stop() {
  if (this.riderTimer >= 0) { clearInterval(this.riderTimer); this.riderTimer = -1 }
}

// UI: Stack 轨道 + 进度条 + 图标 translate
Stack({ alignContent: Alignment.Start }) {
  Row().width('100%').height(6).backgroundColor(COLORS.DIVIDER)
  Row().width(`${Math.round(this.riderProgress * 100)}%`).height(6).backgroundColor(COLORS.PRIMARY)
  Text('🛵').fontSize(20)
    .translate({ x: this.riderProgress * (this.trackWidth - 30) })
    .animation({ duration: 250, curve: Curve.Linear })
}
```

生命周期:aboutToAppear 启动,aboutToDisappear 停止。

## 四、LoadingIndicator 组件(统一加载态)

- 文件:`entry/src/main/ets/components/LoadingIndicator.ets`
- 用法:覆盖层 + `LoadingIndicator({ text: '支付处理中...' })`
- 原理:Circle 双环(外环 DIVIDER 色 + 内环 PRIMARY 色 strokeDashArray)+ setInterval 旋转 @State rotateAngle

## 五、服务层数据方法约定

所有数据访问必须经过 service 层,且带兜底:

```typescript
export function getAllStoresList(): StoreItem[] {
  return AppStorage.get<StoreItem[]>('allStores') || getStores()  // 必须 || 兜底
}
```

页面中 @StorageLink 数组字段默认值 `[]`,但读取时仍建议 `(this.xxx || [])` 兜底(防御 AppStorage 被置 null 的极端情况)。

## 六、构建错误定位流程

1. 构建失败 → 查看终端输出中的 `ERROR:` 块(ArkTS Compiler Error + 文件名:行:列)
2. 或查 `.hvigor/outputs/build-logs/build.log` 末尾(搜索 `ERROR` / `COMPILE RESULT:FAIL`)
3. WARN(ArkTS:WARN)均为提示级别(deprecated API 等),**不阻塞构建**,可暂不处理
4. 修复后重新构建,直到 `BUILD SUCCESSFUL`

