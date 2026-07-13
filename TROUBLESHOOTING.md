# HuaweiCloud Cilium v1.12.19 适配审核与问题记录

本文记录从已完成的 v1.19.1 实际环境测试中筛选问题、审核其是否适用于 v1.12.19，
以及本分支的处理结果。不能因为新版本出现过问题就直接复制修复；每一项都先核对
v1.12.19 的实现和接口。

## 适配结论

| 问题 | v1.12.19 结论 | 处理 |
| --- | --- | --- |
| 入口只识别 skb VLAN 元数据 | 存在；原代码先检查 `ctx->vlan_present` | 0008 支持线内 802.1Q/802.1ad |
| 元数据与线内 VLAN 同时存在 | 存在风险；一次 pop 可能只清除一种表示 | 0008 线内优先并按实际表示执行一或两次 pop |
| helper 后仍被通用 VLAN 过滤 | 存在风险；同一程序后续可能读取旧的 `vlan_present` | 0008 返回 handled 状态并跳过重复过滤 |
| 数据路径使用错误 ifindex | 不存在；v1.12.19 已从 `trunkInterface` 解析 `HWC_TRUNK_IFINDEX` | 不移植 v1.19.1 的 ifindex 改动 |
| 缺少 endpoint route | 不存在；华为云 Helm 模板已设置 `enable-endpoint-routes: true` | 不修改 |
| used-IP 状态合并后残留 | 不存在；本版本使用整对象 `UpdateStatus()` | 不移植对应修复 |
| NetConf 无法设置 `SubnetTags` | 已由 0006 修复，支持 `.conf`、`.conflist` 和字段合并 | 保留 0006，不重复修改 |
| AK/SK 进入 Helm values 和 release | 存在；原 Chart 从 values 生成 Secret | 0009 改为引用预创建 Secret |

## VLAN 入方向问题

### 现象与根因

云侧可能把 SubENI VLAN 以线内 Ethernet 头交付，也可能通过 skb 元数据表示；部分
驱动上下文还能同时观察到两种表示。v1.12.19 原实现只接受元数据，因此线内报文不会
命中 `(VLAN ID, MAC)` 映射。即使命中并调用 helper，同一 BPF 程序中的通用 VLAN
过滤仍可能依据旧上下文再次丢包。

### 修复

0008 仅使用本版本已有的 TC API：

1. 只在 `HWC_TRUNK_IFINDEX` 上处理；
2. 优先解析线内 802.1Q/802.1ad，没有线内头时再读取 skb 元数据；
3. 命中 SubENI map 后设置 handled；
4. 两种表示共存时执行两阶段剥离，只有一种时执行一次；
5. 调用方依据 handled 跳过通用 VLAN 过滤。

### 验证状态

- v1.19.1 中的同类修复：已在实际华为云环境验证跨节点 Pod、DNS 和 Service 恢复。
- v1.12.19 适配代码：已通过本版本 `bpf_host` 全编译排列，其中包括
  `ENABLE_IPV4 + ENABLE_HUAWEICLOUD_VLAN + HWC_TRUNK_IFINDEX`。
- v1.12.19 实际云环境：尚待部署验证，不能标记为“已实际验证”。

现场验证至少执行：

```bash
tcpdump -eni <trunk 网卡> 'vlan and host <目标 Pod IP>'
kubectl exec <源 Pod> -- ping -c 3 <其他节点 Pod IP>
kubectl exec <源 Pod> -- nslookup kubernetes.default.svc.cluster.local
```

## Operator 凭据问题

### 根因与版本差异

原 v1.12.19 Chart 接受 `huaweicloud.accessKey` 和 `huaweicloud.secretKey`，再生成
Kubernetes Secret。这样凭据会进入 values 和 Helm release。v1.12.19 Operator 已原生
绑定 `CILIUM_HUAWEI_CLOUD_ACCESS_KEY` 和 `CILIUM_HUAWEI_CLOUD_SECRET_KEY`，所以无需
移植 v1.19.1 的环境变量兼容代码。

### 修复与验证

0009 删除 Chart 管理的华为云 Secret，新增 `huaweicloud.existingSecret`，并把两个
`secretKeyRef` 设为必需。验证结果：

- `helm lint` 通过；
- 启用华为云后，Deployment 渲染为两个必需的 Secret 引用；
- 渲染结果不包含名为 `cilium-huaweicloud` 的 Secret 对象；
- `existingSecret` 为空时 Helm 明确失败。

实际创建 Secret 的安全命令见 `INSTALL-DEPLOY.md` 第 8 节。

## 本轮遇到的构建与验证错误

### 本机缺少 clang

- 现象：直接运行 `make -C bpf` 报 `/bin/bash: clang: command not found`。
- 原因：宿主机没有 Cilium v1.12.19 所需的 LLVM 工具链。
- 处理：使用该版本固定 digest 的官方 builder 容器编译，并限制为 2 CPU、4 GiB；
  Docker data-root、源码和产物均位于挂载盘。
- 状态：已验证修复，BPF 编译成功。

### builder 容器提示 dubious ownership

- 现象：挂载源码后 Git 提示仓库所有者与容器用户不一致。
- 影响：版本信息探测警告；本次 BPF 编译未因此失败。
- 建议：完整镜像构建时在临时容器配置中加入该源码目录为 safe.directory，不要修改
  宿主机仓库所有权。
- 状态：本次编译不受影响；完整镜像构建时仍需复核版本元数据。

### 对空模板使用 Helm `--show-only`

- 现象：删除华为云 Secret 对象后，`--show-only templates/cilium-operator/secret.yaml`
  在当前条件下提示找不到可输出的模板。
- 原因：该模板只剩其他云厂商的条件对象，华为云场景渲染为空。
- 处理：改为完整渲染，并同时断言 Deployment 的 `secretKeyRef` 与 Secret 对象集合。
- 状态：已验证检查方法，代码无需修改。

### patch 应用身份和中断状态

- 现象：未配置 Git 身份时 `git am` 失败；一次重试进入部分应用状态。
- 处理：先 `git am --abort`，配置明确的提交身份后从干净基线重放。`apply.sh` 也提供
  非自动化名称的安全回退身份。
- 状态：已从 upstream `v1.12.19` 固定提交按 `series` 重放全部 9 个 patch，工作区干净。
