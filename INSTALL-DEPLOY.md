# HuaweiCloud Cilium v1.12.19 安装与部署

本文从固定 upstream 源码开始，依次完成 patch 重放、镜像构建、镜像分发、Helm 安装、
最小验收和回滚。仓库只提供 patch，不提供完整 Cilium 源码，也不负责安装 Kubernetes。

## 1. 适用范围

- Cilium：`v1.12.19`
- upstream commit：`a1d7fbd43b563c809330b1c3e28165a3e7ff43aa`
- Kubernetes：以 `v1.24` 为目标基线
- 网络模式：IPv4、native routing、HuaweiCloud SubENI
- patch：`series` 中的 4 个文件

HuaweiCloud IPAM 模式不支持同时启用 IPv6。需要双栈的环境不要使用本部署配置。

## 2. 部署流程

1. 准备构建机、Kubernetes 集群、云权限和测试资源。
2. 在固定 upstream commit 上依次应用控制面、数据面、测试和修复 4 个 patch。
3. 运行定向测试并构建 Agent、CNI 和 HuaweiCloud Operator 镜像。
4. 选择私有镜像仓库或离线导入，不要混用两种分发方式。
5. 创建外部凭据 Secret，填写无密 values。
6. 应用 CRD，检查 Helm 渲染结果，再安装 Cilium。
7. 完成组件、IPAM 和数据面验收；保存回滚所需的 revision 和镜像。

## 3. 前置条件

### 3.1 构建机

需要以下工具：

- Git、Bash、Make、`findmnt`
- Cilium `go.mod` 对应的 Go 工具链
- Docker 和 Buildx
- 能访问 upstream Cilium、基础镜像和 Go 依赖的网络

源码、Go 缓存、临时文件、镜像层和导出的 tar 必须位于同一块非系统盘。
`build-local.sh` 会检查工作目录和 Docker data-root；两者不在同一挂载设备时会退出。

```bash
export WORKDIR=/mnt/cilium-v1.12.19-huaweicloud
mkdir -p "$WORKDIR"

findmnt -T "$WORKDIR" -o SOURCE,TARGET,FSTYPE
docker info --format 'DockerRoot={{.DockerRootDir}}'
findmnt -T "$(docker info --format '{{.DockerRootDir}}')" \
  -o SOURCE,TARGET,FSTYPE
```

两个 `findmnt` 结果应指向同一块非根挂载盘。

> `build-local.sh` 会删除 `$WORKDIR/.cache`、`.tmp`、`.docker`、`images`，并执行
> `docker builder prune -af`。后者会清理构建机上所有未使用的 BuildKit 缓存。
> 请使用专用构建机，或在执行前确认不会影响其他构建任务。

### 3.2 Kubernetes 集群

安装前确认：

- 所有节点已安装 containerd、kubelet、kubeadm 和 kube-proxy；
- `kubectl` 和 Helm 可访问目标集群；
- 所有节点为 `Ready`，节点间 VPC 网络和 DNS 正常；
- 节点为支持 SubENI 的 HuaweiCloud ECS；
- 每个节点都能访问云 metadata 服务；
- 集群尚未运行与本部署冲突的 CNI。

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
helm version
```

### 3.3 云资源和权限

准备专用的测试或业务资源：

- VPC 和至少一个可用于 SubENI 的 IPv4 子网；
- 允许工作负载所需流量的安全组；
- 支持 trunk/SubENI 的 ECS 规格和足够配额；
- 用于创建、查询、更新和删除 SubENI 的最小权限账号；
- 项目 ID、区域、VPC ID、子网 ID 或标签、安全组 ID。

AK/SK 只能写入 Kubernetes Secret。不要把凭据放入 values、Shell 参数、日志或 Git。

## 4. 获取源码和 patch

```bash
cd "$WORKDIR"

git clone --branch patch-archive/huaweicloud-v1.12.19 \
  https://github.com/lchany/huawei-cilium-v1.19.1.git \
  huawei-cilium-patches

git clone --branch v1.12.19 --depth 1 \
  https://github.com/cilium/cilium.git cilium
```

检查 patch 数量和固定基线：

```bash
cd "$WORKDIR/huawei-cilium-patches"
test "$(grep -Ev '^($|#)' series | wc -l)" -eq 4
test "$(find . -maxdepth 1 -type f -name '*.patch' | wc -l)" -eq 3

