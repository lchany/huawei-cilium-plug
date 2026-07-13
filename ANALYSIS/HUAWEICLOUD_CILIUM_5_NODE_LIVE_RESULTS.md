# HuaweiCloud Cilium 五节点实机测试结果

测试日期：2026-07-13（Asia/Shanghai）

基线：Cilium v1.12.19 + `series` 14 个 patch

集群：Kubernetes v1.24.17，1 control-plane + 4 worker，HuaweiCloud EulerOS 2.0
结论：客户 25 个数据面场景中 24 项通过、1 项配置语义冲突（场景 11）记为 Block；同可用区内五节点通过。跨 AZ 因五台
ECS 均在同一 AZ，记为 Block。客户 `min-allocate=10` 已验证能够进入 CiliumNode，但当前
ECS 规格的 SubENI IPv4 硬上限为 8，因此精确水位 10 记为容量 Block，并以 8 完成耗尽测试。

## 实机拓扑

| 角色 | 节点私网 IP | 测试对象 |
|---|---:|---|
| node1 / control-plane | 192.168.1.65 | pod1=192.168.1.80，pod2=192.168.1.147，cilium_host=192.168.1.7 |
| node2 | 192.168.1.93 | 外部 NodePort 客户端 |
| node3 | 192.168.1.126 | 非本机 NodePort 入口 |
| node4 | 192.168.1.49 | pod3=192.168.1.8 |
| node5 | 192.168.1.238 | 额外 worker、Agent/IPAM/重启覆盖 |

Service `mynginx-nodeport`：ClusterIP `10.104.240.167:80`，NodePort `30080`，后端 pod1、pod3。
HTTP 容器返回自身代号，用于确认实际后端；BusyBox `wget` 与客户 `curl` 执行等价 HTTP
检查。抓包通过宿主机 `nsenter` 进入目标 Pod netns 后使用 `tcpdump`。

## 客户 25 个场景

为消除双后端随机性，每个源地址断言先把 selector 收敛到唯一后端。NodePort 本地后端场景
使用 `externalTrafficPolicy=Local`，远端后端场景使用 `Cluster`；测试后恢复双后端和
`externalTrafficPolicy=Cluster`。这是使“指定本地/远端后端”可重复执行的必要前置条件。

| ID | 场景 | 结果 | 实机证据摘要 |
|---:|---|---|---|
| 1 | 同宿主机 Pod 互访 | Pass | pod2→pod1 返回 `pod1` |
| 2 | Pod 访问宿主机 IP | Pass | 192.168.1.147↔192.168.1.65:30234，双向 `echo-reply` |
| 3 | Pod 访问 cilium_host | Pass | 192.168.1.147↔192.168.1.7:30234，双向 `echo-reply` |
| 4 | Pod 访问跨宿主机 Pod | Pass | pod2→pod3 返回 `pod3` |
| 5 | Pod→ClusterIP→远端 Pod | Pass | 后端 pod3，源 192.168.1.147 |
| 6 | Pod→ClusterIP→同机 Pod | Pass | 后端 pod1，源 192.168.1.147 |
| 7 | Pod→ClusterIP→自身 | Pass | pod1 返回 `pod1`；hairpin 源为本机 cilium_host |
| 8 | Pod→node3 NodePort→远端 Pod | Pass | 后端 pod3，源 192.168.1.126 |
| 9 | Pod→node3 NodePort→node1 Pod | Pass | 后端 pod1，源 192.168.1.126 |
| 10 | Pod→node3 NodePort→自身 | Pass | pod1 返回 `pod1`，源 192.168.1.126 |
| 11 | Pod→node1 NodePort→远端 Pod | Block | 后端 pod3 功能正常；在客户配置指定的 kube-proxy `externalTrafficPolicy=Cluster` 路径中，抓包源为 node1 `192.168.1.65`，而客户期望 Pod 源 `192.168.1.147` |
| 12 | Pod→node1 NodePort→同机 Pod | Pass | 后端 pod1，源 192.168.1.147 |
| 13 | Pod→node1 NodePort→自身 | Pass | 后端 pod1，hairpin 源 192.168.1.7 |
| 14 | Pod 访问其他宿主机 | Pass | pod2↔node2:30234，双向 `echo-reply` |
| 15 | 宿主机访问本机 Pod | Pass | node1→pod1，源 192.168.1.7 |
| 16 | 宿主机访问远端 Pod | Pass | node1→pod3，源 192.168.1.65 |
| 17 | 宿主机→ClusterIP→远端 Pod | Pass | 后端 pod3，源 192.168.1.65 |
| 18 | 宿主机→ClusterIP→本机 Pod | Pass | 后端 pod1，源 192.168.1.7 |
| 19 | 宿主机→node3 NodePort→远端 Pod | Pass | 后端 pod3，源 192.168.1.126 |
| 20 | 宿主机→node3 NodePort→本机 Pod | Pass | 后端 pod1，源 192.168.1.126 |
| 21 | 宿主机→自身 NodePort→远端 Pod | Pass | 后端 pod3，源 192.168.1.65 |
| 22 | 宿主机→自身 NodePort→本机 Pod | Pass | 后端 pod1，源 192.168.1.7 |
| 23 | 宿主机访问其他宿主机 | Pass | node1↔node2:30234，双向 `echo-reply` |
| 24 | node2→node1 NodePort→node1 Pod | Pass | 后端 pod1，源 192.168.1.93 |
| 25 | node2→node1 NodePort→node4 Pod | Pass | 后端 pod3，源 192.168.1.65 |

