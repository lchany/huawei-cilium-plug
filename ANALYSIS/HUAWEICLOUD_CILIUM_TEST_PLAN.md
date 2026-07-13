# HuaweiCloud Cilium v1.12.19 补充测试计划

## 1. 目的与结论

本计划以当前 patch 归档中的 `INSTALL-DEPLOY.md`、7 个 patch、现有 Go 测试和
`test/hwc-real-e2e/netprobe.go` 为依据，补齐客户现有部署验收方案未覆盖或覆盖较弱的部分。

当前方案已经覆盖构建、镜像检查、Helm 部署、基础就绪检查，以及 Pod 的 SubENI、Service、
DNS、NetworkPolicy 和公网访问方向；但代码改动涉及完整的云 API、IPAM 生命周期、
CiliumNode 状态同步、BPF map、VLAN 数据面和异常恢复，现有自动化测试只有 9 个主要用例，
不足以支撑生产验收。建议先完成 P0，再进行客户环境验收；P1 在发布前完成，P2 可进入后续
稳定性迭代。

> 范围说明：仓库是 patch 归档，不是完整 Cilium 源码。单元/集成测试需要把 `series` 应用到
> 固定基线 `a1d7fbd43b563c809330b1c3e28165a3e7ff43aa` 后执行。

## 2. 已有测试基线

### 2.1 已有自动化覆盖

| 模块 | 已有验证 |
| --- | --- |
| Agent 路由兼容 | HuaweiCloud 使用 egress multi-home 规则 |
| 子网选择 | 未知容量可选；标签筛选；显式 subnet ID 优先 |
| 安全组 | 未显式配置时继承 trunk port 安全组 |
| IP 回收 | 回收候选顺序稳定 |
| BPF map | 第二张 map 写失败时回滚第一张 map |
| VPC CIDR | 主/辅助 CIDR 解析，忽略非法辅助 CIDR |
| 配置安全 | AK/SK 参数标记为敏感参数 |
| CNI 配置 | 单文件、conflist 解析 subnet tags；CNI/Agent 字段合并 |
| 构建产物 | Agent/Operator 镜像构建、导出及 Operator 两个命令路径验证 |

### 2.2 客户方案已有现场验收

- Kubernetes、DaemonSet、Operator 和 Cilium 状态就绪。
- CiliumNode 创建及 HuaweiCloud 配置下发。
- Operator 日志中 AK/SK 脱敏。
- 出口 SNAT 规则与 trunk 网卡、VPC CIDR 一致。
- 普通 Pod 的 SubENI IP、ClusterIP Service、DNS、NetworkPolicy 和公网访问。

## 3. 代码风险与待补测试

### P0：客户测试前必须完成

| ID | 测试项 | 核心场景和断言 | 对应代码 |
| --- | --- | --- | --- |
| P0-01 | Patch 可重放与全量定向测试 | 在干净固定基线上依次应用 7 个 patch；`series` 全部成功；工作树无意外修改；执行 HuaweiCloud、IPAM、Operator、CNI、node discovery、daemon 定向测试 | `apply.sh`、`series`、`build-local.sh` |
| P0-02 | 云 API 正常与失败路径 | Create/BatchCreate/Get/List/Delete/Tag SubENI；分页 marker；等待 Active；超时、404、限流、5xx、鉴权失败；batch 部分成功时回滚；错误码标准化 | `pkg/huaweicloud/api/api.go`、`error.go` |
| P0-03 | IPAM 分配生命周期 | 首次分配、批量分配、容量不足、跨 AZ/VPC 排除、无可用子网、显式安全组/标签安全组/继承 trunk 三种路径；CiliumNode status 与云端一致 | `pkg/huaweicloud/eni/node.go`、`instances.go` |
| P0-04 | IP 释放与回收安全 | `releaseExcessIPs=false` 不删除；开启后只释放空闲 SubENI；延迟窗口；已被 Pod 使用的 IP 永不释放；Delete API 失败可重试且状态不丢；连续调谐幂等 | `pkg/huaweicloud/eni/node.go` |
| P0-05 | 子网标签完整矩阵 | 单标签、多标签 AND、无匹配、空标签、标签值为空、同标签跨 VPC/AZ、容量不足；ID 与标签并存时始终 ID 优先；多个合格子网的选择策略稳定 | `instances.go`、`0006` |
| P0-06 | CNI/Agent 配置优先级 | Agent-only、CNI-only、字段级合并、空值不覆盖、`.conf`、`.conflist`、错误 JSON、错误字段类型；滚动重启后 CiliumNode 中值正确 | `plugins/cilium-cni/types`、`pkg/nodediscovery` |
| P0-07 | BPF map 生命周期 | endpoint create/restore/delete；两张 map 成功写入；第一/第二张写失败；旧值存在/不存在时回滚；重复事件幂等；非法 IPv4、MAC、VLAN、ifindex；map reopen/close | `pkg/huaweicloud/subenimap/manager.go`、`endpointmanager/huaweicloud_subeni.go` |
| P0-08 | VLAN 数据面双向通信 | 同节点 Pod↔Pod、跨节点 Pod↔Pod、Pod↔Node、Pod↔ClusterIP、Pod↔外网；抓包确认入方向去 VLAN、出方向添加正确 VLAN/MAC；无策略与有策略均验证 | `bpf/lib/huaweicloud.h`、`bpf_host.c` |
| P0-09 | NetworkPolicy 回归 | 默认拒绝、L3/L4 allow、跨节点 allow/deny、Service 后端策略、策略增删即时生效；确认 VLAN 处理未绕过 conntrack/policy | HuaweiCloud BPF 接线及 Cilium 原生 policy |
| P0-10 | Operator 镜像启动契约 | Config.Cmd 精确为 `/usr/bin/cilium-operator`；通用和 variant 二进制均存在并可启动；Helm 渲染命令与镜像内路径一致；容器重启无 `${OPERATOR_VARIANT}` | `0004`、`0005`、Helm deployment |
| P0-11 | 凭据与日志安全 | Helm Secret 正确引用；启动参数、配置打印、错误日志、panic 日志均不出现 AK/SK；日志采集侧再扫描一次；无密 values 可提交、有密文件权限 0600 | Operator flags、Secret、`pkg/option/config.go` |
| P0-12 | 基础回归 | Cilium upstream 与本改动相关的 IPAM、CNI、datapath、endpoint restore、iptables/masquerade 测试无回归；集群重启后现有 Pod 网络恢复 | 被修改的 upstream 模块 |

