# 脚本说明

| 脚本 | 用途 | 前置条件 / 产物 |
| --- | --- | --- |
| `device-uitest.ps1`、`device-test.ps1` | 构建、安装并运行设备 UiTest | DevEco Studio、hdc、已连接设备；日志写入 `TemporaryCacheStorage/` |
| `device-checkout-regression.ps1`、`device-merchant-regression.ps1`、`device-review-regression.ps1`、`device-role-regression.ps1`、`rider-chain-regression.ps1` | 四端设备链路回归 | 已启动后端和设备；截图/日志写入 `TemporaryCacheStorage/` |
| `build-release.ps1`、`enable-release-signing.ps1`、`release-check.ps1` | Release 构建与签名检查 | `DEVECO_HOME` 或默认 DevEco 安装目录；报告为生成物 |
| `acceptance-performance.py` | 只读 API 性能验收 | Python 3 标准库；`TAKEOUT_PERF_TOKEN`；报告写入 `TemporaryCacheStorage/performance/` |
| `*.test.cjs`、`check-*.cjs` | ArkTS/界面静态检查 | Node.js 与 DevEco TypeScript；使用 `DEVECO_HOME` / `DEVECO_SDK_HOME` |
| `export-database.ps1`、`start-alipay-sandbox.ps1` | 数据导出与沙箱辅助 | 本机 MySQL / 支付宝沙箱配置 |

脚本默认从 `DEVECO_HOME` 读取 DevEco Studio 根目录；未设置时使用 `C:\Program Files\Huawei\DevEco Studio`。源码和 PowerShell 脚本按 UTF-8 读写，临时文件不要写入仓库根目录。
