# 简单外卖：直接执行约定

## 工作方式

- 用户给出需求后，读取相关代码，直接实现、验证并交付结果。常规实现选择自行决定。
- 默认不生成计划、spec、tasks、checklist、ADR、会话记录或交接文档，不逐步等待确认。用户明确要求文档时再写。
- 仅在缺失信息阻止实现，或涉及当前授权外的不可逆操作时提问；其余工作继续完成。
- 不自动提交、推送、发布或部署；用户明确要求时执行。保留用户已有的工作区改动。
- 优先复用项目组件与平台能力，不引入无关依赖或架构迁移。简洁汇报结果、验证及真实限制。

## 工程与验证

- HarmonyOS NEXT ArkTS 严格模式，API 26；前端 `entry/`，Spring Boot / Java 25 后端 `server/`。
- 前端改动运行 debug HAP 构建，确认日志 `BUILD SUCCESSFUL` 和产物；后端改动运行相关 Maven 测试。
- DevEco 位于 `C:\Program Files\Huawei\DevEco Studio`。前端构建：
  ```powershell
  $env:DEVECO_SDK_HOME="C:\Program Files\Huawei\DevEco Studio\sdk"
  & "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --daemon
  ```
- 后端设置 `JAVA_HOME` 为 JDK 25，再运行 `mvn -f server/pom.xml test`；应用运行模块为 `takeout-app`，对外端口 8087，本机 MySQL / Redis 连接端口为 3310 / 6387。
- 设备可用时验证受影响页面；设备不可用如实说明。Code Linter / AppAnalyzer / Release 签名仅在相关任务中执行。
- 临时脚本、截图、日志放 `TemporaryCacheStorage/`；UTF-8 文件使用编辑工具或显式 UTF-8 读写，禁止 PowerShell 默认编码读写源码。`.ps1` 带 UTF-8 BOM。

## UI 基准

- 所有页面沿用登录页风格：暖白背景、深棕文字、陶橙强调、细描边、圆角卡片与控件；同步适配深色模式。
- 共享颜色与尺寸使用 `common/Constants.ets` / `common/theme/AppTheme.ets`；标题栏使用 `PageHeader`。
- 新绘图标、插图使用本地 SVG，保持同套线宽和配色；商品实拍图和用户上传图片保持真实内容。
- 路由统一使用 `UiNavigation` 的 `routerCompat`。保留页面标题、按钮含义、测试 ID、四端权限和业务交互。
- 页面采用“导航 + 可滚动主体（layoutWeight(1)）+ 底部操作区”，长内容不能挤掉提交按钮。
- 输入有标签和示例，操作有成功/失败反馈。共享错误只提示一次。管理端不展示用户端导航，退出登录置于底部。
- ArkTS 使用显式类型；`@CustomDialog` 声明 controller；避免 getter 驱动渲染和 ForEach 参数嵌套闭包；可选值用 `??`。

## 业务底线

- 服务端为业务数据权威，禁止前端模拟订单、余额、地址、优惠券；管理/商户/骑手/用户权限保持隔离。
- 下单为 status=0 待付款，支付后进入 1；状态 4 要结合 escrow 区分待确认与已完成，退款终态允许 status=6 / escrow=2。
- 资金、库存、状态更新保留事务、条件更新及幂等保护；多规格操作传 specId。
- 地址与缓存按账号隔离；隐私同意先落盘再恢复数据，401 清理登录态。

## 按需参考

- 业务、数据和疑难排错：[开发参考](md/开发参考.md)。只读与当前改动有关的章节。
- 设备运行方法：[设备实测指南](md/设备实测指南.md)。
- 完整资料索引见 README；`md/archive/` 的计划和记录仅作历史资料，不触发工作流。