### P1：发布前完成

| ID | 测试项 | 核心场景和断言 |
| --- | --- | --- |
| P1-01 | 节点重启/Agent 重启 | 重启 Cilium Agent、Operator、kubelet、节点；SubENI 不重复创建，BPF map 和邻居项恢复，存量 Pod 通信恢复 |
| P1-02 | 云 API 短时故障 | 注入超时、429、5xx、网络断开；调谐退避合理，恢复后自动收敛，不泄漏 SubENI |
| P1-03 | Operator 主备/重复事件 | Operator 重启或重新选主；重复 CiliumNode 事件、乱序事件不会重复创建/错误删除资源 |
| P1-04 | 容量与边界 | 单节点达到 flavor SubENI 上限、子网剩余 0/1/N、批量申请边界、大规模 Pod burst；失败信息明确，已有 Pod 不受影响 |
| P1-05 | 多节点/多 AZ | 至少 3 节点、2 AZ；每节点只选本 VPC/本 AZ 子网；跨 AZ Service、策略和 DNS 正常 |
| P1-06 | 多网卡 trunk 识别 | 默认路由网卡不是 trunk、metadata 多端口、MAC 对不上、trunk 缺失；错误时 fail-fast，不误操作其他端口 |
| P1-07 | 安全组变化 | 显式 ID、标签选择、继承 trunk；运行中变更安全组后新旧 SubENI 行为符合设计，错误安全组不导致越权放通 |
| P1-08 | Service 类型矩阵 | ClusterIP、NodePort、ExternalIP/LoadBalancer（客户环境支持时）、session affinity；TCP/UDP 分别验证 |
| P1-09 | MTU/分片/长连接 | 小包、接近 MTU、超 MTU、TCP 长连接、并发短连接；无异常丢包、重传或 VLAN 处理错误 |
| P1-10 | 升级/回滚 | 原生 v1.12.19→HuaweiCloud patch、同版本镜像滚动升级、回滚；CRD 字段兼容，存量 CiliumNode/Pod 不丢失 |

### P2：稳定性与长期质量

- 24～72 小时稳定性：持续创建/删除 Pod、策略变更、Service 访问，监控 SubENI 泄漏、
  goroutine、内存、BPF map 容量和 API 错误率。
- 压力：并发 Pod burst、最大节点规模、最大 SubENI 数、Operator 队列积压与收敛时间。
- 性能对比：与未打 patch 的 v1.12.19 基线比较 Pod 创建延迟、吞吐、P99 RTT、CPU 和内存。
- 混沌：随机重启 Agent/Operator、短时断云 API、节点网络抖动、API 限流。
- IPv6 明确性：当前实现以 IPv4/SubENI 为主，应验证 IPv6 配置被明确拒绝或不影响 IPv4，
  避免“配置成功但实际不可用”。

## 4. 分阶段执行计划

### 阶段 A：源码与静态检查（0.5 天）

1. 在挂载盘准备 upstream 固定基线，运行 `apply.sh`。
2. 记录 patch 后 commit、`git status` 和 `git diff --check`。
3. 运行 `go vet`/定向静态检查，并检查新增代码中的错误吞掉、无 context 超时、敏感日志。
4. 输出变更模块—测试用例映射表。

退出条件：7 个 patch 可重复应用，代码格式/静态检查无阻断问题。

