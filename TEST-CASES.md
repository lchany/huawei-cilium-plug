# HuaweiCloud Cilium v1.12.19 测试用例

本文给出 HuaweiCloud SubENI 适配的完整测试目录，共 451 项，仅包含测试条件、
测试操作和预期结果。

适用基线：

- upstream Cilium：`v1.12.19`
- upstream commit：`a1d7fbd43b563c809330b1c3e28165a3e7ff43aa`
- patch 集合：`series` 中的 15 个 patch

## 1. 隐私与记录要求

- 文档和测试报告使用 `<NODE_IP>`、`<POD_IP>`、`<VPC_ID>`、`<SUBNET_ID>`、
  `<SECURITY_GROUP_ID>` 等占位符，不填写真实资源标识。
- AK/SK、密码、Token、私钥和 Secret 数据值不得写入命令行、日志、抓包、报告或 Git。
- Kubernetes Secret 只核对对象名和键名；不得导出或打印 `.data`、`.stringData`。
- 日志和云 API 错误可以保留 request ID，但必须删除认证头、签名和凭据值。
## 2. 优先级与类型

| 标记 | 含义 |
| --- | --- |
| `P0` | 发布阻断项，交付前必须通过或取得明确的风险接受 |
| `P1` | 发布前应完成的功能、恢复和兼容性用例 |
| `P2` | 性能、规模、长期稳定性或可选能力用例 |
| `R` | 在隔离的真实云环境执行 |
| `C` | 故障注入或破坏性操作，只能使用测试资源并准备回滚 |
| `S` | 源码、构建、模拟 API、内核 BPF 或离线检查 |
| `O` | 取决于目标环境是否启用对应能力 |

## 3. 通用测试环境

建议使用一个控制面节点和四个工作节点，覆盖同节点、同可用区跨节点和跨可用区路径。
环境不满足某项拓扑或云配额时，应在测试计划中标记限制，不得把未执行项写成通过。

所有用例共用以下约束：

1. 使用专用 VPC、子网、安全组、凭据和镜像仓库，不操作生产资源。
2. 高风险用例一次只影响一个工作节点；执行前保存 Kubernetes、CiliumNode、路由、
   BPF map 和云资源摘要，结束后确认资源恢复。
3. 网络用例至少覆盖 ICMP、TCP、UDP，以及 Pod、Node、ClusterIP、NodePort、VPC 内网
   和公网中适用的目标。
4. 变更配置、重启组件或注入故障后，除目标断言外还要复测存量 Pod 和基础 Service。
5. 每个用例都应明确前置条件、操作步骤、预期结果和清理步骤；本文表格给出最低断言。

## 4. 功能、部署与实机用例

### 4.1 基线、patch、构建与制品

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| BASE-01 | P0/S | 固定 upstream commit 应用 15 个 patch | `apply.sh` 成功，15 个提交顺序与 `series` 一致，工作树干净 |
| BASE-02 | P0/S | 错误 upstream tag/commit | `apply.sh` 在修改源码前失败，不产生半应用结果 |
| BASE-03 | P1/S | patch 中断后恢复 | `git am --abort` 后可从固定基线重新完整重放 |
| BASE-04 | P0/S | 15 个 patch 完整性 | 文件名、顺序、SHA256、提交 ID 记录到报告 |
| BASE-05 | P0/S | Go 单元/组件定向测试 | HuaweiCloud API、IPAM、CNI、node discovery、routing、daemon 测试通过 |
| BASE-06 | P0/S | privileged routing 测试 | 独立 netns 中验证双 VLAN 表和遗留规则清理 |
| BASE-07 | P0/S | BPF 全排列编译 | HuaweiCloud VLAN 相关宏组合编译通过，无 verifier 错误 |
| BASE-08 | P0/S | Agent/CNI/Operator 构建 | 三类产物构建成功，版本元数据来自固定源码树 |
| BASE-09 | P0/R | 镜像 CPU 架构匹配 | 五台 ECS 均可拉取/导入并启动对应架构镜像 |
| BASE-10 | P0/R | Operator 镜像默认命令 | `Config.Cmd` 精确为 `/usr/bin/cilium-operator` |
| BASE-11 | P0/R | Operator 双二进制 | 通用和 `cilium-operator-huaweicloud` 均存在且 `--help` 成功 |
| BASE-12 | P1/S | 重复构建一致性 | 两次构建功能、文件清单和关键二进制一致；差异有解释 |
| BASE-13 | P1/S | 离线镜像分发 | 每节点导入后 digest 一致，不依赖公网仓库 |
| BASE-14 | P1/R | 私有仓库分发 | imagePullSecret、拉取、重启和跨节点一致性通过 |
| BASE-15 | P2/S | SBOM/漏洞/许可证检查 | 记录扫描工具、数据库时间和未解决高危项 |

### 4.2 ECS、Kubernetes、metadata 与 trunk 前置条件

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| PRE-01 | P0/R | 1 control-plane + 4 worker、2 AZ | 五节点 Ready，业务 Pod 可覆盖四个 worker |
| PRE-02 | P1/O | 3 control-plane + 2 worker | 控制面 HA 正常，仍能覆盖至少两个 AZ 的 worker 流量 |
| PRE-03 | P0/R | Kubernetes/Cilium 版本 | Kubernetes v1.24 与 Cilium v1.12.19 patch 基线可追溯 |
| PRE-04 | P0/R | 内核、cgroup、容器运行时 | 五节点配置一致或差异已记录，Cilium preflight 无阻断 |
| PRE-05 | P0/R | 时钟、DNS、NTP | 五节点时钟偏差在门限内，证据时间可关联 |
| PRE-06 | P0/R | 单网卡 trunk 识别 | 系统 MAC、metadata port、默认路由网卡一一对应 |
| PRE-07 | P0/R | 多网卡 trunk 识别 | 不依赖“第一张网卡”，显式选中正确 trunk |
| PRE-08 | P1/C | 默认路由网卡不是 trunk | 配置正确 trunk 后正常；错误网卡 fail-fast，不误操作其他端口 |
| PRE-09 | P0/R | metadata 中实例/VPC/AZ/port 信息 | 与控制台和 CiliumNode 一致 |
| PRE-10 | P1/C | metadata 短时不可达 | 明确报错并重试，已有 Pod 网络不受影响，恢复后收敛 |
| PRE-11 | P1/C | metadata 返回空、 malformed 或 MAC 不匹配 | 不创建错误 SubENI，错误可诊断 |
| PRE-12 | P1/C | trunk link flap | 恢复后路由、邻居、BPF map 和 Pod 网络自动恢复 |
| PRE-13 | P0/R | VPC、AZ、子网和 SG 归属 | 所有测试资源属于目标项目/VPC/AZ，无跨租户引用 |
| PRE-14 | P0/R | 子网可用 IP 和 SubENI 配额 | 满足计划峰值加 30% 余量 |
| PRE-15 | P1/R | ECS flavor 限额识别 | CiliumNode capacity 与华为云规格上限一致 |
| PRE-16 | P1/C | 未知/不支持 flavor | 不超配，错误明确，已有 Pod 不受影响 |
| PRE-17 | P0/R | 安全组基础矩阵 | 仅放通测试所需 TCP/UDP/ICMP/DNS，不依赖全开放 SG |
| PRE-18 | P1/R | iproute2、tcpdump、ethtool、conntrack 工具 | 五节点可采集路由、抓包和 offload 证据 |

