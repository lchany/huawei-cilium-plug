# 华为云 Cilium v1.19.1 实测结果

## 1. 结果说明

本文记录 `patch-archive/huaweicloud-v1.19.1` 的真实环境验证结果。测试方法以
`TEST-PLAN.md` 为准；未满足前置条件的场景明确标记为“未执行”，不能用代码审查或相邻
用例的结果代替。

- 源码提交：`592648fc`
- Agent 镜像 ID：`sha256:c23b2fd5ede62403cdbee32ac019413b3d577be1dd25aa50276b6171d46dd5b6`
- Agent 产物 SHA256：`cd67af56b62e1dc4eb755d57447b8e848a93b17c9f57391850f7557094d6e21d`
- 测试日期：2026-07-13
- 状态含义：通过、未通过、未执行

## 2. P0 功能测试

| 用例 | 状态 | 实际结果 |
| --- | --- | --- |
| HWC-P0-01 产物、架构与入口 | 通过 | SHA256、镜像架构、Agent 版本及 HuaweiCloud Operator 入口通过检查 |
| HWC-P0-02 Helm 与安装 | 通过 | lint、template、安装及滚动部署通过，系统组件 Ready |
| HWC-P0-03 节点初始化 | 通过 | 实例、VPC、可用区、trunk、子网及安全组字段完成逐节点核对 |
| HWC-P0-04 SubENI 分配 | 通过 | Pod、CiliumEndpoint、CiliumNode、VLAN/MAC 与云侧资源一致 |
| HWC-P0-05 同节点通信 | 通过 | ICMP、TCP 和 UDP 通过 |
| HWC-P0-06 跨节点通信 | 通过 | 双向 ICMP、TCP 和 UDP 通过；VLAN 入站与出站路径已验证 |
| HWC-P0-07 DNS/内外网 | 通过 | 集群内绝对域名、VPC 路径通过；上游 DNS 不可达被单独记录，未误判为集群 DNS 故障 |
| HWC-P0-08 Service | 通过 | ClusterIP、Headless、NodePort 和跨节点后端通过，EndpointSlice 正确 |
| HWC-P0-09 入站策略 | 通过 | 默认拒绝、精确放行和清理后恢复均符合预期 |
| HWC-P0-10 出站策略 | 通过 | DNS、指定 Pod/端口放行成功，未授权目标被拒绝且可观测 |
| HWC-P0-11 BPF map | 通过 | 测试 Pod 在两张 map 中均有一致的 IP、VLAN、MAC 和 endpoint ID |
| HWC-P0-12 删除清理 | 通过 | Pod IP 从 endpoint、used 状态和两张 map 清除，预分配池正常保留 |
| HWC-P0-13 批量与唯一性 | 通过 | 并发 Pod 全部 Ready，IP 全部唯一；缩容后占用全部清除 |
| HWC-P0-14 子网 ID | 通过 | 实际分配仅来自显式配置子网 |
| HWC-P0-15 子网标签 | 未执行 | 当前环境未准备带唯一测试标签的对照子网，不能仅凭单元测试判定通过 |
| HWC-P0-16 安全组选择 | 部分通过 | 显式安全组及允许/拒绝流量通过；标签安全组和云默认分支未执行 |

## 3. P1 可靠性测试

