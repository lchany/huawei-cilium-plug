# HuaweiCloud Cilium v1.12.19 五节点现网测试用例

## 1. 测试目标

在 5 台新购华为云 ECS 上，对 HuaweiCloud Cilium v1.12.19 的 SubENI 控制面、VLAN
数据面、Service、DNS、NetworkPolicy、故障恢复、资源回收和升级回滚进行真实环境验收。

本轮固定使用 upstream `a1d7fbd43b563c809330b1c3e28165a3e7ff43aa` 加 `series` 中
14 个 patch 的基线。完整候选场景目录见
`ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_TEST_SCENARIOS.md`；本文保留 P0/P1 核心场景的
可执行步骤。

本文是可执行测试单，不包含真实 AK/SK、项目 ID、VPC ID、子网 ID 或安全组 ID。环境
标识占位符必须在受控的 `0600` 无密 values 中填写；AK/SK 只能进入预创建的 Kubernetes
Secret。两者均不得提交到 Git 或粘贴到测试报告。

## 2. 推荐五节点拓扑

为覆盖跨节点和跨 AZ，推荐采用 1 个控制面、4 个工作节点。5 台机器均安装 Cilium Agent，
业务测试 Pod 只调度到 4 个工作节点。

| 逻辑名 | 角色 | 可用区 | 用途 |
| --- | --- | --- | --- |
| `cp-01` | control-plane | AZ-A | Kubernetes 控制面、kubectl 执行端 |
| `worker-a1` | worker | AZ-A | 同 AZ/同节点测试、标签子网 A |
| `worker-a2` | worker | AZ-A | 同 AZ/跨节点测试、标签子网 A |
| `worker-b1` | worker | AZ-B | 跨 AZ 测试、标签子网 B |
| `worker-b2` | worker | AZ-B | 跨 AZ测试、标签子网 B、故障注入 |

如果必须验证控制面高可用，可改为 3 control-plane + 2 worker；此时仍需允许测试 Pod
通过 toleration 调度到至少 3 个不同节点，否则无法完整覆盖跨节点/跨 AZ矩阵。

资源要求：

- 5 台 ECS 位于同一 VPC，至少分布于 2 个 AZ。
- 每台 ECS 规格明确支持 trunk/SubENI，且配额能满足测试 Pod 数。
- 每个 AZ 至少准备一个专用 Pod 子网，打标签 `network-role=pod-cilium-test`。
- 准备一个仅用于测试的安全组，明确允许测试所需的节点、Pod、DNS 和外网流量。
- Kubernetes v1.24，Cilium 版本固定为 v1.12.19 patch 基线。
- 测试 namespace 固定为 `cilium-hwc-test`，不得使用生产业务 namespace。

## 3. 现网安全边界

1. 仅在新购的 5 台测试机执行，不对已有生产集群直接安装或替换 CNI。
2. 所有删除、重启、限流、子网耗尽和回滚用例必须在变更窗口执行。
3. 禁止在测试中删除 VPC、业务子网、业务安全组、非测试 SubENI 或非测试节点。
4. 每次资源删除前，用测试 namespace、节点名、资源标签三重确认目标。
5. AK/SK 只能写入预创建的 Kubernetes Secret，不得进入 Helm values、命令行、Shell
   历史或 Git；测试结束按审批删除或轮换临时凭据。
6. 故障注入一次只操作一个节点；控制面和两个以上 worker 不得同时重启。
7. 每个高风险用例开始前保存 CiliumNode、Pod、SubENI 和 Helm 状态，失败后优先回滚。

## 4. 测试变量和证据目录

在 `cp-01` 建立仅当前 shell 使用的变量；不要在此处设置 AK/SK：

```bash
export TEST_NS=cilium-hwc-test
export CILIUM_NS=kube-system
export NODE_A1=worker-a1
export NODE_A2=worker-a2
export NODE_B1=worker-b1
export NODE_B2=worker-b2
export EVIDENCE_ROOT=/mnt/disk2t/cilium-hwc-evidence/$(date +%Y%m%d-%H%M%S)
mkdir -p "$EVIDENCE_ROOT"
chmod 700 "$EVIDENCE_ROOT"
```

记录基础信息：

