# HuaweiCloud Cilium 客户配置与 25 个数据面验收用例

## 1. 结论与适用范围

本文把客户给出的 AlibabaCloud Cilium 配置和 25 个数据面场景转换为当前 HuaweiCloud
Cilium v1.12.19 十四 patch 基线的可执行验收规范。客户 25 个场景全部是 P0 发布门禁：必须
逐项执行并取得功能结果、实际后端和源地址三类证据；任何一项 `Fail` 或未经批准的
`Block` 都不能判定版本通过。

本文只保证用例定义完整、执行路径确定和判定标准无歧义。实机尚未执行前，状态必须是
`NotRun`，不得写成 `Pass`。

固定基线：

- patch 归档提交：`ea34077`；
- upstream Cilium：`v1.12.19`，提交
  `a1d7fbd43b563c809330b1c3e28165a3e7ff43aa`；
- patch：`0001`～`0010`；
- 客户数据面：4 个 worker；第五台机器可作为 control-plane 和证据汇总节点，不参与
  `node1`～`node4` 的源地址断言。

## 2. 原始方案必须先修正的阻断项

| ID | 原始内容 | 问题 | 执行前要求 |
| --- | --- | --- | --- |
| CUST-CFG-01 | `ipam=alibabacloud` | 会进入 AlibabaCloud IPAM，不是本项目实现 | Agent 和 Operator 均改为 `huaweicloud` |
| CUST-CFG-02 | CNI 的 `alibaba-cloud`、`vswitch-tags`、`first-interface-index` | HuaweiCloud CNI 不识别这些云厂商字段 | 使用 `huawei-cloud.subnet-tags`；删除 AlibabaCloud 专有字段 |
| CUST-CFG-03 | Operator 的 `instance-tags-filter` | 不是 HuaweiCloud 子网选择配置 | 使用 `huaweicloud.subnetTags` 或 `huawei-cloud-subnet-tags` |
| CUST-CFG-04 | CNI JSON 中含 `#` 注释 | JSON 非法，CNI 可能无法加载 | 配置文件中不得写注释，先用 `jq -e .` 校验 |
| CUST-CFG-05 | `custom-cni-conf=false`，同时手工维护 `04-cilium-cni-eni.conf` | Agent 可能覆盖文件，且不会读取节点级标签 | 节点级 CNI 配置场景设 `cni.customConf=true` 并配置 `readCniConf`；否则只通过 Helm/ConfigMap 配置，二选一 |
| CUST-CFG-06 | `enable-node-port=false`，但 12 个场景依赖 NodePort | Cilium 不接管 NodePort；集群若无 kube-proxy，测试必失败 | 客户原配置验收必须确认 kube-proxy 正常并由其接管 NodePort；若无 kube-proxy，改为 Cilium NodePort 后重新确认源 IP 基线 |
| CUST-CFG-07 | 单个 Service 同时有 pod1、pod3 两个后端 | 不能指定请求落到本地、远端或自身，原步骤具有随机性 | 每个场景前把 Service selector 切到唯一目标后端，并确认 EndpointSlice 只有一个地址 |
| CUST-CFG-08 | 固定断言 `169.254.42.1` | cilium_host 地址可能变化 | 运行时读取 `CILIUM_HOST_IP`；客户环境确为该地址时再断言等于 `169.254.42.1` |
| CUST-CFG-09 | `clustermesh-config` 指向“空文件” | 该参数按目录使用；文件会导致启动或监听异常 | 不启用 ClusterMesh 时使用存在且为空的目录，并验证 Agent 无 clustermesh 错误 |
| CUST-CFG-10 | 多个值为 `xxx` 或空值 | 无法校验语法、范围和容量 | 启动前替换为经过评审的实际值；原始占位符残留即 Fail |
| CUST-CFG-11 | 用业务 nginx 容器直接 `tcpdump` | 镜像通常没有工具或权限 | 使用带 `NET_ADMIN/NET_RAW` 的专用探针、临时调试容器或在宿主机进入 Pod netns 抓包 |
| CUST-CFG-12 | 场景 24 步骤抓 pod1，预期却写 pod3 | 预期对象笔误 | 统一为 pod1，源 IP 期望为 node2 的宿主机 IP `ip8` |
| CUST-CFG-13 | CNI `ipam.min-allocate=10` | `0011` 已补齐 `min-allocate` 和 `pre-allocate` 传播 | 必须配置 `cni.readCniConf` 并核对 CiliumNode；测试机型硬上限为 8 时按容量边界记录 Block，不得让 Agent 无限等待 10 个地址 |

