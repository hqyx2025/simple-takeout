# Tasks

> **Git 规范**：每完成一个 SubTask 必须提交并推送到 Gitee（`https://gitee.com/pengzhiqiang87/simple-takeout.git`）。Commit Message 格式：`<type>(<scope>): <描述>`。
> **迭代规范**：每个迭代执行 规划→开发→验证→体检→收尾 五步，详见 spec.md。

## 阶段十一：质量加固（Testing & Quality）
- [ ] Task 22: 单元测试补齐（Local Test，`src/test/`）
  - [ ] SubTask 22.1: 金额计算测试（商品总价+配送费-优惠=实付，含无券/门槛边界）
  - [ ] SubTask 22.2: 订单状态流转测试（0→1→2→3→4，含取消5/退款6分支）
  - [ ] SubTask 22.3: normalizeData 归一化测试（缺字段/非对象/空数组回退默认值不崩溃）
  - [ ] SubTask 22.4: MockDataService 数据完整性测试（数量/字段非空/ID 唯一）
  - [ ] SubTask 22.5: 登录校验测试（正确/错误密码、角色、注册重名）
- [ ] Task 23: 静态检查与告警清理
  - [ ] SubTask 23.1: Code Linter 运行并清理 ERROR 级别问题
  - [ ] SubTask 23.2: WARN 级别记录与处理（deprecated API 替换）

## 阶段十二：上架准备（Release Ready）
- [ ] Task 24: 上架材料与配置
  - [ ] SubTask 24.1: 完善 AppScope/app.json5 版本信息（vendor、版本号）
  - [ ] SubTask 24.2: bundleName 与 AGC 应用包名一致性确认
  - [ ] SubTask 24.3: 权限收敛（module.json5 reason/usedScene 核对）
- [ ] Task 25: 隐私合规
  - [ ] SubTask 25.1: 隐私政策展示页（SettingsPage 入口 + 全文）
  - [ ] SubTask 25.2: 首次启动隐私弹窗（同意记录到 preferences）
  - [ ] SubTask 25.3: 隐私政策网页版（可公网访问，供 AGC 填写）
- [ ] Task 26: 发布签名与构建
  - [ ] SubTask 26.1: 生成密钥 .p12/.csr，申请发布证书 .cer 与 Profile .p7b
  - [ ] SubTask 26.2: Signing Configs 配置（SHA256withECDSA）
  - [ ] SubTask 26.3: Build APP(s) 构建带签名 Release 包并真机冒烟
- [ ] Task 27: 上架自检
  - [ ] SubTask 27.1: AppAnalyzer 上架前体检，修复阻塞项
  - [ ] SubTask 27.2: 发布技能 Checklist 逐项确认（软著/备案/隐私/截图/图标）

## 阶段十三：性能优化落地（Performance）
- [ ] Task 28: 长列表懒加载改造
  - [ ] SubTask 28.1: 首页店铺列表 ForEach → LazyForEach + IDataSource + cachedCount
  - [ ] SubTask 28.2: 订单/搜索/优惠券/评价列表同规格改造
  - [ ] SubTask 28.3: 列表项组件加 @Reusable（aboutToReuse 重置状态）
- [ ] Task 29: 状态与动画优化
  - [ ] SubTask 29.1: 状态拆分（局部状态不下沉 AppStorage）
  - [ ] SubTask 29.2: 动画统一 animateTo/transition，无逐帧驱动
  - [ ] SubTask 29.3: Profiler 抽测首页/订单列表帧率

## 阶段十四：体验与细节打磨（Polish）
- [ ] Task 30: 交互细节
  - [ ] SubTask 30.1: 空态/加载态/错误提示统一
  - [ ] SubTask 30.2: 返回键/手势行为检查
  - [ ] SubTask 30.3: 深色模式适配检查
- [ ] Task 31: 数据健壮性
  - [ ] SubTask 31.1: 持久化版本迁移机制（version 字段 + 迁移函数）
  - [ ] SubTask 31.2: 极端数据模拟验证（空 items/余额不足/券过期）

# Task Dependencies
- Task 22-23（质量加固）不依赖其他任务，可与业务并行，最先执行
- Task 24-27（上架准备）依赖 Task 22-23（质量达标才能发布）
- Task 28-29（性能优化）依赖业务功能稳定，可在 Task 22 后并行
- Task 30-31（打磨）依赖全部功能冻结后执行