### 4.3 外部 Secret、Helm 与凭据安全（0009）

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| SEC-01 | P0/S | `existingSecret` 正常渲染 | Deployment 两个 `secretKeyRef` 均为 required |
| SEC-02 | P0/S | `existingSecret` 为空 | `helm lint/template` 明确失败 |
| SEC-03 | P0/R | Secret 对象不存在 | Operator Pod 不启动并给出缺失 Secret 错误，Agent 不泄密 |
| SEC-04 | P0/R | Secret 缺 AK 键 | Operator `CreateContainerConfigError`，不进入错误调谐 |
| SEC-05 | P0/R | Secret 缺 SK 键 | Operator `CreateContainerConfigError`，不进入错误调谐 |
| SEC-06 | P0/R | AK/SK 正确 | Operator 正常调用只读 API 和创建测试 SubENI |
| SEC-07 | P1/C | AK/SK 错误或过期 | 鉴权失败可诊断，日志/事件不显示原值，已有数据面不受影响 |
| SEC-08 | P1/C | Secret 轮换 | 更新 Secret 并滚动 Operator 后新凭据生效，无重复/泄漏 SubENI |
| SEC-09 | P0/S | Helm 渲染对象集合 | 不生成 HuaweiCloud Secret 对象，只引用预创建 Secret |
| SEC-10 | P0/S | Helm values 和命令行扫描 | 不存在 `accessKey`/`secretKey` 值，凭据不进入 shell history |
| SEC-11 | P0/R | Helm release Secret 扫描 | release manifest 不含真实 AK/SK |
| SEC-12 | P0/R | Pod spec、事件、日志扫描 | 不出现真实凭据；仅允许 Secret 名称和键名 |
| SEC-13 | P0/R | Helm upgrade/rollback | 外部 Secret 不被覆盖、重建或删除 |
| SEC-14 | P0/R | Helm uninstall | 外部 Secret 保留，必须由运维显式删除 |
| SEC-15 | P1/O | 自定义 Secret 名称 | 引用正确 namespace 内对象并正常启动 |
| SEC-16 | P1/C | Secret 位于错误 namespace | Operator 明确失败，不跨 namespace 读取 |
| SEC-17 | P1/R | 特殊字符凭据 | 通过 `secretKeyRef` 原样传递，不经过模板/base64 二次处理 |
| SEC-18 | P1/O | External Secrets/CSI 控制器轮换 | 生成的 Kubernetes Secret 与 Operator 重启流程兼容 |
| SEC-19 | P0/R | 最小云权限 | 仅授予所需 SubENI/VPC/ECS 查询与变更权限即可工作 |
| SEC-20 | P1/C | 缺查询/创建/删除/打标签权限分别验证 | 错误分类正确，不误删，不暴露凭据 |

### 4.4 Helm、CRD、安装和基础状态

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| INS-01 | P0/S | CRD server dry-run | v2/v2alpha1 CRD 均可接受 |
| INS-02 | P0/S | Helm lint/template 正常配置 | 无模板错误、双后缀镜像或意外 Secret |
| INS-03 | P0/S | HuaweiCloud disabled | 不渲染 HuaweiCloud 参数和凭据引用，原生路径无回归 |
| INS-04 | P0/R | 首次安装 | Agent 5/5、Operator 1/1 Ready |
| INS-05 | P0/R | 重复 `helm upgrade --install` | 幂等，无无关资源变更和网络中断 |
| INS-06 | P0/R | Cilium status | Kubernetes、Cilium、Cluster health 正常 |
| INS-07 | P0/R | 五个 CiliumNode | 实例、VPC、AZ、trunk、子网配置和状态正确 |
| INS-08 | P0/R | ConfigMap 参数 | trunk、native routing CIDR、masquerade、subnet/SG 配置正确 |
| INS-09 | P1/C | 缺 CRD 安装 | Helm/Pod 错误明确，补装 CRD 后恢复 |
| INS-10 | P1/C | Agent 镜像不可拉取 | 仅目标节点失败，修复镜像后自动恢复 |
| INS-11 | P1/C | Operator 镜像错误或双后缀 | 预检查应阻断，不进入实机安装 |
| INS-12 | P1/R | 节点污点和 toleration | 控制面/worker 的 Agent 调度符合设计 |
| INS-13 | P1/R | Operator 单副本重启 | Deployment 自动拉起并重新调谐 |
| INS-14 | P1/O | Operator 多副本/选主 | 同时仅一个 leader 执行云资源变更 |
| INS-15 | P1/R | CNI 文件落盘 | `.conf`/`.conflist` 与 Helm/Agent 配置符合预期 |

### 4.5 HuaweiCloud API 正常、异常与最终一致性

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| API-01 | P0/R | 单个 Create SubENI | 返回 ID，最终 Active，CiliumNode 状态一致 |
| API-02 | P0/R | BatchCreate SubENI | 数量、子网、父 trunk、SG 正确，无漏项 |
| API-03 | P0/R | Get/Show SubENI | 状态、IP、MAC、VLAN、网关解析正确 |
| API-04 | P0/R | List SubENI | 能发现本测试节点全部 SubENI，不混入其他节点 |
| API-05 | P1/S | List 分页 marker | 跨页不丢失、不重复、不死循环 |
| API-06 | P0/R | SubENI 标签写入 | 预期标签完整，值和资源范围正确 |
| API-07 | P0/R | Delete SubENI | 仅删除目标空闲测试 SubENI，状态最终收敛 |
| API-08 | P1/C | Delete 已不存在资源/404 | 视为可收敛状态或给出可重试错误，不阻塞全局调谐 |
| API-09 | P1/C | Create 超时 | 不无限等待；恢复后核对是否实际创建，避免重复资源 |
| API-10 | P1/C | Wait Active 超过 60 秒 | 超时明确，失败资源回滚或标记待清理 |
| API-11 | P1/C | HTTP 429 | 限流分类、退避和恢复正确，已有 Pod 不受影响 |
| API-12 | P1/C | 5xx/网络断开 | 自动重试且无高频风暴，恢复后收敛 |
| API-13 | P1/C | 401/403 | 不盲目重试高危操作，错误包含 request ID 但无凭据 |
| API-14 | P1/S | batch 部分成功 | 已创建资源被识别，失败路径无泄漏 |
| API-15 | P1/C | 打标签失败 | 本批创建资源回滚；回滚失败时记录可追踪资源 ID |
| API-16 | P1/C | 回滚删除失败 | 后续调谐可再次清理，不误删已使用资源 |
| API-17 | P1/R | API 最终一致性延迟 | 短暂 NotFound/非 Active 不导致重复创建 |
| API-18 | P1/C | endpoint/region/project 配错 | fail-fast，不跨项目/VPC 创建资源 |
| API-19 | P1/R | API QPS/突发限制 | burst 场景无持续 429，调谐速率可接受 |
| API-20 | P2/S | 错误码标准化矩阵 | 404、429、容量不足、鉴权、5xx 映射一致 |