以上 13 项全部关闭后才能开始 `CUST-DP-01`。修正配置不是改变客户验收意图，而是消除
云厂商字段混用、随机后端和不可判定步骤。

## 3. 客户配置审核矩阵

### 3.1 Agent 配置

| 配置组 | 客户值 | HuaweiCloud 验收要求 |
| --- | --- | --- |
| 集群身份 | `cluster-id=实际值`、`cluster-name=实际值`、`annotate-k8s-node=true`、`auto-create-cilium-node-resource=true` | Agent/Operator 值一致；每个 worker 只有一个对应 CiliumNode；节点注解可追溯 |
| API 与同步 | `api-rate-limit=实际值`、`allocator-list-timeout=48h`、`k8s-sync-timeout=600s`、`k8s-kubeconfig-path=/etc/cilium/cilium.kubeconfig` | 值可被当前版本解析；kubeconfig 权限最小；启动和 API 限流下无同步超时 |
| IPAM | `ipam=huaweicloud`、`identity-allocation-mode=kvstore` | 禁止残留 `alibabacloud`；CiliumNode 出现 `spec.huaweiCloud`，Pod 获得 SubENI 地址 |
| HuaweiCloud | `huawei-cloud-trunk-interface=eth0`、实际 project/region/VPC、subnet ID 或 subnet tags、SG 和 SubENI tags | `eth0` 必须由系统 MAC、metadata port、云端 port 三方确认；ID/标签选择互斥且结果符合 VPC/AZ |
| etcd | `kvstore=etcd`、`kvstore-lease-ttl=86400s`、`kvstore-opt={"etcd.config":"/var/lib/etcd-config/etcd.config"}` | 配置文件存在、证书权限正确、所有 Agent/Operator 可连接；身份分配和租约续约无错误 |
| IPv4/IPv6 | `enable-ipv4=true`、`enable-ipv6=false`、`enable-ipv4-masquerade=false` | 只验收 IPv4；源 IP 必须按本文矩阵核对；不得因未做 masquerade 导致回程缺失 |
| 路由/隧道 | `tunnel=disabled`、`enable-endpoint-routes=true`、`blacklist-conflicting-routes=false` | 每个 SubENI 使用 `10000 + VLAN ID` 表；跨节点和回程路由完整；冲突路由场景另行受控验证 |
| Service | `enable-node-port=false`、`kube-proxy-replacement=probe`、`enable-legacy-services=false`、`sockops-enable=false` | 客户基线由 kube-proxy 接管 NodePort；先证明 kube-proxy、iptables/IPVS 和 30080 规则存在，再执行源 IP 断言 |
| CNI | `cni-chaining-mode=none`、`custom-cni-conf` 按 `CUST-CFG-05` 二选一、`keep-config=true` | 唯一有效 CNI 配置；重启/升级后配置不漂移；`.conf` 可被 `jq` 解析 |
| 健康检查 | `enable-endpoint-health-checking=true`、`enable-health-checking=true` | health endpoint、节点连通和 endpoint health 正常，不得只看 Pod Ready |
| 可观测性 | `enable-hubble=true`、`prometheus-serve-addr=:9090`、`metrics=实际值` | Hubble flow 与 tcpdump 可对应；9090 可抓取且只暴露批准的网络范围 |
| 日志 | `debug=false`、`log-driver=syslog`、`log-opt={"syslog.level":"info","syslog.facility":"local5"}` | syslog local5 能收集启动、错误和恢复证据；日志不得含凭据 |
| monitor | `monitor-aggregation=maximum`、`monitor-aggregation-interval=600s` | 明确会压缩观测事件；源 IP 证据以 tcpdump 为准，不能因 monitor 未展示每个包误判 |
| 策略 | `policy-audit-mode=true`、`disable-cnp-status-updates=true` | 本文 25 项按“无阻断策略”运行；策略强制用例必须另起阶段关闭 audit mode，不能混用结论 |
| BPF map 容量 | 六个 `bpf-*-max=实际值`、`preallocate-bpf-maps=false` | 所有值为正且不超出内存预算；并发连接/Service/节点规模达到目标时无 map full |
| 状态清理 | `clean-cilium-bpf-state=false`、`clean-cilium-state=false`、`wait-bpf-mount=false` | 重启不清状态；BPF filesystem 已挂载；不存在“Agent 已 Ready 但 map 未恢复”的窗口 |
| 关闭能力 | `enable-bandwidth-manager=false`、`tofqdns-enable-poller=false`、三个 flannel 选项为 false/空、sidecar image 保持客户值 | 日志无误启用；不执行依赖这些能力的验收结论 |
| ClusterMesh | `clustermesh-config=/var/lib/cilium/clustermesh` | 路径必须是空目录而不是空文件；单集群测试无 clustermesh controller 错误 |
| 其他 | `labels=实际值` | 标签语法合法且不意外改变 identity；五个节点差异有记录 |

