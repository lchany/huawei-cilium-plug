# 华为云 Cilium 故障排查与修复记录

本文记录构建、安装和运行测试中实际遇到的问题。每一项都区分“已实际验证”和“待验证”，便于运维人员判断修复结论是否已经过真实环境检验。

## 状态说明

- **已实际验证**：已在真实环境执行修复，并通过对应验证命令。
- **待验证**：根因和修复代码已确认，但尚未完成真实环境复测。
- **未通过**：修复后复测仍失败，需要继续排查。

## 1. 节点访问本机 Pod 或健康端点失败

**状态：已实际验证**

### 现象

- 节点访问本机 Cilium 健康端点超时。
- `ip route get <本机端点 IP>` 显示流量错误地从主网卡发出，而不是进入端点对应的 veth。

### 根因

华为云 SubENI 模式需要为本机端点安装主机路由。原 Chart 没有在 `ipam.mode=huaweicloud` 时自动启用 `enable-endpoint-routes`。

### 修复

新版 Chart 在华为云 IPAM 模式下自动写入：

```yaml
enable-endpoint-routes: "true"
```

使用旧 Chart 临时处理时，可在自定义 values 文件中加入：

```yaml
endpointRoutes:
  enabled: true
```

然后升级并重启 Cilium DaemonSet：

```bash
helm upgrade cilium ./cilium-1.19.1.tgz \
  --namespace kube-system \
  --values huaweicloud-values.yaml
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n kube-system rollout status daemonset/cilium --timeout=10m
```

### 验证

```bash
ip route get <本机端点 IP>
ping -c 3 <本机端点 IP>
```

实际环境中修复后，路由已指向端点 veth，ICMP 和健康检查均恢复。

## 2. 跨节点发往 Pod 的 802.1Q 入站流量被丢弃

**状态：已实际验证**

### 现象

- 本机端点路由修复后，本机通信正常，但跨节点 Pod 通信仍超时。
- 主网卡抓包能看到目标为 SubENI MAC 的 802.1Q 入站帧，但目标 Pod 没有收到报文。

### 判定依据

```bash
tcpdump -eni <主网卡> 'vlan and host <目标 Pod IP>'
```

真实环境抓包确认云侧交付的是线内 802.1Q Ethernet 头。首次修复部署后，丢包监控进一步发现该内核上下文可能同时表现出 VLAN 元数据标志和线内 VLAN 头；此时元数据中的 TCI 不可靠，必须优先解析线内头。第二次修复部署后仍触发通用 VLAN 过滤，说明一次 `skb_vlan_pop()` 只清除了元数据，线内头仍然存在。

### 根因

根因包含两个层面：

1. 华为云入口和出口函数使用 `direct_routing_dev_ifindex` 判断主网卡。在未启用相关 KPR 路径的配置下，该值为 `0`，而实际挂载程序的 `interface_ifindex` 才是主网卡 ifindex，导致华为云 VLAN 处理函数直接返回；
2. 进入处理函数后，还需要兼容线内 VLAN 头、VLAN 元数据及二者同时存在的情况。

可通过 BPF rodata 验证第一个问题：若 `direct_routing_dev_ifindex` 为 `0`、`interface_ifindex` 为实际主网卡 ifindex，则数据面必须使用后者。

### 修复

数据面现在同时支持，并按以下优先级取值：

1. 保留在线内 Ethernet 帧中的 802.1Q/802.1ad VLAN；
2. 没有线内 VLAN 头时，使用内核放入 `skb` 元数据的 VLAN。

命中 `(VLAN ID, MAC)` 映射后，代码移除 VLAN 头并继续 Cilium 本地交付流程。

当元数据和线内头同时存在时，需要执行两阶段剥离：先清除 VLAN 元数据，再移除线内 VLAN 头；只有一种表示时仅执行一次。此外，处理函数必须显式向调用方返回“已处理”状态。部分内核在 helper 调用后，同一 BPF 程序后续读取的 `ctx->vlan_present` 仍可能保留旧状态；调用方应依据“已处理”状态跳过通用 VLAN 白名单过滤，不能再次依据旧元数据丢弃报文。

### 验证

部署包含修复的 Agent 镜像后执行：

```bash
ping -c 3 <其他节点的 Pod IP>
kubectl exec <测试 Pod> -- ping -c 3 <其他节点的 Pod IP>
kubectl exec <测试 Pod> -- nslookup kubernetes.default.svc.cluster.local
```

实际环境验证结果：

- 跨节点访问远端 Pod：ICMP 3/3 成功；
- Cilium Agent 在全部节点运行同一修复提交；
- CoreDNS 副本全部恢复 Ready；
- 各节点通过集群 DNS Service 查询 `kubernetes.default.svc.cluster.local`，均返回 Kubernetes Service 地址；
- Kubernetes API `/readyz` 正常。