### 4.6 IPAM、子网、安全组、配额和资源生命周期

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| IPAM-01 | P0/R | 每个 worker 首次分配 | Pod IP、CiliumNode、SubENI、trunk、VLAN、MAC 一一对应 |
| IPAM-02 | P0/R | 同节点多个 Pod | IP/VLAN 唯一，均挂到正确 trunk |
| IPAM-03 | P0/R | 四 worker 并发分配 | 不跨节点挂载，不重复 IP |
| IPAM-04 | P0/R | 按标签选择同 AZ 子网 | 只匹配同 VPC、同 AZ、全部标签满足的子网 |
| IPAM-05 | P0/R | 多标签 AND | 缺少任一标签的子网不被选择 |
| IPAM-06 | P1/R | 空标签值、特殊字符标签 | 行为与云标签语义一致并可诊断 |
| IPAM-07 | P0/R | 标签无匹配 | 新 Pod Pending，其他节点与已有 Pod 不受影响 |
| IPAM-08 | P0/R | 显式 subnet ID | 只使用指定且同 VPC/AZ 的子网 |
| IPAM-09 | P0/R | ID 与标签同时配置 | ID 始终优先 |
| IPAM-10 | P1/C | 显式 ID 属于其他 AZ | 不创建错误 SubENI，错误明确 |
| IPAM-11 | P1/C | 显式 ID 属于其他 VPC | 不跨 VPC 创建资源 |
| IPAM-12 | P1/R | 多个合格标签子网 | 选择稳定且容量变化后可合理切换 |
| IPAM-13 | P1/C | 首选子网容量耗尽 | 切换其他合格子网或明确失败，不影响已有 Pod |
| IPAM-14 | P1/C | 所有子网容量为 0 | 新建失败且无泄漏 |
| IPAM-15 | P1/R | 容量未知 | 按实现允许候选，真实 API 结果决定成功/失败 |
| IPAM-16 | P0/R | 显式安全组 ID | 新 SubENI 只附加目标测试 SG |
| IPAM-17 | P1/R | 安全组标签选择 | 只选择同 VPC 且标签完全匹配的 SG |
| IPAM-18 | P0/R | 未配置 SG 时继承 trunk | SubENI SG 与 trunk port 一致 |
| IPAM-19 | P1/C | SG ID 无效/跨 VPC | 创建失败，不降级到不安全默认值 |
| IPAM-20 | P1/R | 多安全组 | 顺序不影响语义，全部目标 SG 生效 |
| IPAM-21 | P1/R | SubENI 资源标签 | 每个新建 SubENI 都带测试归属/用途标签 |
| IPAM-22 | P1/R | Agent-only 配置 | CiliumNode 写入 Agent 配置 |
| IPAM-23 | P1/R | CNI-only 配置 | `.conf` 与 `.conflist` 均能写入节点配置 |
| IPAM-24 | P1/R | Agent+CNI 字段级合并 | CNI 非空字段覆盖，空字段不抹掉 Agent 配置 |
| IPAM-25 | P1/C | CNI JSON 错误/字段类型错误 | CNI 明确失败，不写入半配置 |
| IPAM-26 | P0/R | `releaseExcessIPs=false` | 缩容后不主动删除空闲 SubENI |
| IPAM-27 | P0/C | `releaseExcessIPs=true` | 延迟后只回收空闲测试 SubENI |
| IPAM-28 | P0/C | 在用 IP 保护 | 任意缩容/重调谐都不删除仍被 Pod 使用的 SubENI |
| IPAM-29 | P1/C | 回收 Delete 失败 | 状态不丢，后续重试最终收敛 |
| IPAM-30 | P1/R | 连续扩缩容 10 轮 | 无 IP/SubENI/port/CiliumNode 状态泄漏 |
| IPAM-31 | P1/R | 达到 flavor SubENI 上限 | 新 Pod 有明确容量错误，已有 Pod 正常 |
| IPAM-32 | P1/R | 达到子网 IP 上限 | 不超配、不重复申请、不污染其他子网 |
| IPAM-33 | P1/R | 达到项目配额 | API 错误清晰，恢复配额后自动成功 |
| IPAM-34 | P1/C | 手工删除一个测试 SubENI | 漂移被发现；受影响范围和恢复行为可解释 |
| IPAM-35 | P1/C | 手工修改测试 SubENI SG/标签 | 调谐是否纠正或保留必须与设计一致并记录 |
| IPAM-36 | P1/C | 删除测试节点/CiliumNode | 只处理该节点测试资源，不影响其他节点 |
| IPAM-37 | P1/R | Pod IP 快速复用 | 旧 map/route/邻居项先清理，新 endpoint 正确接管 |

### 4.7 SubENI 策略路由和多网关隔离（0007）

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| ROUTE-01 | P0/R | 单 SubENI 路由基线 | 源 rule、直连路由、default route、gateway 正确 |
| ROUTE-02 | P0/R | 同节点同网关多 SubENI | 每个 VLAN 仍使用独立表，互不覆盖 |
| ROUTE-03 | P0/R | 同节点不同网关双子网 | 各自使用 `10000 + VLAN ID`，持续双向可用 |
| ROUTE-04 | P0/R | A 后 B 创建 | B 创建不改变 A 的 default gateway 和连通性 |
| ROUTE-05 | P0/R | B 后 A 创建 | 创建顺序不影响结果 |
| ROUTE-06 | P0/R | 删除/重建其中一个 Pod | 另一 Pod 路由和连接不中断 |
| ROUTE-07 | P0/R | Agent 重启 | 表号、rule、route 和连通性恢复一致 |
| ROUTE-08 | P0/R | worker 重启 | VLAN 对应表稳定，无共享表回退 |
| ROUTE-09 | P0/C | 从旧共享 ifindex 表升级 | 新表完整后才删除旧 priority 110/111 rule |
| ROUTE-10 | P0/R | 显式 compat=false | HuaweiCloud 不被自动改回 compat，使用 priority 111 |
| ROUTE-11 | P1/R | 显式 compat=true | 仅优先级变为 compat，表仍按 VLAN 隔离 |
| ROUTE-12 | P1/C | 遗留重复 rule | 只清理同源旧 rule，保留当前正确 rule |
| ROUTE-13 | P1/R | VLAN 边界和表范围 | 实际 VLAN 映射到 10001～14094，不占用 253～255 |
| ROUTE-14 | P1/C | VLAN 0、>4094 或解析错误 | 拒绝配置，不创建非法规则 |
| ROUTE-15 | P1/C | 手工删除测试 route/rule | Agent/endpoint 重建路径能恢复或明确告警 |
| ROUTE-16 | P1/R | 宿主已有其他策略规则 | 不删除非 HuaweiCloud、不同源地址的规则 |
| ROUTE-17 | P1/R | VPC 内网与公网双目标 | 两类流量均从该 Pod 对应 SubENI/gateway 返回 |
| ROUTE-18 | P1/R | 长连接期间新增第二网关 Pod | 已建立连接不因默认路由替换而中断 |

### 4.8 BPF map 与 VLAN 数据面（0002、0008）

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| BPF-01 | P0/R | endpoint Ready | IP→VLAN/MAC/ifindex 与 VLAN+MAC→endpoint 两类 map 均写入 |
| BPF-02 | P0/R | endpoint 删除 | 对应两类 map 条目清理，无误删其他 endpoint |
| BPF-03 | P0/R | Agent 重启/endpoint restore | map 从 endpoint/状态恢复，存量 Pod 恢复通信 |
| BPF-04 | P1/R | Pod 快速创建删除 | map 无残留、无缺失、无键冲突 |
| BPF-05 | P1/S | 第二张 map 写失败 | 第一张 map 回滚，避免半配置 |
| BPF-06 | P1/S | 重复 Ready/Delete 事件 | 操作幂等，无 panic 和 stale entry |
| BPF-07 | P1/S | 非法 IP/MAC/VLAN/ifindex | 拒绝写入并记录明确错误 |
| BPF-08 | P1/R | map 容量接近上限 | 新增行为可控，已有条目不损坏 |
| VLAN-01 | P0/R | skb VLAN metadata 入方向 | 命中 map、剥离 VLAN、进入正常 Cilium datapath |
| VLAN-02 | P0/R | 线内 802.1Q 入方向 | `0008` 正确解析、剥离并转发 |
| VLAN-03 | P0/R | 线内 802.1ad 入方向 | `0008` 正确解析、剥离并转发 |
| VLAN-04 | P0/R | 线内 VLAN 与 metadata 同时存在 | 线内优先、按实际表示两阶段 pop，不重复过滤 |
| VLAN-05 | P0/R | 只有一种 VLAN 表示 | 只 pop 一次，不破坏内层原始报文 |
| VLAN-06 | P0/R | 处理后 `vlan_present` 仍为旧值 | `handled` 阻止通用 VLAN 过滤误丢包 |
| VLAN-07 | P0/R | 出方向 VLAN 添加 | VLAN、源/目的 MAC 与 SubENI/trunk 一致 |
| VLAN-08 | P0/R | 入方向目标 MAC+VLAN 命中 | 正确映射到目标 endpoint |
| VLAN-09 | P1/C | VLAN 正确但 MAC 不匹配 | 不误投递到其他 Pod，出现可解释 drop |
| VLAN-10 | P1/C | MAC 正确但 VLAN 不匹配 | 不绕过 map 校验和 NetworkPolicy |
| VLAN-11 | P1/C | 截断/非法 VLAN header | `DROP_INVALID` 或明确 drop reason，无 verifier/Agent 异常 |
| VLAN-12 | P1/C | VLAN pop helper 失败 | `DROP_HWC_VLAN_POP_FAIL` 计数和日志可观测 |
| VLAN-13 | P1/O | 双层 QinQ | 明确验证并记录支持边界，不默认宣称支持 |
| VLAN-14 | P1/R | 非 trunk 接口 VLAN 流量 | HuaweiCloud helper 不处理，不影响原生 VLAN 逻辑 |
| VLAN-15 | P1/R | GSO/GRO/checksum offload 开关矩阵 | 开关前后 TCP/UDP 正确，无 checksum/drop 异常 |
| VLAN-16 | P1/R | ICMP/TCP/UDP、分片与大包 | 各协议双向流量均走正确 VLAN |

