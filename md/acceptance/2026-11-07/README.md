# 2026-11-07 工程升级验收

当前完成开发与本机验收，用户已授权先更新文档、再推送 GitHub 和部署线上。本次提交、独立 CI、线上版本及检查结果须在实际完成后记录；历史发布与 CI 不代表本轮。

## 实现范围

Boot 4.0.9 / Spring 7.0.10 / Cloud 2025.1.4 / Java 25；保留现有 JSON/SDK、支付原始签名体、四端权限和交易事务。新增结构化私人手机号/地址/位置加密、可检索盲索引与旧数据回填，Flyway V1/V2 保留旧库升级能力；补齐跨服务和异步请求追踪、Redis Stream 未读/待确认保留、标准指标与可选监控、覆盖率和依赖/镜像门禁、只读数据库诊断。

## 本机实际结果

| 验证 | 结果 |
| --- | --- |
| 后端完整 clean verify | 802通过，0失败/错误/跳过 |
| 聚合行覆盖率 | 6773/9325，72.63%，门槛70% |
| Node与真实无头浏览器 | 226通过，0跳过 |
| API26 debug HAP | BUILD SUCCESSFUL，未签名，10465208字节 |
| 六项关键保护反向验证 | 六个独立副本分别产生业务断言失败，恢复后14项通过 |
| 双App + ERP + Gateway | 复用Boot3加密库及旧密钥；ERP授权200，跨服务失败400可关联，公开管理路径404 |
| 监控与接口 | 四个Prometheus目标可用，九面板健康，六条告警/四组正反场景通过，内部OpenAPI169路径 |
| 最终应用镜像Trivy0.76.2 | 可修复HIGH/CRITICAL为0，使用--ignore-unfixed，不覆盖所有级别/其他镜像 |

被测源码为 `d5aa3ebf7d548e57e5dfaf7f275c352b138e7635` 加开发工作区，不能仅用该HEAD代表本轮源码。源码快照SHA256为 `9592880a43c0df8e78d5efd30f1dea64361d52637460ec6a7548a7650fe17e0c`。镜像ID为 `sha256:05f88a355c10c82745d2f766bae7fdef225ce6b6b1c4323c0cac5786f761a52e`；未签名HAP SHA256为 `68E71AC3842FFAD38275F1AE30F8DEA44B32AA813F73CD410EB6431BAD7BDE12`。发布前文档更新不改变业务代码与该镜像。

## 复现与原始证据

仓库根目录设置JDK25、隔离MySQL/Redis和私有测试连接；设置 `TAKEOUT_MYSQL_CONCURRENCY_TEST=1`、`TAKEOUT_TEST_REDIS_PORT` 以及两把独立个人资料测试密钥，不连接线上数据库。

```powershell
mvn -f server/pom.xml --batch-mode --no-transfer-progress clean verify
python scripts/backend-evidence.py --since <开始Unix秒> --minimum-line-coverage 0.70 --output TemporaryCacheStorage/backend-summary.json
node --test scripts/*.test.cjs
```

Windows本轮执行入口和JDK域套接字TCP回退见本机 `TemporaryCacheStorage/deepseek-context/run-backend.ps1 -Full -LogName boot4-release`。真实无头浏览器测试需要已安装的Playwright/Chromium；HAP命令见根目录AGENTS.md。全量原始日志保留于本机同目录：`boot4-release.log`、`final-evidence.json`、`node-full.log`、`reverse-summary.json`、`hap-build.log`、`image-release-vulnerabilities.json`、`live-verification.json` 和 `delivery-manifest.json`。该目录被Git忽略，不将私有配置、数据库备份或原始业务数据上传公开仓库；恢复上下文见[开发草稿](../../开发草稿-2026-11-07.md)。

## 升级与真实边界

首次上线须备份主库、ERP库与原密钥，旧应用退出后再完成迁移，健康探针在回填完成前返回503。只补齐缺失的新加密/索引密钥，不替换已有钱包、AI、JWT、数据库或其他凭证；检索密钥需稳定保存。加密回填后不能直接让旧二进制读写新数据，回退须结合备份与新增业务核对。保留数据库、Redis、上传与备份卷，不导入本机演示数据。

无可用设备（hdc Empty），未运行本轮设备Hypium/UiTest；HAP未签名。真实外部支付/退款、邮件、物理GPS、长时间容量、独立托管CI尚未验收。告警未设置外部接收人，监控默认关闭；看板中的重启窗口和小负载不能作为容量成绩。上线验证只读，不在线上创建交易或进行破坏性反向测试。