## 3. 重建镜像仍显示旧源码提交号

**状态：已实际验证**

### 现象

构建日志中的版本信息仍为上一次提交号，无法证明镜像来自最新修复代码。

### 根因

镜像构建上下文不携带 `.git`，而是读取源码根目录生成的 `GIT_VERSION`。源码提交后如果没有刷新该文件，镜像版本元数据仍会引用旧提交。

### 修复

每次提交修复后、正式构建前执行：

```bash
make GIT_VERSION
cat GIT_VERSION
git rev-parse --short=8 HEAD
```

两处提交号必须一致。若不一致，停止构建并清理本次中断产生的构建层后重新开始。

### 验证

本次已中止带旧版本标识的构建，刷新缓存并从零构建；新构建日志中的提交号与当前修复提交一致。

镜像生成后还应再次验证：

```bash
docker run --rm --entrypoint cilium-dbg <Agent 镜像> version
docker run --rm --entrypoint cilium-operator-huaweicloud <Operator 镜像> version
```

## 4. CoreDNS Pod 因节点缺少镜像启动失败

**状态：已实际验证**

### 现象

CoreDNS 更新后出现 `ImagePullBackOff`，部分节点无法启动新副本。

### 根因

目标节点没有 CoreDNS 镜像，且测试环境无法稳定访问外部镜像仓库。

### 修复

在已有镜像的节点导出，再导入其他节点的 containerd `k8s.io` 命名空间：

```bash
ctr -n k8s.io images export /tmp/coredns.tar <CoreDNS 镜像>
ctr -n k8s.io images import /tmp/coredns.tar
```

离线环境应在安装前完成所有依赖镜像的分发和校验，不要等 Pod 启动失败后再补传。

### 验证

```bash
crictl images | grep coredns
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
```

实际环境中导入后，`ImagePullBackOff` 已消失。后续 DNS 就绪问题与跨节点数据面故障分开处理。

## 5. 清理后归档目录不存在

**状态：已实际验证**

### 现象

`docker save` 报错，提示 `artifacts/images` 不存在。

### 根因

清理旧产物时删除了整个产物目录树，归档前没有重新建立分类目录。

### 修复

清理完成后、归档开始前显式创建目录：

```bash
mkdir -p artifacts/images artifacts/chart
```

### 验证

重新创建目录后，Agent、Operator 和 Chart 均成功写入挂载盘并完成 SHA256 校验。

## 6. 低资源参数导致 Operator 无法在正式镜像中启动

**状态：已实际验证**

### 现象

Operator 文件存在于镜像中，但启动时报 `no such file or directory`。`file` 检查显示二进制为动态链接，并依赖 `/lib64/ld-linux-x86-64.so.2`。

### 根因

通过覆盖 `GO_BUILD_ENV` 设置 `GOMAXPROCS`，同时覆盖了项目原有的 `CGO_ENABLED=0`。Operator 正式镜像以 `scratch` 为基础，不包含动态链接器。

### 修复

不要覆盖 `GO_BUILD_ENV`。低资源构建改为保留默认环境，仅限制 Go 包并发：

```bash
docker build \
  --target release \
  --platform linux/amd64 \
  --build-arg 'MODIFIERS=EXTRA_GO_BUILD_FLAGS=-p=2' \
  --build-arg OPERATOR_VARIANT=operator-huaweicloud \
  -f images/operator/Dockerfile \
  -t <Operator 镜像名> .
```

Agent 构建使用相同的 `--target release` 和 `MODIFIERS`，但不传 `OPERATOR_VARIANT`。

### 验证

```bash
docker run --rm --entrypoint /usr/bin/cilium-operator-huaweicloud \
  <Operator 镜像名> --help
file cilium-operator-huaweicloud
```

重新构建后，Operator 可在容器内执行，ELF 检查结果为 `statically linked`。

## 7. 镜像传输中断后导入报 unexpected EOF

**状态：已实际验证**

### 现象

公网传输长时间速率过低，中止传输后执行 `ctr images import`，出现 `unexpected EOF`。

### 根因

目标路径中保留了未传完的 tar 文件。containerd 可以读到归档头，但在读取镜像层时发现数据不完整。

### 修复

1. 删除目标节点上的半包，不要继续导入；
2. 优先通过集群内网从已持有完整产物的节点重新传输；
3. 导入前逐个节点校验 SHA256；
4. 校验一致后再执行 `ctr -n k8s.io images import`。

```bash
rm -f <未完成的镜像归档>
scp <源节点上的完整归档> <目标节点>:<目标目录>/
sha256sum <目标目录>/<镜像归档>
ctr -n k8s.io images import <目标目录>/<镜像归档>
```

### 验证