cd "$WORKDIR/cilium"
test "$(git rev-parse HEAD)" = \
  a1d7fbd43b563c809330b1c3e28165a3e7ff43aa
test -z "$(git status --short)"
```

`apply.sh` 必须从 Cilium 仓库根目录运行：

```bash
cd "$WORKDIR/cilium"
"$WORKDIR/huawei-cilium-patches/apply.sh"
```

成功标准：

```bash
test "$(git rev-list --count a1d7fbd43b563c809330b1c3e28165a3e7ff43aa..HEAD)" -eq 3
test -z "$(git status --short)"
git log --oneline --max-count=3
```

若 `git am` 中断，先执行 `git am --abort`，重新确认 HEAD 和工作区，再从干净基线重放。
不要在部分应用的源码树上继续构建。

## 5. 测试和构建镜像

### 5.1 设置镜像名

私有仓库方式在构建前设置仓库和标签：

```bash
export DOCKER_REGISTRY=registry.example.com
export DOCKER_DEV_ACCOUNT=network
export DOCKER_IMAGE_TAG=v1.12.19-huaweicloud
```

离线方式可保留默认值：

```bash
export DOCKER_REGISTRY=localhost
export DOCKER_DEV_ACCOUNT=huaweicloud
export DOCKER_IMAGE_TAG=v1.12.19-huaweicloud
```

### 5.2 执行构建

```bash
chmod +x "$WORKDIR/huawei-cilium-patches/build-local.sh"
"$WORKDIR/huawei-cilium-patches/build-local.sh" "$WORKDIR"
```

脚本会运行 HuaweiCloud、IPAM 和 Operator 定向测试，构建 Agent 与 HuaweiCloud
Operator 镜像，并导出两份 tar。

```bash
test "$(cat "$WORKDIR/build.status")" = SUCCESS
sha256sum -c "$WORKDIR/images/SHA256SUMS"
ls -lh "$WORKDIR/images/"*.tar
```

失败时查看 `$WORKDIR/logs/`，不要继续使用上一轮镜像。重新构建前保留需要的日志，
其余旧产物由脚本清理。

### 5.3 检查 Operator 镜像

```bash
OPERATOR_IMAGE="$DOCKER_REGISTRY/$DOCKER_DEV_ACCOUNT/operator-huaweicloud:$DOCKER_IMAGE_TAG"

docker image inspect "$OPERATOR_IMAGE" --format '{{json .Config.Cmd}}'
docker run --rm "$OPERATOR_IMAGE" /usr/bin/cilium-operator --help >/dev/null
docker run --rm "$OPERATOR_IMAGE" \
  /usr/bin/cilium-operator-huaweicloud --help >/dev/null
```

镜像默认命令必须是：

```text
["/usr/bin/cilium-operator"]
```

两个 Operator 二进制都必须可执行。Helm 会显式使用
`/usr/bin/cilium-operator-huaweicloud`。

## 6. 分发镜像

### 6.1 私有镜像仓库

```bash
docker login "$DOCKER_REGISTRY"
docker push "$DOCKER_REGISTRY/$DOCKER_DEV_ACCOUNT/cilium:$DOCKER_IMAGE_TAG"
docker push "$DOCKER_REGISTRY/$DOCKER_DEV_ACCOUNT/operator-huaweicloud:$DOCKER_IMAGE_TAG"
```

确认每个节点具备拉取权限。需要认证时，在 `kube-system` 创建 imagePullSecret，并通过
现有集群规范挂载；不要把仓库密码写入 values 文件。

### 6.2 离线导入

将以下文件复制到每个 Kubernetes 节点：

- `cilium-v1.12.19-huaweicloud.tar`
- `operator-huaweicloud-v1.12.19-huaweicloud.tar`
- `SHA256SUMS`

在每个节点执行：

```bash
cd <镜像文件目录>
sha256sum -c SHA256SUMS
ctr -n k8s.io images import cilium-v1.12.19-huaweicloud.tar
ctr -n k8s.io images import operator-huaweicloud-v1.12.19-huaweicloud.tar
ctr -n k8s.io images ls | \
  grep -E 'localhost/huaweicloud/(cilium|operator-huaweicloud)'
