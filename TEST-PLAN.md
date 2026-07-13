# HuaweiCloud Cilium v1.19.1 真实环境测试方案

本文用于验证 `patch-archive/huaweicloud-v1.19.1` 在华为云真实 Kubernetes 环境中的
功能、可靠性和可运维性。测试不绑定节点数量；执行时只要求场景所需的节点、可用区、
子网和安全组条件已满足。

## 1. 测试准入与结论规则

优先级定义：

| 优先级 | 含义 | 发布要求 |
|---|---|---|
| P0 | 安装、IPAM、数据面和策略核心路径 | 必须全部通过 |
| P1 | 故障恢复、资源回收、升级回滚 | 必须全部通过；无法执行时必须说明环境限制 |
| P2 | 性能、长稳和极限场景 | 记录基线，不得出现资源泄漏或不可恢复故障 |

最终结论只能是以下之一：

- **通过**：P0、P1 全部通过，P2 没有阻断性问题。
- **有条件通过**：P0 全部通过，未执行的 P1 有明确环境原因、风险和补测时间。
- **不通过**：任一 P0 失败，或出现 SubENI 泄漏、策略绕过、不可恢复网络中断。

## 2. 测试前准备

### 2.1 云资源条件

- ECS 已启用 trunk ENI/辅助弹性网卡能力。
- 测试 VPC 至少有可用于 Pod 的子网；测试子网与节点位于兼容的可用区。
- 准备可用安全组、错误安全组、带标签子网和不带匹配标签子网。
- 为子网耗尽/回退用例准备容量可控的隔离子网，不得使用业务子网制造故障。
- 测试账号具备查询 ECS/VPC/子网/安全组和创建、查询、删除 SubENI 的权限。
- 记录测试前已有 SubENI、端口和私网 IP，便于识别泄漏。

### 2.2 本地产物

```bash
export ARTIFACT_DIR=/home/lchych/leicheng/disk1/cilium-v1.19.1-huaweicloud/artifacts
cd "$ARTIFACT_DIR"
sha256sum -c SHA256SUMS
```

校验以下内容存在：

- `images/cilium-v1.19.1-huaweicloud-amd64.tar`
- `images/operator-huaweicloud-v1.19.1-huaweicloud-amd64.tar`
- `helm/cilium-1.19.1.tgz`
- `bin/cilium-agent`、`bin/cilium-cni`、`bin/cilium-operator-huaweicloud`

### 2.3 测试变量

```bash
export TEST_NS=hwc-e2e
export TRUNK_DEV=<实际 trunk 网卡名>
export VPC_CIDR=<VPC IPv4 CIDR>
export POD_SUBNET_ID=<Pod SubENI 子网 ID>
export POD_SECURITY_GROUP_ID=<Pod 安全组 ID>
export CILIUM_IMAGE=<镜像仓库>/cilium:v1.19.1-huaweicloud
export OPERATOR_IMAGE=<镜像仓库>/operator-huaweicloud:v1.19.1-huaweicloud
kubectl create namespace "$TEST_NS"
```

不要把 AK/SK 写入本文、测试日志、命令行历史或测试结果。凭证只通过 Kubernetes Secret
注入，结果归档前检查并脱敏。

### 2.4 统一取证