本次改用节点间内网重新传输，目标节点 SHA256 与构建机一致，随后两个镜像均成功导入。

## 8. Pod 删除后 CiliumNode 仍显示旧 IP 被占用

**状态：已实际验证**

### 现象

- Pod、CiliumEndpoint 和 HuaweiCloud BPF 条目已经删除；
- Agent 的 `cilium-dbg status --verbose` 已不再显示该地址；
- `CiliumNode.status.ipam.used` 仍保留已删除 Pod 的 IP 和 owner，重新分配地址后旧键继续累积。

### 根因

Agent 使用 JSON Merge Patch 更新 `status.ipam.used`。Merge Patch 对对象字段采用合并语义：
新映射中没有出现的旧 IP 键不会被删除。因此内部 allocator 已释放地址，Kubernetes 中的
状态却无法收敛。

### 修复

改用 JSON Patch 的 `add /status/ipam/used` 操作，整体替换 `used` 映射。这里的 `add` 在
字段已存在时等价于替换，在字段不存在时创建字段。

### 验证

修复后完成了以下真实环境复测：

1. 新 Agent 在所有节点运行同一修复提交；
2. Agent 启动后的首次同步清除了历史测试 Pod 的旧 owner；
3. 新建 Pod 后，`status.ipam.used` 正确增加对应 IP；
4. 删除 Pod 后 5 秒内，IP 从 `status.ipam.used` 和两张 HuaweiCloud BPF map 删除；
5. 地址仍保留在 `spec.ipam.pool`，作为预分配 SubENI 正常复用；
6. 节点、CoreDNS 和 Cilium 状态保持正常。

检查时只读取 `status.ipam.used`，不要对整份 CiliumNode YAML 直接搜索 IP：同一个地址可能
仍正常存在于 `spec.ipam.pool` 或 `status.huawei-cloud.subenis`。

```bash
kubectl get ciliumnodes -o go-template='{{range .items}}{{.metadata.name}}{{"\\n"}}{{range $ip,$v := .status.ipam.used}}  {{$ip}} {{$v.owner}}{{"\\n"}}{{end}}{{end}}'
kubectl -n kube-system exec ds/cilium -- cilium-dbg map get cilium_hwc_srcip4
kubectl -n kube-system exec ds/cilium -- cilium-dbg map get cilium_hwc_vlan_mac
```

## 9. 连通性测试清单自身启动失败或策略放行短暂失败

**状态：已实际验证**

### 现象

- 测试容器使用 `cilium-health-responder --listen 0.0.0.0:4240` 时 CrashLoop；
- 给源 Pod 新增允许标签后，NetworkPolicy 首次访问仍超时，稍后访问成功。

### 根因

- `cilium-health-responder --listen` 参数只接受端口整数；
- Pod 标签变化后，Cilium 需要分配新 identity 并下发策略。Endpoint 处于
  `waiting-for-identity` 时立即判断，会把正常传播过程误报为策略失败。

### 修复

测试服务使用：

```bash
cilium-health-responder --listen 4240
```

修改标签或策略后等待 CiliumEndpoint 恢复 `ready`，再执行允许/拒绝断言：

```bash
kubectl -n <namespace> get ciliumendpoints
```

### 验证

修正端口参数后测试工作负载全部 Ready；等待 identity 收敛后，允许源访问成功，未授权源
超时，删除策略后基础连通恢复。

## 10. 替换 BPF 文件后端点仍加载旧模板

**状态：已实际验证**

### 现象

调试时替换 Agent 容器中的 `/var/lib/cilium/bpf`，仅触发 endpoint regenerate，行为仍像旧代码。

### 根因

Cilium 会缓存编译后的 endpoint BPF 模板。只替换源码目录并不保证模板缓存失效。

### 修复

正式验证必须构建新 Agent 镜像并滚动重启 DaemonSet。临时调试如果需要排除缓存，也应先
确认模板缓存已失效，不能把一次 endpoint regenerate 当成新 BPF 已加载的证据。

### 验证

本次数据面修复以正式镜像滚动部署后验证，所有 Agent 的镜像 ID 和源码提交一致；跨节点
Pod、DNS 和 Service 路径恢复。未真正编入新模板的临时替换结果未计入修复结论。

## 11. DNS 策略已放行但 `getent` 仍超时

**状态：已实际验证**

### 现象

出站策略已允许 CoreDNS 的 UDP/TCP 53，直接访问 CoreDNS Pod IP 和 DNS Service 的 TCP
53 均成功，但 `getent hosts kubernetes.default.svc.cluster.local` 超时。删除 NetworkPolicy
后仍然超时。

### 判定依据