```

离线镜像的实际名称是：

```text
localhost/huaweicloud/cilium:v1.12.19-huaweicloud
localhost/huaweicloud/operator-huaweicloud:v1.12.19-huaweicloud
```

values 中的 `operator.image.repository` 仍填写基础名
`localhost/huaweicloud/operator`。Chart 会自动追加 `-huaweicloud`；直接填写
`operator-huaweicloud` 会得到错误的双后缀镜像名。

## 7. 确认 trunk 网卡

不要默认所有节点都使用 `eth0`。在每台节点上检查默认路由、系统 MAC 和 metadata
中的 port ID/MAC：

```bash
TRUNK_IF=$(ip -4 route show default | awk 'NR == 1 {print $5}')
printf 'candidate=%s\n' "$TRUNK_IF"
ip -br link show dev "$TRUNK_IF"
cat "/sys/class/net/$TRUNK_IF/address"
curl -fsS http://169.254.169.254/openstack/latest/network_data.json
```

单网卡 ECS 通常使用默认路由网卡。多网卡环境必须按 MAC 将系统网卡与 metadata port
对应，确认真正的 trunk 后再填写 values。错误网卡可能导致 SubENI 挂载、路由和 VLAN
处理全部失败。

## 8. 创建外部 Secret

下面命令交互式读取凭据，不回显输入，也不把值放到进程参数中。临时文件仅当前用户
可读，并在命令结束时删除：

```bash
(
set +x
umask 077
SECRET_ENV=$(mktemp)
trap 'rm -f "$SECRET_ENV"' EXIT

read -rsp 'HuaweiCloud AK: ' HUAWEI_AK; echo
read -rsp 'HuaweiCloud SK: ' HUAWEI_SK; echo
printf 'CILIUM_HUAWEI_CLOUD_ACCESS_KEY=%s\n' "$HUAWEI_AK" > "$SECRET_ENV"
printf 'CILIUM_HUAWEI_CLOUD_SECRET_KEY=%s\n' "$HUAWEI_SK" >> "$SECRET_ENV"
unset HUAWEI_AK HUAWEI_SK

kubectl -n kube-system create secret generic cilium-huaweicloud \
  --from-env-file="$SECRET_ENV" \
  --dry-run=client -o yaml | kubectl apply -f -
)
```

只检查键名，不读取 Secret 值：

```bash
kubectl -n kube-system get secret cilium-huaweicloud \
  -o go-template='{{range $k, $_ := .data}}{{printf "%s\n" $k}}{{end}}' | sort
```

预期包含：

```text
CILIUM_HUAWEI_CLOUD_ACCESS_KEY
CILIUM_HUAWEI_CLOUD_SECRET_KEY
```

Secret 不由 Helm 管理。更新 Secret 后，已运行的 Operator 不会自动刷新环境变量，
需要执行 `kubectl -n kube-system rollout restart deploy/cilium-operator`。

## 9. 准备 values

```bash
cd "$WORKDIR"
umask 077
cp huawei-cilium-patches/huaweicloud-values.example.yaml huawei-values.yaml
chmod 600 huawei-values.yaml
${EDITOR:-vi} huawei-values.yaml
```

必须确认以下字段：

| 字段 | 要求 |
| --- | --- |
| `image.repository` | Agent 镜像仓库，与第 6 节分发方式一致 |
| `operator.image.repository` | 不带 `-huaweicloud` 的基础仓库名 |
| `huaweicloud.existingSecret` | 第 8 节创建的 Secret 名称 |
| `projectID`、`region`、`vpcID` | 与节点和 SubENI 资源处于同一云项目和 VPC |
| `trunkInterface` | 第 7 节逐节点确认的 trunk 网卡 |
| `subnetIDs` / `subnetTags` | 至少配置一种；两者并存时 `subnetIDs` 优先 |
| `securityGroupIDs` | 只放通工作负载需要的流量 |
| `ipv4NativeRoutingCIDR` | VPC IPv4 CIDR，不是 Kubernetes PodCIDR |
| `egressMasqueradeInterfaces` | 与 `trunkInterface` 一致 |

检查权限和占位符：

```bash
stat -c '%a %n' "$WORKDIR/huawei-values.yaml"
if grep -nE '<[^>]+>' "$WORKDIR/huawei-values.yaml"; then
  echo 'huawei-values.yaml 仍有未填写的占位符' >&2
  exit 1