### 4.9 Pod、Node、Service、DNS 与出口网络

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| NET-01 | P0/R | 同节点 Pod↔Pod | 正反向 ICMP/TCP/UDP 成功 |
| NET-02 | P0/R | 同 AZ 跨节点 Pod↔Pod | A1↔A2 全协议成功 |
| NET-03 | P0/R | 跨 AZ Pod↔Pod | A1/A2↔B1/B2 正反向成功 |
| NET-04 | P0/R | Pod→本节点 NodeIP | 可达且源地址/策略符合配置 |
| NET-05 | P0/R | Pod→远端 NodeIP | 跨节点双向路径正常 |
| NET-06 | P1/R | Node→本节点 Pod | host 发起访问成功，回程正确 |
| NET-07 | P1/R | Node→远端 Pod | 不出现非对称路由或 rp_filter 问题 |
| NET-08 | P1/R | hostNetwork Pod↔SubENI Pod | 行为与安全策略设计一致 |
| SVC-01 | P0/R | ClusterIP TCP | 四节点 client 连续访问全部成功 |
| SVC-02 | P0/R | ClusterIP UDP | UDP Service 正常，无 conntrack 异常 |
| SVC-03 | P1/R | Headless Service | DNS 返回 Pod IP，逐个后端可达 |
| SVC-04 | P1/R | NodePort TCP/UDP | 5 个 NodeIP、本地/远端后端组合通过 |
| SVC-05 | P1/R | `externalTrafficPolicy=Cluster` | 全节点入口可用，源地址语义符合预期 |
| SVC-06 | P1/R | `externalTrafficPolicy=Local` | 有本地后端节点可用，无后端节点按设计失败 |
| SVC-07 | P1/R | sessionAffinity | 同 client 在超时窗口内保持后端 |
| SVC-08 | P1/O | ExternalIP | 目标环境允许时验证正反向路径 |
| SVC-09 | P1/O | LoadBalancer | 云 LB 健康检查、后端、源 IP 和策略通过 |
| SVC-10 | P1/R | Service 后端滚动更新 | 无长期黑洞，旧 conntrack 最终回收 |
| DNS-01 | P0/R | 集群域名 UDP | 四 worker 上解析稳定 |
| DNS-02 | P0/R | 集群域名 TCP fallback | 大响应/强制 TCP 解析成功 |
| DNS-03 | P0/R | 公网域名 | 解析和回程正常 |
| DNS-04 | P1/R | CoreDNS 单 Pod 重启 | 客户端在门限内恢复，无节点特异故障 |
| EGR-01 | P0/R | Pod→同 VPC 内网 | 不错误 SNAT 或按配置 SNAT，回程正常 |
| EGR-02 | P0/R | Pod→公网 | 从 trunk 出口 SNAT，回包进入原 Pod |
| EGR-03 | P1/R | 多目标并发出口 | 不因不同目的更新错误默认路由 |
| EGR-04 | P1/R | 公网失败但 VPC 内网正常 | 能区分外部网络/安全组与 Cilium 故障 |
| MTU-01 | P0/R | 小包、MTU-1、MTU、MTU+1 | 成功或产生正确 PMTU/分片行为，无静默黑洞 |
| MTU-02 | P1/R | DF ping/PMTUD | ICMP Too Big/Fragmentation Needed 路径正常 |
| CONN-01 | P1/R | TCP 长连接 30 分钟 | Agent/Operator正常运行期间不异常断开 |
| CONN-02 | P1/R | 1000 并发短连接 | 错误率和延迟满足门限，conntrack 不溢出 |
| CONN-03 | P1/R | UDP 持续流 | 无明显乱序、单向通或持续丢包 |
| IPV6-01 | P1/O | IPv6 配置边界 | 当前 IPv4/SubENI 方案应明确拒绝或不影响 IPv4，不误宣称双栈支持 |

### 4.10 NetworkPolicy 与安全边界

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| NP-01 | P0/R | 无策略基线 | 所有允许的测试路径正常 |
| NP-02 | P0/R | namespace 默认 deny ingress/egress | 新建连接被拒绝且有 policy drop 证据 |
| NP-03 | P0/R | label L3 allow | 仅目标 label 可达 |
| NP-04 | P0/R | TCP/UDP 端口 allow | 仅协议和端口精确放通 |
| NP-05 | P0/R | DNS allow + 其他 egress deny | DNS 成功，未授权出口失败 |
| NP-06 | P1/R | CIDR allow/deny | VPC 和公网 CIDR 行为符合策略 |
| NP-07 | P0/R | 同节点策略 | VLAN helper 不绕过 conntrack/policy |
| NP-08 | P0/R | 跨节点/跨 AZ 策略 | 与同节点语义一致 |
| NP-09 | P1/R | Service 前端到后端策略 | ClusterIP/NodePort 后端策略正确 |
| NP-10 | P1/R | 策略动态增删 | 在收敛门限内切换，无残留 |
| NP-11 | P1/R | 已建立连接遇到策略变化 | 行为符合 Cilium conntrack/policy 语义并记录 |
| NP-12 | P1/R | 其他 namespace 隔离 | 测试策略不影响 kube-system 和非测试 namespace |

### 4.11 故障注入、漂移与恢复

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| REC-01 | P0/C | 删除单个 Cilium Agent Pod | 自动拉起，map/route 恢复，不重复创建 SubENI |
| REC-02 | P0/C | 滚动重启 DaemonSet | 五节点逐一恢复，业务中断满足门限 |
| REC-03 | P0/C | 删除 Operator Pod | 恢复后继续调谐，无重复/泄漏资源 |
| REC-04 | P1/C | Operator 在创建过程中退出 | 最终识别已创建资源，不重复创建 |
| REC-05 | P1/C | Operator 在打标签过程中退出 | 恢复后补齐或回滚，资源可追踪 |
| REC-06 | P1/C | kubelet 重启 | Node/Pod/CNI 自动恢复 |
| REC-07 | P1/C | containerd/Docker 重启 | Cilium 和工作负载恢复，已有云资源不被误删 |
| REC-08 | P1/C | worker-b2 重启 | 其他四节点持续可用，目标节点恢复完整状态 |
| REC-09 | P1/C | worker cordon/drain/uncordon | Pod 重调度与 SubENI 生命周期正确 |
| REC-10 | P1/C | 控制面 API Server 短时不可达 | 已有数据面继续，新调谐恢复后收敛 |
| REC-11 | P1/C | Operator→云 API 网络断开 | 退避合理，恢复后无泄漏 |
| REC-12 | P1/C | 节点 DNS 故障 | 能区分云 API 域名与集群 DNS 故障 |
| REC-13 | P1/C | 错误云凭据 | 只影响新云操作，现有 Pod 网络保持 |
| REC-14 | P1/C | 测试子网耗尽 | 仅新 Pod Pending，恢复容量后自动成功 |
| REC-15 | P1/C | 测试 SG 临时阻断 | drop 与 SG 规则一致，恢复后连接恢复 |
| REC-16 | P1/C | trunk 接口 down/up | 目标节点故障可观测，up 后自动恢复 |
| REC-17 | P1/C | 删除一条测试策略路由 | 重建 endpoint/Agent 后恢复，无跨 Pod 污染 |
| REC-18 | P1/C | 删除一个测试 BPF map 条目 | 影响范围可控，恢复路径可验证 |
| REC-19 | P1/C | 云端手工删除空闲 SubENI | CiliumNode 和云状态最终一致 |
| REC-20 | P1/C | 云端手工删除在用 SubENI | 明确记录当前修复边界，不误删其他资源 |
| REC-21 | P1/C | 节点 NotReady 超过回收窗口 | 不提前回收仍可能在用的 SubENI |
| REC-22 | P1/O | Operator 多副本 leader 切换 | 单次云操作，不因重复事件产生重复资源 |
| REC-23 | P2/C | 节点时间跳变 | 超时/释放窗口不产生提前删除 |
| REC-24 | P2/C | 大量 Kubernetes 事件积压 | 恢复后按最终状态收敛，无调谐风暴 |

