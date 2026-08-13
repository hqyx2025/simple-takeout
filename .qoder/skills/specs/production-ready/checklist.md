# Checklist

## 迭代规范检查（每个迭代）
- [ ] 已读取 `开发须知.md` 与相关 skill（arkts-takeout-dev / harmonyos-testing / arkts-performance-optimization / harmonyos-release-publish）
- [ ] 每完成一个 SubTask 已 commit 并 push 到 Gitee
- [x] 构建 `BUILD SUCCESSFUL` 后才标记任务完成（33.7 已验证）
- [ ] 迭代收尾更新了 spec.md / tasks.md / checklist.md

## 阶段十一：质量加固
- [ ] `src/test/` 存在金额计算测试（总价/配送费/优惠/实付，含边界）
- [ ] 存在订单状态流转测试（0→1→2→3→4，含取消/退款分支）
- [ ] 存在 normalizeData 归一化测试（脏数据不崩溃）
- [ ] 存在 Mock 数据完整性测试（数量/非空/ID 唯一）
- [ ] 存在登录校验测试（密码/角色/重名）
- [ ] Code Linter 无 ERROR 级别告警

## 阶段十二：上架准备
- [ ] AppScope/app.json5 版本信息完整（versionCode/versionName/vendor）
- [ ] bundleName 与 AGC 创建应用包名一致
- [ ] module.json5 权限有 reason 与 usedScene，无超范围权限
- [ ] 隐私政策展示页存在，设置页有入口
- [ ] 首次启动隐私弹窗实现，同意状态持久化
- [ ] 隐私政策网页版可公网访问
- [ ] 发布证书 .cer 与 Profile .p7b 已申请
- [ ] Signing Configs 已配置（SHA256withECDSA）
- [ ] Build APP(s) 产物为带签名 .app 且真机可安装
- [ ] AppAnalyzer 上架前体检无阻塞项
- [ ] 软著/备案/隐私/截图/图标材料清单齐全

## 阶段十三：性能优化
- [ ] 首页店铺列表使用 LazyForEach + IDataSource + cachedCount
- [ ] 订单/搜索/优惠券/评价列表均懒加载
- [ ] 列表项组件已加 @Reusable
- [ ] 数据增删后数据源已 notifyDataChanged
- [ ] 局部状态未下沉 AppStorage
- [ ] 无逐帧 @State 驱动动画（统一 animateTo/transition）
- [ ] Profiler 抽测首页/订单列表帧率 ≥50fps

## 阶段十四：体验与打磨
- [ ] 空态/加载态/错误提示全局统一
- [ ] 返回键/手势行为正确，子页面返回不丢状态
- [ ] 深色模式无明显花屏/对比度问题
- [ ] 持久化版本迁移机制存在（version + 迁移函数）
- [ ] 极端数据（空 items/余额不足/券过期）不崩溃

## 发布门禁（全部通过才可上架）
- [ ] Debug 全链路冒烟通过（登录→点单→下单→商户接单→配送→完成→评价）
- [ ] 单元测试全部通过
- [ ] Code Linter 无 ERROR
- [ ] 上架前体检无阻塞项
- [ ] 带签名 Release 包可安装真机
- [x] SubTask 33.8 定位选点体验已完成：系统定位开关提示、刷新地图、重新定位、确认位置
- [x] SubTask 33.9 定位结果竞态修复已完成：忽略默认地图中心，优先使用系统真实坐标