```bash
kubectl version --short >"$EVIDENCE_ROOT/k8s-version.txt"
kubectl get nodes -o wide >"$EVIDENCE_ROOT/nodes-before.txt"
kubectl get pods -A -o wide >"$EVIDENCE_ROOT/pods-before.txt"
helm -n kube-system list >"$EVIDENCE_ROOT/helm-before.txt"
```

测试报告中的每个用例必须记录：用例 ID、执行人、时间、实际结果、Pass/Fail/Block、缺陷号
和证据文件路径。证据中如出现凭据必须先脱敏。

## 5. 测试前置检查

### TC-PRE-01：节点与拓扑检查

优先级：P0；风险：低。

步骤：

```bash
kubectl get nodes -L topology.kubernetes.io/zone -o wide
kubectl get --raw='/readyz?verbose'
for n in cp-01 worker-a1 worker-a2 worker-b1 worker-b2; do
  kubectl get node "$n" >/dev/null
done
```

预期：5 台节点均存在且 `Ready`；AZ-A/AZ-B 分布符合设计；API Server 所有 readyz 项通过。

### TC-PRE-02：trunk 网卡与 metadata 对照

优先级：P0；风险：低。在每台机器执行：

```bash
TRUNK_IF=$(ip -4 route show default | awk 'NR == 1 {print $5}')
echo "candidate=$TRUNK_IF"
ip -br link show dev "$TRUNK_IF"
cat "/sys/class/net/$TRUNK_IF/address"
curl -fsS http://169.254.169.254/openstack/latest/network_data.json
```

预期：系统网卡 MAC 与 metadata 中目标 trunk port 匹配；记录每台节点的网卡名、MAC 和脱敏
port ID。多网卡时不得仅凭默认路由猜测 trunk。

### TC-PRE-03：云资源与权限检查

优先级：P0；风险：低。

步骤：在华为云控制台/只读 CLI 确认 VPC、两个 AZ 的 Pod 子网、标签、安全组、SubENI 配额，
并用测试账号执行一次只读查询。

预期：子网均属于目标 VPC，AZ 正确，剩余地址满足“计划 Pod 数 + 30% 余量”；测试账号具备
所需的 ECS/VPC/SubENI 查询、创建、更新、删除权限，但无无关高危权限。

### TC-PRE-04：镜像与配置检查

优先级：P0；风险：低。

```bash
docker image inspect '<AGENT_IMAGE>' --format '{{.Id}} {{.Architecture}}'
docker image inspect '<OPERATOR_IMAGE>' --format '{{json .Config.Cmd}}'
docker run --rm '<OPERATOR_IMAGE>' /usr/bin/cilium-operator --help >/dev/null
docker run --rm '<OPERATOR_IMAGE>' /usr/bin/cilium-operator-huaweicloud --help >/dev/null
```

预期：架构与 ECS 一致；Operator Cmd 为 `["/usr/bin/cilium-operator"]`；两个二进制均可运行。

## 6. 安装与基础状态用例

### TC-INS-01：Helm 和 CRD 预检查

优先级：P0；风险：低。

```bash
kubectl apply --dry-run=server -f pkg/k8s/apis/cilium.io/client/crds/v2/
kubectl apply --dry-run=server -f pkg/k8s/apis/cilium.io/client/crds/v2alpha1/
helm lint ./install/kubernetes/cilium -f '<HUAWEI_VALUES>'
helm template cilium ./install/kubernetes/cilium -n kube-system \
  -f '<HUAWEI_VALUES>' >"$EVIDENCE_ROOT/helm-rendered.yaml"
```

预期：CRD server dry-run、lint 和 template 均成功；Operator 镜像无双重 `-huaweicloud`；
Operator 的 AK/SK 均为 `existingSecret` 的 required `secretKeyRef`；渲染结果不包含
HuaweiCloud Secret 对象，也不包含真实 AK/SK。

### TC-INS-02：首次安装和 rollout

优先级：P0；风险：中。

```bash
kubectl apply -f pkg/k8s/apis/cilium.io/client/crds/v2/
kubectl apply -f pkg/k8s/apis/cilium.io/client/crds/v2alpha1/
kubectl -n kube-system get secret '<HUAWEICLOUD_EXISTING_SECRET>' \
  -o jsonpath='{range $k,$v := .data}{$k}{"\n"}{end}' | sort
helm upgrade --install cilium ./install/kubernetes/cilium \
  -n kube-system --create-namespace -f '<HUAWEI_VALUES>'
kubectl -n kube-system rollout status ds/cilium --timeout=10m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=10m
```