### 4.12 容量、性能和稳定性

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| SCALE-01 | P1/R | 40 Pod burst 均匀分布 | 全部 Ready，记录 P50/P95/P99 分配时延 |
| SCALE-02 | P1/R | 单节点 burst | 不超 flavor/子网上限，其他节点不受影响 |
| SCALE-03 | P1/R | 五节点并发扩容 | API 限流可控，CiliumNode 最终一致 |
| SCALE-04 | P1/R | 40→4→40 循环 10 次 | 无 SubENI/IP/map/route 泄漏 |
| SCALE-05 | P2/R | 接近最大 Pod 数 | 记录最大稳定规模和失败边界 |
| PERF-01 | P1/R | 同节点吞吐/RTT | 与原生/旧 CNI 基线对比 |
| PERF-02 | P1/R | 同 AZ 跨节点吞吐/RTT | 每组至少三次，记录中位数和偏差 |
| PERF-03 | P1/R | 跨 AZ 吞吐/RTT | 区分 AZ 网络基线与 Cilium 开销 |
| PERF-04 | P1/R | TCP/UDP PPS | 无异常 softirq、drop 或 BPF 开销尖峰 |
| PERF-05 | P1/R | Pod 创建到 Ready 时延 | 分解 API、IPAM、CNI、镜像拉取时间 |
| PERF-06 | P1/R | Agent/Operator CPU、内存 | 空闲、burst、稳定性三阶段记录 |
| PERF-07 | P1/R | 云 API 调用率 | 无无效高频 List/Create/Delete |
| STAB-01 | P2/O | 持续探测（可选时长） | 成功率达标，无资源持续增长 |
| STAB-02 | P2/O | 持续 Pod churn（可选时长） | 每 10 分钟扩缩容，状态始终收敛 |
| STAB-03 | P2/O | 长期发布候选验证（可选） | 无 P0/P1 缺陷、泄漏或性能漂移 |
| STAB-04 | P2/R | 长时间无变更空闲 | Operator 不产生无意义云 API 风暴 |

### 4.13 升级、混部与回滚

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| UPG-01 | P0/C | 旧候选→9 patch 候选滚动升级 | Agent/Operator 就绪，存量 Pod 网络满足门限 |
| UPG-02 | P0/C | `0007` 前共享表→独立表 | 新路由完整后清理旧 rule，无瞬时跨网关污染 |
| UPG-03 | P0/C | `0008` 前→支持线内 VLAN | 跨节点/DNS/Service 恢复或保持正常 |
| UPG-04 | P0/C | values 凭据→`existingSecret` | 先建外部 Secret，再升级；凭据不进入新 release |
| UPG-05 | P1/C | 新旧 Agent 短时混部 | 每个节点本地路径正常，Service 不长期黑洞 |
| UPG-06 | P1/C | 新旧 Operator 切换 | 同时仅一个版本执行云调谐 |
| UPG-07 | P0/C | 同版本新 digest 滚动 | 五节点完成且状态可追溯 |
| UPG-08 | P0/C | Helm rollback | 镜像/配置恢复，外部 Secret 保留 |
| UPG-09 | P0/C | Agent 镜像回滚 | map/route/CNI 兼容，无存量 Pod 数据损坏 |
| UPG-10 | P1/C | Operator 镜像回滚 | 不重复创建或误删 SubENI |
| UPG-11 | P1/C | 升级中单节点失败 | rollout 停止可诊断，其他节点继续可用 |
| UPG-12 | P1/C | 回滚中途失败后继续 | 可从确定 revision 恢复，不删除 CRD |
| UPG-13 | P1/R | CRD 字段向前/向后兼容 | CiliumNode HuaweiCloud 字段保留 |
| UPG-14 | P1/C | Helm uninstall/reinstall | 外部 Secret 保留；云资源清理策略符合预期 |

### 4.14 可观测性、审计和证据质量

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| OBS-01 | P0/R | Cilium status/health | 每阶段保存并可对比 |
| OBS-02 | P0/R | CiliumNode 与云端快照 | Pod IP、SubENI、VLAN、MAC、SG、子网可关联 |
| OBS-03 | P0/R | `ip rule/route/neigh` 快照 | 双网关、重启、升级前后可差分 |
| OBS-04 | P0/R | BPF map 快照 | endpoint 创建/删除/恢复前后可差分 |
| OBS-05 | P0/R | trunk 双端抓包 | 只抓测试 IP/协议，不保存业务正文 |
| OBS-06 | P0/R | Cilium monitor/drop counters | policy、VLAN、无 map、helper 失败可区分 |
| OBS-07 | P1/R | Kubernetes Event | 缺 Secret、CNI、镜像、调谐错误可诊断 |
| OBS-08 | P1/R | 云 API request ID | 错误可追踪但不包含凭据 |
| OBS-09 | P1/R | 资源变化审计 | Create/Tag/Delete 与用例时间线一致 |
| OBS-10 | P0/R | 敏感信息二次扫描 | values、release、Pod spec、日志、事件、报告无真实 AK/SK |
| OBS-11 | P1/R | 证据目录权限 | 目录 0700、文件最小权限、脱敏后归档 |
| OBS-12 | P1/R | 指标长期趋势 | SubENI、map、goroutine、CPU、内存无单调增长 |

### 4.15 清理、资源归属和测试结束

| ID | 优先级/类型 | 测试内容 | 预期结果 |
| --- | --- | --- | --- |
| CLEAN-01 | P0/C | 删除测试 namespace | 只删除测试 Pod/Service/Policy |
| CLEAN-02 | P0/C | `releaseExcessIPs=false` 下清理 | 空闲 SubENI 是否保留与配置一致 |
| CLEAN-03 | P0/C | `releaseExcessIPs=true` 下清理 | 延迟后测试 SubENI 回收，非测试资源不动 |
| CLEAN-04 | P0/R | 云端孤儿检查 | 无未归属测试 SubENI、port、IP |
| CLEAN-05 | P0/R | 节点 route/map/neighbor 残留检查 | 无已删除 Pod 的残留项 |
| CLEAN-06 | P0/R | 节点标签/污点恢复 | 只移除本测试添加的标识 |
| CLEAN-07 | P0/R | 外部 Secret 处理 | Helm 不删除；测试结束按审批显式删除或轮换 |
| CLEAN-08 | P0/R | 证据脱敏和归档 | 无凭据/私网敏感标识泄漏，报告可追溯 |
| CLEAN-09 | P1/R | 五节点最终健康检查 | Node Ready、Cilium health 正常，无失败 Pod |
| CLEAN-10 | P1/R | 清理后 30 分钟复核 | 无延迟泄漏、重复创建或异常调谐 |

## 5. 源码与边界用例

本节不是对前述正常路径的重复，而是按 `0001`～`0009` 中的条件分支、数值限制、类型转换、
空响应、回滚和并发行为反查出的边界场景。未注明可实机直接构造的场景，优先在 fake API、
netns、BPF 单测或隔离节点完成，再选择低风险子集上云复核。

### 5.1 metadata、region 与 trunk 选择边界

