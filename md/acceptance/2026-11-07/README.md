# 2026-11-07 工程升级验收

已按用户要求先更新文档，再推送GitHub并部署线上；运行源码 [`3ce067c`](https://github.com/hqyx2025/simple-takeout/commit/3ce067caaa5bdfd92cd1ff7f0822382deae7f6ab)，发布版本 `engineering-boot4-20261107-r1`，时间 **2026-11-07 17:15:33 +0800**。[线上入口](https://hqyx.website/takeout/) 已恢复并完成HTTP与真实浏览器核验；后续纯文档提交不改变运行代码。

## GitHub与线上验收

- [Backend CI](https://github.com/hqyx2025/simple-takeout/actions/runs/42358171295)：802通过，0失败/错误/跳过，覆盖率门禁通过，原始日志已留存。
- [Frontend CI](https://github.com/hqyx2025/simple-takeout/actions/runs/42358171300)：HAP构建与脚本检查通过；8项浏览器用例因缺Playwright跳过。本机相应用例已真实执行通过，不能把两种环境的结果混写。
- [Security CI](https://github.com/hqyx2025/simple-takeout/actions/runs/42359502871)：独立构建与镜像扫描已通过，使用CI配置修复提交 `d5c9700`，应用源码与被部署版本一致；下文本机实际被部署镜像的扫描记录另行保留。
- App、ERP、Gateway同镜像健康；3个JAR哈希匹配本机被测产物，8个HTTPS静态资源哈希匹配；14项授权只读检查通过，未登录ERP401，公网指标/内部接口/OpenAPI404。
- 540店目录正常；升级前后订单/账号/地址/商品等行数、库存及余额汇总一致，ERP业务汇总一致。私人资料回填完成、主库Flyway三条成功记录（含基线）、ERP版本V1；旧密钥、MySQL/Redis/上传/备份数据卷与博客实例保留。
- 切换前主库与ERP库备份完成，gzip完整性检查通过；原私有配置和实际旧容器配置已备份。新加密和索引密钥仅补缺，不公开。未在生产运行下单、支付、退款或破坏性测试。

本机原始发布证据：`TemporaryCacheStorage/deepseek-context/online-rollout.log`、`online-deployment-summary.json`、`online-public-checks.json`、`online-ci-evidence.json`、`online-*-logs.zip`、`online-home-verified.png`。服务器备份位于 `/srv/takeout-data/backups/engineering-boot4-20261107-r1-*-before.sql.gz` 和 `/etc/portfolio/backups/engineering-boot4-20261107-r1/`，这些私有文件不进入GitHub。部署摘要见[脱敏发布证据](release-summary.json)。

安全CI首轮 [42358171303](https://github.com/hqyx2025/simple-takeout/actions/runs/42358171303) 在镜像构建阶段失败：区域Maven镜像缺少 `micrometer-registry-prometheus:1.16.8`，当时未执行扫描。已在 `d5c9700` 将云端构建切到项目现有Maven Central配置，重跑完成真实构建与扫描；没有忽略漏洞、删除依赖或改变线上应用。首轮与通过轮日志均保留于本机证据目录。升级前后私有配置及双库恢复备份另已下载到访问受限且Git忽略的本机目录，哈希一致，未做恢复演练。

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

无可用设备（hdc Empty），未运行本轮设备Hypium/UiTest；HAP未签名。真实外部支付/退款、邮件、物理GPS、长时间容量尚未验收；GitHub Backend/Frontend结果及跳过项见上方，Security已通过。告警未设置外部接收人，监控默认关闭；看板中的重启窗口和小负载不能作为容量成绩。上线验证只读，不在线上创建交易或进行破坏性反向测试。