预期：Secret 键名包含 `CILIUM_HUAWEI_CLOUD_ACCESS_KEY` 和
`CILIUM_HUAWEI_CLOUD_SECRET_KEY`，但命令不打印值；5/5 Agent Ready，Operator 1/1
Ready；无 CrashLoopBackOff、ImagePullBackOff。

### TC-INS-03：Cilium 和 CiliumNode 状态

优先级：P0；风险：低。

```bash
kubectl -n kube-system exec ds/cilium -- cilium status --verbose \
  | tee "$EVIDENCE_ROOT/cilium-status.txt"
kubectl get ciliumnodes -o yaml >"$EVIDENCE_ROOT/ciliumnodes-after-install.yaml"
kubectl get ciliumnodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.huaweiCloud.subnetTags}{"\n"}{end}'
```

预期：Cilium、Kubernetes 和 Cluster health 正常；5 个 CiliumNode 存在；每个节点的 VPC、
AZ、trunk、subnet tags 符合实际云资源。

### TC-INS-04：敏感信息检查

优先级：P0；风险：低。

```bash
kubectl -n kube-system logs deploy/cilium-operator >"$EVIDENCE_ROOT/operator.log"
kubectl -n kube-system logs ds/cilium >"$EVIDENCE_ROOT/agent.log"
helm -n kube-system get manifest cilium >"$EVIDENCE_ROOT/helm-manifest.yaml"
grep -n -A5 'name: CILIUM_HUAWEI_CLOUD_' "$EVIDENCE_ROOT/helm-manifest.yaml"
```

预期：Helm manifest 只包含两个 `secretKeyRef`，不包含 HuaweiCloud Secret 对象；日志、
Pod spec、Event 和 Helm release 中不存在真实 AK/SK。检查结束后对证据再次脱敏。

### TC-INS-05：外部 Secret 失败契约

优先级：P0；风险：中；一次只验证一种错误配置。

步骤：依次在离线渲染或测试窗口验证 `existingSecret` 为空、Secret 不存在、缺 AK 键、缺
SK 键；每次验证后立即恢复正确 Secret。

预期：`existingSecret` 为空时 Helm 明确失败；对象或键缺失时 Operator 为
`CreateContainerConfigError`，不会带空凭据启动；Agent 和已有 Pod 网络不受影响；任何错误
输出都不包含密钥值。

### TC-INS-06：凭据轮换与 Secret 所有权

优先级：P1；风险：中。

步骤：更新预创建 Secret 后滚动重启 Operator，执行一次只读云 API 和一次测试 Pod 创建；
再验证 Helm upgrade/rollback 不覆盖 Secret。卸载演练只在独立测试窗口执行。

预期：新凭据生效，无重复或泄漏 SubENI；upgrade、rollback、uninstall 均不修改或删除外部
Secret；Secret 只能由运维显式轮换或删除。

## 7. 测试工作负载准备

```bash
kubectl create namespace "$TEST_NS"
kubectl label namespace "$TEST_NS" purpose=cilium-hwc-test --overwrite

for n in "$NODE_A1" "$NODE_A2" "$NODE_B1" "$NODE_B2"; do
  kubectl label node "$n" cilium-hwc-test=true --overwrite
done
```

创建服务端 Pod；`<NETPROBE_IMAGE>` 必须包含归档中的 `test/hwc-real-e2e/netprobe.go`：

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: netprobe-server
  namespace: cilium-hwc-test
spec:
  selector:
    matchLabels: {app: netprobe-server}
  template:
    metadata:
      labels: {app: netprobe-server}
    spec:
      nodeSelector: {cilium-hwc-test: "true"}
      containers:
      - name: server
        image: <NETPROBE_IMAGE>
        args: ["server"]
        ports:
        - {name: http, containerPort: 8080}
---
apiVersion: v1
kind: Service
metadata:
  name: netprobe
  namespace: cilium-hwc-test
spec:
  selector: {app: netprobe-server}
  ports:
  - {name: http, port: 80, targetPort: 8080}
