# HuaweiCloud Cilium v1.12.19 故障排查

本文按部署阶段整理常见问题。命令中的资源名和地址均为占位符；输出对外提供前必须删除
AK/SK、Token、认证头、私钥、真实密码和不必要的云资源标识。

## 1. Patch 无法应用

### 基线不匹配

`apply.sh` 只接受以下 upstream commit：

```text
a1d7fbd43b563c809330b1c3e28165a3e7ff43aa
```

检查：

```bash
git rev-parse HEAD
git status --short
```

工作区必须干净。不要用 `--no-base-check` 绕过普通安装错误；该选项只用于明确的 patch
移植工作。

### `git am` 中断

```bash
git status
git am --abort
```

确认 HEAD 回到固定基线、工作区干净后，再重新运行 `apply.sh`。不要在部分应用状态继续
构建。

## 2. 构建失败

### 工作目录或 Docker data-root 在系统盘

```bash
findmnt -T "$WORKDIR" -o SOURCE,TARGET,FSTYPE
docker info --format 'DockerRoot={{.DockerRootDir}}'
findmnt -T "$(docker info --format '{{.DockerRootDir}}')" \
  -o SOURCE,TARGET,FSTYPE
```

两处必须位于同一块非系统盘。迁移 Docker data-root 后要重启 Docker，并再次核对实际
路径。

### 编译或测试报错

查看 `$WORKDIR/logs/` 中对应日志：

```bash
ls -lh "$WORKDIR/logs"
tail -n 100 "$WORKDIR/logs/test-huaweicloud.log"
tail -n 100 "$WORKDIR/logs/test-ipam-operator.log"
tail -n 100 "$WORKDIR/logs/build-agent.log"
tail -n 100 "$WORKDIR/logs/build-operator.log"
```

`build.status` 不是 `SUCCESS` 时，不得部署旧 tar 或旧镜像。构建脚本会清理旧缓存和
BuildKit 未使用缓存，建议在专用构建机运行。

## 3. 镜像问题

### Agent 或 Operator `ImagePullBackOff`

```bash
kubectl -n kube-system describe pod <POD_NAME>
kubectl -n kube-system get ds/cilium deploy/cilium-operator -o yaml |
  grep -n 'image:'
```

检查镜像 tag、仓库认证，以及离线镜像是否已导入每个节点的 `k8s.io` containerd
namespace。

### Operator 镜像出现双后缀

错误示例：

```text
registry.example.com/network/operator-huaweicloud-huaweicloud:<TAG>
```

`operator.image.repository` 应填写基础名：

```yaml
operator:
  image:
    repository: registry.example.com/network/operator
```

Chart 会自动追加 `-huaweicloud`。

### Operator 默认命令错误

```bash
docker image inspect <OPERATOR_IMAGE> --format '{{json .Config.Cmd}}'
docker run --rm <OPERATOR_IMAGE> /usr/bin/cilium-operator --help
docker run --rm <OPERATOR_IMAGE> /usr/bin/cilium-operator-huaweicloud --help
```

默认命令必须是 `/usr/bin/cilium-operator`，两个二进制都必须存在。若输出包含字面量
`${OPERATOR_VARIANT}`，说明镜像不是从完整 patch 源码构建。

## 4. Helm 和 Secret

### `existingSecret` 校验失败

```bash
kubectl -n kube-system get secret <SECRET_NAME>
kubectl -n kube-system get secret <SECRET_NAME> \
  -o go-template='{{range $k, $_ := .data}}{{printf "%s\n" $k}}{{end}}' | sort
```

必须包含以下键名，但不要打印值：

```text
CILIUM_HUAWEI_CLOUD_ACCESS_KEY
CILIUM_HUAWEI_CLOUD_SECRET_KEY
```

Secret 必须与 Operator 位于同一 namespace。名称需要满足 Kubernetes DNS-1123 规则。

### 更新 Secret 后 Operator 仍使用旧凭据

Pod 环境变量不会随 Secret 更新自动刷新：

```bash
kubectl -n kube-system rollout restart deploy/cilium-operator
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m
```

### 缺少 CiliumNode 或 CRD

```bash
kubectl get crd | grep cilium.io
kubectl get ciliumnodes
```

从应用 patch 后的源码树重新应用 CRD：

```bash
kubectl apply -f pkg/k8s/apis/cilium.io/client/crds/v2/
kubectl apply -f pkg/k8s/apis/cilium.io/client/crds/v2alpha1/
```

## 5. Metadata 和 trunk 网卡

### Agent 找不到实例、VPC、可用区或 port