配置取证至少保存以下脱敏输出：DaemonSet 参数、ConfigMap、`cilium config`、`cilium status
--verbose`、BPF map 容量、kube-proxy 模式和 NodePort 规则。不能保存 AK/SK、etcd 私钥或原始
Secret 数据。

### 3.2 HuaweiCloud CNI 配置

节点级标签选择时，使用有效 JSON；注释写在运维文档中，不写入文件：

```json
{
  "cniVersion": "0.3.1",
  "name": "cilium",
  "type": "cilium-cni",
  "huawei-cloud": {
    "subnet-tags": {
      "function": "standard",
      "netsd": "prod"
    }
  },
  "ipam": {
    "pre-allocate": 4,
    "min-allocate": 10
  }
}
```

执行前必须满足：

```bash
jq -e . /etc/cni/net.d/04-cilium-cni-eni.conf >/dev/null
test "$(find /etc/cni/net.d -maxdepth 1 -type f \( -name '*.conf' -o -name '*.conflist' \) | wc -l)" -ge 1
```

Agent 必须配置 `cni.customConf=true` 和
`cni.readCniConf=/host/etc/cni/net.d/04-cilium-cni-eni.conf`，滚动重启后核对每个 CiliumNode
的 `spec.huaweiCloud.subnetTags`。如果采用 Helm 全局 `huaweicloud.subnetTags`，则不手工维护
上述文件，避免双重配置源。

`0011` 已让 HuaweiCloud CiliumNode 同时复制 `pre-allocate` 和 `min-allocate`；实机必须核对
两者确实进入 `spec.ipam`。若 ECS 规格的硬上限小于 10，应在部署前做容量门禁，并用该规格
可达到的上限执行耗尽边界，不能让 Agent 在 `required > capacity` 状态无限等待。
`0010` 必须证明容量为 0 或小于本次申请量的子网不会被选择，并在多个候选中选择真实剩余
地址最多者。

### 3.3 Operator 配置