```

预期：4 个 worker 各 1 个 server Pod；每个 Pod 获得华为云 SubENI 地址。

## 8. SubENI 与子网选择用例

### TC-IPAM-01：首次 SubENI 分配

优先级：P0；风险：中。

步骤：创建测试 DaemonSet 后，对比 Pod IP、CiliumNode status 和云控制台 SubENI。

```bash
kubectl -n "$TEST_NS" get pod -o wide
kubectl get ciliumnodes -o yaml >"$EVIDENCE_ROOT/ciliumnodes-ipam-01.yaml"
```

预期：4 个 Pod IP 与对应节点 CiliumNode、云端 SubENI 一一匹配；SubENI 的父 trunk、VLAN、
MAC、子网、安全组正确，无重复 IP。

### TC-IPAM-02：标签按 AZ 选择子网

优先级：P0；风险：中。

步骤：values 仅配置 `subnetTags: {network-role: pod-cilium-test}`，`subnetIDs: []`；滚动
重启 Agent 后扩容工作负载。

预期：AZ-A 节点只使用 AZ-A 目标子网，AZ-B 节点只使用 AZ-B 目标子网；不会选择同 VPC
内无标签、标签不完全匹配或其他 AZ 子网。

### TC-IPAM-03：显式 subnet ID 优先

优先级：P0；风险：中。

步骤：在受控窗口同时配置一个有效 `subnetID` 和指向另一候选子网的 `subnetTags`，创建新 Pod。

预期：新 SubENI 使用显式 ID 指定的同 AZ 子网；CiliumNode 保留配置；事件/日志能解释选择结果。

### TC-IPAM-04：标签无匹配

优先级：P0；风险：中。

步骤：仅在 `worker-b2` 使用节点级 CNI 配置设置不存在的标签，滚动重启该节点 Agent，再创建
固定到 `worker-b2` 的 Pod。

预期：Pod 因无可用子网无法获得地址；Operator/Agent 给出明确错误；其他 3 个 worker 的
Pod 和网络不受影响。恢复正确配置后 Pod 自动成功，且云端无泄漏 SubENI。

### TC-IPAM-05：批量创建与 burst

优先级：P1；风险：中。

步骤：创建 40 个轻量 Pod，使用反亲和尽量均匀分布到 4 个 worker；记录全部 Ready 时间。

```bash
START=$(date +%s)
kubectl -n "$TEST_NS" scale deployment/netprobe-client --replicas=40
kubectl -n "$TEST_NS" wait --for=condition=Ready pod -l app=netprobe-client --timeout=10m
echo "ready_seconds=$(($(date +%s)-START))"
```

预期：Pod 全部 Ready；IP 唯一且子网/AZ正确；无失败后遗留的 SubENI；时间满足客户门限。

### TC-IPAM-06：安全回收

优先级：P0；风险：高；必须在测试子网和变更窗口执行。

步骤：先验证 `releaseExcessIPs=false` 时缩容不删除空闲 SubENI；再启用回收，缩容 40→4，
等待配置的释放周期。

预期：关闭时无删除；开启后仅测试工作负载产生的空闲 SubENI 被回收；仍被 4 个 Pod 使用的
IP 不释放；CiliumNode 和云端最终一致，无其他节点/业务资源被删除。

### TC-IPAM-07：多子网策略路由表隔离

优先级：P0；风险：高；当前代码存在发布阻断风险。

背景：`0007` 修复前，HuaweiCloud 会自动设置
`egress-multi-home-ip-rule-compat=true`，导致同一 trunk 上的 SubENI 共用 ifindex 路由表，
不同网关可能通过 `RouteReplace` 互相替换默认路由。修复后不再自动开启 compat，并为每个
SubENI 使用 `10000 + VLAN ID` 的独立路由表。本用例验证补丁在真实环境中确实生效。

前置条件：在同一 AZ 准备两个网关不同的测试 Pod 子网 A/B，均允许同一测试节点选择。只在
`worker-b2` 执行，其他节点保持单子网基线。

步骤：

1. 先让固定到 `worker-b2` 的 Pod-A 从子网 A 获取 SubENI，保存策略路由和连通性基线。
2. 通过显式 subnet ID 切换或容量控制，使 Pod-B 从子网 B 获取 SubENI。
3. 在创建 Pod-B 前后分别保存：

```bash
ip -4 rule show >"$EVIDENCE_ROOT/worker-b2-rules-before-after.txt"
for table in $(ip -4 rule show | awk '/from <POD_A_IP>|from <POD_B_IP>/ {print $NF}' | sort -u); do
  echo "table=$table"
  ip -4 route show table "$table"
