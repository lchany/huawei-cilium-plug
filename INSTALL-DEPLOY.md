# HuaweiCloud Cilium v1.12.19 Patch 安装部署说明

本文说明如何把 HuaweiCloud patch 应用到 upstream Cilium `v1.12.19`，构建镜像并
部署到华为云 Kubernetes 集群。

## 使用顺序

按下面顺序执行，不要跳步：

1. 准备挂载盘、构建工具和具备 SubENI 权限的云账号。
2. 获取固定版本的 Cilium 源码并应用 patch。
3. 构建并校验 Agent、Operator 镜像。
4. 选择镜像仓库分发或离线导入其中一种方式。
5. 确认 Kubernetes 集群节点均为 `Ready`，再填写 values、安装 CRD 和 Helm Chart。
6. 按部署后检查和数据面验收逐项确认。

本文不负责替代现有的 Kubernetes 节点基线安装流程。执行 Helm 安装前，必须已有一个
可用的 Kubernetes `v1.24` 集群、可工作的 `kubectl` context，以及已安装的
containerd、kubeadm、kubelet 和 kube-proxy。

## 1. 前置条件

准备以下工具：

- Git、Bash、Make
- Cilium `go.mod` 对应的 Go 工具链
- Docker Buildx 或兼容的镜像构建工具
- Helm、kubectl

节点必须是支持 SubENI 的华为云 ECS。部署账号需要查询 ECS、VPC、虚拟子网、安全组
和端口，并有创建、查询、删除 SubENI 的权限。

### Kubernetes 镜像仓库不可达时的处理

若节点访问 `registry.k8s.io` 超时，先从可访问的镜像仓库预拉取控制平面镜像，并在
初始化时显式指定同一镜像仓库。不要让 `kubeadm init` 持续重试超时的默认仓库。

```bash
K8S_VERSION=v1.24.13
K8S_IMAGE_REPOSITORY=registry.aliyuncs.com/google_containers

kubeadm config images pull \
  --kubernetes-version="$K8S_VERSION" \
  --image-repository="$K8S_IMAGE_REPOSITORY" \
  --cri-socket=unix:///run/containerd/containerd.sock

kubeadm init \
  --kubernetes-version="$K8S_VERSION" \
  --image-repository="$K8S_IMAGE_REPOSITORY" \
  --apiserver-advertise-address="<控制平面私网 IP>" \
  --cri-socket=unix:///run/containerd/containerd.sock
```

工作节点加入前，如果 kubeadm 仍尝试从 `registry.k8s.io` 拉取 kube-proxy，可预拉取并
给本地镜像加上默认仓库标签，再执行正常的 `kubeadm join`：

```bash
crictl pull "$K8S_IMAGE_REPOSITORY/kube-proxy:$K8S_VERSION"
ctr -n k8s.io images tag \
  "$K8S_IMAGE_REPOSITORY/kube-proxy:$K8S_VERSION" \
  "registry.k8s.io/kube-proxy:$K8S_VERSION"
```

源码、Go 缓存、临时目录、镜像层和导出的 tar 包只能放在挂载盘，不能写入系统盘。
Docker 的 data-root 也必须位于同一块挂载盘；只把源码放到挂载盘并不能避免 BuildKit
把镜像层写入系统盘。

```bash
export WORKDIR=/mnt/cilium-v1.12.19-huaweicloud
mkdir -p "$WORKDIR"

findmnt -T "$WORKDIR" -o SOURCE,TARGET,FSTYPE
docker info --format 'DockerRoot={{.DockerRootDir}}'
findmnt -T "$(docker info --format '{{.DockerRootDir}}')" -o SOURCE,TARGET,FSTYPE
```

上述两个 `findmnt` 命令必须显示同一个非根挂载设备。若任一位置属于 `/`，先迁移
Docker data-root，再开始构建。

## 2. 获取 patch 分支

```bash
cd "$WORKDIR"
git clone --branch patch-archive/huaweicloud-v1.12.19 \
  https://github.com/lchany/huawei-cilium-v1.19.1.git \
  huawei-cilium-patches
```

目录中应有 10 个编号 patch、`series`、`apply.sh`、部署示例和问题记录。

## 3. 获取 Cilium v1.12.19

完整克隆方式：

```bash
cd "$WORKDIR"
git clone https://github.com/cilium/cilium.git cilium
cd cilium
git checkout a1d7fbd43b563c809330b1c3e28165a3e7ff43aa
```

