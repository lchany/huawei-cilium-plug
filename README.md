# HuaweiCloud Cilium Patch Archive

这个项目用于管理 HuaweiCloud/SubENI 对 Cilium `v1.19.1` 的适配改动。

它的目标不是维护一份完整的 Cilium fork，而是把 HuaweiCloud 相关修改整理成
patch series。需要构建 HuaweiCloud 版本 Cilium 时，将这些 patch 按顺序应用到
干净的 upstream Cilium `v1.19.1` 源码上。

本项目对外 **不提供 Cilium 源码**。使用方需要自行准备合法获取的 upstream Cilium
`v1.19.1` 源码，本项目只提供 HuaweiCloud 适配 patch。

这种方式解决的是 **源码管理方式解耦**：

- Cilium upstream 源码作为独立基线存在。
- HuaweiCloud 适配逻辑以 patch 文件归档。
- 对外交付内容不包含 Cilium 源码树。
- 后续升级 Cilium 时，可以重新审查和迁移这些 patch。
- patch 应用后仍然会修改 Cilium 源码，这一点和 Terway 的 Cilium patch 管理方式一致。

## 基线版本

这些 patch 面向以下 Cilium 基线：

- upstream tag: `v1.19.1`
- commit: `d0d0c8792c3420b3a6739fa21e3a182827a0bbc6`

`apply.sh` 默认会检查目标仓库是否处于这个 commit，避免 patch 打到错误版本。

## 目录说明

```text
.
├── 0001-huaweicloud-control-plane.patch
├── 0002-huaweicloud-datapath-runtime.patch
├── 0003-huaweicloud-generated-tests-docs.patch
├── series
├── apply.sh
├── runtime-checklist.md
└── README.md
```

- `series`：patch 应用顺序。
- `apply.sh`：在干净的 Cilium 源码树中按 `series` 应用 patch。
- `runtime-checklist.md`：部署后需要验证的基础运行时场景。

## Patch 管理流程

```mermaid
flowchart TB
    base["upstream Cilium v1.19.1 baseline"]
    apply["按 series 顺序应用 patch"]
    source["HuaweiCloud 定制版 Cilium 源码树"]
    build["构建 cilium-agent 和 cilium-operator 镜像"]
    deploy["部署到 HuaweiCloud Kubernetes 集群"]
    verify["按 runtime-checklist.md 验证"]

    change["HuaweiCloud 适配改动"]
    patch["整理为编号 patch"]
    series["更新 series 顺序"]
    run["在目标 Cilium baseline 上运行 apply.sh"]

    base --> apply --> source --> build --> deploy --> verify
    change --> patch --> series --> run --> apply
```

这个项目只保存图中的“编号 patch、series、应用脚本”。Cilium 源码本身不保存在这个
分支里。

## HuaweiCloud 插件原理

HuaweiCloud 适配分为控制面和数据面两部分：

- 控制面负责发现 ECS/VPC/子网/trunk ENI 信息，调用 HuaweiCloud API 创建和释放
  SubENI，并把 Pod 与 SubENI 的关系写入 CiliumNode 和 BPF map。
- 数据面负责在 trunk 网卡上处理 SubENI VLAN 流量。Pod 出方向打 VLAN、改写 SubENI
  MAC；Pod 入方向识别 VLAN、去 VLAN 后交回 Cilium 原生 datapath，继续走连接跟踪、
  NetworkPolicy 和本地投递逻辑。

### 控制面流程

控制面可以先理解成一套“办入网手续”的系统：Pod 要上网，Cilium 需要先向华为云申请
SubENI/IP，再把申请结果登记下来，最后把这些结果写给数据面使用。

先认清几个角色：