| 配置组 | 客户值/修正值 | 验收要求 |
| --- | --- | --- |
| 集群身份 | `cluster-id=实际值`、`cluster-name=实际值` | Agent/Operator 完全一致，且不与任何互联集群冲突 |
| IPAM | `ipam=huaweicloud`、`identity-allocation-mode=kvstore`、`kvstore=etcd` | Agent/Operator 模式一致；禁止 `alibabacloud` |
| etcd | `etcd-config`/`kvstore-opt` 指向经过验证的 etcd 配置 | Operator 可连接、证书权限最小、身份同步无超时；不得记录私钥内容 |
| HuaweiCloud 子网 | `huaweicloud.subnetTags={"function":"standard","netsd":"prod"}` 或显式 subnet IDs | 删除 `instance-tags-filter`；同 VPC、同 AZ、标签和真实容量均满足才可选中 |
| 凭据 | `huaweicloud.existingSecret=<预创建 Secret>` | 使用 `0009` 外部 Secret；Deployment、values、release、日志中无明文 AK/SK |
| 网络 | `tunnel=disabled`、`enable-ipv4=true`、`enable-ipv6=false`、`masquerade=false`、`auto-direct-node-routes=false` | 与 Agent 和客户源地址预期一致；不能把连通性与源地址断言拆开判 Pass |
| Service | `kube-proxy-replacement=probe` | 启动日志记录探测结果；客户基线 NodePort owner 为 kube-proxy |
| CNI | `cni-chaining-mode=none`、`custom-cni-conf` 按 `CUST-CFG-05` 二选一 | 与 Agent 的最终配置一致，不由 Operator ConfigMap 意外覆盖 |
| 状态 | 两个 clean state 为 false、`preallocate-bpf-maps=false`、`wait-bpf-mount=false` | 重启/滚动升级无状态意外清理 |
| CRD/状态 | `disable-endpoint-crd=false`、`disable-cnp-status-updates=true`、`cnp-node-status-gc-interval=0`、`synchronize-k8s-nodes=true` | CiliumNode 同步正常；不以缺失 CNP node status 误判失败 |
| GC | `identity-gc-interval=30m`、`unmanaged-pod-watcher-interval=0` | 30 分钟以上观察身份 GC；未管理 Pod 必须由独立检查发现 |
| 监控 | `operator-api-serve-addr=0.0.0.0:9234`、`operator-prometheus-serve-addr=:6942`、Agent Prometheus `:9090` | 端口可用、指标可抓取、网络访问受限；不要把 Agent 和 Operator 端口混淆 |
| monitor | Operator ConfigMap 中的 medium/5s 值 | Agent 客户值是 maximum/600s；确认各自最终生效对象，禁止用同名键互相覆盖 |
| 启动参数 | `--config-dir=/tmp/cilium/config-map`、`--debug=$(CILIUM_DEBUG)`、`--enable-metrics=true` | 环境变量已展开，目录存在，参数被当前二进制接受；Operator 1/1 Ready |
| 其他 | `debug=false`、`enable-xt-socket-fallback=true`、sidecar image 保持客户值 | 日志无未知参数或静默回退 |

## 4. 确定性拓扑和变量

| 变量 | 客户占位符 | 含义 |
| --- | --- | --- |
| `POD1_IP` | `ip1` | node1 上 web 后端 pod1 |
| `NODE1_IP` | `ip2` | node1 宿主机 IP |
| `CILIUM_HOST_IP` | `ip3` | node1 的 cilium_host IPv4，运行时读取 |
| `POD3_IP` | `ip4` | node4 上 web 后端 pod3 |
| `SERVICE_IP` | `ip5` | `mynginx-nodeport` ClusterIP |
| `NODE3_IP` | `ip6` | node3 宿主机 IP |
| `POD2_IP` | `ip7` | node1 上客户端 pod2 |
| `NODE2_IP` | `ip8` | node2 宿主机 IP |
| `NODEPORT` | `30080` | Service NodePort |

开始测试前自动读取并保存这些变量，不允许手工猜测。pod1、pod3 的 HTTP 响应体必须分别
包含 `pod1`、`pod3`，以证明实际后端。为两个 Pod 增加唯一标签，例如
`customer.cilium/backend=pod1|pod3`。每个涉及指定后端的场景先把 Service selector 切到唯一
目标，再等待 EndpointSlice 中只有目标 IP：

```bash
kubectl -n "$TEST_NS" patch svc mynginx-nodeport --type merge \
  -p '{"spec":{"selector":{"customer.cilium/backend":"pod3"}}}'
kubectl -n "$TEST_NS" get endpointslice -l kubernetes.io/service-name=mynginx-nodeport -o wide
```