### 阶段 B：单元与组件测试（2～3 天）

1. 先执行现有测试，建立结果基线。
2. 优先补 P0-02～P0-07、P0-10、P0-11。
3. 对云 API 使用 fake HTTP server，对调谐逻辑使用已有 mock API，对 BPF map 使用内存 backend。
4. 对新增/修改包采集覆盖率；关键分支目标不低于 80%，云资源删除和回滚路径必须逐分支覆盖。

退出条件：所有定向测试通过；关键失败/回滚路径有断言；无敏感信息输出。

### 阶段 C：构建、镜像与 Helm（0.5～1 天）

1. 执行 `build-local.sh`，确认 `build.status=SUCCESS` 和两份镜像 SHA256。
2. 检查镜像架构、用户、Cmd、两个 Operator 二进制和 Agent/CNI 二进制。
3. 对示例 values 执行 `helm lint`、`helm template`，覆盖 subnet ID、subnet tags、二者并存、
   空配置和错误 repository 五组 values。

退出条件：镜像可重复构建；Helm 渲染结果与配置优先级、启动命令一致。

### 阶段 D：华为云功能 E2E（2～3 天）

1. 使用至少 2 节点，尽可能覆盖 2 AZ；记录 VPC、子网标签、trunk 端口和安全组的脱敏信息。
2. 先执行客户已有就绪、SubENI、Service、DNS、NetworkPolicy、公网用例。
3. 补 P0-08、P0-09、P0-12，以及 P1 的多节点、重启、容量、Service 和 MTU 用例。
4. 每个网络用例同时保存：Pod/Node 地址、CiliumNode 摘要、BPF map 摘要、tcpdump 证据和结果。

退出条件：P0 全通过；无资源泄漏；失败用例已定位或明确阻断发布。

### 阶段 E：稳定性与报告（1～3 天）

1. 执行最少 24 小时 churn；生产发布建议 72 小时。
2. 汇总通过率、遗留问题、性能对比、资源泄漏检查及回滚演练。
3. 给每个问题标注严重级别、复现步骤、影响范围和是否阻断发布。

## 5. 推荐命令基线

在应用 patch 后的完整 Cilium 源码树执行：

```bash
go test -mod=vendor ./pkg/huaweicloud/...
go test -mod=vendor -tags=ipam_provider_huaweicloud ./pkg/ipam/... ./operator/...
go test -mod=vendor ./pkg/nodediscovery/... ./plugins/cilium-cni/types/...
go test -mod=vendor ./daemon/cmd/... ./pkg/option/...

go test -mod=vendor -coverprofile=coverage-huaweicloud.out ./pkg/huaweicloud/...
go tool cover -func=coverage-huaweicloud.out
```

测试命令需要按 Cilium v1.12.19 的实际 build tags 调整；首次失败时先判断是环境/历史基线
问题还是 HuaweiCloud patch 回归，不能直接删除失败包。

## 6. E2E 核心矩阵

| 维度 | 最小覆盖集合 |
| --- | --- |
| 拓扑 | 同节点、跨节点；条件允许时跨 AZ |
| 地址选择 | subnet ID、单标签、多标签、ID+标签、无匹配 |
| 协议 | ICMP、TCP、UDP、DNS |
| 目的地 | Pod、Node、ClusterIP、NodePort、VPC 内网、公网 |
| 策略 | 无策略、默认拒绝、允许、动态增删 |
| 生命周期 | 新建、删除、重建、Agent 重启、Operator 重启、Node 重启 |
| 故障 | API 超时/429/5xx、子网耗尽、权限不足、错误 trunk、安全组错误 |

## 7. 结果记录与发布门禁

每个用例至少记录：用例 ID、环境、前置条件、步骤、预期、实际结果、开始/结束时间、证据路径、
资源清理结果和缺陷链接。日志必须脱敏，不保存 AK/SK 或 Helm Secret。

发布门禁：

- P0 用例通过率 100%，不存在未解决的致命/严重缺陷。
- P1 若未完成或失败，必须有客户认可的风险说明和回滚方案。
- 无 SubENI、端口、IP、BPF map 条目或 Kubernetes 资源泄漏。
- 镜像 digest、patch commit、values 摘要和测试报告可追溯。
- 回滚演练成功，存量 Pod 网络恢复时间满足客户要求。

## 8. 当前阻塞与所需输入

- 缺少独立的“客户测试方案”附件；本计划暂以仓库 `INSTALL-DEPLOY.md` 第 10 节作为客户
  现有验收基线。如客户另有 Excel/Word/Markdown 用例，需要再做逐条去重和差距映射。
- 真机 E2E 需要华为云 Kubernetes 集群、支持 SubENI 的 ECS、VPC/子网/安全组及脱敏后的
  环境标识；凭据不得写入本文或 Git。
- 当前仓库只有 patch，执行测试前还需准备固定基线的完整 Cilium 源码树。