| 角色 | 可以理解成 | 主要职责 |
|---|---|---|
| `cilium-operator-huaweicloud` | 节点网络资源管理员 | 发现节点信息，调用华为云 API，维护 `CiliumNode` |
| `CiliumNode` | 每个节点的网络资源档案 | 记录节点有哪些 trunk ENI、子网、安全组、SubENI/IP |
| `Cilium CNI` | Pod 入网办理入口 | Pod 创建时被 kubelet 调用，为 Pod 申请网络 |
| `HuaweiCloud IPAM allocator` | IP/SubENI 分配器 | 决定给 Pod 分配哪个 SubENI/IP |
| `SubENI Endpoint Manager` | 数据面映射下发器 | 把 Pod 和 SubENI 的关系写入 BPF map |
| BPF map | 数据面的查表规则 | 让 BPF 知道出方向怎么打 VLAN，入方向怎么找到 Pod |

下面这张图按编号展示完整流程，后面的步骤说明与图中编号一一对应。

```mermaid
flowchart TB
    subgraph node["节点准备阶段"]
        s1["1 operator 启动"]
        s2["2 读取 Metadata"]
        s3["3 查询华为云资源"]
        s4["4 写入 CiliumNode"]
        s1 --> s2 --> s3 --> s4
    end

    subgraph pod["Pod 入网阶段"]
        s5["5 Pod 创建触发 CNI"]
        s6["6 IPAM 申请 SubENI/IP"]
        s7["7 华为云返回分配结果"]
        s8["8 创建或更新 Endpoint"]
        s5 --> s6 --> s7 --> s8
    end

    subgraph datapath["下发给数据面"]
        s9["9 Endpoint Manager 监听变化"]
        s10["10 写出方向 BPF map"]
        s11["11 写入方向 BPF map"]
        s9 --> s10
        s9 --> s11
    end

    s4 --> s6
    s8 --> s9
```

编号解释：

| 编号 | 发生了什么 | 为什么需要这一步 |
|---|---|---|
| 1 | `cilium-operator-huaweicloud` 启动 | 需要一个组件负责和华为云 API 交互 |
| 2 | operator 读取 `HuaweiCloud Metadata` | 确认“我当前在哪台 ECS、哪个 VPC、哪个可用区” |
| 3 | operator 查询华为云 VPC/SubENI API | 获取 trunk ENI、子网、安全组、SubENI 配额和已有 SubENI |
| 4 | operator 写入 `CiliumNode` | 把节点网络资源登记到 Kubernetes，后续分配 Pod 网络时可以读取 |
| 5 | Pod 创建时 kubelet 调用 `Cilium CNI` | 每个新 Pod 都需要通过 CNI 获得 IP 和网络配置 |
| 6 | `HuaweiCloud IPAM allocator` 申请 SubENI/IP | 给 Pod 选择一个可用的 SubENI/IP；资源不够时创建新的 SubENI |
| 7 | 华为云返回分配结果 | 结果里包含 Pod IP、VLAN ID、SubENI MAC、网关、CIDR |
| 8 | Cilium 创建或更新 `Cilium Endpoint` | Cilium 用 Endpoint 记录这个 Pod 的本地网络状态 |
| 9 | `SubENI Endpoint Manager` 监听 Endpoint 变化 | Endpoint 有了 SubENI 信息后，需要同步给 BPF 数据面 |
| 10 | 写 `cilium_hwc_srcip4` | 出方向使用：BPF 根据 Pod 源 IP 查到 VLAN 和 SubENI MAC |
| 11 | 写 `cilium_hwc_vlan_mac` | 入方向使用：BPF 根据 VLAN 和目的 MAC 找到本地 Pod |

一句话总结：控制面不直接转发数据包，它只负责三件事：**向华为云申请资源、把资源关系登记
到 Cilium、把查表规则下发给 BPF 数据面**。

关键状态：

- `CiliumNode.spec.huawei-cloud`：记录节点侧实例、VPC、trunk ENI、子网、安全组等信息。
- `CiliumNode.status.huawei-cloud`：记录已分配的 SubENI/IP/VLAN/MAC 等运行时状态。
- `cilium_hwc_srcip4`：Pod IP 到 SubENI VLAN/MAC 的映射，供 egress 使用。
- `cilium_hwc_vlan_mac`：VLAN + SubENI MAC 到 endpoint 的映射，供 ingress 识别本地
  SubENI 流量。