网络较慢时可以只获取固定 tag：

```bash
cd "$WORKDIR"
git clone --branch v1.12.19 --depth 1 \
  https://github.com/cilium/cilium.git cilium
cd cilium
git rev-parse HEAD
```

输出必须是：

```text
a1d7fbd43b563c809330b1c3e28165a3e7ff43aa
```

## 4. 应用 patch

在 Cilium 仓库根目录执行：

```bash
"$WORKDIR/huawei-cilium-patches/apply.sh"
```

成功后会新增 10 个提交：

```bash
git log --oneline --max-count=11
```

如果 `git am` 失败，先执行 `git am --abort`。确认源码基线和工作区状态后再重试；不要
在已经部分应用 patch 的目录里继续构建。

## 5. 编译和测试

归档提供了 `build-local.sh`，它会在开始前校验工作目录和 Docker data-root 是否处于
同一块非根挂载盘；不满足条件会直接退出。脚本会清理上一轮的 Go 缓存、临时目录、
导出镜像和 BuildKit 缓存，再运行定向测试、构建镜像并导出校验和。

默认镜像名使用 `localhost/huaweicloud`。若计划推送到私有仓库，请在首次执行构建脚本
前设置下面三个变量；这样只需要构建一次。

```bash
export DOCKER_REGISTRY=registry.example.com
export DOCKER_DEV_ACCOUNT=network
export DOCKER_IMAGE_TAG=v1.12.19-huaweicloud

chmod +x "$WORKDIR/huawei-cilium-patches/build-local.sh"
"$WORKDIR/huawei-cilium-patches/build-local.sh" "$WORKDIR"
```

成功后，构建状态、日志和镜像产物都位于 `$WORKDIR`：

```bash
cat "$WORKDIR/build.status"
cat "$WORKDIR/images/SHA256SUMS"
```

仅当 `build.status` 内容为 `SUCCESS` 且两份 tar 都出现在 `SHA256SUMS` 中时，才进入
下一步。失败时先查看 `$WORKDIR/logs/` 中同名日志；不要拿上一轮的镜像继续部署。

## 6. 分发镜像

构建完成后选择一种分发方式即可。不要同时推送和离线导入，以免排障时无法判断实际使用
的是哪一份镜像。

### 方式 A：推送到镜像仓库

```bash
# 登录信息由当前用户的 Docker 配置管理；构建脚本不会读取或保存凭据。
docker login "$DOCKER_REGISTRY"
docker push "$DOCKER_REGISTRY/$DOCKER_DEV_ACCOUNT/cilium:$DOCKER_IMAGE_TAG"
docker push "$DOCKER_REGISTRY/$DOCKER_DEV_ACCOUNT/operator-huaweicloud:$DOCKER_IMAGE_TAG"
```

Helm values 中应使用以下两个镜像名：

```text
registry.example.com/network/cilium:v1.12.19-huaweicloud
registry.example.com/network/operator-huaweicloud:v1.12.19-huaweicloud
```

### 方式 B：离线导入

将 `$WORKDIR/images/` 中的两份 tar 复制到每个 Kubernetes 节点后执行：

```bash
ctr -n k8s.io images import cilium-v1.12.19-huaweicloud.tar
ctr -n k8s.io images import operator-huaweicloud-v1.12.19-huaweicloud.tar
ctr -n k8s.io images ls | grep -E 'localhost/huaweicloud/(cilium|operator-huaweicloud)'
```

离线方式的 values 使用 `localhost/huaweicloud/cilium` 和
`localhost/huaweicloud/operator` 作为两个基础仓库名，并保持 `pullPolicy: IfNotPresent`。
Operator 的实际镜像名仍由 Chart 自动追加 `-huaweicloud`。

### Operator 默认启动命令修复与验证

官方 Cilium `v1.12.19` 基线的 `images/operator/Dockerfile` 使用 JSON 格式的
`CMD ["/usr/bin/cilium-${OPERATOR_VARIANT}"]`。JSON/exec 格式的 `CMD` 不会在容器
启动时展开构建参数，因此镜像默认启动会尝试执行一个包含 `${OPERATOR_VARIANT}`
字面量的不存在路径。

