# HuaweiCloud Cilium v1.12.19 Patch 安装部署说明

本文说明如何把 HuaweiCloud patch 应用到 upstream Cilium `v1.12.19`，构建镜像并
部署到华为云 Kubernetes 集群。

## 1. 前置条件

准备以下工具：

- Git、Bash、Make
- Cilium `go.mod` 对应的 Go 工具链
- Docker Buildx 或兼容的镜像构建工具
- Helm、kubectl

节点必须是支持 SubENI 的华为云 ECS。部署账号需要查询 ECS、VPC、虚拟子网、安全组
和端口，并有创建、查询、删除 SubENI 的权限。

源码、Go 缓存、临时目录和镜像缓存会占用较多空间。建议把工作目录和容器运行时的
数据目录放到挂载盘。

```bash
export WORKDIR=/mnt/cilium-v1.12.19-huaweicloud
mkdir -p "$WORKDIR"
```

## 2. 获取 patch 分支

```bash
cd "$WORKDIR"
git clone --branch patch-archive/huaweicloud-v1.12.19 \
  https://github.com/lchany/huawei-cilium-v1.19.1.git \
  huawei-cilium-patches
```

目录中应有 4 个编号 patch、`series`、`apply.sh` 和两份文档。

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

成功后会新增 4 个提交：

```bash
git log --oneline --max-count=5
```

如果 `git am` 失败，先执行 `git am --abort`。确认源码基线和工作区状态后再重试；不要
在已经部分应用 patch 的目录里继续构建。

## 5. 编译和测试

把 Go 缓存和临时文件放在工作目录：

```bash
cd "$WORKDIR/cilium"
rm -rf "$WORKDIR/.cache/go-build" "$WORKDIR/.tmp"
mkdir -p "$WORKDIR/.cache/go-build" "$WORKDIR/.tmp"
export GOCACHE="$WORKDIR/.cache/go-build"
export GOTMPDIR="$WORKDIR/.tmp"
export TMPDIR="$WORKDIR/.tmp"
```

先运行 HuaweiCloud 相关测试：

```bash
go test -mod=vendor ./pkg/huaweicloud/...
go test -mod=vendor -tags=ipam_provider_huaweicloud ./pkg/ipam/... ./operator/...
```

构建二进制：

```bash
make build-container
make -C operator cilium-operator-huaweicloud
```

每次重新构建前删除旧产物，避免把上一轮二进制装进镜像。Docker 的 data-root 和
Buildx 存储不受 `GOCACHE` 控制，需要另外确认它们也位于容量足够的磁盘。

## 6. 构建镜像

将镜像仓库和 tag 换成实际值：

```bash
export DOCKER_REGISTRY=registry.example.com
export DOCKER_DEV_ACCOUNT=network
export DOCKER_IMAGE_TAG=v1.12.19-huaweicloud
export DOCKER_FLAGS=--push

make docker-cilium-image
make docker-operator-huaweicloud-image
```

最终应有 Agent 和 HuaweiCloud Operator 两个镜像：

```text
registry.example.com/network/cilium:v1.12.19-huaweicloud
registry.example.com/network/operator-huaweicloud:v1.12.19-huaweicloud
```

### Operator 默认启动命令修复与验证

官方 Cilium `v1.12.19` 基线的 `images/operator/Dockerfile` 使用 JSON 格式的
`CMD ["/usr/bin/cilium-${OPERATOR_VARIANT}"]`。JSON/exec 格式的 `CMD` 不会在容器
启动时展开构建参数，因此镜像默认启动会尝试执行一个包含 `${OPERATOR_VARIANT}`
字面量的不存在路径。

本归档通过 `0004-images-fix-operator-runtime-command-expansion.patch` 修复该问题：构建时
仍按 variant 选择 `cilium-operator-huaweicloud`，最终镜像内统一安装为
`/usr/bin/cilium-operator`，并把默认启动命令固定为该路径。

构建完成后必须检查镜像配置并实际启动二进制：

```bash
OPERATOR_IMAGE=registry.example.com/network/operator-huaweicloud:v1.12.19-huaweicloud

docker image inspect "$OPERATOR_IMAGE" \
  --format '{{json .Config.Cmd}}'
docker run --rm "$OPERATOR_IMAGE" /usr/bin/cilium-operator --help >/dev/null
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

创建权限为 `0600` 的临时文件 `huaweicloud-values.yaml`。AK/SK 不要放在命令行或
提交到 Git。

```yaml
image:
  repository: registry.example.com/network/cilium
  tag: v1.12.19-huaweicloud
  pullPolicy: IfNotPresent

operator:
  replicas: 1
  image:
    repository: registry.example.com/network/operator-huaweicloud
    tag: v1.12.19-huaweicloud
    pullPolicy: IfNotPresent

ipam:
  mode: huaweicloud

huaweicloud:
  enabled: true
  accessKey: "<AK>"
  secretKey: "<SK>"
  projectID: "<项目 ID>"
  region: "cn-south-1"
  vpcID: "<VPC ID>"
  trunkInterface: "eth0"
  subnetIDs:
    - "<SubENI 子网 ID>"
  securityGroupIDs:
    - "<安全组 ID>"
  subENITags: {}
  releaseExcessIPs: false

tunnel: disabled
kubeProxyReplacement: disabled
ipv4NativeRoutingCIDR: "<VPC IPv4 CIDR>"
enableIPv4Masquerade: true
egressMasqueradeInterfaces: "eth0"
```

`huaweicloud.trunkInterface` 和 `egressMasqueradeInterfaces` 必须填写同一张实际 trunk
网卡。SubENI Pod 地址不属于 Cilium 默认 PodCIDR；缺少出口 masquerade 配置时，Pod
访问华为云内网 DNS 或公网可能收不到回包。

生产环境先保持 `releaseExcessIPs: false`。开启后，Operator 会按水位线和释放延迟
回收空闲 SubENI；先在测试节点观察一个完整回收周期。

## 9. Helm 安装

先检查渲染结果：

```bash
cd "$WORKDIR/cilium"
helm lint ./install/kubernetes/cilium -f huaweicloud-values.yaml
helm template cilium ./install/kubernetes/cilium \
  --namespace kube-system \
  -f huaweicloud-values.yaml >/dev/null
```

确认当前 kubectl context 后安装：

```bash
kubectl config current-context
helm upgrade --install cilium ./install/kubernetes/cilium \
  --namespace kube-system \
  --create-namespace \
  -f huaweicloud-values.yaml
```

安装完成后删除本地临时 values 文件。集群中的 `cilium-huaweicloud` Secret 仍由 Helm
维护。

## 10. 部署后检查

```bash
kubectl -n kube-system rollout status ds/cilium --timeout=5m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m
kubectl get ciliumnodes
kubectl get ciliumnode "$(hostname)" -o yaml
```

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
访问。只看到 Pod Running 不代表数据面已经完整通过。