done
```

4. Pod-A、Pod-B 同时持续访问同节点、跨节点、VPC 内网和公网目标；删除并重建 Pod-B 后复测。
5. 核对每个源 IP 的 rule 所指表、表内 default gateway、SubENI 子网 gateway、trunk 抓包
   中的 VLAN/MAC 是否一一对应。

预期：Pod-A 和 Pod-B 分别指向 `10000 + 各自 VLAN ID` 的路由表，且始终使用各自 SubENI
对应的网关/VLAN/MAC，创建顺序不能改变已有 Pod 网络。若两个源 IP 指向同一表、default
gateway 只保留最后写入值，或先创建 Pod 的网络在后一个 Pod 创建后中断，判定为 P0 Fail，
禁止发布。

补充边界：验证 VLAN 1、243～245、4094 均映射到 10001～14094 的专用范围，不得与 Linux
默认表 253～255 冲突；Agent 和节点重启后表号必须保持稳定。

## 9. 数据面与 Service 用例

客户给出的 25 个数据面场景是本节的强制 P0 专项，必须按
`ANALYSIS/HUAWEICLOUD_CILIUM_CUSTOMER_ACCEPTANCE_CASES.md` 执行。该专项通过唯一 Service
后端消除负载均衡随机性，并把功能、实际后端、源 IP 分开取证；不能用本节较粗粒度的
TC-NET-01～05 替代。

### TC-NET-01：同节点 Pod 到 Pod

优先级：P0；风险：低。

步骤：在 `worker-a1` 放置 client/server，client 执行 `netprobe probe <server-pod-ip>:8080`。

预期：连续 100 次全部成功；无异常重传；源/目的 IP 与预期一致。

### TC-NET-02：同 AZ 跨节点 Pod 到 Pod

优先级：P0；风险：低。

步骤：`worker-a1` client 访问 `worker-a2` server，正反向各 100 次。

预期：全部成功；Cilium monitor 无 policy drop；连接跟踪正常。

### TC-NET-03：跨 AZ Pod 到 Pod

优先级：P0；风险：低。

步骤：A1→B1、B1→A1、A2→B2、B2→A2，分别测试 ICMP、TCP 8080。

预期：全部成功；RTT 在客户网络基线范围内，无单向通或 MTU 异常。

### TC-NET-04：ClusterIP Service

优先级：P0；风险：低。

```bash
SVC_IP=$(kubectl -n "$TEST_NS" get svc netprobe -o jsonpath='{.spec.clusterIP}')
kubectl -n "$TEST_NS" exec '<CLIENT_POD>' -- netprobe probe "$SVC_IP:80"
```

预期：从 4 个 worker 各执行 100 次均成功，后端分布合理。

### TC-NET-05：NodePort

优先级：P1；风险：低。

步骤：为 netprobe 增加 NodePort，从每个 Pod 访问 5 个 NodeIP:NodePort，覆盖本地/远端后端。

预期：20 组路径全部成功；源地址转换符合配置；无节点只对本地后端可用的问题。

### TC-NET-06：DNS

优先级：P0；风险：低。

```bash
kubectl -n "$TEST_NS" exec '<CLIENT_POD>' -- netprobe dns kubernetes.default.svc.cluster.local
kubectl -n "$TEST_NS" exec '<CLIENT_POD>' -- netprobe dns '<PUBLIC_DOMAIN>'
```

预期：4 个节点上的 client 均可解析集群域名和允许访问的公网域名，无间歇超时。

### TC-NET-07：VPC 内网和公网出口

优先级：P0；风险：低。

步骤：每个 worker 上的 client 分别访问一个允许的 VPC 内 HTTP 服务和公网测试地址；检查 NAT：

```bash
iptables-save -t nat | grep 'cilium masquerade non-cluster'
```

预期：访问成功；出口网卡等于 trunkInterface；排除 CIDR 为 VPC CIDR；回包路径正常。

### TC-NET-08：MTU、分片和长连接

优先级：P1；风险：低。

步骤：逐步测试小包、接近接口 MTU、超过 MTU 的 ping；保持 TCP 连接 30 分钟；并发发起
1000 个短连接。

预期：允许的包成功或产生正确的 PMTU 行为；无静默黑洞；长连接不异常中断；错误率满足门限。

### TC-NET-09：VLAN 封装证据

优先级：P0；风险：低。

步骤：在源/目的节点的 trunk 网卡同时 tcpdump，执行跨节点请求；并检查 HuaweiCloud BPF map。

```bash
tcpdump -eni '<TRUNK_IF>' -c 100 'vlan or host <TEST_POD_IP>' 
kubectl -n kube-system exec ds/cilium -- cilium bpf map list
```

预期：出方向使用对应 SubENI VLAN/MAC，入方向 VLAN 被正确处理；BPF map 条目与 Pod 的
IP、VLAN、MAC、ifindex 一致。证据不得包含业务流量正文。

### TC-NET-10：入口 VLAN 表示矩阵

优先级：P0；风险：中；对应 `0008`。

步骤：结合 trunk 抓包、`ethtool -k/-K`、Cilium monitor/drop counters 和驱动实际交付行为，
分别覆盖线内 802.1Q、线内 802.1ad、skb VLAN metadata，以及线内头与 metadata 同时可见的
情况；每种表示执行跨节点 Pod、ClusterIP、DNS、ICMP、TCP 和 UDP 探测。若环境无法自然
产生某种表示，应记录 Block，并在可控 tc/netns 环境补测，不能以另一种表示的结果替代。

预期：线内 VLAN 优先解析，单表示只 pop 一次，双表示按实际表示完成两阶段 pop；成功命中
HuaweiCloud map 后不会被通用 VLAN 过滤再次丢弃。不得出现持续
`DROP_HWC_VLAN_POP_FAIL`、单向通、DNS/Service 特异失败或 NetworkPolicy 绕过。

### TC-NET-11：错误 VLAN/MAC 与非 trunk 回归

优先级：P1；风险：中。

步骤：在隔离环境构造错误 VLAN、错误目标 MAC、截断 VLAN header 和非 trunk 接口 VLAN
流量，并观察 map 命中和 drop reason。

预期：错误流量不得投递给其他 Pod；非法头明确丢弃；非 trunk 流量不进入 HuaweiCloud
helper；Cilium 原生 VLAN 逻辑无回归。

## 10. NetworkPolicy 用例

### TC-NP-01：无策略基线

优先级：P0；风险：低。预期：client 可访问 server、DNS 和允许的出口目标。

### TC-NP-02：默认拒绝

优先级：P0；风险：低。

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: default-deny, namespace: cilium-hwc-test}
spec:
  endpointSelector: {}
  ingress: []
  egress: []
```