| ID | 优先级/类型 | 测试条件或输入 | 预期结果 |
| --- | --- | --- | --- |
| BMETA-01 | P0/S | OpenStack metadata `uuid` 为空 | Agent 明确失败，不使用 EC2 短 instance-id 继续调谐 |
| BMETA-02 | P0/S | `vpc_id` 为空 | 不创建无 VPC 约束的 SubENI |
| BMETA-03 | P0/S | `availability_zone` 为空 | region/AZ 推导失败且错误明确 |
| BMETA-04 | P1/S | AZ 只有 1 个字符 | region 推导结果必须明确，不静默生成错误 endpoint |
| BMETA-05 | P1/S | AZ 不以单字符后缀表示 region | 不应仅靠截掉最后一个字符误推 region；记录支持格式 |
| BMETA-06 | P0/S | `network_data.links` 为空 | fail-fast，不产生空 parent port |
| BMETA-07 | P0/S | `links[0].vif_id` 为空但后续 link 有值 | 不得静默选择错误 trunk；明确当前只读第一项的限制 |
| BMETA-08 | P0/R | 多网卡且真正 trunk 不是 `links[0]` | CiliumNode `trunk-interface-id` 必须与系统 MAC/云端 port 三方一致 |
| BMETA-09 | P0/S | metadata links 顺序重排 | 不应因数组顺序变化把 SubENI 挂到错误父口 |
| BMETA-10 | P1/S | metadata HTTP 204/301/404/500 | 状态码分类清晰，不解析错误页 |
| BMETA-11 | P1/S | metadata 响应恰好/超过 1 MiB | 超限截断不得产生部分有效配置；JSON 解析应失败 |
| BMETA-12 | P1/S | metadata JSON `null`、空对象、未知字段 | 未知字段可忽略，必填字段缺失必须失败 |
| BMETA-13 | P1/S | metadata 上下文已取消/10 秒超时边界 | 及时退出，无 goroutine/连接泄漏 |
| BMETA-14 | P1/R | OS 网卡重命名但 port ID 不变 | 显式 trunk 名更新后可恢复，不复用旧 ifindex |

### 5.2 API 参数、空响应、分页与网关解析边界

| ID | 优先级/类型 | 测试条件或输入 | 预期结果 |
| --- | --- | --- | --- |
| BAPI-01 | P0/S | BatchCreate `count=-1`、`0` | 本地拒绝，不调用云 API |
| BAPI-02 | P0/S | BatchCreate `count=1`、`10` | 两个合法边界均成功 |
| BAPI-03 | P0/S | BatchCreate `count=11` | 本地拒绝并说明上限 10 |
| BAPI-04 | P0/S | Create 的 subnet ID/parent ID 为空或纯空格 | 不得创建未限定父口/子网的资源 |
| BAPI-05 | P1/S | SG 列表包含空串、重复 ID、超云端数量上限 | 在调用前校验或得到可诊断失败，不产生半成品 |
| BAPI-06 | P0/S | 单创建返回 HTTP 成功但对象为 `nil` | 判定失败，不把空对象写入缓存 |
| BAPI-07 | P0/S | 批创建返回 `nil` 数组 | 不得把“创建 0 个”当作满足当前分配请求 |
| BAPI-08 | P0/S | 批创建返回数量少于/多于请求 | 记录实际资源，触发后续补齐或回滚，不丢失多出资源 |
| BAPI-09 | P0/S | 批创建数组包含 `nil`、空 ID、重复 ID | 不写入空键/覆盖资源，错误可追踪 |
| BAPI-10 | P1/S | 空 tags | Tag API 为 no-op，创建流程仍成功 |
| BAPI-11 | P1/S | tag 空 key/value、重复 key、Unicode、超长度/超数量 | 行为符合华为云限制，失败时整批回滚可追踪 |
| BAPI-12 | P0/S | finalize 第 1/N 个网关解析失败 | 本批所有已创建资源进入回滚，无前半批泄漏 |
| BAPI-13 | P0/S | finalize 最后一个打标签失败 | 前面已完成标签的对象也按设计回滚 |
| BAPI-14 | P1/S | 回滚多个 Delete 同时失败 | 返回信息保留全部待清理资源，而不是只保留最后一个错误 |
| BAPI-15 | P0/S | Show/List 返回对象缺 ID/IP/MAC/VLAN/subnet/parent | 不进入 Ready/路由/map 正常路径 |
| BAPI-16 | P0/S | Wait 状态为 `BUILD`/`DOWN`/未知值 | 继续等待到 Active、ERROR、取消或 60 秒超时 |
| BAPI-17 | P0/S | Wait 首次遇到最终一致性 404 | 不应立即造成重复创建；明确当前重试/失败策略 |
| BAPI-18 | P0/S | Wait 恰好在 60 秒转为 ACTIVE | 结果无竞态歧义，记录允许边界 |
| BAPI-19 | P1/S | List 页 `PageInfo=nil`/`NextMarker=nil`/空串 | 正常结束且不丢当前页 |
| BAPI-20 | P0/S | List 服务端重复同一 marker | 检测无进展并退出，不无限循环 |
| BAPI-21 | P1/S | List 某页 items 为 nil 但有 next marker | 能继续下一页，最终集合正确 |
| BAPI-22 | P1/S | server 分页恰好 999/1000/1001 条 | 无漏项、重复或越界 |
| BAPI-23 | P1/S | server `Count=nil`、小于实际、超过实际 | 终止条件稳健，不死循环 |
| BAPI-24 | P0/S | SubENI private IP 命中辅助 IPv4 CIDR | 选择该 CIDR 的 gateway，而非第一个 CIDR |
| BAPI-25 | P0/S | private IP 不属于任何返回 CIDR | 不应静默回退到错误 gateway；明确失败/兼容策略 |
| BAPI-26 | P1/S | subnet 仅有 IPv6、空 CIDR、非法 CIDR | 当前 IPv4 路径明确失败或跳过，不生成空 route |
| BAPI-27 | P0/S | router port 查询返回 0 个 | 不把缺 gateway MAC 的 endpoint 当成完整 Ready |
| BAPI-28 | P1/S | router port 查询返回多个 MAC | 选择规则稳定且能验证与目标 gateway 对应 |
| BAPI-29 | P0/S | SG API 返回多个 VPC 的组 | 不得把所有结果都标记成当前 VPC 后参与标签选择 |
| BAPI-30 | P1/S | API 20 QPS/40 burst 前后边界 | 不丢上下文取消，不发生无限等待或请求风暴 |
| BAPI-31 | P0/S | `0010` V1/V2 子网容量页为 0/1/1999/2000/2001 条 | 页边界无漏项、重复或越界，2001 条必须请求第二页 |
| BAPI-32 | P0/S | 容量 API 连续返回满 2000 条且末项 ID/marker 不前进 | 检测无进展并退出，不靠 context 超时结束无限循环 |
| BAPI-33 | P0/S | 容量 API 返回 nil、错误类型、HTTP 成功但 `subnets=nil` | nil 集合按空集合处理；错误响应类型明确失败，不 panic |
| BAPI-34 | P0/S | 容量 API 返回空 subnet ID 或同一 ID 重复且容量冲突 | 空 ID 明确失败；重复 ID 不得静默覆盖而隐藏云端异常 |
| BAPI-35 | P1/S | 容量为 0、1、`MaxInt32` 或负数 | 非负值转换无溢出；负数 fail-closed |
| BAPI-36 | P0/S | V3 Virsubnet 在 V1/V2 容量表缺失，或容量表包含 V3 不存在的 ID | 前者明确失败；后者不生成幽灵 subnet，错误可诊断 |
| BAPI-37 | P1/S | 容量 API 和 Virsubnet API 分页期间 context 取消/限流 | 及时返回取消，不发布半份 subnet 快照，不产生请求风暴 |
| BAPI-38 | P0/S | 容量 API 403/404/429/5xx、超时后恢复 | 未知容量不当作可用；错误可观测，恢复后重新同步成功 |

### 5.3 flavor、容量、配置合并和选择算法边界