### 数据面流程

数据面可以理解成“真正搬运数据包”的部分。控制面已经告诉 BPF：某个 Pod 对应哪个
SubENI、哪个 VLAN、哪个 MAC。数据面收到包以后，就按这些映射表处理。

这里分两条路看：

- **Pod 出方向**：Pod 发出去的包，需要打上对应 SubENI 的 VLAN，并把源 MAC 改成
  SubENI MAC。
- **Pod 入方向**：trunk ENI 收到带 VLAN 的包，需要识别它属于哪个 Pod，去掉 VLAN，
  再交给 Cilium 原生 datapath 继续处理。

#### Pod 出方向

```mermaid
flowchart TB
    e1["1 Pod 发包"]
    e2["2 进入 Cilium endpoint datapath"]
    e3["3 执行 Cilium CT / policy / service 逻辑"]
    e4["4 到达 bpf_host: cil_to_netdev"]
    e5["5 按 Pod 源 IP 查询 cilium_hwc_srcip4"]
    e6["6 改源 MAC 并 push VLAN"]
    e7["7 从 trunk ENI 发出"]

    e1 --> e2 --> e3 --> e4 --> e5 --> e6 --> e7
```

| 编号 | 发生了什么 | 小白解释 |
|---|---|---|
| 1 | Pod 发出数据包 | 比如 Pod 访问 Kubernetes API、Service 或外部地址 |
| 2 | 包先进入 Cilium endpoint datapath | Cilium 先接管 Pod 的流量 |
| 3 | Cilium 执行 CT / policy / service 逻辑 | 这里会处理连接跟踪、网络策略、Service 转发等原生能力 |
| 4 | 包准备从节点网卡发出，进入 `cil_to_netdev` | 这是 Cilium 发往物理网卡前的 BPF 入口 |
| 5 | BPF 用 Pod 源 IP 查询 `cilium_hwc_srcip4` | 查到这个 Pod 应该使用哪个 VLAN 和 SubENI MAC |
| 6 | BPF 改写源 MAC，并给包打 VLAN tag | 华为云用 VLAN 区分不同 SubENI 的流量 |
| 7 | 包从 trunk ENI 发出 | 对云网络来说，这个包看起来就是从对应 SubENI 发出的 |

#### Pod 入方向

```mermaid
flowchart TB
    i1["1 trunk ENI 收到 VLAN 包"]
    i2["2 进入 bpf_host: cil_from_netdev"]
    i3["3 按 VLAN + 目的 MAC 查询 cilium_hwc_vlan_mac"]
    i4["4 pop VLAN 并修正 PACKET_HOST"]
    i5["5 回到 Cilium 原生 datapath"]
    i6["6 执行 Cilium CT / ingress policy / proxy"]
    i7["7 local delivery 到目标 Pod"]

    i1 --> i2 --> i3 --> i4 --> i5 --> i6 --> i7
```

| 编号 | 发生了什么 | 小白解释 |
|---|---|---|
| 1 | trunk ENI 收到带 VLAN 的回包 | 这是云网络返回给某个 SubENI/Pod 的流量 |
| 2 | 包进入 `cil_from_netdev` | 这是 Cilium 处理物理网卡入方向流量的 BPF 入口 |
| 3 | BPF 查询 `cilium_hwc_vlan_mac` | 根据 VLAN 和目的 MAC 判断这个包属于哪个本地 Pod |
| 4 | BPF 去掉 VLAN，并把包标记为 `PACKET_HOST` | 去 VLAN 后，包才能继续按本机 Pod 流量处理 |
| 5 | 包回到 Cilium 原生 datapath | HuaweiCloud 逻辑到这里结束，不直接送进 Pod |
| 6 | Cilium 执行 CT / ingress policy / proxy | 入方向网络策略、连接跟踪、L7 proxy 等能力仍然保留 |
| 7 | Cilium 把包投递到目标 Pod | 这是最终进入 Pod 的一步 |