预期：新建连接被拒绝；Cilium monitor 能看到 policy drop；其他 namespace 不受影响。

### TC-NP-03：L3/L4 精确放通

优先级：P0；风险：低。

步骤：只允许 `app=netprobe-client` 到 `app=netprobe-server` TCP/8080，并单独允许 DNS。

预期：目标 HTTP 和 DNS 成功；其他标签、端口和出口仍失败；同节点、跨节点、跨 AZ 一致。

### TC-NP-04：策略动态变更

优先级：P1；风险：低。

步骤：建立持续探测，依次创建 deny、添加 allow、删除 allow、删除 deny。

预期：行为在策略收敛门限内切换，最终恢复基线；无 Agent 重启和策略残留。

## 11. 恢复与故障用例

### TC-REC-01：Cilium Agent 重启

优先级：P0；风险：中。

步骤：只删除 `worker-b2` 上的 Cilium Pod，持续从其他节点探测其测试 Pod。

预期：Agent 自动恢复；BPF map 和邻居项重建；已有 SubENI 不重复创建；Pod 网络在客户允许
时间内恢复；其他节点无中断。

### TC-REC-02：Operator 重启

优先级：P0；风险：中。

步骤：持续创建/删除少量测试 Pod 时滚动重启 Operator。

预期：Operator 恢复后调谐收敛；无重复/泄漏 SubENI；已有 Pod 数据面不受影响。

### TC-REC-03：worker 重启

优先级：P1；风险：高；一次只操作 `worker-b2`。

步骤：记录状态，安全重启节点，等待 Node Ready、Agent Ready、测试 Pod Ready。

预期：节点和网络自动恢复；CiliumNode 未损坏；SubENI 与 BPF map 一致；其他节点持续可用。

### TC-REC-04：云 API 短时不可达