- 删除策略后现象不变，排除策略误拦截；
- `kubernetes.default.svc.cluster.local.` 在同一 Pod 内立即返回；
- CoreDNS 日志显示不带末尾点号的查询被追加 `openstacklocal`，随后访问上游 DNS 超时；
- 使用绝对域名重新应用默认拒绝和精确放行策略后，DNS、Headless Service 和允许的 TCP
  流量成功，未放行的 API Service TCP 流量按预期超时。

### 根因

Pod 的 `/etc/resolv.conf` 含额外搜索域。不带末尾点号的名称会被解析器按搜索域展开；测试
环境的上游 DNS 当时不可达，前序扩展查询耗尽了测试命令的超时时间。这不是 HuaweiCloud
数据面或 NetworkPolicy 故障。

### 修复

集群内 DNS 自动化断言使用绝对域名：

```bash
getent hosts kubernetes.default.svc.cluster.local.
```

需要验证短名称时，应为搜索过程设置足够超时，并把上游 DNS 可达性作为单独检查项。

### 验证

真实环境中，恢复仅允许 CoreDNS 53 和指定业务端口的 egress 策略后，绝对域名查询立即
成功；Headless Service 返回全部后端地址，允许流量成功，未授权 TCP 流量超时。

## 12. 本机构建环境缺少 Helm

**状态：已实际验证**

### 现象

补丁从零应用成功，但无法执行 Chart lint 和模板渲染，因为本机没有 `helm` 命令。

### 根因

构建机未预装 Helm。这是工具链缺失，不是源码或 Chart 问题。

### 修复

将 Helm 安装在挂载盘的工具目录，并使用该绝对路径执行校验；不要把下载包、解压目录或
缓存放入系统盘。生产环境应按组织的软件来源和校验规范安装受信版本。

### 验证

安装后已实际执行 Chart lint 和模板渲染，渲染结果包含 endpoint routes、HuaweiCloud
trunk 参数和 HuaweiCloud Operator，校验通过。

## 13. 节点排空后部分 Pod 长时间停在 ContainerCreating

**状态：已实际验证**

### 现象

节点排空后，大部分 Deployment Pod 在其他节点恢复，少数 Pod 持续报告：

```text
no IPs currently available on the node, allocation will be retried once Cilium Operator allocates more IPs
```

### 判定依据

Operator 成功同步云侧状态并报告目标实例的 `ipv4Limit` 和已有 SubENI 数量相同；没有认证、
子网或 API 错误。恢复原节点调度并重新触发调度后，等待中的 Pod 立即获得预分配 IP 并
Ready。

### 根因

排空把工作负载集中到了其余节点，而这些实例已经达到规格允许的 SubENI 上限。调度器只
判断 Kubernetes 资源请求，不了解云网卡配额，因此仍可能把 Pod 绑定到没有可用 IP 的节点。

### 修复

排空前计算剩余节点可用 SubENI/IP，容量不足时先扩容节点或降低待迁移副本数。已经发生时，
恢复具备容量的节点调度，并删除尚未创建 sandbox 的等待 Pod，让控制器重新调度。不要修改
代码绕过云侧实例配额。

### 验证

真实环境中恢复被排空节点并重新调度等待 Pod 后，Deployment 全部 Ready；等待期间错误
明确，没有半写入 `status.ipam.used` 或 BPF map，也没有超过云侧实例配额。

## 14. 低资源校验命令返回后仍有编译进程

**状态：已实际验证**

### 现象

终端执行器在长时间无输出时先返回，但 `go test` 仍在运行。重复执行后出现多个并行编译
进程，CPU 和内存占用高于预期。首次校验还因为挂载盘上的 `TMPDIR` 被清理而报
`no such file or directory`。

### 根因

长命令的终端等待窗口结束不等于子进程已经退出；同时，清理旧临时产物后没有重新创建
`TMPDIR`。再次启动同一测试会绕过原定的低并发约束。

### 修复

先创建挂载盘临时目录，再启动单个低资源测试；终端返回后用 `ps` 核对原进程，禁止直接
重复启动：

```bash
mkdir -p "$MOUNT_ROOT/tmp"
export TMPDIR="$MOUNT_ROOT/tmp" GOMAXPROCS=2
go test -p=2 ./pkg/ipam
ps -eo pid,ppid,stat,etime,cmd | grep '[g]o test'
```

若已经误启动重复任务，只终止重复进程，保留最早的一项等待结束。所有缓存和临时目录仍
必须位于挂载盘。

### 验证

重复校验进程已终止，只保留一个 `GOMAXPROCS=2`、`-p=2` 的任务；系统盘没有新增构建
目录，构建缓存和临时文件均位于挂载盘。

## 记录新问题的模板

```markdown
## 问题标题

**状态：待验证 / 已实际验证 / 未通过**

### 现象

### 判定依据

### 根因

### 修复

### 验证
```