fi
```

需要按子网标签选择时，将 `subnetIDs` 设为空数组：

```yaml
huaweicloud:
  subnetIDs: []
  subnetTags:
    network-role: pod
```

生产环境建议先保持 `releaseExcessIPs: false`。启用回收前，应在隔离节点验证释放延迟、
在用地址保护和云资源收敛。

## 10. 安装 CRD 和 Helm Chart

先应用 patch 后源码树中的 CRD：

```bash
cd "$WORKDIR/cilium"
kubectl apply -f pkg/k8s/apis/cilium.io/client/crds/v2/
kubectl apply -f pkg/k8s/apis/cilium.io/client/crds/v2alpha1/
```

先 lint 和渲染，不要直接安装：

```bash
helm lint ./install/kubernetes/cilium \
  -f "$WORKDIR/huawei-values.yaml"

helm template cilium ./install/kubernetes/cilium \
  --namespace kube-system \
  -f "$WORKDIR/huawei-values.yaml" \
  > "$WORKDIR/cilium-rendered.yaml"
```

渲染检查：

```bash
grep -n -A5 'name: CILIUM_HUAWEI_CLOUD_' \
  "$WORKDIR/cilium-rendered.yaml"

if grep -B2 -A2 '^kind: Secret$' "$WORKDIR/cilium-rendered.yaml" |
   grep -q '^  name: cilium-huaweicloud$'; then
  echo 'Chart 不应生成 HuaweiCloud 凭据 Secret' >&2
  exit 1
fi

grep -n 'image:.*operator-huaweicloud' "$WORKDIR/cilium-rendered.yaml"
```

安装：

```bash
helm upgrade --install cilium ./install/kubernetes/cilium \
  --namespace kube-system \
  --create-namespace \
  -f "$WORKDIR/huawei-values.yaml"

helm status cilium --namespace kube-system
rm -f "$WORKDIR/cilium-rendered.yaml"
```

## 11. 部署后检查

### 11.1 组件状态

```bash
kubectl -n kube-system rollout status ds/cilium --timeout=5m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl -n kube-system get pods -l io.cilium/app=operator -o wide
kubectl get ciliumnodes
kubectl -n kube-system exec ds/cilium -- cilium status --verbose
```

Cilium `v1.12` 的 `cilium status` 不支持 `--wait`。等待组件就绪应使用上面的
`kubectl rollout status`。

通过标准：

- 所有 Kubernetes 节点为 `Ready`；
- Cilium DaemonSet 在所有节点可用，Operator 为 `1/1` Ready；
- `cilium status` 显示 Cilium、Kubernetes 和 Cluster health 正常；
- 每个节点都有 CiliumNode，HuaweiCloud instance、trunk、子网和安全组配置正确；
- Operator 日志没有持续鉴权、配额、子网或 SubENI 调谐错误。

### 11.2 凭据和 SNAT

日志不得出现凭据值。若命令行配置被记录，只允许看到 `<redacted>`：

```bash
kubectl -n kube-system logs deploy/cilium-operator --tail=500 |
  grep -E -- '--huawei-cloud-(access-key|secret-key)=' || true
```

先用 `kubectl get pod -o wide` 确认业务 Pod 所在节点，再登录该 Kubernetes 节点检查
出口 masquerade。不要在本地部署机执行以下命令：

```bash
iptables-save -t nat | grep 'cilium masquerade non-cluster'
```

出口网卡应为 trunk 网卡，排除目标应使用实际 VPC CIDR。

### 11.3 最小数据面验收

下面示例使用 BusyBox；无法访问公共镜像时替换为内部镜像仓库中的等价镜像。

```bash
kubectl create namespace cilium-smoke
kubectl -n cilium-smoke create deployment web \
  --image=busybox:1.36 --replicas=2 -- \
  sh -c 'mkdir -p /www; echo ok >/www/index.html; exec httpd -f -p 8080 -h /www'
kubectl -n cilium-smoke expose deployment web --port=80 --target-port=8080
kubectl -n cilium-smoke run client --image=busybox:1.36 --restart=Never -- sleep 3600