优先级：P1；风险：高；不得在共享生产控制面注入。

步骤：仅对 Operator 所在测试节点、仅在 2 分钟内阻断华为云 API 目标，观察调谐，然后恢复。

预期：错误日志明确且无凭据；已有 Pod 通信不受影响；恢复后自动收敛，无资源泄漏。

### TC-REC-05：错误权限

优先级：P1；风险：高。

步骤：换用仅缺少 SubENI 创建权限的临时测试凭据，创建新 Pod；随后恢复正确凭据。

预期：新资源创建失败且错误可诊断；现有网络不受影响；恢复后创建成功；日志不暴露凭据。

## 12. 性能与稳定性用例

### TC-PERF-01：基准性能

优先级：P1；风险：低。

步骤：同节点、同 AZ 跨节点、跨 AZ 分别运行 TCP 吞吐、TCP/UDP P99 RTT 和 CPU 使用率测试，
每组至少 3 次，每次 5 分钟。

预期：记录中位数和最大偏差；与客户认可的原生网络/旧 CNI 基线对比，退化不超过约定门限。

### TC-STAB-01：24 小时稳定性

优先级：P1；风险：中。

步骤：持续 Service/DNS/跨节点探测；每 10 分钟创建和删除一批测试 Pod；每小时保存 Cilium、
CiliumNode、SubENI 数、Agent/Operator CPU/内存和错误日志摘要。

预期：探测成功率达到客户门限；无持续增长的 SubENI、BPF map、goroutine 或内存；无调谐卡死。

### TC-STAB-02：72 小时发布候选稳定性

优先级：P2；风险：中。生产发布前推荐执行。预期：无严重故障和资源泄漏，错误率和性能稳定。

## 13. 升级与回滚用例

### TC-UPG-01：同版本镜像滚动升级

优先级：P0；风险：高。

步骤：保存旧 image digest 和 Helm values；升级到候选 digest；持续执行网络探测并观察 rollout。

预期：5 个 Agent 和 Operator 完成滚动；存量连接影响符合门限；CiliumNode/CRD 数据保留。

### TC-UPG-02：回滚

优先级：P0；风险：高。

```bash
helm -n kube-system history cilium
helm -n kube-system rollback cilium '<PREVIOUS_REVISION>' --wait --timeout 10m
```

预期：旧镜像和配置恢复；5 个 Agent、Operator 就绪；存量/新建 Pod 网络正常；无 SubENI
误删或泄漏。CRD 回滚需遵循兼容性评估，不能盲目删除 CRD。

## 14. 测试结束清理

```bash
kubectl delete namespace "$TEST_NS" --wait=true
for n in "$NODE_A1" "$NODE_A2" "$NODE_B1" "$NODE_B2"; do
  kubectl label node "$n" cilium-hwc-test-
done
kubectl get ciliumnodes -o yaml >"$EVIDENCE_ROOT/ciliumnodes-after-cleanup.yaml"
kubectl get pods -A -o wide >"$EVIDENCE_ROOT/pods-after.txt"
```

随后在华为云控制台核对测试 SubENI、端口和 IP 是否已按设计保留或回收。不得用模糊名称
批量删除云资源。删除临时有密 values，轮换临时凭据；证据脱敏后只保留必要内容。

## 15. 发布门禁

- P0 用例 100% Pass；P1 至少完成并通过 24 小时稳定性、重启恢复、多节点/跨 AZ 和性能基线。
- 无致命/严重缺陷，无 SubENI、端口、IP、BPF map 或 Kubernetes 资源泄漏。
- 5 台节点全部 Ready，Agent 5/5、Operator 1/1，Cilium/Kubernetes/Cluster health 正常。
- 同节点、同 AZ 跨节点、跨 AZ、Service、DNS、VPC 内网、公网、NetworkPolicy 全部通过。
- 标签子网选择、显式 ID 优先、无匹配失败恢复和安全回收均有云端证据。
- 同节点同时使用两个不同网关的 Pod 子网时，源策略规则和路由表完全隔离，不受 Pod 创建顺序影响。
- 线内 802.1Q/802.1ad、skb metadata 和双表示路径均有证据；任何无法实机产生的表示必须
  明确标记 Block 并补充受控测试。
- Operator 只引用预创建的外部 Secret；values、Helm release、日志和报告中均无真实 AK/SK，
  upgrade/rollback/uninstall 不删除外部 Secret。