每个用例执行前后都记录时间。失败时至少收集：

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl get ciliumnodes -o yaml
kubectl -n kube-system logs -l k8s-app=cilium --all-containers --since=30m
kubectl -n kube-system logs -l io.cilium/app=operator --all-containers --since=30m
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
kubectl -n kube-system exec ds/cilium -- cilium-dbg endpoint list
kubectl -n kube-system exec ds/cilium -- cilium-dbg map list
kubectl get events -A --sort-by=.lastTimestamp
```

云侧同时记录 SubENI ID、父网卡 ID、IP、MAC、VLAN、子网、安全组、状态及创建时间。

## 3. P0 核心功能用例

### HWC-P0-01 产物、架构与启动入口

**目标**：确保交付产物可加载，架构正确，镜像包含预期程序。

**步骤**：

1. 执行 `sha256sum -c SHA256SUMS`。
2. 加载两个镜像 tar，执行 `docker image inspect`。
3. 在镜像中执行 `/usr/bin/cilium-agent --version`。
4. 在 Operator 镜像中执行 `/usr/bin/cilium-operator-huaweicloud --help`。

**预期**：校验全部成功；镜像为 `linux/amd64`；版本为 `1.19.1`；Operator 启动文件存在。

### HWC-P0-02 Helm 渲染与首次安装

**目标**：验证 Chart 能正确启用 HuaweiCloud IPAM。

**步骤**：

1. 按 `INSTALL-DEPLOY.md` 准备 Secret 和 values。
2. 执行 `helm lint`、`helm template`，检查镜像、`ipam.mode`、trunk 网卡和 Secret 引用。
3. 执行 `helm upgrade --install`。
4. 等待 Agent、Operator、CoreDNS 和节点全部 Ready。

**预期**：无渲染错误；Operator 运行 HuaweiCloud variant；所有 Agent Ready；无持续重启。

### HWC-P0-03 节点元数据与 CiliumNode 初始化

**目标**：验证 Metadata、ECS/VPC 信息和 trunk 端口发现。

**步骤**：

```bash
kubectl get ciliumnodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.huawei-cloud}{"\n"}{end}'
kubectl get ciliumnodes -o yaml
```

逐节点与云控制台/API 对比实例 ID、实例规格、VPC、可用区、trunk interface ID、子网和
安全组。

**预期**：字段非空且与云侧一致；无节点串用其他 VPC/可用区资源。

### HWC-P0-04 基础 Pod 创建与 SubENI 分配

**目标**：验证 Pod 创建触发 SubENI/IP 分配。

**步骤**：

1. 创建固定到目标节点的测试 Pod。
2. 等待 Pod Ready，记录 Pod IP。
3. 查询 `CiliumEndpoint`、`CiliumNode.status.huawei-cloud` 和云侧 SubENI。
4. 对比 IP、MAC、VLAN、CIDR、网关、父网卡、子网和安全组。

**预期**：各层字段一一对应；Pod IP 属于目标子网；SubENI 绑定正确 trunk；无重复 IP。

### HWC-P0-05 同节点 Pod 通信

**目标**：验证本地 endpoint datapath 不受 SubENI 接入破坏。

**步骤**：在同一节点创建 client/server，分别测试 ICMP、TCP 和 UDP。

**预期**：三种协议均成功；Cilium endpoint 状态为 ready；无异常 drop。

### HWC-P0-06 跨节点 Pod 通信

**目标**：验证跨节点 SubENI VLAN 收发路径。

**步骤**：将 client/server 调度到不同节点，测试 ICMP、TCP、UDP 和双向主动建连。

**预期**：全部成功；抓包可看到 trunk 侧 VLAN；进入 Pod 前 VLAN 已被移除。

### HWC-P0-07 DNS、VPC 内网与公网访问

**目标**：验证真实业务常用出口路径。

**步骤**：从 Pod 查询 Kubernetes DNS，访问同 VPC 地址、跨子网地址和允许访问的公网
地址；记录源地址和回包。

**预期**：DNS 正常；内网路由正确；公网行为符合 masquerade 配置；无单向通或回包丢失。

### HWC-P0-08 Service 数据面

**目标**：验证 SubENI 模式与 Kubernetes Service 兼容。

**步骤**：部署多副本服务，测试 ClusterIP、Headless Service、NodePort（若启用）以及
后端跨节点时的访问；滚动删除后端并持续请求。

**预期**：Service 可达；后端切换期间无长期黑洞；EndpointSlice 更新正常。

### HWC-P0-09 NetworkPolicy 入方向

**目标**：确认去 VLAN 后仍进入 Cilium 原生 ingress policy。

**步骤**：

1. 无策略时验证 client 可访问 server。
2. 应用 server 默认拒绝 ingress，确认访问失败。
3. 仅放行指定 namespace/label 和端口，验证允许流量成功、其他流量失败。

**预期**：策略结果与规则完全一致；不得因 HuaweiCloud VLAN 路径绕过策略。

### HWC-P0-10 NetworkPolicy 出方向

**目标**：验证 endpoint egress policy 与 VLAN 封装顺序正确。

**步骤**：应用默认拒绝 egress，分别放行 DNS、指定 Pod、指定 CIDR/端口并逐项验证。

**预期**：允许流量正常封装发送；拒绝流量在 Cilium datapath 被丢弃并可观测。

### HWC-P0-11 双 BPF map 一致性

**目标**：验证 Pod IP 与 VLAN/MAC 映射完整且对称。

**步骤**：

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg map list
kubectl -n kube-system exec ds/cilium -- cilium-dbg map get cilium_hwc_srcip4
kubectl -n kube-system exec ds/cilium -- cilium-dbg map get cilium_hwc_vlan_mac
```

