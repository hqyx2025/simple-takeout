---
name: harmonyos-testing
description: 鸿蒙HarmonyOS应用测试与质量保障技能，覆盖Hypium单元测试（Local/Instrument）、UI自动化测试（UiTest Driver）、Code Linter静态检查、AppAnalyzer体检工具与上架前质量自检。当需要编写测试用例、修复质量告警或准备上架质量材料时使用。
---

# HarmonyOS 测试与质量保障

## 测试体系概览（测试金字塔）

| 层级 | 目录 | 运行环境 | 成本 | 场景 |
|---|---|---|---|---|
| Local Test 单元测试 | `src/test/` | 无需设备 | 低 | 纯逻辑：金额计算、状态流转、数据归一化 |
| Instrument Test 仪器测试 | `src/ohosTest/` | 设备/模拟器 | 中 | 依赖系统能力：持久化、路由、组件行为 |
| UI 自动化测试 | `src/ohosTest/` + Hypium UiTest | 设备/模拟器 | 高 | 端到端：登录→下单→接单→评价全链路 |

> 测试金字塔：底层单元测试最多最快最便宜，UI 测试少量覆盖关键链路。

## 一、Hypium 单元测试框架

### 1. 基础结构（describe / it / expect 三要素）

```typescript
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';

export default function orderTest() {
  describe('orderTest', () => {
    beforeAll(() => { /* 套件开始前执行一次 */ });
    beforeEach(() => { /* 每条用例前执行 */ });
    afterEach(() => { /* 每条用例后清理 */ });
    afterAll(() => { /* 套件结束后清理 */ });

    it('calculateTotal', 0, () => {
      expect(calc(100, 10, 20)).assertEqual(90);  // 100 + 10 - 20 = 90
    });
  });
}
```

### 2. 常用断言

- `assertEqual(expected)` / `assertNotEqual`：相等/不相等
- `assertTrue` / `assertFalse`：布尔
- `assertContain(item)`：数组/字符串包含
- `assertNull` / `assertNotNull`：空判断
- `assertLarger` / `assertLess`：数值比较

### 3. 测试入口聚合（List.test.ets 模式）

```typescript
import localUnitTest from './LocalUnit.test';
import orderTest from './Order.test';
import couponTest from './Coupon.test';

export default function testsuite() {
  localUnitTest();
  orderTest();
  couponTest();
}
```

### 4. 项目中的可测纯逻辑（建议优先覆盖）

- `AppStorageManager`：金额计算（`calcTotal` 类）、优惠券抵扣、订单状态流转校验
- `DataPersistence.normalizeData`：旧数据归一化兜底（防启动崩溃的关键逻辑）
- `MockDataService`：数据完整性（每类 30 条、字段非空、ID 唯一）
- `Constants`：订单状态码映射、时间格式化
- 登录校验：账号密码规则、角色判断

## 二、UI 自动化测试（Hypium UiTest）

```typescript
import { Driver, ON, Component } from '@kit.UiTestKit';

it('loginFlow', 0, async () => {
  const driver: Driver = await Driver.create();
  // 查找控件：ON 匹配器（id/text/type 组合）
  await driver.findComponent(ON.text('登录')).click();
  // 输入文本
  await driver.findComponent(ON.type('TextInput')).text('13800138000');
  // 等待与断言
  await driver.delayMs(500);
  const comp: Component = await driver.findComponent(ON.text('美食家小张'));
  expect(comp !== undefined).assertTrue();
});
```

注意：Instrument/UI 测试运行在 `ohosTest` 模块，`src/ohosTest/module.json5` 中也需声明被测功能所需权限。

## 三、Code Linter 静态检查

- 位置：DevEco Studio 菜单 **Code → Inspect Code**（或分析入口）
- 作用：不运行程序，检查语法、结构、逻辑缺陷；支持自定义规则（项目 `code-linter.json5`）
- 要求：**ERROR 级别问题必须清零**；WARN 级别（deprecated API 等）可暂缓但应记录
- 与构建的关系：Linter 通过 ≠ 构建通过，两者都要做

## 四、AppAnalyzer 应用体检（上架前必做）

DevEco Studio：**Tools → AppAnalyzer**，三种体检模式：

| 模式 | 用途 |
|---|---|
| 规则体检 | 按兼容性/性能/最佳实践规则自选检测 |
| 场景化体检 | 基于实际场景对特定页面检测，输出优化指引 |
| 上架前体检 | 检测上架阻塞问题，结果可上传供市场审核参考 |

## 五、专项质量（上架审核六大核心）

上架审核关注：**兼容性、稳定性、性能、功耗、安全、UX**。提交前自检：

1. **稳定性**：连续操作不崩溃、内存不持续增长、无 ANR/闪退
2. **兼容性**：不同分辨率/折叠屏适配，深色模式不花屏
3. **性能**：首屏 <2s、列表滚动 60fps
4. **功耗**：无后台持续定位/无循环动画空转（本项目定位为 inuse 时使用）
5. **安全**：不存明文密码、无危险权限
6. **UX**：空态/加载态/错误提示齐全、返回键行为正确

## 六、测试执行方式

```bash
# Local Test（无需设备，命令行可跑）
# DevEco Studio: 在 test 目录右键 Run 或配置 Test Runner
```

- 修改测试代码后重新运行；断言失败先检查被测逻辑还是测试数据
- Mock 数据项目：测试数据从 `MockDataService` 取，测试不依赖页面

## 七、本项目质量门禁（每个迭代必须满足）

- [ ] 核心纯逻辑（金额/状态流转/归一化）有单元测试覆盖
- [ ] Code Linter 无 ERROR 级别告警
- [ ] 构建 BUILD SUCCESSFUL
- [ ] 全链路手工冒烟通过（登录→点单→下单→商户接单→配送→完成→评价）
- [ ] AppAnalyzer 上架前体检无阻塞项