- Agent、Operator、worker 重启恢复通过；升级和回滚演练通过。
- 镜像 digest、patch commit、脱敏配置摘要、测试记录和证据路径可追溯。
- 客户 `CUST-DP-01`～`CUST-DP-25` 首次安装和重启恢复两轮均为 Pass；任何“连通但源 IP
  不符”都按 Fail 处理。

## 16. 执行排期建议

| 天数 | 内容 |
| --- | --- |
| D1 | 5 台 ECS、VPC、子网、标签、安全组、配额和 Kubernetes 基线检查 |
| D2 | Cilium 安装、外部 Secret 契约、凭据脱敏、首次 SubENI 分配 |
| D3 | 标签/ID 子网选择、双网关路由、Service、DNS、内外网、VLAN 表示矩阵 |
| D4 | NetworkPolicy、IP burst、安全回收、容量边界 |
| D5 | Agent/Operator/worker 故障恢复、升级和回滚 |
| D6 | 性能基线，启动 24 小时稳定性 |
| D7 | 稳定性收尾、资源泄漏检查、缺陷复测和报告 |

建议 2 人执行：1 人负责 Kubernetes/Cilium 和证据记录，1 人负责华为云资源、抓包和复核。
高风险用例必须双人确认。

## 17. 执行前仍需确认的参数

- 5 台机器的实际节点名、AZ、规格、操作系统和 CPU 架构。
- 采用 1 control-plane + 4 worker，还是 3 control-plane + 2 worker。
- VPC CIDR、两个 Pod 子网及标签、测试安全组、SubENI 配额。
- Agent、Operator、netprobe 的最终镜像地址与 digest。
- 外部 Secret 名称、临时凭据最小权限和轮换负责人；不得在本文填写真实 AK/SK。
- 公网/VPC 内网测试目标，性能、恢复时间和探测成功率门限。
- 是否允许执行 worker 重启、API 不可达、错误权限、子网无匹配、安全回收等高风险用例。

## 18. 边界专项门禁

执行实机安装前，必须先完成
`ANALYSIS/HUAWEICLOUD_CILIUM_BOUNDARY_COVERAGE_REVIEW.md` 的 P0/S 场景。以下边界若未明确，
不得只靠正常 Pod 连通性判定版本可发布：

1. 多网卡节点不能仅相信 metadata `links[0]`，必须完成系统 MAC、metadata port、云端 port
   三方核对；
2. 同标签、不同 VPC 的安全组不得被选入当前节点；
3. BatchCreate 返回 nil、空、少于或多于请求数量时，资源和分配状态必须一致；
4. Create 后短暂 404、BUILD/DOWN、60 秒超时边界不能导致重复 SubENI；
5. 显式 subnet ID 的空值、重复、跨 VPC/AZ、首项耗尽和非容量错误必须分别验证；
6. SG tags 无匹配时必须确认是 fail-closed 还是允许回退继承，不能保留未定义安全语义；
7. IP private address 未命中任何 subnet CIDR 时不得静默选择错误 gateway；
8. Used 状态在 PrepareIPRelease 与 Delete 之间变化时不得误删在用 SubENI；
9. VLAN ID 0/4095/负数/溢出及 endpoint ID 超过 uint16 时不得通过截断形成 map 冲突；
10. 线内未知 VLAN map miss、线内与 metadata VLAN 不一致必须 fail-closed；
11. 节点已占用 10001～14094 路由表、rule/route 分步失败和 stale rule 清理失败必须可恢复；
12. CNI conflist 含空 plugins、`null` plugin、多个/缺少 cilium-cni 时不得 panic 或误加载。
13. `0010` 的容量 0、小于/等于申请量、V1/V2 分页、缺失/重复 subnet ID、负容量和 API
    错误必须 fail-closed，不能把未知容量当成无限容量。
14. `0011` 已补齐客户 CNI `min-allocate` 的传播；实机仍必须检查 `cni.readCniConf`、
    CiliumNode 水位及实例硬容量。当机型上限小于 10 时必须明确 Block 并验证容量耗尽行为。

边界场景执行后逐项记录 Pass/Fail/Block。P0 Block 只有在等价受控测试已通过且限制得到
客户书面接受时才可关闭；P0 Fail 直接阻断发布。