按测试 Pod 对比两张 map、CiliumEndpoint、CiliumNode 和云侧字段。

**预期**：每个 Ready Pod 都有对应条目；IP、VLAN、MAC 一致；无冲突和半写入状态。

### HWC-P0-12 Pod 删除与数据面清理

**目标**：验证 endpoint 删除时清理 BPF 条目和 IPAM 占用。

**步骤**：删除测试 Pod，持续观察 CiliumEndpoint、两张 BPF map、CiliumNode used 状态
和云侧 SubENI。

**预期**：endpoint 与两张 map 条目均删除；IP 不再标记已用；无残留网络命名空间状态。

### HWC-P0-13 批量创建与唯一性

**目标**：验证并发分配和水位线补充。

**步骤**：快速扩容 Deployment，使 Pod 分布到可调度节点；记录 Ready 时间、IP、SubENI
和创建错误；再缩容到零。

**预期**：Pod 最终全部 Ready；IP/SubENI 无重复；不超过实例动态配额；缩容后占用释放。

### HWC-P0-14 子网 ID 选择

**目标**：验证显式 `subnet-ids`。

**步骤**：配置一个或多个合法子网 ID，滚动重启 Agent，创建 Pod 并检查云侧 SubENI。

**预期**：只使用配置的子网；不会分配到未列出的子网。

### HWC-P0-15 子网标签选择与优先级

**目标**：验证 CNI NetConf 的 `huawei-cloud.subnet-tags` 真实生效。

**步骤**：

1. 为目标子网添加唯一测试标签，并确保另一个可用子网不含该标签。
2. 配置 `cni.customConf: true` 和正确的 `cni.readCniConf`，删除所有 `subnet-ids` 参数。
3. 分别使用独立 `.conf` 和包含 `cilium-cni` 插件的 `.conflist`，加入：

```json
"huawei-cloud": {
  "subnet-tags": {"network-role": "pod-test"}
}
```

4. 重启 Agent，确认 `CiliumNode.spec.huawei-cloud.subnet-tags`，再创建 Pod并核对云侧子网。
5. 同时删除 ID 和标签，确认 Agent 明确拒绝无约束子网选择。
6. 同时配置 `subnet-ids` 与不一致标签，验证显式 ID 优先。

**预期**：`.conf`、`.conflist` 仅标签配置均选择匹配子网；空配置失败且错误明确；同时
配置时按显式 ID；不匹配时不得静默选错子网。

### HWC-P0-16 安全组选择

**目标**：验证显式安全组、标签安全组和云默认行为。

**步骤**：分别测试 `security-group-ids`、`security-group-tags` 和均为空；创建 Pod 后检查
云侧 SubENI 安全组，并用允许/拒绝端口验证规则。显式安全组场景必须覆盖同 VPC/Pod 子网内
ICMP、TCP、UDP、DNS（53）和 Cilium health（4240）的双向通信；默认安全组仅在规则已预先
审计的隔离环境执行。

**预期**：安全组选择符合配置；标签查询限定在正确 VPC；空配置行为与文档一致；禁止规则
实际拒绝，允许规则实际放通，且 CoreDNS 与跨节点 health 均恢复 Ready。

## 4. P1 可靠性与运维用例

