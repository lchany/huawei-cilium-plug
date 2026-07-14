# HuaweiCloud Cilium v1.12.19 Patch 归档

这个分支保存 HuaweiCloud SubENI 对 Cilium `v1.12.19` 的适配 patch。它不包含
Cilium 源码。构建时先准备干净的 upstream Cilium 源码，再按 `series` 应用 patch。

patch 应用后会修改 Cilium 源码，这是预期行为。这里所说的解耦，是把 upstream 基线
和 HuaweiCloud 改动分开管理，方式与 Terway 的 Cilium patch 管理相同。

## 固定基线

- upstream tag：`v1.12.19`
- upstream commit：`a1d7fbd43b563c809330b1c3e28165a3e7ff43aa`
- 当前 patch 数量：15（保留最早的 14 个功能 patch，后续测试发现的 bug 修复合并为 1 个 patch）

`apply.sh` 默认检查完整基线 commit，避免把 patch 应用到其他 Cilium 版本。

## 分支内容

```text
.
├── 0001-huaweicloud-control-plane.patch
├── 0002-huaweicloud-datapath-runtime.patch
├── 0003-huaweicloud-generated-tests-dependencies.patch
├── 0004-0014：原有功能与适配 patch
├── 0015-fix-huaweicloud-consolidate-validation-bug-fixes.patch
├── series
├── apply.sh
├── build-local.sh
├── huaweicloud-values.example.yaml
├── INSTALL-DEPLOY.md
├── TROUBLESHOOTING.md
└── README.md
```

### 0001：控制面

接入 HuaweiCloud IPAM、ECS/VPC/SubENI API、metadata、CiliumNode、Operator、Helm
和 SubENI 生命周期管理。空闲 SubENI 回收开关也在这一组，默认关闭。

### 0002：数据面和运行时

增加 trunk 网卡上的 VLAN 处理、HuaweiCloud BPF map、CNI 分配结果传递和 daemon
接线。入方向只去除 VLAN 并回到 Cilium 原生 datapath，连接跟踪和 NetworkPolicy
仍由 Cilium 处理。

### 0003：依赖、生成物和测试

包含华为云 Go SDK vendor、Go 依赖、CRD/DeepCopy 生成文件、CI 构建配置和测试程序。
这一组体积最大，主要原因是 vendor SDK，不代表有同等规模的手写业务代码。

### 0004：Operator 镜像启动修复

修复 upstream Cilium `v1.12.19` Operator 镜像默认启动命令包含未展开的
`${OPERATOR_VARIANT}` 字面量路径的问题。最终镜像统一使用
`/usr/bin/cilium-operator`，并在部署文档中提供构建后验证步骤。

### 0005：保留 Helm variant 启动路径

Helm 的 HuaweiCloud Operator Deployment 会显式执行
`cilium-operator-huaweicloud`。本 patch 在保留通用
`/usr/bin/cilium-operator` 默认命令的同时，也保留 variant 二进制路径，确保两种
启动方式均可用。

### 0006：按标签选择 SubENI 子网

为 Agent 和 Helm 增加华为云子网标签配置，写入 `CiliumNode.Spec.HuaweiCloud.SubnetTags`
并由 Operator 在同 VPC、同可用区内筛选子网。保留 CNI NetConf 的节点级配置方式，补充
单文件、conflist、字段合并和标签筛选回归测试。显式 `subnetIDs` 的优先级高于标签。

### 0007：隔离 SubENI 策略路由表

取消 HuaweiCloud 对 `egress-multi-home-ip-rule-compat` 的自动开启。每个 SubENI 使用
`10000 + VLAN ID` 的独立路由表，避免同一 trunk 上不同网关的 SubENI 互相替换默认路由，
同时避开 Linux 保留表 253～255。VLAN ID 按华为云约束校验为 1～4094，并补充普通单元测试
和真实 network namespace 特权测试。升级时会在新规则和路由完整写入后清理同一 Pod IP
遗留的共享 trunk 表规则，避免旧的 priority 110 规则继续优先生效。

### 0008：兼容华为云入口 VLAN 表示

按 Cilium v1.12.19 的 TC 数据路径适配线内 802.1Q/802.1ad、skb VLAN 元数据以及二者
同时存在的情况。命中 SubENI 映射后显式标记为已处理，避免同一程序后续读取旧
`vlan_present` 状态而被通用 VLAN 过滤误丢弃。v1.12.19 已使用正确的
`HWC_TRUNK_IFINDEX`，因此没有移植 v1.19.1 的 ifindex 修复。

### 0009：使用外部 Secret 注入 Operator 凭据

保留 v1.12.19 原生的 `CILIUM_HUAWEI_CLOUD_*` 环境变量接口，但不再从 Helm values
生成包含 AK/SK 的 Secret。部署前必须创建 Secret，并通过 `huaweicloud.existingSecret`
引用；Secret 或键不存在时 Operator Pod 会明确启动失败。

### 0010：同步子网真实可用地址数

通过华为云 V1/V2 子网接口读取 `available_ip_address_count`，再与 V3 Virsubnet 的标签、
VPC 和可用区信息合并，填充 `ipamTypes.Subnet.AvailableAddresses`。容量为 0 或小于本次
申请量的子网不再参与选择；自动候选选择真实剩余地址最多的一个，同容量时按 ID
稳定选择；显式列表严格按配置顺序选择首个合法且容量充足的子网。

### 0011～0014：原有行为适配

分别处理 CNI `min-allocate`、probe 模式下显式关闭 NodePort、endpoint route 源地址以及
本地 Service 源地址语义。这些功能 patch 保持独立，不与后续测试修复混合。

### 0015：统一的测试修复 patch

只包含相对前 14 个功能 patch 的后续 bug 修复增量，来源是边界、并发和五节点实机测试。
按完整 `series` 回放后的 Git tree 与最终验证源码树一致。

## 管理流程

```mermaid
flowchart LR
    base["upstream Cilium v1.12.19"]
    patches["按 series 应用 14 个功能 patch + 1 个 bugfix patch"]
    source["HuaweiCloud 定制源码树"]
    build["构建 Agent / CNI / Operator"]
    deploy["部署并验证 SubENI"]

    base --> patches --> source --> build --> deploy
```

快速使用：

```bash
git clone --branch v1.12.19 --depth 1 https://github.com/cilium/cilium.git cilium
cd cilium
git rev-parse HEAD
/path/to/huawei-cilium-patches/apply.sh
```

从准备、构建、镜像分发到验收的完整步骤见 [INSTALL-DEPLOY.md](INSTALL-DEPLOY.md)。
部署配置从 [huaweicloud-values.example.yaml](huaweicloud-values.example.yaml) 复制，填写
实际云资源后使用。AK/SK 只写入 Kubernetes Secret，不写入 values 或命令行。

版本适配审核、实际问题对应关系和验证记录见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

华为云子网既可以通过 `huaweicloud.subnetIDs` 指定，也可以通过
`huaweicloud.subnetTags` 按标签选择；同时配置时子网 ID 优先。节点级差异化配置可通过
CNI NetConf 的 `huawei-cloud.subnet-tags` 设置，完整步骤见部署文档。

## 更新 patch

不要直接手改 patch 文件。先在独立开发分支修改和测试源码，再按控制面、数据面、
依赖/生成物/测试和独立修复等职责重新生成 patch。每次更新后都要在干净基线上运行
`apply.sh`，并比较重放结果和已验证源码树。