只有看到唯一目标地址后才能发起请求。每次 HTTP 探测使用
`curl --fail --silent --show-error --connect-timeout 3 --max-time 10`，连续执行 100 次；每次响应
均需匹配目标 Pod 名。双向消息场景使用固定的 TCP 探针或 `socat`，避免不同 `nc` 实现参数
不兼容。

## 5. 客户 25 个 P0 数据面用例

下表中的“抓包源 IP”是客户要求的严格验收值。实际观察值不同，即使 HTTP 成功也记为
`Fail`；只有客户书面批准调整源地址契约后才能更新基线。

| ID | 场景与唯一后端 | 执行方式 | 严格预期 |
| --- | --- | --- | --- |
| CUST-DP-01 | 同宿主机 Pod 互访；pod2→pod1 | pod2 请求 `POD1_IP:80`；pod1 抓包 | 100/100 成功，响应为 pod1；源为 `POD2_IP` |
| CUST-DP-02 | Pod 访问本宿主机 IP | node1 在 `NODE1_IP:30234` 启动 TCP 服务；pod2 建连并双向发送唯一字符串 | 双向字符串完全一致；五轮重连均成功 |
| CUST-DP-03 | Pod 访问本机 cilium_host | node1 在 `CILIUM_HOST_IP:30234` 监听；pod2 建连并双向发送 | 双向通信成功；地址必须等于运行时读取值 |
| CUST-DP-04 | Pod 访问其他宿主机 Pod；pod2→pod3 | pod2 请求 `POD3_IP:80`；pod3 抓包 | 100/100 成功，响应为 pod3；源为 `POD2_IP` |
| CUST-DP-05 | Pod 经 ClusterIP 到远端后端 pod3 | selector=pod3；pod2 请求 `SERVICE_IP:80`；pod3 抓包 | 响应为 pod3；源为 `POD2_IP` |
| CUST-DP-06 | Pod 经 ClusterIP 到同机其他后端 pod1 | selector=pod1；pod2 请求 `SERVICE_IP:80`；pod1 抓包 | 响应为 pod1；源为 `POD2_IP` |
| CUST-DP-07 | Pod 经 ClusterIP 到自身 pod1 | selector=pod1；pod1 请求 `SERVICE_IP:80` 并抓包 | 响应为 pod1；抓包一端为 `CILIUM_HOST_IP`，客户现场应为 `169.254.42.1` |
| CUST-DP-08 | Pod 经 node3 NodePort 到远端 pod3 | selector=pod3；pod2 请求 `NODE3_IP:NODEPORT`；pod3 抓包 | 响应为 pod3；源为 `NODE3_IP` |
| CUST-DP-09 | Pod 经 node3 NodePort 到 node1 后端 pod1 | selector=pod1；pod2 请求 `NODE3_IP:NODEPORT`；pod1 抓包 | 响应为 pod1；源为 `NODE3_IP` |
| CUST-DP-10 | pod1 经 node3 NodePort 到自身 | selector=pod1；pod1 请求 `NODE3_IP:NODEPORT` 并抓包 | 响应为 pod1；源为 `NODE3_IP` |
| CUST-DP-11 | pod2 经 node1 IP NodePort 到远端 pod3 | selector=pod3；pod2 请求 `NODE1_IP:NODEPORT`；pod3 抓包 | 响应为 pod3；源为 `POD2_IP` |
| CUST-DP-12 | pod2 经 node1 IP NodePort 到同机 pod1 | selector=pod1；pod2 请求 `NODE1_IP:NODEPORT`；pod1 抓包 | 响应为 pod1；源为 `POD2_IP` |
| CUST-DP-13 | pod1 经 node1 IP NodePort 到自身 | selector=pod1；pod1 请求 `NODE1_IP:NODEPORT` 并抓包 | 响应为 pod1；抓包一端为 `CILIUM_HOST_IP`，客户现场应为 `169.254.42.1` |
| CUST-DP-14 | Pod 访问其他宿主机 | node2 在 `NODE2_IP:30234` 监听；pod2 建连并双向发送 | 双向字符串一致；五轮重连均成功 |
| CUST-DP-15 | 宿主机访问本机 Pod | node1 请求 `POD1_IP:80`；pod1 抓包 | 响应为 pod1；源为 `CILIUM_HOST_IP` |
| CUST-DP-16 | 宿主机访问远端 Pod | node1 请求 `POD3_IP:80`；pod3 抓包 | 响应为 pod3；源为 `NODE1_IP` |
| CUST-DP-17 | 宿主机经 ClusterIP 到远端 pod3 | selector=pod3；node1 请求 `SERVICE_IP:80`；pod3 抓包 | 响应为 pod3；源为 `NODE1_IP` |
| CUST-DP-18 | 宿主机经 ClusterIP 到本机 pod1 | selector=pod1；node1 请求 `SERVICE_IP:80`；pod1 抓包 | 响应为 pod1；源为 `CILIUM_HOST_IP` |
| CUST-DP-19 | 宿主机经 node3 NodePort 到远端 pod3 | selector=pod3；node1 请求 `NODE3_IP:NODEPORT`；pod3 抓包 | 响应为 pod3；源为 `NODE3_IP` |
| CUST-DP-20 | 宿主机经 node3 NodePort 到本机 pod1 | selector=pod1；node1 请求 `NODE3_IP:NODEPORT`；pod1 抓包 | 响应为 pod1；源为 `NODE3_IP` |
| CUST-DP-21 | node1 经自身 IP NodePort 到远端 pod3 | selector=pod3；node1 请求 `NODE1_IP:NODEPORT`；pod3 抓包 | 响应为 pod3；源为 `NODE1_IP` |
| CUST-DP-22 | node1 经自身 IP NodePort 到本机 pod1 | selector=pod1；node1 请求 `NODE1_IP:NODEPORT`；pod1 抓包 | 响应为 pod1；源为 `CILIUM_HOST_IP` |
| CUST-DP-23 | 宿主机互访 | node2 在 `NODE2_IP:30234` 监听；node1 建连并双向发送 | 双向字符串一致；五轮重连均成功 |
| CUST-DP-24 | node1 接收 node2 NodePort，请求到本机 pod1 | selector=pod1；node2 请求 `NODE1_IP:NODEPORT`；**pod1** 抓包 | 响应为 pod1；源为 `NODE2_IP`；已修正原文“pod3”笔误 |
| CUST-DP-25 | node1 接收 node2 NodePort，请求到远端 pod3 | selector=pod3；node2 请求 `NODE1_IP:NODEPORT`；pod3 抓包 | 响应为 pod3；源为 `NODE1_IP` |