### HWC-P1-01 Agent 重启恢复

保持 Pod 持续通信，滚动重启 Cilium Agent，观察 endpoint 恢复、BPF map 重建和丢包。

**预期**：Agent 自动恢复；已有 Pod 不重新申请重复 SubENI；两张 map 最终与状态一致。

### HWC-P1-02 Operator 重启与主从切换

在持续扩缩容期间重启 Operator；若配置多个副本，再删除当前 leader。

**预期**：新 leader 接管；已创建资源被重新发现；无重复创建、误删或永久 Pending。

### HWC-P1-03 节点重启

保持节点上有测试 Pod，安全重启节点并等待 Ready。

**预期**：Cilium 恢复；云侧 SubENI 状态一致；重建 Pod 后网络正常；无重复/孤儿资源。

### HWC-P1-04 API 凭证错误与恢复

在隔离测试窗口临时使用无效 AK/SK 或缺权限账号，触发一次扩容，然后恢复正确 Secret。

**预期**：Operator 明确报告 401/403；不会无限创建资源；恢复凭证后无需重装即可继续分配；
AK/SK 不得出现在 Pod 参数、启动日志、测试日志或归档证据中。

### HWC-P1-05 华为云 API 短时不可达

通过受控网络规则短时阻断 Operator 到云 API 的连接，再恢复并创建 Pod。

**预期**：请求按重试/退避处理；Kubernetes 控制面不被拖垮；恢复后自动收敛，无资源泄漏。

### HWC-P1-06 子网容量不足与回退

将容量不足的隔离子网排在候选列表前，后面配置有容量子网，触发新 SubENI 创建。

**预期**：识别子网 IP 不足错误并尝试下一个候选子网；非容量错误不得错误回退。

### HWC-P1-07 所有候选子网耗尽

在隔离环境让所有候选子网均无可分配 IP，再创建 Pod；随后恢复一个子网容量。

**预期**：Pod 保持 Pending 并有明确事件/日志；无半创建 SubENI；容量恢复后自动成功。

### HWC-P1-08 实例 SubENI 配额上限

逐步扩容到实例规格返回的 SubENI 动态上限，再继续请求并最终缩容。

**预期**：不超过云侧配额；超限时错误明确且不忙循环；缩容/释放后可再次分配。

### HWC-P1-09 创建中途失败与事务回滚

在隔离环境制造创建后绑定/状态同步失败，检查云侧端口、CiliumNode 和 BPF map。

**预期**：失败资源被回滚或后续 reconcile 清理；不得出现单 map 条目或无法识别的孤儿 SubENI。

### HWC-P1-10 状态漂移与重新同步

在云侧和 Kubernetes 状态之间制造一个可恢复的测试漂移，再触发 Operator resync。

**预期**：以云侧真实状态重新收敛；不会误占用其他实例资源；状态字段恢复一致。

### HWC-P1-11 空闲 SubENI 保留策略

保持 `releaseExcessIPs=false`，扩容后缩容到零并观察完整水位线周期。

**预期**：空闲 SubENI 可保留供复用；再次扩容优先复用，Pod Ready 时间应缩短。

### HWC-P1-12 空闲 SubENI 回收

仅在隔离测试环境启用 `releaseExcessIPs=true`，扩容后缩容并等待释放延迟。

**预期**：只回收 excess 且未使用的 SubENI；使用中地址不被删除；CiliumNode 与云侧同步更新。

### HWC-P1-13 CNI 调用失败清理

制造 Pod sandbox 创建中断或 kubelet 在 CNI ADD 后失败的场景，再删除 Pod sandbox。

**预期**：CNI DEL/GC 最终释放 endpoint 与 IPAM 使用状态；无长期泄漏。

### HWC-P1-14 MTU、分片与大包

使用 `ping -M do`、TCP 大文件和 UDP 不同报文长度验证 MTU 边界。

**预期**：配置范围内不丢包；超限行为可解释；无 VLAN 额外开销导致的隐蔽黑洞。

### HWC-P1-15 Helm 滚动升级

