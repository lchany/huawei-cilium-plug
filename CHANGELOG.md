# HuaweiCloud Cilium Patch Changelog

## v1.1.2 - 2026-08-04

- HuaweiCloud gateway 静态邻居设置 `NUD_PERMANENT + NTF_EXT_LEARNED`。
- 新增当前 gateway 精确归属注册表，`NodeCleanNeighbors` 只保留当前仍使用的
  `(trunk interface, IPv4, MAC)` 表项。
- 修复 Agent 启动阶段 HuaweiCloud 静态邻居可能被通用邻居清理误删的问题。
- 相同 IP/MAC 的旧 permanent 表项自动补齐 `extern_learn`，MAC 冲突继续 fail-closed。
- Endpoint 删除或 gateway 变化后回收不再使用的 HuaweiCloud 标记表项。
- gateway 归属尚未初始化时拒绝执行 HuaweiCloud 启动邻居清理，避免启动顺序回归。
- 增加 registry、Endpoint 生命周期、两种邻居清理模式和特权内核测试。
- `0001`、`0002`、`0003` 保持不变，所有新增源码修改继续由 `0004` 承载。

## v1.1.1 - 2026-07-29

- 新增 `0004-huaweicloud-fixes.patch`。
- 优化 HuaweiCloud Sub-ENI 启动阶段 gateway 查询逻辑，改为批量查询。
- `series` 从 3 个 patch 扩展为 4 个 patch。
- README、INSTALL-DEPLOY 和 TEST-CASES 已同步更新。
- Gitee 同步使用功能型提交备注：`fix(huaweicloud): batch sub-eni gateway lookups`。

## v1.1.0 - 2026-07-15

- 初始 patch archive。
- 包含控制面、数据面和测试 3 个 patch。