kubectl -n cilium-smoke wait --for=condition=Available deploy/web --timeout=3m
kubectl -n cilium-smoke wait --for=condition=Ready pod/client --timeout=3m
kubectl -n cilium-smoke get pods -o wide
kubectl -n cilium-smoke exec client -- nslookup kubernetes.default.svc.cluster.local
kubectl -n cilium-smoke exec client -- wget -qO- http://web
```

预期返回 `ok`。同时确认两个 web Pod 的节点和 SubENI IP；若未跨节点调度，应使用
node affinity 或完整测试清单补做跨节点路径。测试结束后清理：

```bash
kubectl delete namespace cilium-smoke
```

完整的功能、故障、边界、升级和性能用例见 [TEST-CASES.md](TEST-CASES.md)。

### 11.4 HuaweiCloud gateway 邻居和 Agent 重启

先从 CiliumNode 的 HuaweiCloud SubENI 状态确认 trunk、GatewayIP 和 GatewayMAC，
再登录对应工作节点检查邻居表。以下命令中的值必须来自当前节点状态，不要手工猜测：

```bash
ip -d neigh show dev <TRUNK_INTERFACE> to <GATEWAY_IP>
```

正常表项必须同时满足：

- 网卡为当前 SubENI 的 trunk interface；
- IP 和 MAC 与 CiliumNode 一致；
- 状态包含 `PERMANENT`；
- 标记包含 `extern_learn`。

滚动重启 Agent 前，在被测节点持续记录邻居变化：

```bash
ip monitor neigh dev <TRUNK_INTERFACE>
```

随后只重启一个测试节点上的 Agent，并保持一条通过该 SubENI 的持续业务流量。通过标准：

- 当前 gateway 没有删除事件；
- 重启后 IP、MAC、trunk、`PERMANENT` 和 `extern_learn` 均不变；
- 不再使用的旧 gateway 能由 HuaweiCloud reconciliation 回收；
- 普通 Cilium stale neighbor 仍按原逻辑清理；
- Agent 恢复后业务流量无持续中断。

必须分别覆盖 `enable-l2-neigh-discovery=true` 和 `false` 两条启动清理路径。故障注入、
SubENI 删除和 MAC 冲突仅在隔离测试节点执行。

## 12. 升级和回滚

升级前记录当前 revision、values 和镜像：

```bash
umask 077
helm history cilium -n kube-system
helm get values cilium -n kube-system -o yaml > "$WORKDIR/cilium-values-backup.yaml"
kubectl -n kube-system get ds/cilium deploy/cilium-operator -o yaml \
  > "$WORKDIR/cilium-workloads-backup.yaml"
```

values 不含 AK/SK，但备份仍按敏感配置管理。更新镜像 tag 或其他配置后执行：

```bash
helm upgrade cilium "$WORKDIR/cilium/install/kubernetes/cilium" \
  -n kube-system -f "$WORKDIR/huawei-values.yaml"
kubectl -n kube-system rollout status ds/cilium --timeout=5m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m
```

升级后重复第 11 节。需要回滚时：

```bash
helm history cilium -n kube-system
helm rollback cilium <REVISION> -n kube-system --wait --timeout=5m
```

回滚不会删除外部 Secret。若新版本修改了 CRD，回滚前先确认旧版本能读取现存字段，
不要直接删除 CRD 或 CiliumNode。

## 13. 卸载边界

```bash
helm uninstall cilium -n kube-system
```

Helm 不会删除预创建的 `cilium-huaweicloud` Secret，也不应自动删除云端 SubENI。
卸载、重装或释放云资源前，先确认工作负载已迁移，并按变更流程检查 CiliumNode、SubENI、
路由和 BPF map。不要把 `kubectl delete crd` 作为常规卸载步骤。

## 14. 故障排查

出现问题时先保存以下脱敏信息：

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get ciliumnodes -o yaml
kubectl -n kube-system logs ds/cilium --tail=300
kubectl -n kube-system logs deploy/cilium-operator --tail=300
helm status cilium -n kube-system
```

不要提交 Secret、认证头、AK/SK、私钥、真实密码或未经脱敏的完整云资源清单。
排查时按照 patch 重放、构建、镜像、Helm、Operator、IPAM 和数据面顺序逐层缩小范围。