本归档通过 `0004-images-fix-operator-runtime-command-expansion.patch` 修复该问题：构建时
仍按 variant 选择 `cilium-operator-huaweicloud`，最终镜像内安装稳定的
`/usr/bin/cilium-operator`，并把默认启动命令固定为该路径。
随后 `0005-images-retain-variant-operator-binary-for-Helm-comma.patch` 保留
`/usr/bin/cilium-operator-huaweicloud`，因为 Helm Deployment 会显式使用该 variant
命令。两个路径都必须存在。

构建完成后必须检查镜像配置并实际启动二进制：

```bash
OPERATOR_IMAGE=registry.example.com/network/operator-huaweicloud:v1.12.19-huaweicloud

docker image inspect "$OPERATOR_IMAGE" \
  --format '{{json .Config.Cmd}}'
docker run --rm "$OPERATOR_IMAGE" /usr/bin/cilium-operator --help >/dev/null
docker run --rm "$OPERATOR_IMAGE" /usr/bin/cilium-operator-huaweicloud --help >/dev/null
```

第一条命令必须输出：

```text
["/usr/bin/cilium-operator"]
```

Operator 镜像使用 `CMD` 而不是 `ENTRYPOINT`。因此不能直接在镜像名后追加
`--help`，否则 Docker 会用 `--help` 覆盖整个默认命令；验证二进制时必须像上面一样
显式写出 `/usr/bin/cilium-operator`。

如果输出仍包含 `${OPERATOR_VARIANT}`，说明没有应用 `series` 中的 `0004` patch，
该镜像不可用于部署，应清理旧二进制、镜像和 BuildKit 缓存后重新构建。

## 7. 确认 trunk 网卡

下面的 `eth0` 只是常见结果，不能直接复制到所有环境。在每台节点上执行：

```bash
TRUNK_IF=$(ip -4 route show default | awk 'NR == 1 {print $5}')
printf 'trunk candidate: %s\n' "$TRUNK_IF"
ip -br link show dev "$TRUNK_IF"
cat "/sys/class/net/$TRUNK_IF/address"
curl -fsS http://169.254.169.254/openstack/latest/network_data.json
```

单网卡 ECS 通常使用默认路由网卡。多网卡 ECS 需要把 metadata 中的端口 ID、端口
MAC 和系统网卡 MAC 对照后再填写，不能只取第一张网卡。

## 8. 准备 Helm values

先创建 Operator 引用的 Kubernetes Secret，再从无密示例创建 values。AK/SK 不要放在
Helm values、命令行、Shell 历史或 Git 提交中。下面命令会交互式读取凭据；输入不会
回显，也不会出现在进程参数中。

```bash
read -rsp 'HuaweiCloud AK: ' HUAWEI_AK; echo
read -rsp 'HuaweiCloud SK: ' HUAWEI_SK; echo
kubectl -n kube-system create secret generic cilium-huaweicloud \
  --from-literal=CILIUM_HUAWEI_CLOUD_ACCESS_KEY="$HUAWEI_AK" \
  --from-literal=CILIUM_HUAWEI_CLOUD_SECRET_KEY="$HUAWEI_SK" \
  --dry-run=client -o yaml | kubectl apply -f -
unset HUAWEI_AK HUAWEI_SK
```

只核对 Secret 和键名，不读取或打印密钥值：

```bash
kubectl -n kube-system get secret cilium-huaweicloud \
  -o jsonpath='{range $k,$v := .data}{$k}{"\n"}{end}' | sort
```

输出必须包含 `CILIUM_HUAWEI_CLOUD_ACCESS_KEY` 和
`CILIUM_HUAWEI_CLOUD_SECRET_KEY`。

```bash
cd "$WORKDIR"
umask 077
cp huawei-cilium-patches/huaweicloud-values.example.yaml huawei-values.yaml
chmod 600 huawei-values.yaml
${EDITOR:-vi} huawei-values.yaml
```

必须填写的字段如下：

| 字段 | 填写内容 | 获取或校验方式 |
| --- | --- | --- |
| `image.repository` | Agent 镜像基础仓库 | 与第 6 节选择的分发方式一致 |
| `operator.image.repository` | 不带 `-huaweicloud` 的 Operator 基础仓库 | 例如 `registry.example.com/network/operator` |
| `huaweicloud.existingSecret` | 预创建的凭据 Secret 名称 | 默认 `cilium-huaweicloud` |
| `projectID`、`region`、`vpcID` | 当前云项目、区域和 VPC | 与节点所属网络一致 |
| `trunkInterface` | 第 7 节确认的网卡 | 常见为 `eth0`，不能猜测 |
| `subnetIDs` 或 `subnetTags` | 按 ID 或标签选择用于 SubENI 的子网 | 二选一；同时填写时 `subnetIDs` 优先 |
| `securityGroupIDs` | SubENI 使用的安全组 | 必须允许工作负载需要的流量 |
| `ipv4NativeRoutingCIDR` | VPC IPv4 CIDR | 不能填写 Pod CIDR |
| `egressMasqueradeInterfaces` | 与 `trunkInterface` 相同的网卡 | 用于 Pod 出网 SNAT |