入方向的关键原则是：HuaweiCloud 逻辑不直接 `redirect` 到 Pod，只做 VLAN 归一化，
然后回到 Cilium 原生路径。这样可以保留 Cilium 的连接跟踪、NetworkPolicy、L7 proxy
和观测能力。

## Patch 说明

### 0001-huaweicloud-control-plane.patch

管理面适配 patch。

这个 patch 负责把 HuaweiCloud 作为一种 Cilium IPAM/云厂商后端接入到控制面。

主要内容：

- 增加 `huaweicloud` IPAM mode。
- 扩展 `CiliumNode` 中的 HuaweiCloud/SubENI 字段。
- 增加 HuaweiCloud VPC/SubENI API client、错误处理和类型定义。
- 增加 SubENI allocator、节点实例信息、配额、metadata 查询逻辑。
- 在 node discovery 中写入 HuaweiCloud 节点、VPC、子网、trunk ENI 等信息。
- 增加 SubENI endpoint manager，用于维护 Pod 与 SubENI/VLAN/MAC 的关系。
- 接入 operator、Helm、RBAC 和构建入口。

它主要影响 Cilium 的 operator、IPAM、CiliumNode CRD、HuaweiCloud API 封装和
SubENI 分配管理逻辑。

### 0002-huaweicloud-datapath-runtime.patch

数据面和运行时接线 patch。

这个 patch 负责让 HuaweiCloud SubENI 分配结果进入 Cilium datapath，并在 BPF 中处理
SubENI VLAN 流量。

主要内容：

- 增加 HuaweiCloud VLAN BPF datapath。
- 在 egress 路径中根据 Pod IP 查找 SubENI 信息，改写源 MAC 并 push VLAN。
- 在 ingress 路径中识别 trunk 网卡上的 SubENI VLAN 包，pop VLAN 后交回 Cilium 原生
  datapath。
- 增加 HuaweiCloud 相关 BPF map、drop reason 和 monitor 展示。
- 将 CNI 返回的 gateway、CIDR、VLAN ID、MAC 等结果传递给 daemon/datapath。
- 接入 endpoint、health endpoint、iptables、node config 等运行时路径。
- 增加 Kubernetes Endpoint / EndpointSlice 兼容处理。

它主要影响 Cilium 的 BPF 代码、CNI 接线、daemon datapath 配置、endpoint 运行时状态
和 K8s service/endpoints 兼容逻辑。

### 0003-huaweicloud-generated-tests-docs.patch

生成物、依赖、测试和文档 patch。

这个 patch 不承载主要业务逻辑，主要用于补齐前两个 patch 引入的依赖和验证材料。

主要内容：

- 更新 `go.mod` / `go.sum`。
- 增加 HuaweiCloud SDK 等 vendor 依赖。
- 更新 CRD yaml、deepcopy、deepequal 等 generated 文件。
- 增加 HuaweiCloud API、allocator、metadata、SubENI map、IPAM、EndpointSlice 等单测。
- 增加 HuaweiCloud Cilium README 和技术说明文档。

它主要用于保证代码生成、依赖 vendoring、测试覆盖和文档说明完整。

## 应用方式

准备干净的 upstream Cilium 源码。该源码由使用方自行获取，本项目不提供：

```bash
git clone https://github.com/cilium/cilium.git cilium-v1.19.1
cd cilium-v1.19.1
git checkout d0d0c8792c3420b3a6739fa21e3a182827a0bbc6
```

从 Cilium 仓库根目录执行本项目中的 `apply.sh`：

```bash
/path/to/patch-archive/apply.sh
```

脚本会按 `series` 顺序应用三个 patch。

## 边界说明

这个项目不是运行时插件，也不是独立 CNI 实现。

它只是 HuaweiCloud 对 Cilium 的源码改动归档，不包含 Cilium 源码。patch 应用后，
使用方本地的 Cilium 源码仍会被修改，包括 Go 控制面代码、BPF 数据面代码、Helm/RBAC、
generated 文件和 vendor 依赖。

后续升级 Cilium 时，应以 `series` 中的 patch 为迁移单元，逐个检查是否仍然需要、
是否可以上游化、是否需要重写。