在故障节点本地检查 metadata，不要把完整响应直接贴到工单：

```bash
curl -fsS http://169.254.169.254/openstack/latest/meta_data.json
curl -fsS http://169.254.169.254/openstack/latest/network_data.json
```

核对实例 ID、VPC、可用区、port ID 和 MAC 是否存在。metadata 超时、空字段或 MAC
不匹配时应先修复云主机网络，不能手工编造 ID 绕过检查。

### trunkInterface 配错

```bash
ip -4 route show default
ip -br link
for dev in /sys/class/net/*; do
  printf '%s ' "$(basename "$dev")"
  cat "$dev/address"
done
```

多网卡节点不能按接口顺序猜测 trunk。必须把系统 MAC 与 metadata port 对应后再修改
values，并滚动重启 Agent。

## 6. Pod 无法分配 SubENI 地址

```bash
kubectl get ciliumnodes -o yaml
kubectl -n kube-system logs deploy/cilium-operator --tail=300
kubectl describe pod <POD_NAME>
```

按顺序检查：

1. HuaweiCloud project、region、VPC 是否与节点一致；
2. 显式 `subnetIDs` 是否属于同一 VPC 和可用区；
3. `subnetTags` 是否确实匹配，且未被非空 `subnetIDs` 覆盖；
4. 子网是否有可用 IPv4 地址；
5. ECS 规格的 SubENI 上限和项目配额是否已满；
6. 安全组是否存在且属于同一 VPC；
7. 云账号是否具备查询、创建、更新和删除权限。

不要通过扩大云权限或改用全开放安全组来掩盖具体错误。

## 7. Pod 网络不通

### 先区分故障范围

```bash
kubectl get pods -A -o wide
kubectl -n kube-system exec ds/cilium -- cilium status --verbose
kubectl -n kube-system exec ds/cilium -- cilium endpoint list
```

分别测试同节点、跨节点、ClusterIP、NodePort、DNS、VPC 内网和公网。只检查 Pod
`Running` 不足以证明数据面正常。

### 检查策略路由

在 Pod 所在节点执行：

```bash
ip -4 rule show
ip -4 route show table all
ip neigh show
```

每个 SubENI 应使用 `10000 + VLAN ID` 的独立路由表。不要手工把多个网关写回同一共享
trunk 表。

### 检查 VLAN 和 BPF map

```bash
tcpdump -eni <TRUNK_IF> 'vlan and host <POD_IP>'
kubectl -n kube-system exec ds/cilium -- cilium bpf map list
```

抓包前先确认目标 Pod、节点和流量方向。对外共享抓包时应替换节点、Pod 和公网地址。

## 8. DNS 或公网不通

```bash
kubectl exec <POD_NAME> -- nslookup kubernetes.default.svc.cluster.local
kubectl get pod <POD_NAME> -o wide
```

登录该 Pod 所在的 Kubernetes 节点后执行：

```bash
iptables-save -t nat | grep 'cilium masquerade non-cluster'
```

检查 `ipv4NativeRoutingCIDR` 是否为 VPC CIDR，`egressMasqueradeInterfaces` 是否与
trunk 网卡一致。若 values 明确关闭 IPv4 masquerade，公网不通可能是配置结果，不应
直接判断为 Cilium 故障。

## 9. 升级或回滚后异常

```bash
helm history cilium -n kube-system
helm get values cilium -n kube-system -o yaml
kubectl -n kube-system rollout status ds/cilium --timeout=5m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m
```

确认 Agent 和 Operator 使用同一发布批次的镜像，Agent 镜像内的 BPF 文件与二进制匹配。
回滚 Chart 不会回滚外部 Secret，也不应删除 CRD 或云端 SubENI。

## 10. 安全地收集信息

建议收集：

- `kubectl get nodes -o wide` 和脱敏后的 `kubectl get pods -A -o wide`；
- Cilium status、CiliumNode 摘要和相关事件；
- Cilium/Operator 最近 300 行脱敏日志；
- 相关节点的路由、邻居、网卡和 BPF map 摘要；
- Helm revision、镜像 tag/digest 和无密 values 摘要。

禁止收集或提交：

- Secret `.data` / `.stringData`；
- AK/SK、密码、Token、私钥、registry auth；
- 未脱敏的认证头、签名请求、完整抓包；
- 与问题无关的真实项目、VPC、子网、安全组和公网地址。

部署和回滚流程见 [INSTALL-DEPLOY.md](INSTALL-DEPLOY.md)，完整测试项见
[TEST-CASES.md](TEST-CASES.md)。