## 6. 每个用例的统一执行与判定

每项必须按以下顺序执行，不能只保存一条成功的 `curl`：

1. 保存节点、Pod、Service、EndpointSlice、CiliumEndpoint、CiliumNode 和 kube-proxy 状态。
2. 指定唯一后端并确认 EndpointSlice 收敛；清空旧连接或使用每次不同的源端口。
3. 后端开始抓包；记录接口、过滤条件和开始时间。
4. 连续执行 100 次 HTTP 请求，或 5 次 TCP 建连及双向消息。
5. 同时保存 Hubble flow；monitor aggregation 为 maximum 时不得替代 tcpdump。
6. 核对成功率、HTTP 响应后端、五元组、源 IP、目的 IP 和是否发生 SNAT。
7. 停止抓包并保存 pcap、命令输出、退出码和脱敏配置快照。
8. 切换后端后等待旧 EndpointSlice/conntrack 失效，再执行下一项。

判定状态只有四种：

- `Pass`：功能、唯一后端、严格源 IP 和证据全部满足；
- `Fail`：任一断言不满足，包含“请求成功但源 IP 不符”；
- `Block`：环境原因无法执行，必须写明原因、责任人和解除日期；
- `NotRun`：尚未执行。

禁止以“多试几次刚好命中目标后端”替代唯一后端控制，也禁止把 tcpdump 中任意方向的一条
地址误当作源地址。抓包必须按请求方向和 TCP SYN 首包判定源地址。