`operator.image.repository` 必须是不带云厂商后缀的基础仓库名。Chart 会根据
`huaweicloud.enabled: true` 自动拼接 `-huaweicloud`，因此上述配置实际拉取的是
`registry.example.com/network/operator-huaweicloud:v1.12.19-huaweicloud`。若把
repository 直接写成 `operator-huaweicloud`，Chart 会生成错误的双后缀镜像名。

`huaweicloud.trunkInterface` 和 `egressMasqueradeInterfaces` 必须填写同一张实际 trunk
网卡。SubENI Pod 地址不属于 Cilium 默认 PodCIDR；缺少出口 masquerade 配置时，Pod
访问华为云内网 DNS 或公网可能收不到回包。

生产环境先保持 `releaseExcessIPs: false`。开启后，Operator 会按水位线和释放延迟
回收空闲 SubENI；先在测试节点观察一个完整回收周期。

### 8.1 按标签选择 SubENI 子网

所有节点使用同一组规则时，直接在 `huawei-values.yaml` 中配置 `subnetTags`。先在华为云
控制台确认目标子网已经设置对应标签，然后把 `subnetIDs` 设为空；否则显式子网 ID 会
优先，标签不会参与选择。

```yaml
huaweicloud:
  subnetIDs: []
  subnetTags:
    network-role: pod
```

安装或升级后，确认标签已经进入 `CiliumNode`。以下命令应在每个节点的输出中看到
`subnetTags`，且键值与 values 一致：

```bash
kubectl get ciliumnodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.huaweiCloud.subnetTags}{"\n"}{end}'
```

如果不同节点必须使用不同标签，也可以使用节点本地 CNI 配置。此方式只适用于明确由
运维管理 CNI 文件的环境，并且必须同时让 agent 读取该文件：

```yaml
cni:
  customConf: true
  readCniConf: /host/etc/cni/net.d/04-cilium-cni-eni.conf
```

对应的 `/etc/cni/net.d/04-cilium-cni-eni.conf` 在 `cilium-cni` 配置对象中增加：

```json
"huawei-cloud": {
  "subnet-tags": {
    "network-role": "pod"
  }
}
```

修改 CNI 文件后需要滚动重启 Cilium agent，再执行上面的 `CiliumNode` 检查命令。仅修改
文件但不配置 `readCniConf` 不会生效。单文件 `.conf` 和包含 `cilium-cni` 插件的
`.conflist` 均支持该字段。

保存后先确认文件权限和占位符：

```bash
stat -c '%a %n' huawei-values.yaml
if grep -nE '<(项目 ID|VPC ID|SubENI 子网 ID|安全组 ID)' huawei-values.yaml; then
  echo '仍有未填写的占位符'
  exit 1
fi
```

## 9. Helm 安装

先确认目标集群可用；任一节点不是 `Ready` 时先修复 Kubernetes，再安装 Cilium。

```bash
kubectl config current-context
kubectl get nodes
kubectl get --raw='/readyz?verbose'
```

Chart 本身不携带这版源码生成的 CRD 清单；安装前必须先应用源码中的 CRD。否则
`CiliumNode` 等资源无法被 API Server 识别，Operator 和 Agent 无法正常工作。

```bash
cd "$WORKDIR/cilium"
kubectl apply -f pkg/k8s/apis/cilium.io/client/crds/v2/
kubectl apply -f pkg/k8s/apis/cilium.io/client/crds/v2alpha1/
```

先检查渲染结果：