| ID | 优先级/类型 | 测试条件或输入 | 预期结果 |
| --- | --- | --- | --- |
| BCFG-01 | P0/S | flavor limit 为 `0` | 节点容量为 0，不调用 BatchCreate |
| BCFG-02 | P0/S | flavor limit 为 `1` 且最小预分配为 2 | 不超配；明确最小分配与硬上限冲突的行为 |
| BCFG-03 | P0/S | flavor limit 为负数 | 拒绝并不更新静态缓存 |
| BCFG-04 | P0/S | flavor limit 为空、空格、非数字、溢出整数 | 解析失败并安全回退/阻断 |
| BCFG-05 | P1/S | flavor 通过 ID 命中、通过 Name 命中、均不命中 | 三条分支结果明确 |
| BCFG-06 | P1/S | 动态 limit 查询超时但静态表有值 | 10 秒后使用已知静态值，不永久阻塞 |
| BCFG-07 | P0/S | 动态 limit 查询失败且静态表无值 | 不分配资源，CiliumNode 错误明确 |
| BCFG-08 | P1/S | 动态 limit 在运行中降低到当前已用数以下 | 不创建新资源，也不误删在用资源 |
| BCFG-09 | P1/S | 动态 limit 提高 | 后续调谐能利用新增容量 |
| BCFG-10 | P0/S | `toAllocate` 为负、0、1、10、11 | 负值/0 不调用 API；合法值分批且每批不超过 10 |
| BCFG-11 | P0/S | subnet `AvailableAddresses=-1`、`0`、`1`、N | 明确负数/0 是未知还是耗尽；不得把真实耗尽当可用 |
| BCFG-12 | P1/S | 两个候选子网可用地址数完全相同 | 选择应稳定，不能受 Go map 随机迭代影响 |
| BCFG-13 | P1/S | subnet tags 为空 map 与 nil | 两者语义一致且有文档说明 |
| BCFG-14 | P0/S | 显式 subnet 列表含空 ID、重复 ID | 跳过非法/重复项或明确失败，不重复云调用 |
| BCFG-15 | P0/S | 显式 subnet 列表跨 VPC/AZ | 本地或云端阻断，不能因“显式优先”绕过归属校验 |
| BCFG-16 | P0/S | 第一个显式子网容量不足、第二个正常 | 仅容量不足错误触发有序 fallback，PoolID 指向实际成功子网 |
| BCFG-17 | P1/S | 第一个显式子网 404/403/5xx | 不误当容量不足跳过；错误和恢复动作明确 |
| BCFG-18 | P0/S | SG 显式 ID、SG tags、trunk 继承同时存在 | 严格遵循“显式 ID > tags > trunk/现有 SubENI” |
| BCFG-19 | P0/S | 配置了 SG tags 但 0 个匹配 | 明确是 fail-closed 还是回退继承，不能静默扩大权限 |
| BCFG-20 | P1/S | SG tags 匹配数量超过云端附加上限 | 不提交必然失败的超长列表，错误可诊断 |
| BCFG-21 | P1/S | trunk 无 SG，现有 SubENI 有重复/空 SG | 去重、忽略空值并保持稳定集合 |
| BCFG-22 | P0/S | 首次启动无 `TrunkInterfaceID` 且无历史 SubENI | 明确阻断，不进入无法自举的创建循环 |
| BCFG-23 | P1/S | `.conflist` plugins 为空、包含 `null`、无 cilium-cni | 不 panic，不把整份 conflist 误解析成有效单配置 |
| BCFG-24 | P1/S | `.conflist` 含多个 cilium-cni | 明确选择第一项或拒绝歧义配置 |
| BCFG-25 | P1/S | JSON 重复键、未知键、超大文件 | 行为可预测；未知键兼容但关键重复键应被识别 |
| BCFG-26 | P1/S | `prevResult` 版本为空、不支持、malformed | 返回可诊断错误，不影响已有 CNI 配置 |
| BCFG-27 | P1/S | CNI `preAllocate=-1/0/1/极大值` | 不产生负分配或超过 flavor 上限 |
| BCFG-28 | P1/S | CNI map/slice 后续被调用方修改 | CiliumNode 已应用值不被共享引用意外改变 |
| BCFG-29 | P0/S | `AvailableAddresses` 小于/等于/大于 `toAllocate` | 小于时跳过，等于和大于时可选；容量 0 不再表示“未知且可用” |
| BCFG-30 | P0/S | 多个候选的剩余容量不同、相同或同步期间变化 | 选择真实余量最大者；同分规则稳定；下一轮按新快照收敛 |

### 5.4 IPAM 状态、回收和不支持能力边界

| ID | 优先级/类型 | 测试条件或输入 | 预期结果 |
| --- | --- | --- | --- |
| BIPAM-01 | P0/S | CiliumNode/spec/HuaweiCloud 为 nil | 调谐安全返回，不 panic、不创建资源 |
| BIPAM-02 | P0/S | instance ID 为空或运行中变化 | 不把资源写入空实例；旧/新实例状态不串扰 |
| BIPAM-03 | P0/S | Resync 返回 SubENI 空 private IP | 计入接口上限但不作为可分配 IP，状态可诊断 |
| BIPAM-04 | P0/S | 两个 SubENI 返回相同 private IP | 检测冲突，不用 map 覆盖隐藏其中一个资源 |
| BIPAM-05 | P1/S | Resync 中单个资源类型错误 | 跳过并告警，不破坏其他有效资源 |
| BIPAM-06 | P0/S | BatchCreate 成功但返回空列表 | 当前操作不应报告成功满足 allocation |
| BIPAM-07 | P0/S | BatchCreate 返回含 nil 项 | 实际创建数与缓存/返回计数一致 |
| BIPAM-08 | P1/S | `excessIPs=-1`、`0`、大于全部空闲数 | 负值/0 不释放；大值最多释放全部真正空闲项 |
| BIPAM-09 | P0/S | Used 状态缺失/滞后 | 在未确认空闲前不得删除可能仍在用的 SubENI |
| BIPAM-10 | P0/S | Used 状态在 Prepare 与 Release 间变为在用 | Release 前重新校验或证明握手能阻止误删 |
| BIPAM-11 | P1/S | release 请求包含未知 IP | 安全跳过并可观测，不影响其他释放项 |
| BIPAM-12 | P1/S | release 请求包含重复 IP | 不重复 Delete 同一 SubENI，不因第二次 404 中断 |
| BIPAM-13 | P0/S | 批量 release 第 N 个 Delete 失败 | 前 N-1 个状态一致，剩余项可重试，无假成功 |
| BIPAM-14 | P1/S | release 期间上下文取消 | 已完成和未完成资源可准确区分 |
| BIPAM-15 | P1/S | 空闲候选 IP 为 `.2`、`.10` 等 | 排序虽为字典序但跨调谐必须稳定，不能候选抖动 |
| BIPAM-16 | P0/S | `releaseExcessIPs` 运行中 false→true→false | 只在开启窗口进入释放握手，关闭后停止新删除 |
| BIPAM-17 | P0/S | `AllocateStaticIP` 被调用 | 明确返回 unsupported，不创建随机 SubENI |
| BIPAM-18 | P0/S | prefix delegation 被误启用 | HuaweiCloud 始终报告不支持，不把 no-op 当成功能力 |
| BIPAM-19 | P1/S | SubENI 同时带 IPv4/IPv6 | 只管理明确支持的 IPv4；IPv6 不进入错误 map/route |
| BIPAM-20 | P1/S | VPC primary/extended CIDR 为空、非法、重复、重叠 | 状态同步不 panic，native routing 采用明确有效集合 |
| BIPAM-21 | P1/C | CiliumNode 被删除后立即重建 | 旧资源被重新发现，不重复创建、不错误回收 |
| BIPAM-22 | P1/C | 节点名相同但 provider/instance ID 已变化 | 不把旧实例 SubENI 归到新节点 |

### 5.5 endpoint、BPF map 和邻居边界