从已验证旧版本升级到本版本，升级期间持续运行 Pod 通信、DNS 和 Service 请求。

**预期**：DaemonSet/Operator 正常滚动；已有 SubENI 不重复创建；升级后状态与策略正常。

### HWC-P1-16 Helm 回滚

执行一次可控的配置或镜像升级后按文档回滚到前一 revision。

**预期**：回滚完成；核心通信恢复；CRD 字段兼容；无云资源泄漏。

### HWC-P1-17 节点排空与重新调度

对节点执行 cordon/drain，将测试工作负载迁移到其他节点，然后 uncordon。

**预期**：旧节点资源正确释放/保留，新节点正确分配；业务只出现调度允许范围内的中断。

### HWC-P1-18 可观测性与排障证据

分别制造 policy deny、无匹配子网、无效凭证和容量不足，检查 Cilium/Hubble/Operator
日志、事件和指标。

**预期**：故障原因可由标准运维命令定位；日志不泄露 AK/SK；没有无意义高速刷屏。

## 5. P2 性能与长稳用例

### HWC-P2-01 分配时延基线

分空闲池命中与新建 SubENI 两种情况，统计 Pod 创建到 Ready 的 P50/P95/P99。

### HWC-P2-02 吞吐、时延与丢包

分别测同节点、跨节点和 Pod 到 VPC 服务的 TCP/UDP 吞吐、RTT、抖动和丢包，并与未施加
压力时基线对比。

### HWC-P2-03 高频扩缩容

循环扩容、缩容和删除命名空间，持续核对 Pod、CiliumEndpoint、CiliumNode、BPF map 与
云侧 SubENI 数量。

### HWC-P2-04 长时间稳定性

持续运行混合长连接、短连接、DNS、Service、策略允许/拒绝和周期扩缩容。

**预期**：无 Agent/Operator OOM 或持续重启；无 goroutine、内存、BPF map、SubENI/IP
持续增长；测试结束后资源回到水位线。

### HWC-P2-05 API 限流压力

在不影响其他租户的隔离配额内并发创建 Pod，观察 API 调用速率、429 处理和退避。

**预期**：限流时可恢复；无请求风暴；恢复后最终收敛。

## 6. 每个用例的结果记录模板

```text
用例 ID：
执行时间：
执行人：
环境/集群：
源码提交：
Agent 镜像 digest：
Operator 镜像 digest：
Helm revision 与 values 摘要：
前置条件：满足 / 不满足
执行结果：通过 / 失败 / 阻塞
实际现象：
云侧资源变化：
Kubernetes 资源变化：
日志与证据目录：
缺陷编号：
清理结果：
备注：
```

## 7. 测试结束清理与泄漏审计

1. 删除测试 namespace、NetworkPolicy、Service、Deployment 和临时 Secret。
2. 确认没有残留测试 Pod、CiliumEndpoint 和 EndpointSlice。
3. 等待一个完整 reconcile/release 周期。
4. 对比测试前后的云侧 SubENI、端口、私网 IP 和安全组绑定。
5. 检查所有节点两张 HuaweiCloud BPF map 无测试条目。
6. 恢复被修改的子网标签、容量、路由、安全组、API 网络规则和 Helm 配置。

以下任一项存在时不得结束测试：

- 测试 SubENI/端口/IP 未回收且不属于配置的预分配水位线。
- BPF map 仍有已删除 Pod 的 IP、VLAN 或 MAC。
- 节点或系统 Pod 未恢复 Ready。
- 临时错误凭证、宽松安全组或故障注入规则仍然存在。

## 8. 发布验收汇总

测试报告必须汇总：

- P0、P1、P2 的通过、失败、阻塞数量。
- 所有失败用例的根因、修复提交和复测结果。
- Pod Ready 时延、网络性能和长稳资源曲线。
- 测试前后云侧资源差异与最终泄漏审计结果。
- Agent/Operator 镜像 digest、Patch Archive 提交和 Helm values 脱敏副本。

只有 P0、P1 满足第 1 节准入规则，并完成测试结束清理，才能给出可部署结论。