## 7. 配置和边界补充用例

客户数据面开始前，还必须通过以下专项：

| ID | 场景 | 预期 |
| --- | --- | --- |
| CUST-EDGE-01 | CNI 文件包含 `#`、尾逗号、`null` plugin 或重复 cilium-cni | 安装前被校验阻断，不进入半配置状态 |
| CUST-EDGE-02 | `ipam=alibabacloud` 或残留 `alibaba-cloud` 字段 | 预检明确失败并指出 HuaweiCloud 修正项 |
| CUST-EDGE-03 | `xxx`、空 project/VPC/region、非法 map size | 预检失败，Agent/Operator 不带错误配置上线 |
| CUST-EDGE-04 | clustermesh 路径为空文件 | 预检失败；改为空目录后 Agent 正常 |
| CUST-EDGE-05 | kube-proxy 缺失且 Cilium NodePort 关闭 | NodePort 前置检查失败，不执行 CUST-DP-08～13、19～22、24～25 |
| CUST-EDGE-06 | Service 同时存在两个 Endpoint | 指定后端用例被前置检查阻断 |
| CUST-EDGE-07 | 后端切换期间的旧连接 | 新连接只到新 Endpoint；旧连接行为单独记录，不污染判定 |
| CUST-EDGE-08 | `pre-allocate=4`、`min-allocate=10` 的 10/9/4/3/0 边界 | 水位行为符合设计，无负数、忙循环或过量创建 |
| CUST-EDGE-09 | `0010` 返回容量 0、小于申请量、恰好等于申请量 | 前两者不选，恰好等于可选；选择和指标可追溯 |
| CUST-EDGE-10 | `0010` V1/V2 容量 API 分页、重复 ID、缺失 ID、负容量、API 错误 | 分页完整；非法/缺失/错误 fail-closed，不把未知容量当作无限容量 |
| CUST-EDGE-11 | syslog 不可用、Hubble 不可用、Prometheus 端口冲突 | 不影响数据面时明确降级并修复证据链；发布前可观测性必须恢复 |
| CUST-EDGE-12 | BPF CT/LB/ipcache/node/sock map 接近上限 | 达到客户目标规模仍无 map full；容量和主机内存有余量 |
| CUST-EDGE-13 | policy audit mode 下加载 deny policy | 流量按 audit 语义处理，不能误报“策略强制通过” |
| CUST-EDGE-14 | Agent/Operator/kube-proxy 重启后重跑 25 项 | Endpoint、NodePort、路由、BPF map 恢复，25 项仍全部 Pass |
| CUST-EDGE-15 | pod1/pod2 重建、pod3 跨节点重建后重跑相关项 | 变量自动刷新，不复用旧 IP/conntrack/pcap |

## 8. 客户验收发布门禁

只有同时满足以下条件才能写“客户用例通过”：

1. `CUST-CFG-01`～`13` 全部关闭并有配置证据，特别是 `min-allocate=10` 已实际进入 CiliumNode；
2. `CUST-DP-01`～`25` 全部 `Pass`，成功率为 100%，无抽样跳过；
3. 每个 Service 场景均证明唯一实际后端，每个源地址断言均有 pcap；
4. `CUST-EDGE-01`～`15` 全部 `Pass`，破坏性场景若受限必须有客户书面接受的等价证据；
5. 重启恢复后再次执行 25 项，不能只验证首次安装；
6. `0010` 的容量同步和 0/不足/相等/分页/API 错误边界通过；
7. 所有证据记录 patch commit、镜像 digest、节点、时间、命令退出码和脱敏配置；
8. 无未关闭 P0 缺陷，且清理后无 SubENI、IP、路由、BPF map、Endpoint 或 Service 泄漏。

建议结果表：

| 用例 ID | 首次安装 | Agent 重启后 | kube-proxy 重启后 | Pod 重建后 | 证据路径 | 缺陷 |
| --- | --- | --- | --- | --- | --- | --- |
| `<CUST-DP-ID>` | NotRun | NotRun | NotRun/N/A | NotRun | 待填 | - |