| 用例 | 状态 | 实际结果 |
| --- | --- | --- |
| HWC-P1-01 Agent 重启 | 通过 | 持续 Service 请求无失败，endpoint 与 BPF map 自动恢复 |
| HWC-P1-02 Operator 切换 | 通过 | 副本恢复，状态重新同步，无重复分配 |
| HWC-P1-03 节点重启 | 通过 | 节点经历 NotReady/Ready；Agent、Pod、used 状态和 BPF map 恢复一致 |
| HWC-P1-04 错误凭证 | 未执行 | 尚未进入受控凭证故障窗口 |
| HWC-P1-05 API 短时不可达 | 未执行 | 尚未配置只影响 Operator 的隔离阻断规则 |
| HWC-P1-06 子网不足回退 | 未执行 | 缺少容量可控的隔离候选子网 |
| HWC-P1-07 全部子网耗尽 | 未执行 | 缺少可安全耗尽的隔离子网 |
| HWC-P1-08 实例配额上限 | 通过 | 达到实例 SubENI 上限时 Pod 明确等待，未超配、未产生半资源；恢复容量后成功 |
| HWC-P1-09 事务回滚 | 未执行 | 尚未准备云 API 中途失败注入条件 |
| HWC-P1-10 状态漂移 | 未执行 | 尚未准备可安全修改的隔离云资源 |
| HWC-P1-11 空闲保留 | 通过 | 缩容后 used 清除，再扩容复用大部分预分配地址，恢复时间稳定 |
| HWC-P1-12 空闲回收 | 未执行 | 当前配置未启用 `releaseExcessIPs`，避免改变共享测试基线 |
| HWC-P1-13 CNI 失败清理 | 部分通过 | 无 IP 时 CNI ADD 明确失败且无半写入；ADD 后 sandbox 中断分支未执行 |
| HWC-P1-14 MTU | 通过 | MTU 内跨节点报文零丢包；DF 超限报文按预期被拒绝 |
| HWC-P1-15 滚动升级 | 部分通过 | 当前版本镜像滚动期间连续请求通过；从旧版本开始的完整升级未执行 |
| HWC-P1-16 Helm 回滚 | 未执行 | 尚未建立可回滚的旧版本基线 revision |
| HWC-P1-17 节点排空 | 通过 | 容量充足部分成功迁移；容量不足错误明确；恢复调度后全部自动收敛 |
| HWC-P1-18 可观测性 | 部分通过 | policy deny、IP 配额不足和 BPF drop 可定位；凭证、无匹配子网分支未执行 |

## 4. P2 性能与长稳测试

P2 尚未完成正式基线。当前仅取得以下短时数据，不替代 P2 验收：

- 一轮批量 Pod 从创建到全部 Ready 约 5 秒；
- 缩容后再次扩容约 5 秒，20 个地址中复用 17 个；
- MTU 内跨节点 ICMP 样本为 0% 丢包；
- Agent 重启期间 120 次一秒间隔 ClusterIP 请求全部成功。

吞吐、P50/P95/P99、长时间稳定性、高频扩缩容和 API 限流仍需专门测试窗口。

## 5. 已验证修复

1. 线内 VLAN 与 VLAN metadata 并存时不再重复处理，跨节点 ICMP/TCP/UDP 恢复。
2. BPF 使用实际挂载网卡 ifindex，非 KPR native-routing 路径正常执行 SubENI 处理。
3. CNI NetConf 中 HuaweiCloud 子网标签能够写入 CiliumNode；代码和补丁从零应用测试通过，真实标签子网选择仍按 P0-15 单独验收。
4. Pod 删除后 `status.ipam.used` 不再保留旧键；真实删除、批量缩容、节点恢复和命名空间清理均通过。

详细现象、根因、修复和验证命令见 `TROUBLESHOOTING.md`。

## 6. 清理结果

- 服务、策略和批量测试命名空间在对应场景结束后删除；
- 测试 Pod IP 已从 `status.ipam.used` 和 HuaweiCloud BPF map 清除；
- 被排空节点已恢复可调度；
- 节点、Cilium Agent、Operator 和 CoreDNS 恢复 Ready；
- 未遗留错误凭证、临时安全组或 API 阻断规则。

## 7. 当前结论

已执行的 P0/P1 场景通过，已发现的源码缺陷均已修复并完成针对性实测。但完整发布验收尚
不能判定通过：子网标签/优先级、安全组标签与默认分支、受控云 API 故障、回收策略、完整
升级回滚以及 P2 长稳/性能仍缺少真实环境证据。后续执行时必须继续使用本表逐项补齐，不能
把“未执行”改写为“通过”。