| ID | 优先级/类型 | 测试条件或输入 | 预期结果 |
| --- | --- | --- | --- |
| BMAP-01 | P0/S | endpoint 为 nil、ID=0、ifindex=0、IPv4 为空 | 安全忽略，不写零值 map |
| BMAP-02 | P0/S | endpoint IPv4 非法或为 IPv6 | 返回明确错误，不截断/转换 |
| BMAP-03 | P0/S | SubENI MAC 为空、短、长、multicast、非法字符 | 不写错误 `(VLAN,MAC)` 键 |
| BMAP-04 | P0/S | VLAN `-1`、`0`、`1`、`4094`、`4095`、`65536` | 仅 1～4094 可写，不因 int32→uint16 截断产生键冲突 |
| BMAP-05 | P0/S | endpoint ID `65535`、`65536`、`>65536` | `EPInfo.LxcID` 不静默 uint16 截断到其他 endpoint |
| BMAP-06 | P1/S | 同 source IP 绑定不同 SubENI | 替换两个 map 时保持原子一致，失败能回滚旧值 |
| BMAP-07 | P1/S | 两 endpoint 使用相同 VLAN+MAC | 检测冲突，不让后者劫持前者 ingress |
| BMAP-08 | P1/S | 第一个 map lookup 返回非 ENOENT | 不继续覆盖，错误保留 |
| BMAP-09 | P1/S | 第二个 map 更新失败且第一张回滚也失败 | 报告主错误和回滚错误，触发一致性修复 |
| BMAP-10 | P1/S | endpoint delete 的 map 删除失败 | 不能只吞错后长期保留 stale entry；后续清理可验证 |
| BMAP-11 | P1/S | Close 与 Ready/Delete 并发 | 不 use-after-close、double close 或数据竞争 |
| BMAP-12 | P1/S | CiliumNode status 中 0/2 个 SubENI 匹配同一 IP | 0 个不写 map；2 个必须检测歧义而非依赖 map 遍历顺序 |
| BMAP-13 | P0/S | gateway IP 有值但 MAC 空，或反之 | 邻居 no-op/错误边界明确，不能把 endpoint 标为完全可用 |
| BMAP-14 | P1/S | trunkInterface 为空/不存在 | NeighSet 不作用到错误链路，错误可诊断 |
| BMAP-15 | P1/C | 已有同 gateway IP、不同 MAC 的 permanent neighbor | 更新策略可控，不污染其他子网/节点 |
| BMAP-16 | P1/R | 两个子网 gateway IP 相同但 VLAN/MAC 不同 | 邻居和路由仍能正确返回；如不支持必须阻断配置 |

### 5.6 VLAN 报文和策略路由边界

| ID | 优先级/类型 | 测试条件或输入 | 预期结果 |
| --- | --- | --- | --- |
| BVLAN-01 | P0/S | Ethernet header 不完整 | `DROP_INVALID`，不越界读 |
| BVLAN-02 | P0/S | 802.1Q/802.1ad header 只有部分字节 | `DROP_INVALID`，无 verifier 问题 |
| BVLAN-03 | P0/S | VLAN TCI 含 PCP/DEI 位 | 只取低 12 位 VLAN ID，优先级位不污染 map key |
| BVLAN-04 | P0/S | 线内 VLAN ID=0/4095 | 不匹配有效 SubENI，不误投递 |
| BVLAN-05 | P0/S | 线内 VLAN 与 metadata VLAN ID 相同 | 正确两阶段 pop，内层 ethertype 保留 |
| BVLAN-06 | P0/S | 线内 VLAN 与 metadata VLAN ID 不同 | 不能用外层命中掩盖不一致；应丢弃或明确支持语义 |
| BVLAN-07 | P0/S | 线内未知 VLAN+MAC 且无 metadata | 不得绕过 HuaweiCloud map 后被作为普通未标记流量放行 |
| BVLAN-08 | P0/S | map miss 后 metadata VLAN | 进入通用 VLAN allow/drop 逻辑，不能误标 handled |
| BVLAN-09 | P1/S | 内层非 IPv4（ARP/IPv6/LLDP） | 各协议按设计处理，不把控制帧投递给错误 endpoint |
| BVLAN-10 | P1/S | 三层或更多 VLAN/QinQ | 明确只支持层数，超出边界 fail-closed |
| BROUTE-01 | P0/S | gateway 为 IPv6、空、非法字符串 | NewRoutingInfo 拒绝，不生成 IPv4 route |
| BROUTE-02 | P0/S | CIDR nil/空，masquerade true/false 矩阵 | 只在允许条件接受空 CIDR |
| BROUTE-03 | P0/S | CIDR IPv6、非法、重复、重叠 | HuaweiCloud IPv4 路径不产生错误规则集合 |
| BROUTE-04 | P0/S | MAC 为空/非法/multicast | 不通过错误 master MAC 查接口 |
| BROUTE-05 | P0/S | MTU 为 0、负数、与 trunk 当前 MTU 不同 | 不误改错误接口；错误和恢复行为明确 |
| BROUTE-06 | P0/S | 同机已有表 10001～14094 的非 Cilium 路由 | 安装前检测冲突，不覆盖用户/系统路由 |
| BROUTE-07 | P0/S | VLAN ID 在不同 trunk 上重复 | 当前单 trunk 假设必须校验；多 trunk 不得共享同 table ID |
| BROUTE-08 | P0/S | 新 rule 成功、nexthop route 失败 | 留下的部分 rule 可在重试/清理中收敛 |
| BROUTE-09 | P0/S | nexthop 成功、default route 失败 | 不清理旧共享 rule，避免切到不完整新表 |
| BROUTE-10 | P0/S | 新表完整但 stale rule 删除失败 | 下次重试幂等；两套规则并存期间路径可预测 |
| BROUTE-11 | P1/S | stale rule 有 mark/mask/to 字段 | 删除精确目标，不扩大匹配范围 |
| BROUTE-12 | P1/S | 同源同优先级存在多个规则 | 不因 generic Delete 的多匹配保护留下永久垃圾 |
| BROUTE-13 | P1/R | Pod 删除后 route table 保留、VLAN 后续复用新 gateway | RouteReplace 更新为新 gateway，不使用旧缓存 |
| BROUTE-14 | P1/R | host=true 与普通 endpoint | host 不装 ingress main rule，普通 endpoint 必须装 |

### 5.7 Secret 值、对象生命周期和并发竞态边界

| ID | 优先级/类型 | 测试条件或输入 | 预期结果 |
| --- | --- | --- | --- |
| BSEC-01 | P0/S | `existingSecret=""` 与仅空格 | 两者均在渲染阶段拒绝，不生成空 name |
| BSEC-02 | P0/R | Secret 键存在但值为空 | Pod 可能启动但云鉴权必须 fail-closed，错误不泄值 |
| BSEC-03 | P1/R | Secret 类型 Opaque/非 Opaque | 只依赖键值的兼容边界明确 |
| BSEC-04 | P1/R | Secret 为 immutable | 常规启动正常；轮换必须新建对象并改引用 |
| BSEC-05 | P0/C | Operator 运行中删除 Secret | 现有进程环境不自动清空；重启应明确失败，不能误判已轮换 |
| BSEC-06 | P1/C | Secret 更新但不重启 Operator | 明确旧环境变量仍生效，文档必须要求 rollout restart |
| BSEC-07 | P1/S | Secret 名含 DNS 非法字符/超长 | Kubernetes/Helm 预检查阻断 |
| BSEC-08 | P1/R | Helm release 与外部 Secret 同名资源冲突 | Chart 不接管 ownerReferences/labels，不覆盖外部对象 |
| BRACE-01 | P0/S | Resync 与 CreateInterface 并发 | 不丢新资源、不用旧 cache 覆盖新 cache |
| BRACE-02 | P0/S | Resync 与 ReleaseIPs 并发 | 不删除已重新标为 used 的资源，cache 最终一致 |
| BRACE-03 | P1/S | UpdatedNode 与 getLimits/Create 并发 | instance ID/spec 必须来自同一一致快照 |
| BRACE-04 | P1/S | 两个调谐同时为同一节点扩容 | 不超过 limit，不重复创建同一批容量 |
| BRACE-05 | P1/S | endpoint Ready 与 Delete 乱序 | 最终 map 与实际 endpoint 生命周期一致 |
| BRACE-06 | P1/S | endpoint Restore 与新 Create 同 IP | 不让旧 endpoint 覆盖新 endpoint map |
| BRACE-07 | P1/S | Operator leader 切换时 API 请求在途 | 至多一次效果或可通过 resync 去重 |
| BRACE-08 | P1/C | Pod delete、Agent 重启、Operator 回收同时发生 | 不误删仍恢复中的 SubENI，不留下 stale map |
| BRACE-09 | P1/S | 配置从 subnet IDs 切到 tags 的调谐边界 | 已有资源保留，新资源按新配置，不混用 PoolID |
| BRACE-10 | P1/S | 配置从 SG A 切到 SG B | 明确只影响新 SubENI还是调谐存量，不能产生未定义混合 |
| BRACE-11 | P1/S | context cancel 发生在 limiter 等待后、API 调用前 | 不继续发起无主请求 |
| BRACE-12 | P2/O | 持续并发 churn + resync（可选时长） | 使用 race/一致性检查确认无锁问题和资源漂移 |
