---
name: harmonyos-testing
description: 在简单外卖项目中运行或编写 HarmonyOS Hypium / UiTest 用例，诊断设备回归失败。
---

# HarmonyOS 相关验证

按改动运行现有构建与相关用例，日常修改无需创建测试计划、检查清单或执行上架体检。运行方法见 `md/设备实测指南.md`；脚本与用例才是实际入口。

- 前端必须确认 BUILD SUCCESSFUL 和 HAP 产物。设备未验证时如实报告，不以编译代替运行结论。
- 使用 `scripts/device-uitest.ps1 -Class <类名> -Build`，一次只跑一个类；根据用例注明的前置状态布置测试数据。清数据仅用于可重建的测试环境。
- 用例先调用 UiTestHelper.launchAppUnderTest，避免 TestAbility 遮住应用。
- findComponent/findComponents 未命中返回 null，使用 isFound / requireComponent；每次点击重新查找句柄。
- 优先 ID 或真实文本定位；屏外控件先 scrollUntilVisible，不能按整屏边界算坐标点击。
- 验证布局时检查浅色/深色、窄屏/展开屏、滚动和底部操作区，保留截图与日志到 TemporaryCacheStorage。
- 业务数据走真实服务或测试隔离实例，不能靠前端模拟数据宣称链路通过。
- Code Linter、AppAnalyzer、Release 签名仅在用户要求质量专项或发布时执行；IDE 工具不可用时说明限制。