```bash
cd "$WORKDIR/cilium"
helm lint ./install/kubernetes/cilium -f "$WORKDIR/huawei-values.yaml"
helm template cilium ./install/kubernetes/cilium \
  --namespace kube-system \
  -f "$WORKDIR/huawei-values.yaml" \
  > "$WORKDIR/cilium-rendered.yaml"

# 只能出现 Operator 的两个 secretKeyRef；不能渲染出名为
# cilium-huaweicloud 的 Secret 对象。
grep -n -A5 'name: CILIUM_HUAWEI_CLOUD_' "$WORKDIR/cilium-rendered.yaml"
if grep -B2 -A2 '^kind: Secret$' "$WORKDIR/cilium-rendered.yaml" |
   grep -q '^  name: cilium-huaweicloud$'; then
  echo '错误：Chart 仍在生成华为云凭据 Secret'
  exit 1
fi
```

渲染成功后安装：

```bash
kubectl config current-context
helm upgrade --install cilium ./install/kubernetes/cilium \
  --namespace kube-system \
  --create-namespace \
  -f "$WORKDIR/huawei-values.yaml"
helm status cilium --namespace kube-system
```

安装完成后删除本地渲染文件。`cilium-huaweicloud` 是安装前独立创建的 Secret，不由
Helm release 管理；卸载或回滚 Cilium 不会自动删除它。需要删除时必须由运维显式执行。

## 10. 部署后检查

```bash
kubectl -n kube-system rollout status ds/cilium --timeout=5m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m
kubectl get ciliumnodes
kubectl get ciliumnodes -o yaml
kubectl -n kube-system exec ds/cilium -- cilium status --verbose
```

Cilium `v1.12` 的 `cilium status` 不支持 `--wait` 参数。不要把该参数用于本版本的
自动检查；DaemonSet 和 Deployment 的 rollout status 已负责等待就绪。

通过标准：所有节点为 `Ready`，`cilium` DaemonSet 的 `DESIRED`、`CURRENT`、`READY`
和 `AVAILABLE` 数值一致，Operator 为 `1/1` Ready，且 `cilium status` 显示
`Cilium: Ok`、`Kubernetes: Ok` 和可达的 Cluster health。

检查 Operator 日志中的密钥脱敏：

```bash
kubectl -n kube-system logs deploy/cilium-operator |
  grep -E -- '--huawei-cloud-(access-key|secret-key)='
```

两行都应显示 `<redacted>`。

检查出口 SNAT 规则：

```bash
iptables-save -t nat | grep 'cilium masquerade non-cluster'
```

规则中的出口网卡应与 `trunkInterface` 相同，目标排除 CIDR 应是实际 VPC CIDR。最后
创建普通 Pod，验证 SubENI IP、ClusterIP Service、集群 DNS、NetworkPolicy 和公网
访问。只看到 Pod Running 不代表数据面已经完整通过。若测试 Pod 被固定调度到带污点的
控制平面，请同时容忍历史 `node-role.kubernetes.io/master:NoSchedule` 和
`node-role.kubernetes.io/control-plane:NoSchedule`；不同 Kubernetes 版本可能同时存在
这两个污点。基于 BusyBox `httpd` 做 HTTP 验证时，应先创建可返回 200 的首页，避免把
404 响应误判为网络不通。

## 11. 常见问题排查

| 现象 | 优先检查 | 处理方向 |
| --- | --- | --- |
| `kubeadm init` 卡在拉取镜像 | containerd 日志是否访问 `registry.k8s.io` 超时 | 按第 1 节的镜像仓库处理预拉取后重新执行 |
| Cilium Pod `ImagePullBackOff` | values 中镜像名、节点本地镜像、镜像仓库凭据 | 离线方式重新导入两份 tar；仓库方式确认镜像已推送 |
| Cilium Pod `CrashLoopBackOff` | `kubectl -n kube-system logs ds/cilium --previous` | 对照 trunk 网卡、VPC CIDR、子网和安全组 ID |
| 没有 `CiliumNode` 或 Operator 报资源不存在 | CRD 是否已应用 | 重新执行第 9 节的两个 `kubectl apply -f` 命令 |
| Pod 为 Running 但无法访问 DNS 或公网 | SNAT 规则、`egressMasqueradeInterfaces`、VPC CIDR | 确认第 10 节 NAT 规则出口为 trunk 网卡 |
| Pod 无法分配地址 | Operator 日志、云账号权限、子网剩余地址 | 检查 SubENI 创建/查询权限和安全组、子网配置 |

收集问题信息时不要直接粘贴包含 AK/SK 的 values 文件或 Helm release Secret。可优先提供
`kubectl get pods -A -o wide`、Cilium/Operator 脱敏日志、`CiliumNode` 状态和第 10 节
的 SNAT 输出。