## 本轮发现并修复的问题

1. `0011`：CNI `min-allocate` 未传播到 CiliumNode。
2. `0012`：`kube-proxy-replacement=probe` 会无条件打开 BPF NodePort，覆盖客户明确的
   `enable-node-port=false`；现在显式 false 优先，由 kube-proxy 接管 NodePort。
3. `0013`：HuaweiCloud endpoint route 未设置 cilium_host 源地址，导致 host→本机 Pod
   使用宿主机主 IP；现在路由带 `src cilium_host`。
4. `0014`：本地 Service hairpin 和 host→本地 DNAT 的 SNAT 源不符合客户基线；现在
   HuaweiCloud 专用规则使用 cilium_host，同时不改变远端后端的 node-IP SNAT。
5. 节点安装脚本补齐 containerd pause 镜像镜像站和 kubelet 的 kubeconfig/config 参数。
6. kube-proxy `clusterCIDR` 从不适用于 ENI Pod IP 的 `10.244.0.0/16` 修正为 VPC
   `192.168.0.0/16`。

## 边界与恢复

| 项目 | 结果 | 说明 |
|---|---|---|
| Agent 5/5、Operator 1/1、节点 5/5 | Pass | 多轮 Helm upgrade 和 DaemonSet rollout 后均 Ready |
| etcd kvstore | Pass | TLS 连接 1/1、quorum 正常 |
| SubENI 创建/识别 | Pass | 五节点均识别实例、VPC、AZ、trunk port，分配真实 VPC IP |
| `pre-allocate=4` | Pass | CiliumNode 五节点均为 4 |
| `min-allocate=10` 传播 | Pass | 使用原配置时 CiliumNode 明确显示 10 |
| `min-allocate=10` 水位 | Block | 当前 ECS 云侧硬上限 8；Agent 正确显示 `available=8 required=10`，无法达到 10 |
| 当前机型 `min-allocate=8` | Pass | 五节点 CiliumNode 均为 8，Agent 5/5 Ready |
| IP 池耗尽 | Pass | 额外 Pod 超出池后明确返回 `No more IPs available`，无崩溃；删除后回收 |
| Agent 滚动重启 | Pass | 多轮重启后已有 Pod、ClusterIP、NodePort 恢复 |
| Operator 调谐 | Pass | 重启/升级后 CiliumNode 与云端 SubENI 保持一致 |
| 双后端随机负载 | Pass | 12 次请求均观察到 pod1、pod3 |
| 跨 AZ | Block | 五台购买机器均在同一 AZ，需新增另一 AZ 机器后执行 |

## 发布注意事项

- 场景 11 的期望与客户配置存在冲突：`enable-node-port=false` 表示 NodePort 由 kube-proxy
  接管，而 kube-proxy 的 `externalTrafficPolicy=Cluster` 会对经 node1 转发到远端 pod3 的
  流量做 node SNAT；切换为 `Local` 又不会把请求转发给远端后端。不能把实际观察到的 node1
  源地址误报为 Pod 源。发布前必须由客户确认采用 node SNAT 语义，或授权改变 NodePort
  owner/流量策略后重新定义场景 11；其余 24 项不受影响。
- 测试构建因公网基础镜像下载受限，运行镜像关闭了未被客户 25 项覆盖的 L7 Envoy 代理，
  `l7Proxy=false`；L3/L4、Hubble 内核观测、IPAM 和 Service 数据面均已实测。正式发布镜像
  应在可访问完整基础镜像的构建环境恢复 Envoy/gops 层并补 L7 验收。
- 该小规格实例最多 8 个 SubENI IPv4。生产若必须使用 `min-allocate=10`，必须选择容量至少
  10 的 ECS 规格；这不是软件可突破的云侧配额。
- 五节点仍在运行并保留测试 namespace，便于复核。测试凭据只存在预创建 Secret，未写入
  values、patch、结果文档或 Git 历史。
