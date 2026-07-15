# HuaweiCloud Cilium 451 项执行审计账本

状态只允许 Pass、Fail、Skip、Pending。Pass 必须有证据指针；Skip 仅限用户批准的环境限制。

| ID | P/类型 | 场景 | 状态 | 证据/结论 |
| --- | --- | --- | --- | --- |
| BASE-01 | P0/S | 固定 upstream commit 应用全部 patch | Pass | 2026-07-14 audit60：从 upstream `a1d7fbd43` 顺序应用 15/15 成功，干净回放提交 `6fab161f8`、tree `e1d395fc4`，与权威源码树完全一致 |
| BASE-02 | P0/S | 错误 upstream tag/commit | Pass | 错误 HEAD 被 `apply.sh` 以 rc=1 拒绝，HEAD 未变化；见 20260714 evidence |
| BASE-03 | P1/S | patch 中断后恢复 | Pass | 强制 `git am` 失败后 abort，工作树干净，随后 15/15 完整重放 |
| BASE-04 | P0/S | patch 完整性 | Pass | 保留 14 个功能 patch，后续 bugfix/验证测试统一为 0015；`series` 与目录均为 15 项，audit92 0015 SHA256 `2436c960...`，干净重放 tree 与最终源码 `591aa02e...` 完全一致 |
| BASE-05 | P0/S | Go 单元/组件定向测试 | Pass | audit60 干净回放：受影响 endpointmanager/metadata 普通、race、privileged 定向测试通过；endpointmanager 全包普通/race 单轮通过 |
| BASE-06 | P0/S | privileged routing 测试 | Pass | 2026-07-14：`go test -mod=vendor -tags=privileged_tests ./pkg/datapath/linux/routing` 通过 |
| BASE-07 | P0/S | BPF 全排列编译 | Pass | audit59 严格构建全部 8 个 `bpf/tests/*.o`，随后逐对象内核加载执行通过；HuaweiCloud 对象另连续执行20次 |
| BASE-08 | P0/S | Agent/CNI/Operator 构建 | Pass | Agent、CNI、generic Operator、HuaweiCloud Operator 均从最终功能源码构建通过；audit60 从干净回放重建 Agent 并封装 165 文件 BPF install tree |
| BASE-09 | P0/R | 镜像 CPU 架构匹配 | Pass | 五节点 x86_64，audit60 为 linux/amd64 静态二进制；5/5 Agent SHA256 `06c7efa7...`、运行时 `huaweicloud.h` SHA256 `8dae79a6...` |
| BASE-10 | P0/R | Operator 镜像默认命令 | Pass | 运行命令为 `cilium-operator-huaweicloud` |
| BASE-11 | P0/R | Operator 双二进制 | Pass | 两个 `/usr/bin/cilium-operator*` 均可执行并报告 1.12.19 |
| BASE-12 | P1/S | 重复构建一致性 | Pass | audit60 使用同一干净源码和项目 Makefile 清理旧产物后重新构建，两次 amd64 静态 Agent SHA256 均为 `06c7efa7...` |
| BASE-13 | P1/S | 离线镜像分发 | Pass | audit17 两份 tar 校验 SHA256 后导入五节点 containerd；Agent 5/5、Operator 1/1 运行并完成客户 25 项及 56/56 回归 |
| BASE-14 | P1/R | 私有仓库分发 | Pending | 待执行 |
| BASE-15 | P2/S | SBOM/漏洞/许可证检查 | Pending | 待执行 |
| PRE-01 | P0/R | 1 control-plane + 4 worker、2 AZ | Skip | 1+4 已验证；用户批准跨 AZ Skip，五台均为 cn-south-1g |
| PRE-02 | P1/O | 3 control-plane + 2 worker | Pending | 待执行 |
| PRE-03 | P0/R | Kubernetes/Cilium 版本 | Pass | Kubernetes v1.24.17、Cilium 1.12.19 audit17，五节点一致 |
| PRE-04 | P0/R | 内核、cgroup、容器运行时 | Pass | HCE2 5.10、cgroup v1、containerd 1.6.36，五节点一致 |
| PRE-05 | P0/R | 时钟、DNS、NTP | Pass | 五节点 NTP synchronized；集群/公网 DNS 最终均通过 |
| PRE-06 | P0/R | 单网卡 trunk 识别 | Pass | 五节点 eth0 单物理网卡，SubENI/VLAN 路由和数据面均通过 |
| PRE-07 | P0/R | 多网卡 trunk 识别 | Pass | audit61 将真实系统默认网卡与 privileged dummy trunk 并存，显式 trunk 名连续20轮命中其 MAC/port；另将真正 trunk 放在 metadata links 第2项并正反重排100轮，均不依赖第一张网卡 |
| PRE-08 | P1/C | 默认路由网卡不是 trunk | Pass | audit61 现场默认设备为 `vpneth0`，privileged trunk 为独立 dummy；正确显式名连续20轮成功，旧/错误名 fail-fast，测试前后默认路由字节级一致且未误操作默认端口 |
| PRE-09 | P0/R | metadata 中实例/VPC/AZ/port 信息 | Pass | 五节点 metadata UUID/AZ/network 非空，CiliumNode instance/trunk 信息完成调谐 |
| PRE-10 | P1/C | metadata 短时不可达 | Pass | `TestMetadataHTTPTimeout/CancelledContext/HTTPStatuses` 在干净 15-patch replay 连续 10 轮通过，覆盖超时、取消、204/3xx/404/5xx |
| PRE-11 | P1/C | metadata 返回空、 malformed 或 MAC 不匹配 | Pass | `TestOpenStackMetadataRequiredFields` 与 `TestGetTrunkInterfaceIDValidation` 连续 10 轮通过，覆盖空/null/malformed/空 links/空 port ID/MAC 无匹配 |
| PRE-12 | P1/C | trunk link flap | Pass | audit64 修复并复测真实 trunk `eth0` 连续3轮 down 5秒/up；每轮故障前5/5、故障中恰有25/150丢包、恢复后20/20；所有当前 priority-111 表均恢复精确两条路由，permanent neighbor 恢复，Agent不重启且不会提前拉起故障中的接口 |
| PRE-13 | P0/R | VPC、AZ、子网和 SG 归属 | Pass | 五节点真实 SubENI 均在目标 VPC/AZ/子网且客户 25 条互通 |
| PRE-14 | P0/R | 子网可用 IP 和 SubENI 配额 | Skip | 用户批准：当前 flavor IPv4 上限 8，无法物理达到 min-allocate=10；传播与上限错误已验证 |
| PRE-15 | P1/R | ECS flavor 限额识别 | Pass | `TestSubENILimitMatchesFlavorIDOrName` 按 flavor ID/name 均识别上限 8，连续 10 轮通过 |
| PRE-16 | P1/C | 未知/不支持 flavor | Pass | `TestSubENILimitMustBePositive/MatchesFlavorIDOrName` 覆盖未知 flavor 及空白、0、负数、非数字、溢出 limit，连续 10 轮通过 |
| PRE-17 | P0/R | 安全组基础矩阵 | Pending | 待执行 |
| PRE-18 | P1/R | iproute2、tcpdump、ethtool、conntrack 工具 | Pass | 五节点四项工具均存在 |
| SEC-01 | P0/S | `existingSecret` 正常渲染 | Pass | 自定义 Secret 名渲染为两处 secretKeyRef，无内联值 |
| SEC-02 | P0/S | `existingSecret` 为空 | Pass | HuaweiCloud enabled 时空值被 Helm required 拒绝 |
| SEC-03 | P0/R | Secret 对象不存在 | Pass | 隔离 namespace 中稳定进入 CreateContainerConfigError: Secret not found |
| SEC-04 | P0/R | Secret 缺 AK 键 | Pass | 稳定进入 CreateContainerConfigError: AK key not found |
| SEC-05 | P0/R | Secret 缺 SK 键 | Pass | 稳定进入 CreateContainerConfigError: SK key not found |
| SEC-06 | P0/R | AK/SK 正确 | Pass | Operator 1/1 Ready 且五个 CiliumNode 正常云端调谐 |
| SEC-07 | P1/C | AK/SK 错误或过期 | Pass | audit79 远端0600备份原 Secret 后注入无效 AK/SK 并重启；云鉴权错误可诊断且未输出原值，mesh 56/56、pool 恒等；恢复 Secret/重启后鉴权错误归零并删除备份 |
| SEC-08 | P1/C | Secret 轮换 | Pass | audit82 不暴露凭据值地在集群内复制为新 Secret，同时切换 AK/SK 引用；新 audit81 Operator Ready/restart0、无鉴权错误、mesh 56/56、pool 恒等，随后恢复原引用并确认临时 Secret 清零 |
| SEC-09 | P0/S | Helm 渲染对象集合 | Pass | Helm lint/template 通过，对象 kind 集合已统计；见 20260714 evidence |
| SEC-10 | P0/S | Helm values 和命令行扫描 | Pass | 渲染物无 AK/SK 值，只有 Secret key 引用 |
| SEC-11 | P0/R | Helm release Secret 扫描 | Pass | 运行资源与 Helm 配置扫描未发现内联云凭据 |
| SEC-12 | P0/R | Pod spec、事件、日志扫描 | Pass | Pod spec 无内联值，Operator 最后 500 行无凭据泄漏 |
| SEC-13 | P0/R | Helm upgrade/rollback | Pass | audit91 用最新 audit90 Git Chart 在隔离 namespace 实跑 install rev1→upgrade rev2→rollback rev1（历史rev3）；外部 Secret 的 UID、resourceVersion、data哈希及非Helm所有权元数据逐阶段完全不变，release manifest 始终不含该 Secret |
| SEC-14 | P0/R | Helm uninstall | Pass | audit91 卸载隔离 release 后 release 归零而外部 Secret 仍以相同 UID/resourceVersion/data哈希存在；仅在断言通过后由测试显式删除，namespace/release无残留，生产 mesh 56/56 |
| SEC-15 | P1/O | 自定义 Secret 名称 | Pass | audit80 从原 Secret 仅在集群内复制临时自定义名称并切换两个 secretKeyRef；新 Operator Ready/restart0、无鉴权错误，mesh 56/56、pool 恒等；最终恢复原引用并删除临时 Secret |
| SEC-16 | P1/C | Secret 位于错误 namespace | Pass | audit80 将凭据副本仅放在 default、kube-system 引用同名缺失 Secret；候选 Pod 稳定 CreateContainerConfigError，旧 Operator 保持 Ready，mesh/pool 不变；恢复原引用后坏 Pod 与跨 namespace 临时 Secret 均清零 |
| SEC-17 | P1/R | 特殊字符凭据 | Pass | `TestNewClientAcceptsOpaqueCredentialCharacters` 验证非空凭据中的标点按 opaque string 接受；API 边界批次连续 10 轮通过 |
| SEC-18 | P1/O | External Secrets/CSI 控制器轮换 | Pending | 待执行 |
| SEC-19 | P0/R | 最小云权限 | Pending | 待执行 |
| SEC-20 | P1/C | 缺查询/创建/删除/打标签权限分别验证 | Pending | 待执行 |
| INS-01 | P0/S | CRD server dry-run | Pass | 14/14 CRD 通过 Kubernetes server-side dry-run |
| INS-02 | P0/S | Helm lint/template 正常配置 | Pass | HuaweiCloud enabled chart lint/template 通过 |
| INS-03 | P0/S | HuaweiCloud disabled | Pass | disabled 渲染无 HuaweiCloud 凭据 env 引用 |
| INS-04 | P0/R | 首次安装 | Pass | 五节点首次安装完成，Agent 5/5、Operator 1/1 |
| INS-05 | P0/R | 重复 `helm upgrade --install` | Pass | 多轮 upgrade/rollout 后资源稳定；见五节点实机结果 |
| INS-06 | P0/R | Cilium status | Pass | 多轮最终 `cilium status --brief` 5/5 OK |
| INS-07 | P0/R | 五个 CiliumNode | Pass | 5/5，instance ID 与水位字段完整且 Operator 重启后稳定 |
| INS-08 | P0/R | ConfigMap 参数 | Pass | ipam/tunnel/IPv4/IPv6/NodePort/KPR/identity 参数逐项读取匹配 |
| INS-09 | P1/C | 缺 CRD 安装 | Pending | 待执行 |
| INS-10 | P1/C | Agent 镜像不可拉取 | Pass | audit67 仅移除 node0003 的运行别名后删除 Agent；新 Pod 明确进入 ErrImagePull/ImagePullBackOff，事件记录 localhost registry connection refused；恢复本地别名后新 Agent Ready/OK、哈希正确且mesh 56/56 |
| INS-11 | P1/C | Operator 镜像错误或双后缀 | Pass | audit78 注入不存在的 `audit76-missing` Operator 镜像，确认新 Pod 进入 ErrImagePull/ImagePullBackOff、候选 rollout 超时且旧 audit76 保持 Ready；恢复后坏 Pod/镜像引用归零 |
| INS-12 | P1/R | 节点污点和 toleration | Pass | audit68 node0004 加临时NoSchedule污点后删除Agent；DaemonSet的全量Exists toleration使新Agent仍在该节点Ready/OK且哈希正确；移除污点后无残留，mesh 56/56 |
| INS-13 | P1/R | Operator 单副本重启 | Pass | 删除后新 Pod Ready，五个 CiliumNode 稳定，数据面通过 |
| INS-14 | P1/O | Operator 多副本/选主 | Pass | audit69 Operator扩至2副本均Ready，仅Lease holder执行leader；删除当前leader后standby取得不同holderIdentity且Deployment补齐2/2，客户链路20/20；最终恢复1/1 |
| INS-15 | P1/R | CNI 文件落盘 | Pass | 五节点 JSON 校验通过且 SHA256 一致，cilium-cni 可执行 |
| API-01 | P0/R | 单个 Create SubENI | Pass | audit81 暂停 Operator 后真实删除两个已确认空闲资源腾出配额；生产 Client 单个 Create 成功，响应、Show 与父网卡精确 List 均校验通过 |
| API-02 | P0/R | BatchCreate SubENI | Pass | audit81 生产 Client BatchCreate count=2 成功，两个响应逐项通过身份、地址、父网卡、子网及 Show/List 校验 |
| API-03 | P0/R | Get/Show SubENI | Pass | audit81 对基线、单建、批建及删除等待均执行真实 Show；创建资源字段完整，删除后均稳定返回 NotFound |
| API-04 | P0/R | List SubENI | Pass | audit81 在变更前、单建后、批建后、清理后及恢复后执行父网卡精确集合校验，无遗漏、重复或残留 |
| API-05 | P1/S | List 分页 marker | Pass | `TestListSubNetworkInterfacesRejectsRepeatedMarker/NextMarkerTerminalForms/ListAllowsNilItemsWhenPaginationAdvances` 连续 10 轮通过 |
| API-06 | P0/R | SubENI 标签写入 | Pass | audit81 发现旧实现误用仅深圳发布的 Port 标签接口；修复为单建/批建请求内联 SubENI tags，真实 cn-south-1 创建后 Show 精确核验两项标签，单元/竞态/全包及云端复测通过 |
| API-07 | P0/R | Delete SubENI | Pass | audit81 删除两个基线空闲资源、一个单建资源和两个批建资源；每次均轮询到 NotFound，最终父网卡集合无测试资源残留 |
| API-08 | P1/C | Delete 已不存在资源/404 | Pass | audit76 修复 404 提前返回导致本地状态残留；HTTP 404→`ErrNotFound` 归一化及 `TestReleaseIPsTreatsNotFoundAsConvergedAndContinues` 连续/竞态复测通过，证明清理本地状态并继续后续删除；新 Operator 实机回归全通过 |
| API-09 | P1/C | Create 超时 | Pass | audit90 使用 20ms SDK HTTP timeout 对 200ms Create 服务端执行受控超时：返回 error、无成功 ID/对象、仅发出一次请求且小于 500ms；定向100轮、race20轮、API全包20+race20、HuaweiCloud全域10+race10及vet均通过 |
| API-10 | P1/C | Wait Active 超过 60 秒 | Pass | `TestWaitSubENIActiveStopsOnTimeoutAndContext` 以缩短测试时钟验证完整 timeout/cancel 分支，连续 10 轮通过 |
| API-11 | P1/C | HTTP 429 | Pass | `TestAPIHTTPErrorNormalization` 将 429 标准化为 `ErrRateLimited`，连续 10 轮通过 |
| API-12 | P1/C | 5xx/网络断开 | Pass | `TestAPIHTTPErrorNormalization` 覆盖 500 原错返回，`TestAPINetworkDisconnectIsReturned` 覆盖断连；连续 10 轮通过 |
| API-13 | P1/C | 401/403 | Pass | `TestAPIHTTPErrorNormalization` 验证 401/403 均可由 `errors.Is(ErrUnauthorized)` 识别；连续 10 轮通过 |
| API-14 | P1/S | batch 部分成功 | Pass | `TestValidateCreatedSubENIs/CreateResponsesAreValidatedBeforeFinalize` 覆盖短数组、nil、空 ID、重复 ID、过多结果并 fail closed；连续 10 轮通过 |
| API-15 | P1/C | 打标签失败 | Pass | `TestFinalizeRollsBackAllCreatedSubENIsOnLastTagFailure` 验证末项标签失败后两个已创建 SubENI 均回滚；连续 10 轮通过 |
| API-16 | P1/C | 回滚删除失败 | Pass | `TestRollbackReportsEveryDeleteFailure` 验证所有删除均尝试且两个资源 ID/失败均保留；连续 10 轮通过 |
| API-17 | P1/R | API 最终一致性延迟 | Pass | `waitSubENIActive` 单测注入 NotFound→BUILD→ACTIVE 并验证 timeout/context 边界；audit81 真实创建后 Show/List 可见，删除后轮询到 NotFound，最终云端集合与 pool 精确一致 |
| API-18 | P1/C | endpoint/region/project 配错 | Pass | audit90 修复初始化时未校验 endpoint/region/project 路径安全的问题；单测覆盖非法 scheme/host/query/credentials、region 空格/路径、project 路径注入及错误 project 的精确404作用域。实机用独立 leader namespace 启动两个隔离候选，非法 endpoint/region 均明确 Failed/fail-fast，生产 Operator 全程 Ready/restart0、pool 哈希不变，恢复后无 Pod/Namespace/ConfigMap 残留 |
| API-19 | P1/R | API QPS/突发限制 | Pass | `TestHuaweiCloudAPIRateLimitBoundaries` 验证 burst 40 无等待、第 41 次按 20 QPS 限流并上报 delay；连续 10 轮通过 |
| API-20 | P2/S | 错误码标准化矩阵 | Pass | `TestAPIHTTPErrorNormalization` 覆盖 400/401/403/404/429/500，`TestAPINetworkDisconnectIsReturned` 覆盖 transport error；连续 10 轮通过 |
| IPAM-01 | P0/R | 每个 worker 首次分配 | Pass | 四 worker 均分配真实 SubENI Pod IP，8/8 Running |
| IPAM-02 | P0/R | 同节点多个 Pod | Pass | 每个 worker 同时运行 2 个 matrix Pod，IP 唯一 |
| IPAM-03 | P0/R | 四 worker 并发分配 | Pass | 两个 DaemonSet 并发形成 8 Pod/4 worker，全部 Ready |
| IPAM-04 | P0/R | 按标签选择同 AZ 子网 | Pass | `TestFindOneSubnetFiltersByTagsAndPrefersExplicitIDs` 验证 VPC/AZ 过滤后按标签选择；连续 10 轮通过 |
| IPAM-05 | P0/R | 多标签 AND | Pass | `TestFindOneSubnetTagConjunctionNoMatchAndMultipleCandidates` 使用 role+environment 两标签，排除任一部分匹配与错 AZ 子网，100 次均选中完整 AND 匹配且容量最高项；audit81 全包 10 轮通过 |
| IPAM-06 | P1/R | 空标签值、特殊字符标签 | Pass | audit87 新增精确匹配测试：要求值为空时，缺少 key 的高容量子网不得被当作空值匹配；含 `:=+_./@-` 的 key/value 仅按 opaque 字符串精确匹配。定向100轮、race20轮、ENI/full HuaweiCloud 普通与 race 各10轮及 vet 通过 |
| IPAM-07 | P0/R | 标签无匹配 | Pass | 同一 AND 标签测试将 environment 改为不存在值，即使有 role 部分匹配也稳定返回 nil，不错选高容量子网；audit81 全包 10 轮通过 |
| IPAM-08 | P0/R | 显式 subnet ID | Pass | `TestFindOneSubnetFiltersByTagsAndPrefersExplicitIDs` 验证显式 ID 精确命中；连续 10 轮通过 |
| IPAM-09 | P0/R | ID 与标签同时配置 | Pass | 同一测试配置冲突的 ID/标签并证明显式 ID 优先；连续 10 轮通过 |
| IPAM-10 | P1/C | 显式 ID 属于其他 AZ | Pass | `TestFindOneSubnetExplicitOrderValidationAndFallback` 注入 wrong-AZ 显式项并拒绝后按序选择合法项；连续 10 轮通过 |
| IPAM-11 | P1/C | 显式 ID 属于其他 VPC | Pass | 同一测试注入 wrong-VPC 显式项并拒绝后按序选择合法项；连续 10 轮通过 |
| IPAM-12 | P1/R | 多个合格标签子网 | Pass | AND 标签测试同时提供 5/9 两个完整匹配候选，内层 100 次均确定性选中可用地址 9 的子网；audit81 全包 10 轮通过 |
| IPAM-13 | P1/C | 首选子网容量耗尽 | Pass | `TestFindOneSubnetExplicitOrderValidationAndFallback` 证明首项仅余 1、申请 3 时 fallback 到第二项；连续 10 轮通过 |
| IPAM-14 | P1/C | 所有子网容量为 0 | Pass | `TestFindOneSubnetRejectsInsufficientCapacityAndSelectsMostAvailable` 覆盖所有显式候选 0/不足时返回 nil；连续 10 轮通过 |
| IPAM-15 | P1/R | 容量未知 | Pass | `TestFindOneSubnetAllocationAndTieBoundaries` 将 `AvailableAddresses=-1` 视为未知/不可选，且合法容量不足时 fail closed；连续 10 轮通过 |
| IPAM-16 | P0/R | 显式安全组 ID | Pass | `TestSecurityGroupPrecedenceValidationAndNormalization` 验证显式 SG 优先、去空/去重/稳定排序；连续 10 轮通过 |
| IPAM-17 | P1/R | 安全组标签选择 | Pass | 同一测试验证标签选择优先于 trunk，`TestSecurityGroupTagSelectionIsScopedToVPC` 验证 VPC 约束；连续 10 轮通过 |
| IPAM-18 | P0/R | 未配置 SG 时继承 trunk | Pass | `TestSecurityGroupsInheritedFromTrunkPort` 及 precedence 测试验证从 trunk 继承并规范化；连续 10 轮通过 |
| IPAM-19 | P1/C | SG ID 无效/跨 VPC | Pass | audit92 首次满池请求被VPC.9905配额先拒绝并明确排除；最终 cordon 单节点、暂停Operator、仅删除1个确认未使用SubENI腾出槽位后，无效SG Create被云端以安全组错误和request ID明确拒绝，父网卡7项集合哈希不变。恢复Operator后旧ID消失、精确云端集合=新pool8、总pool40、used-outside0、error0、mesh56/56 |
| IPAM-20 | P1/R | 多安全组 | Pass | 显式、标签、trunk 三条路径均验证多 SG、去重和稳定排序，且 101 个超过云上限会 fail closed；连续 10 轮通过 |
| IPAM-21 | P1/R | SubENI 资源标签 | Pass | audit81 修复为 Create/BatchCreate 请求内联 tags，生产 Client 在 cn-south-1 真实单建和批建后 Show 精确返回两项预期资源标签，清理/恢复后无残留 |
| IPAM-22 | P1/R | Agent-only 配置 | Pass | `TestApplyHuaweiCloudIPAMNetConf/NetConf` 验证空 CNI 字段不覆盖 Agent 已有水位、子网和 SG；连续 10 轮通过 |
| IPAM-23 | P1/R | CNI-only 配置 | Pass | CNI standalone/conflist HuaweiCloud 解析及 apply 测试验证 CNI-only 字段进入节点配置；连续 10 轮通过 |
| IPAM-24 | P1/R | Agent+CNI 字段级合并 | Pass | apply 测试验证 CNI 非空字段逐字段覆盖、空字段保留 Agent 值且深拷贝隔离；连续 10 轮通过 |
| IPAM-25 | P1/C | CNI JSON 错误/字段类型错误 | Pass | CNI 边界套件覆盖重复 key、负水位、错误字段类型、非法 prevResult、oversize、缺失/重复 plugin；全套连续 10 轮通过 |
| IPAM-26 | P0/R | `releaseExcessIPs=false` | Pass | audit74确认运行配置为false；五节点各并发新增2个Pod并删除后，等待210秒超过默认180秒释放延迟，40个SubENI/IP池条目的IP与resource映射逐项不变，未触发主动回收 |
| IPAM-27 | P0/C | `releaseExcessIPs=true` | Pass | audit75在node0003临时将min-allocate 8→4并移走2个测试Pod，重启Operator加载true后80秒内池8→6；确认池内容实际变化，然后恢复false/min8/池8及全部测试Pod |
| IPAM-28 | P0/C | 在用 IP 保护 | Pass | audit75释放前锁定node0003仍在用的router/health IP 192.168.1.167、192.168.1.45；池8→6后两者仍在池内且used集合未损失，恢复后仍存在，未删除在用SubENI |
| IPAM-29 | P1/C | 回收 Delete 失败 | Pass | `TestReleaseIPsStopsAtDeleteFailure` 验证第 2 次删除失败后停止，保留未删资源且提交此前成功删除；连续 10 轮通过 |
| IPAM-30 | P1/R | 连续扩缩容 10 轮 | Pass | 8 个 matrix Pod 连续删除/重建 10 轮；每轮两组 DaemonSet 8/8 Ready 且全向 mesh 56/56 |
| IPAM-31 | P1/R | 达到 flavor SubENI 上限 | Pass | 实机达到 8 上限后返回受控 `No more IPs available`，无崩溃 |
| IPAM-32 | P1/R | 达到子网 IP 上限 | Pending | 待执行 |
| IPAM-33 | P1/R | 达到项目配额 | Pending | 待执行 |
| IPAM-34 | P1/C | 手工删除一个测试 SubENI | Pass | audit81 在 Operator 停止且目标节点 cordon 后云端删除两个已确认空闲 SubENI；恢复 Operator 后池自动回到8，旧资源ID归零、used 全部仍在池内、错误为空 |
| IPAM-35 | P1/C | 手工修改测试 SubENI SG/标签 | Pending | 待执行 |
| IPAM-36 | P1/C | 删除测试节点/CiliumNode | Pending | 待执行 |
| IPAM-37 | P1/R | Pod IP 快速复用 | Pass | 10 轮快速重建期间 `.230/.75/.12/.129` 等 IP 被重新分配，最终 endpoint Ready、mesh 56/56、客户矩阵全通过 |
| ROUTE-01 | P0/R | 单 SubENI 路由基线 | Pass | 8/8 Pod source rule、独立表、default+gateway route 完整 |
| ROUTE-02 | P0/R | 同节点同网关多 SubENI | Pass | 四 worker 各 2 Pod，使用不同 10001–14094 表且同网关正常 |
| ROUTE-03 | P0/R | 同节点不同网关双子网 | Pending | 待执行 |
| ROUTE-04 | P0/R | A 后 B 创建 | Pending | 待执行 |
| ROUTE-05 | P0/R | B 后 A 创建 | Pending | 待执行 |
| ROUTE-06 | P0/R | 删除/重建其中一个 Pod | Pass | 删除整组 4 Pod 后旧 endpoint/map 清理，重建 4/4 Ready |
| ROUTE-07 | P0/R | Agent 重启 | Pass | audit57 金丝雀启动将已删 endpoint 1847 的 pinned-map 残留从1条清为0；五节点顺序 rollout 后每步 mesh 56/56，最终10轮重建均 56/56 |
| ROUTE-08 | P0/R | worker 重启 | Pass | node0002 实机重启暴露并修复启动期 BPF pin-map 竞态；audit53 无人工干预恢复，客户 HTTP 21/21、TCP 4/4、源 IP 19/19 全通过 |
| ROUTE-09 | P0/C | 从旧共享 ifindex 表升级 | Pass | audit83 在 node0003 停止 Agent 进程后为存量 Pod 注入 priority-111/from-IP/table=eth0-ifindex(2) 旧规则；Agent 重启自动删除旧规则，保留独立 VLAN 表 13109 及两条完整路由，pool 不变、mesh 56/56 |
| ROUTE-10 | P0/R | 显式 compat=false | Pass | 当前 compat=false 客户配置下 8 Pod 路由表及 56/56 mesh 通过 |
| ROUTE-11 | P1/R | 显式 compat=true | Pass | audit88 等待 ConfigMap 投影生效后仅重建 node0003 Agent；两个活跃 matrix Pod 均从 priority111 切换为 compat priority110，无同源旧优先级，per-VLAN 表仍完整，pool不变、mesh56/56；恢复后反向切回111并再次全通 |
| ROUTE-12 | P1/C | 遗留重复 rule | Pass | audit65 在 node0002 为 pod3 注入 priority-110 legacy rule 与独立 blackhole 表；周期reconcile在4秒内只删除旧rule，保留正确priority-111 rule/两条当前路由且不修改外部表，清理后mesh 56/56 |
| ROUTE-13 | P1/R | VLAN 边界和表范围 | Pass | audit88 `TestEgressRulePriorityAndTableID` 覆盖 VLAN1、旧 offset 可能碰 main 的 VLAN244、VLAN4094+compat，精确断言 priority/table 范围及两 VLAN 不共表；定向100轮、race20轮、privileged20/race10 及 vet 通过 |
| ROUTE-14 | P1/C | VLAN 0、>4094 或解析错误 | Pass | audit88 同一边界套件明确拒绝 VLAN0/4095；`TestHuaweiCloudRoutingInfoBoundaries` 拒绝空、非数字、0/4095 interface number 以及非法网关/MAC/CIDR，高重复普通/race/privileged 执行通过 |
| ROUTE-15 | P1/C | 手工删除测试 route/rule | Pass | audit64 在 node0002 同时删除 pod3 与 `cilium_host` 的 priority-111 rule、两组完整路由以及 permanent gateway neighbor；3秒内全部恢复，Agent未重启，两张 HuaweiCloud map 哈希不变，随后 mesh 56/56 |
| ROUTE-16 | P1/R | 宿主已有其他策略规则 | Pass | audit65 注入 priority-112、源198.51.100.1、table50000及blackhole default；跨4个五秒reconcile周期rule/route逐字不变，全部当前HuaweiCloud策略表仍完整，清理后mesh 56/56 |
| ROUTE-17 | P1/R | VPC 内网与公网双目标 | Pending | 待执行 |
| ROUTE-18 | P1/R | 长连接期间新增第二网关 Pod | Pending | 待执行 |
| BPF-01 | P0/R | endpoint Ready | Pass | 8 个 matrix endpoint 均 ready 且存在于 endpoint BPF map |
| BPF-02 | P0/R | endpoint 删除 | Pass | 4 Pod 整组删除后旧 endpoint/map 4/4 消失，重建后 4/4 恢复 |
| BPF-03 | P0/R | Agent 重启/endpoint restore | Pass | audit57 现场证明启动调谐清理 endpoint 1847 的双图残留；全量 rollout 后所有 map LxcID 均属于当前 endpoint，stale=0，mesh 56/56 |
| BPF-04 | P1/R | Pod 快速创建删除 | Pass | 10 轮共快速删除/重建 80 个 Pod；每轮新 Pod 8/8 Ready 且 BPF 数据面全向 56/56，无 Agent/BPF 错误日志 |
| BPF-05 | P1/S | 第二张 map 写失败 | Pass | patch0029 注入 ingress map 更新失败，验证 source map 恢复旧值或删除新值；rollback 再失败时返回组合错误 |
| BPF-06 | P1/S | 重复 Ready/Delete 事件 | Pass | patch0034 连续 Ready 10 次仅保留各一条 map entry，连续 Delete 10 次保持两图为空；普通与 `-race` 测试通过 |
| BPF-07 | P1/S | 非法 IP/MAC/VLAN/ifindex | Pass | patch0028 在 map 写入前覆盖非法/IPv6 IP、零/组播 MAC、VLAN 越界和零 ifindex，全部 fail closed |
| BPF-08 | P1/R | map 容量接近上限 | Pending | 待执行 |
| VLAN-01 | P0/R | skb VLAN metadata 入方向 | Pending | 待执行 |
| VLAN-02 | P0/R | 线内 802.1Q 入方向 | Pass | audit61 两端 `eth0` 的 RX VLAN offload 均为 fixed-off；物理入口抓到 VLAN 1443/662 单层 802.1Q，20/20 ICMP 与20/20 HTTP 到达目标 Pod，内核抓包0丢包 |
| VLAN-03 | P0/R | 线内 802.1ad 入方向 | Pass | audit59 内核 BPF_PROG_TEST_RUN 以真实 `ETH_P_8021AD` 线内帧进入 HuaweiCloud 解析路径，未知 VLAN 稳定 fail-closed；audit84 复核 20/20 完整迭代通过且无 FAIL |
| VLAN-04 | P0/R | 线内 VLAN 与 metadata 同时存在 | Pass | audit59 内核 BPF 测试同时构造线内 802.1Q 与同 VLAN metadata，命中实际 map 后两种表示均仅 pop 一次，最终帧长/乙太类型正确；20/20 通过 |
| VLAN-05 | P0/R | 只有一种 VLAN 表示 | Pass | audit61 现场 RX VLAN offload=fixed-off，入口 skb 仅有线内 802.1Q；目标 Pod 正常接收 ICMP/HTTP，结合 audit59 packet-level 最终 ethertype/长度断言证明单次 pop 不破坏内层报文 |
| VLAN-06 | P0/R | 处理后 `vlan_present` 仍为旧值 | Pass | 双表示内核测试在 `hwc_from_netdev` 前断言 metadata 存在，处理后断言 `vlan_present=false`；metadata 非 IPv4 分支亦验证 pop 后状态清零，20/20 通过 |
| VLAN-07 | P0/R | 出方向 VLAN 添加 | Pass | audit61 两端 TX VLAN offload=fixed-off；`-Q out` 各抓10帧，pod2 帧为源 MAC `fa:16:3e:ba:13:19`/VLAN1443，pod3 帧为 `fa:16:3e:ba:13:d9`/VLAN662，均发往 trunk 网关 MAC 且10/10往返成功 |
| VLAN-08 | P0/R | 入方向目标 MAC+VLAN 命中 | Pass | audit61 物理入口分别抓到目标 MAC+VLAN `fa:16:3e:ba:13:19+1443`、`fa:16:3e:ba:13:d9+662`；实时 pinned map 精确存在相同 key 并映射到 pod2/pod3 endpoint，流量成功投递 |
| VLAN-09 | P1/C | VLAN 正确但 MAC 不匹配 | Pending | 待执行 |
| VLAN-10 | P1/C | MAC 正确但 VLAN 不匹配 | Pending | 待执行 |
| VLAN-11 | P1/C | 截断/非法 VLAN header | Pending | 待执行 |
| VLAN-12 | P1/C | VLAN pop helper 失败 | Pending | 待执行 |
| VLAN-13 | P1/O | 双层 QinQ | Pass | audit59 真实内核 BPF 包级测试分别构造 802.1ad→802.1Q 双标签与三标签，两者均稳定 `DROP_INVALID`/handled=false；20/20 完整迭代通过 |
| VLAN-14 | P1/R | 非 trunk 接口 VLAN 流量 | Pending | 待执行 |
| VLAN-15 | P1/R | GSO/GRO/checksum offload 开关矩阵 | Pending | 待执行 |
| VLAN-16 | P1/R | ICMP/TCP/UDP、分片与大包 | Pass | audit61 跨节点双向 ICMP、双向1MiB TCP及双向100行 UDP 哈希一致；4KB ICMP 双向5/5，物理两端均抓到 VLAN 分片且0丢包；另覆盖56/1400/1472/2000字节与HTTP 20/20 |
| NET-01 | P0/R | 同节点 Pod↔Pod | Pass | 客户场景 1，HTTP 100/100；见五节点实机结果 |
| NET-02 | P0/R | 同 AZ 跨节点 Pod↔Pod | Pass | 客户场景 4，HTTP 100/100；见五节点实机结果 |
| NET-03 | P0/R | 跨 AZ Pod↔Pod | Skip | 用户批准：五台均在同一 AZ；同 AZ 跨节点 56/56 已通过 |
| NET-04 | P0/R | Pod→本节点 NodeIP | Pass | 客户场景 2，TCP 双向 5/5 |
| NET-05 | P0/R | Pod→远端 NodeIP | Pass | 客户场景 14，TCP 双向 5/5 |
| NET-06 | P1/R | Node→本节点 Pod | Pass | 客户场景 15，HTTP 100/100，源 IP 192.168.1.7 |
| NET-07 | P1/R | Node→远端 Pod | Pass | 客户场景 16，HTTP 100/100，源 IP 192.168.1.65 |
| NET-08 | P1/R | hostNetwork Pod↔SubENI Pod | Pass | 五节点实机：node0005 hostNetwork BusyBox HTTP→node0002 pod3 返回 `pod3`；pod3→192.168.1.65:18084 返回 `hostnet-ok`，双向通过并清理临时 Pod |
| SVC-01 | P0/R | ClusterIP TCP | Pass | 客户场景 5、6、7、17、18，各 100/100 且源地址断言通过 |
| SVC-02 | P0/R | ClusterIP UDP | Pass | agnhost UDP 应用响应经 ClusterIP 返回成功 |
| SVC-03 | P1/R | Headless Service | Pass | DNS 返回 8 个唯一 matrix Pod 地址 |
| SVC-04 | P1/R | NodePort TCP/UDP | Pass | NodePort 30081/TCP 与 30053/UDP 均返回应用响应 |
| SVC-05 | P1/R | `externalTrafficPolicy=Cluster` | Pass | 客户远端 NodePort 场景 8、11、19、21、25，各 100/100 且源地址断言通过 |
| SVC-06 | P1/R | `externalTrafficPolicy=Local` | Pass | 客户本地 NodePort 场景 12、13、22、24，各 100/100 且源地址断言通过 |
| SVC-07 | P1/R | sessionAffinity | Pass | 实机配置变体：仅开 affinity 且 `enable-node-port=false` 时状态明确 Disabled、20 次分布到 pod1/pod3；再启用 NodePort/KPR 后状态 Enabled，pod2 连续 50/50 固定 pod1。随后恢复客户基线并完成 customer HTTP 21x100、TCP 4x5、source 21/21 回归 |
| SVC-08 | P1/O | ExternalIP | Pass | 五节点实机临时 Service `externalIPs=[192.168.1.65]`、port 18085：pod2→ExternalIP 返回 pod1，远端 node0004→ExternalIP 返回 pod3；测试 Service 已删除 |
| SVC-09 | P1/O | LoadBalancer | Pending | 待执行 |
| SVC-10 | P1/R | Service 后端滚动更新 | Pass | 实机 2 副本 Deployment 经同一 ClusterIP 从 v1 滚动到 v2；pod2 连续 240 请求 0 失败（v1=23、v2=217），最终 2/2 Ready，临时资源清理完成 |
| DNS-01 | P0/R | 集群域名 UDP | Pass | matrix Pod 解析 kubernetes.default 与 8 地址 Headless 成功 |
| DNS-02 | P0/R | 集群域名 TCP fallback | Pass | Pod 向 10.96.0.10:53 发送 DNS-over-TCP，收到 108 字节响应 |
| DNS-03 | P0/R | 公网域名 | Pass | 配置外部出口前置后公网域名解析成功 |
| DNS-04 | P1/R | CoreDNS 单 Pod 重启 | Pass | 实机删除一个 CoreDNS Pod 前后解析均返回 2 个 Address；替换期间 pod2 连续 30/30 次 Service FQDN 查询成功，最终 CoreDNS 2/2 Ready |
| EGR-01 | P0/R | Pod→同 VPC 内网 | Pass | 8 Pod mesh 56/56、Pod→Node 与客户 VPC 路径均通过 |
| EGR-02 | P0/R | Pod→公网 | Pass | 明确配置 VPC 外出口 SNAT 前置后，公网 HTTPS 8/8 通过 |
| EGR-03 | P1/R | 多目标并发出口 | Pass | audit89 从客户 pod2 在每轮同一时间窗并发访问跨节点 pod3、ClusterIP 和另一节点 NodePort，20/20 轮三目标全部成功，Agent5/5、pool40、used-outside0 |
| EGR-04 | P1/R | 公网失败但 VPC 内网正常 | Pass | 当前客户配置 `enable-ipv4-masquerade=false`，pod2 到公网 1.1.1.1 稳定超时；audit89 每轮将该失败与三条 VPC/服务路径并发，20/20 轮均证明公网失败不影响内网数据面 |
| MTU-01 | P0/R | 小包、MTU-1、MTU、MTU+1 | Pass | MTU=1500；小包至 1472 payload 通过，1473 明确触发边界拒绝 |
| MTU-02 | P1/R | DF ping/PMTUD | Pass | DF 1472 通过，1473 返回 `message too long, mtu=1500` |
| CONN-01 | P1/R | TCP 长连接 30 分钟 | Pass | 跨节点 BusyBox 单 TCP echo 连接每 30 秒发送一帧，连续 tick-0～tick-60 共 61/61，首尾及数量断言通过、进程 rc=0；临时 namespace 清理，5/5 Node Ready |
| CONN-02 | P1/R | 1000 并发短连接 | Pass | pod2 以 50 worker×20 HTTP 短连接并发访问双后端 ClusterIP，共 1000 请求，`FAIL_WORKERS=0` |
| CONN-03 | P1/R | UDP 持续流 | Pass | 4 个 matrix source Pod 并发调用 agnhost netexec UDP dial，各 1000 次；总响应 4000/4000、覆盖 4 个后端、RC=0 |
| IPV6-01 | P1/O | IPv6 配置边界 | Pending | 待执行 |
| NP-01 | P0/R | 无策略基线 | Pass | 同节点/跨节点 HTTP+UDP 4/4；清理策略后恢复 |
| NP-02 | P0/R | namespace 默认 deny ingress/egress | Pass | enforcement 模式下同/跨节点 HTTP+UDP 4/4 阻断；audit 模式语义另行验证 |
| NP-03 | P0/R | label L3 allow | Pass | set=a→set=b 同/跨节点允许，错误 label 保持阻断 |
| NP-04 | P0/R | TCP/UDP 端口 allow | Pass | 8080/TCP、5353/UDP 4/4 允许，8081 阻断 |
| NP-05 | P0/R | DNS allow + 其他 egress deny | Pass | cluster DNS 成功，其他 egress 阻断 |
| NP-06 | P1/R | CIDR allow/deny | Pass | enforcement 实机：node0005 临时 netns 源 `198.18.0.2` 经专用回程路由访问 SubENI Pod；错误 CIDR 超时，`198.18.0.2/32` 返回 `policy-ok`。并验证 managed Pod 使用 endpoint identity、不能伪装成 CIDR 来源 |
| NP-07 | P0/R | 同节点策略 | Pass | deny 与 L3/L4 allow 均在同节点实测 |
| NP-08 | P0/R | 跨节点/跨 AZ 策略 | Skip | 跨节点策略已通过；用户批准跨 AZ Skip |
| NP-09 | P1/R | Service 前端到后端策略 | Pass | np-a namespace identity 被允许时，client-a 经 PodIP 与 `policy-svc.np-b` 均返回 `policy-ok`；np-c 两条路径均阻断，证明前端转换后策略仍作用于后端 |
| NP-10 | P1/R | 策略动态增删 | Pass | 同一 endpoint 在线经历 CIDR deny→CIDR allow→namespace allow→策略删除；每阶段等待收敛并验证，删除后 np-a/np-c 均恢复访问 |
| NP-11 | P1/R | 已建立连接遇到策略变化 | Pass | enforcement 实机：BusyBox TCP echo 长连接先返回 `before`，应用有效 CIDR deny 后新连接 DENIED，原连接未返回延迟发送的 `after` 并结束；证明策略变更切断既有连接。空 ingress 列表不启用方向的语义也单独识别，未误判为 deny |
| NP-12 | P1/R | 其他 namespace 隔离 | Pass | CNP 仅允许 `k8s:io.kubernetes.pod.namespace=np-a`：np-a direct/Service 均允许，np-c direct/Service 均拒绝；临时三 namespace 已全部删除 |
| REC-01 | P0/C | 删除单个 Cilium Agent Pod | Pass | audit57 金丝雀 Pod 删除重建后 Agent Ready/OK，清理真实 stale map owner，10轮 mesh 56/56 |
| REC-02 | P0/C | 滚动重启 DaemonSet | Pass | audit57 五节点顺序重启每步 Agent OK/mesh 56/56；全量后 HTTP 21/21、TCP 4/4、源IP 19/19 |
| REC-03 | P0/C | 删除 Operator Pod | Pass | 新 Operator Ready，CiliumNode 5/5 稳定，数据面正常 |
| REC-04 | P1/C | Operator 在创建过程中退出 | Pending | 待执行 |
| REC-05 | P1/C | Operator 在打标签过程中退出 | Pending | 待执行 |
| REC-06 | P1/C | kubelet 重启 | Pass | node0002 重启 kubelet 后 Agent/endpoint/客户数据面恢复并完成全量客户矩阵复测 |
| REC-07 | P1/C | containerd/Docker 重启 | Pass | node0002 重启 containerd 后 Agent/endpoint/客户数据面恢复并完成全量客户矩阵复测 |
| REC-08 | P1/C | worker-b2 重启 | Pass | node0002 整机重启后 audit53 自动创建并 pin HuaweiCloud BPF map，5/5 Agent/Node Ready，客户矩阵全通过 |
| REC-09 | P1/C | worker cordon/drain/uncordon | Pass | audit68 对node0004执行真实cordon/drain，节点保持Ready+SchedulingDisabled，Cilium/kube-proxy/matrix DaemonSet保持，客户pod2→pod3 20/20；uncordon后unschedulable与临时taint均为空，mesh 56/56 |
| REC-10 | P1/C | 控制面 API Server 短时不可达 | Pass | 2026-07-14：控制面因压力失联并完成软重启；发现 Worker Agent 通过 Service IP 启动形成循环依赖，设置 `k8s-api-server=https://192.168.1.65:6443` 后 Agent 5/5、Operator 1/1 恢复，客户25项及 mesh 56/56 复测通过 |
| REC-11 | P1/C | Operator→云 API 网络断开 | Pass | audit93 通过独立leader namespace启动隔离audit90 Operator并把API endpoint指向TEST-NET黑洞；候选以明确connect/timeout网络错误进入Failed，生产Operator全程Ready/restart0、pool哈希不变，恢复后endpoint key无残留、mesh56/56 |
| REC-12 | P1/C | 节点 DNS 故障 | Pass | audit93 隔离候选使用不存在的`.invalid`云API域名，DNS错误被明确归因并进入Failed；生产单例未替换/重启，测试Pod/namespace/ConfigMap全部清理，pool40、error0、mesh56/56 |
| REC-13 | P1/C | 错误云凭据 | Pass | audit79 无效凭据窗口只造成新云操作鉴权失败，现有 Pod 网络 mesh 56/56、40 个 pool 资源映射不变；恢复原 Secret 后 Operator Ready/restart0、各 CiliumNode error 为空 |
| REC-14 | P1/C | 测试子网耗尽 | Pending | 待执行 |
| REC-15 | P1/C | 测试 SG 临时阻断 | Pending | 待执行 |
| REC-16 | P1/C | trunk 接口 down/up | Pass | audit64 真实 trunk 连续3轮 down 5秒/up；每轮125/150后20/20，Node/Agent Ready且restart=0，五个当前策略表均为完整两路由，permanent neighbor与map owner均正确；末尾mesh 56/56 |
| REC-17 | P1/C | 删除一条测试策略路由 | Pass | audit64 实机删除 ordinary endpoint 与 router 策略路由并确认故障状态非no-op；周期reconcile在3秒内恢复两者规则/路由和neighbor，不重写BPF map，完整客户回归通过 |
| REC-18 | P1/C | 删除一个测试 BPF map 条目 | Pass | audit57 实机删除 matrix Pod `192.168.1.246` 的 source-map entry 后跨机 ping 按预期失败；重启该节点 Agent 后 entry 自动恢复、Agent OK、定向 ping 和 mesh 56/56 恢复 |
| REC-19 | P1/C | 云端手工删除空闲 SubENI | Pass | audit81 真实云端删除两个空闲资源并完成精确恢复；恢复后云端父网卡集合与 CiliumNode 新8项一致，matrix 56/56，完整客户 HTTP/TCP/源IP 回归通过 |
| REC-20 | P1/C | 云端手工删除在用 SubENI | Pending | 待执行 |
| REC-21 | P1/C | 节点 NotReady 超过回收窗口 | Pending | 待执行 |
| REC-22 | P1/O | Operator 多副本 leader 切换 | Pass | audit69 删除Lease holder所在Operator，holder从node0003身份切到node0004 standby，2副本重新Ready；缩回1副本又安全切至node0002身份，Operator错误扫描0、Nodes 5/5、mesh 56/56 |
| REC-23 | P2/C | 节点时间跳变 | Pending | 待执行 |
| REC-24 | P2/C | 大量 Kubernetes 事件积压 | Pending | 待执行 |
| SCALE-01 | P1/R | 40 Pod burst 均匀分布 | Pending | 待执行 |
| SCALE-02 | P1/R | 单节点 burst | Pending | 待执行 |
| SCALE-03 | P1/R | 五节点并发扩容 | Pass | audit73 单次并发创建10个Pod，通过强制hostname拓扑约束在五节点精确均分为每节点2个，2540 ms全部Ready；删除后五个CiliumNode的IPAM used计数均回到逐节点基线，未发生泄漏 |
| SCALE-04 | P1/R | 40→4→40 循环 10 次 | Pending | 待执行 |
| SCALE-05 | P2/R | 接近最大 Pod 数 | Pending | 待执行 |
| PERF-01 | P1/R | 同节点吞吐/RTT | Pass | audit71 对保留旧候选audit60与当前audit64分别完成同节点3轮各300秒TCP及TCP/UDP各3轮10000次请求应答；audit64吞吐中位1120.03 Mbps，较audit60的1120.02 Mbps持平（+0.001%），TCP P99中位改善15.08%，UDP P99中位增加1.82%，两者均0丢失且在无客户数值门槛时采用的10%保守技术护栏内 |
| PERF-02 | P1/R | 同 AZ 跨节点吞吐/RTT | Pass | audit70 同 AZ 跨节点完成3轮各300秒持续TCP：中位1405.31 Mbps、最大偏差3.238%；TCP/UDP各3轮10000次请求应答均0丢失，P99分别87.382–94.302/80.502–88.403 us；另有3轮100包ICMP均0丢失 |
| PERF-03 | P1/R | 跨 AZ 吞吐/RTT | Skip | 用户批准跨 AZ 环境限制 Skip；五台购买机器均位于同一 AZ，audit70已完成同 AZ 跨节点基线 |
| PERF-04 | P1/R | TCP/UDP PPS | Pass | audit72 每种拓扑/协议完成3轮各100000次64字节请求应答且0丢失；同节点TCP/UDP请求中位49427.20/53527.51 PPS（双向消息98854.40/107055.02 PPS），跨节点14536.28/15416.17 PPS（双向消息29072.56/30832.34 PPS）；相关宿主机与Pod接口、softnet均无新增drop/error/time-squeeze，Agent平均CPU 2.195–2.220 mcore，末尾mesh 56/56 |
| PERF-05 | P1/R | Pod 创建到 Ready 时延 | Pass | audit70 在node0004连续删除/重建20个DaemonSet Pod：P50/P95/P99=3998/4039/4084 ms；Scheduled到Cilium Create endpoint请求P50/P95=344/354 ms，20次镜像均为本机缓存命中；末尾mesh 56/56 |
| PERF-06 | P1/R | Agent/Operator CPU、内存 | Pass | audit70以crictl累计CPU时钟和working set记录空闲、两轮mesh burst、60秒settled三阶段各6个Agent/Operator样本；CPU 1.707–2.799 mcore，working set 35.08–239.98 MiB，阶段内最大绝对内存变化2.04 MiB，无重启/严重日志且mesh 56/56 |
| PERF-07 | P1/R | 云 API 调用率 | Pending | 待执行 |
| STAB-01 | P1/R | 24 小时持续探测 | Pending | 待执行 |
| STAB-02 | P1/R | 24 小时 Pod churn | Pending | 待执行 |
| STAB-03 | P2/R | 72 小时发布候选 | Pending | 待执行 |
| STAB-04 | P2/R | 长时间无变更空闲 | Pending | 待执行 |
| UPG-01 | P0/C | 旧候选→当前 15 patch 候选滚动升级 | Pass | audit90 从 audit81 滚动到最新 Operator：1/1 Ready、restart0、severe0，pool 映射哈希 `0202559d...` 不变，matrix 56/56；客户 HTTP 21项各100/100、TCP 4项各5/5、源IP 19/19 全通过 |
| UPG-02 | P0/C | `0007` 前共享表→独立表 | Pass | audit83 真实模拟旧 Agent 留存的 trunk-ifindex 共享表规则；新 Agent 启动后收敛到 per-VLAN 独立表，清除 stale 规则且数据面/pool 无回归，最终更换为 restart0 新 Pod |
| UPG-03 | P0/C | `0008` 前→支持线内 VLAN | Pending | 待执行 |
| UPG-04 | P0/C | values 凭据→`existingSecret` | Pending | 待执行 |
| UPG-05 | P1/C | 新旧 Agent 短时混部 | Pass | audit64 五节点逐台升级每步mesh 56/56；audit66 进一步形成4台audit64+1台audit60真实混部，旧节点Agent Ready/OK且全向mesh 56/56，随后恢复audit64 |
| UPG-06 | P1/C | 新旧 Operator 切换 | Pass | audit77 在 release=false 下实机 audit76→audit20→audit76；两侧均 1/1 Ready、restart0、severe0，切换后 mesh 各 56/56，完整 pool 资源映射不变 |
| UPG-07 | P0/C | 同版本新 digest 滚动 | Pass | audit64 在DaemonSet镜像名保持`audit25b`不变时逐节点将manifest从audit60切换为audit64新digest；每步Agent哈希/状态和mesh通过，最终五节点imageID完全一致 |
| UPG-08 | P0/C | Helm rollback | Pending | 待执行 |
| UPG-09 | P0/C | Agent 镜像回滚 | Pass | audit66 node0004 将`audit25b`从audit64回指保留的audit60并重建Agent，旧哈希/完整BPF/状态OK且混部mesh 56/56；再回指audit64，路由/neighbor完整、五节点哈希一致且mesh 56/56 |
| UPG-10 | P1/C | Operator 镜像回滚 | Pass | audit77 五节点预置保留的 audit20 镜像后执行真实 Deployment 回滚及恢复；旧版窗口和恢复窗口均通过健康、数据面与 pool 恒等校验，最终 audit76 二进制 SHA256 精确匹配 |
| UPG-11 | P1/C | 升级中单节点失败 | Pass | audit67 node0003 单节点因缺镜像进入ImagePullBackOff时其余4 Agent保持Ready，客户pod2→pod3持续20/20；恢复别名后该节点Agent Ready/OK、策略表/neighbor完整且全mesh 56/56 |
| UPG-12 | P1/C | 回滚中途失败后继续 | Pass | audit78 将 maxUnavailable 临时收紧为0后注入不可拉取候选，验证失败阶段仍有1个旧 Operator Ready、mesh 56/56、pool 恒等；继续恢复 audit76 并还原 1/1 strategy 后再次全通过 |
| UPG-13 | P1/R | CRD 字段向前/向后兼容 | Pending | 待执行 |
| UPG-14 | P1/C | Helm uninstall/reinstall | Pending | 待执行 |
| OBS-01 | P0/R | Cilium status/health | Pass | 多轮 5/5 `cilium status --brief=OK` |
| OBS-02 | P0/R | CiliumNode 与云端快照 | Pass | 五节点 instance/watermark 快照在 Operator 重启前后稳定 |
| OBS-03 | P0/R | `ip rule/route/neigh` 快照 | Pass | 8 个 source rule/table/default/gateway 已逐项审计 |
| OBS-04 | P0/R | BPF map 快照 | Pass | audit57 逐节点解析两张 HuaweiCloud pinned map 原始 value，所有 LxcID 均存在于实时 endpoint 集，5/5 节点 stale=0 |
| OBS-05 | P0/R | trunk 双端抓包 | Pass | audit61 在 node0005/node0002 的 trunk 物理口双端并发抓包，仅过滤测试 Pod IP 与 ICMP/TCP/UDP；分别记录185/208帧、VLAN1443/662、双向分片和校验信息，内核丢包均为0 |
| OBS-06 | P0/R | Cilium monitor/drop counters | Pass | 五节点 `cilium status --brief` 全 OK 并读取 forward/drop 指标；在 pod2 连续 30 次 ClusterIP 请求期间抓取其本节点 monitor：385 events、357 含 pod2 IP、0 drop，双向 Service NAT trace 完整 |
| OBS-07 | P1/R | Kubernetes Event | Pass | 2026-07-14 全 namespace 按 lastTimestamp 审计：5/5 Node Ready、Agent 5/5 Running/0 restart；仅见 rollout 启动窗口的瞬时 startup-probe connection-refused，随后全部健康，无持续 Warning |
| OBS-08 | P1/R | 云 API request ID | Pass | audit92 对400/401/403/404/429/500逐项注入`X-Request-Id`，归一化错误均保留精确ID且不含AK/SK/Authorization；定向100、race20、API全包20+race20、HuaweiCloud全域10+race10及vet通过。真实无效SG错误也确认request ID存在 |
| OBS-09 | P1/R | 资源变化审计 | Pending | 待执行 |
| OBS-10 | P0/R | 敏感信息二次扫描 | Pass | rendered resources、Pod spec、Operator logs 均无凭据值 |
| OBS-11 | P1/R | 证据目录权限 | Pass | 本地 `ANALYSIS` 为 root:root 0755，核心台账/证据为 root:root 0644；递归检查无 group/other-writable 目录或文件 |
| OBS-12 | P1/R | 指标长期趋势 | Pending | 待执行 |
| CLEAN-01 | P0/C | 删除测试 namespace | Pass | audit74删除含10个跨五节点Pod的隔离namespace，42.506秒完成且namespace无残留；五个CiliumNode used状态逐项回到创建前基线，末尾mesh 56/56 |
| CLEAN-02 | P0/C | `releaseExcessIPs=false` 下清理 | Pass | audit74在false配置下删除隔离namespace后等待210秒，五节点各8个、合计40个池条目的IP/resource清单与删除前完全一致；节点/Agent/Operator健康且无重启 |
| CLEAN-03 | P0/C | `releaseExcessIPs=true` 下清理 | Pass | audit75在隔离单节点缩容窗口真实删除2个空闲SubENI，保护全部在用IP；随后恢复false、min8和池8，DaemonSet 4/4+4/4、路由表4组各2条、永久邻居及mesh 56/56 |
| CLEAN-04 | P0/R | 云端孤儿检查 | Pass | audit81 恢复后通过生产 Client 精确 List 父端口全集，与五个 CiliumNode 的 40 个 pool 资源 ID 集合一致，所有测试创建/删除 ID 均无残留 |
| CLEAN-05 | P0/R | 节点 route/map/neighbor 残留检查 | Pass | audit57 对 5 节点 CiliumNode/SubENI、endpoint、双 pinned map、priority 20/110/111 rule、VLAN 路由表和 permanent neighbor 做交叉审计；活跃表全部精确匹配，未引用表均为允许的完整 default+nexthop 保留对，stale=0、malformed=0 |
| CLEAN-06 | P0/R | 节点标签/污点恢复 | Pass | audit57 五节点终态审计：4 worker 污点均为0，control-plane 仅保留 kubeadm 的 master/control-plane NoSchedule 污点；无 customer/matrix/audit/test/canary 临时标签或污点，Agent 5/5 Running |
| CLEAN-07 | P0/R | 外部 Secret 处理 | Pass | audit80/audit82 验证自定义 Secret 引用、错 namespace 失败边界及 EXIT 恢复；最终仅原 `cilium-huaweicloud` 引用存在，两个临时 Secret 在相应 namespace 均不存在 |
| CLEAN-08 | P0/R | 证据脱敏和归档 | Pass | 执行工作树与全 Git 历史高置信凭据扫描：私钥 PEM、AKIA 样式、内联云 SK 均 0 命中；`ANALYSIS` 无 `.out/.log/.tar/.key` 敏感原始件，仅归档脱敏结论和 `/tmp` 证据路径 |
| CLEAN-09 | P1/R | 五节点最终健康检查 | Pass | audit60 全量回归后 5 Node Ready、5 Agent Ready/OK、Operator 1/1；Agent/BPF/测试源码三哈希一致，map stale=0、相关错误=0、DiskPressure=0，mesh/HTTP/TCP/源IP 全通过 |
| CLEAN-10 | P1/R | 清理后 30 分钟复核 | Pass | audit86 在 audit81 最终清理后 1801s 执行独立复核：5 Node/5 Agent/1 Operator 全 Ready 且 restart0，pool40、used-outside0、operator error0、异常 Pod0、临时 Secret0、五节点独立表/永久 neighbor 完整，matrix 56/56 |
| BMETA-01 | P0/S | OpenStack metadata `uuid` 为空 | Pass | 新增单测验证明确报错 |
| BMETA-02 | P0/S | `vpc_id` 为空 | Pass | 新增单测验证明确报错 |
| BMETA-03 | P0/S | `availability_zone` 为空 | Pass | 新增单测验证明确报错 |
| BMETA-04 | P1/S | AZ 只有 1 个字符 | Pass | 修复为拒绝无 region 的单字符 AZ，单测通过 |
| BMETA-05 | P1/S | AZ 不以单字符后缀表示 region | Pass | 修复为仅接受小写单字母 AZ 后缀，单测通过 |
| BMETA-06 | P0/S | `network_data.links` 为空 | Pass | 新增单测验证明确报错 |
| BMETA-07 | P0/S | `links[0].vif_id` 为空但后续 link 有值 | Pass | 修复为跳过空占位 link，单测通过 |
| BMETA-08 | P0/R | 多网卡且真正 trunk 不是 `links[0]` | Pass | `TestSelectTrunkInterfaceIDOrderIndependent` 将真实 trunk 放在第 2 项并反转顺序，始终按 MAC 命中 `trunk-port`；连续 10 轮通过 |
| BMETA-09 | P0/S | metadata links 顺序重排 | Pass | 按配置网卡 MAC 选择，正反顺序单测均命中同一 port ID |
| BMETA-10 | P1/S | metadata HTTP 204/301/404/500 | Pass | httptest 四种状态均被拒绝 |
| BMETA-11 | P1/S | metadata 响应恰好/超过 1 MiB | Pass | 恰好上限接受，超 1 字节明确拒绝 |
| BMETA-12 | P1/S | metadata JSON `null`、空对象、未知字段 | Pass | null/空对象拒绝，未知字段兼容，单测通过 |
| BMETA-13 | P1/S | metadata 上下文已取消/10 秒超时边界 | Pass | 已取消 context 与同一 10 秒 client timeout 机制的缩短边界测试均通过 |
| BMETA-14 | P1/R | OS 网卡重命名但 port ID 不变 | Pass | audit60 privileged netlink 测试将真实 dummy trunk down 后显式重命名再 up；旧名立即拒绝，新名按同一 MAC 恢复相同 port ID，普通100轮、privileged100轮及 race20轮通过 |
| BAPI-01 | P0/S | BatchCreate `count=-1`、`0` | Pass | `TestBatchCreateCountValidation` 明确拒绝 -1、0（及 11），1/10 边界成功；audit25b clean suite 通过 |
| BAPI-02 | P0/S | BatchCreate `count=1`、`10` | Pass | httptest 完整创建/子网/网关链路均返回精确数量 |
| BAPI-03 | P0/S | BatchCreate `count=11` | Pass | 请求前明确拒绝，单测通过 |
| BAPI-04 | P0/S | Create 的 subnet ID/parent ID 为空或纯空格 | Pass | 请求校验单测覆盖空串和空白 |
| BAPI-05 | P1/S | SG 列表包含空串、重复 ID、超云端数量上限 | Pass | patch0035：空串、重复 ID、官方最大 100/超限 101 均在发请求前验证；边界单测通过 |
| BAPI-06 | P0/S | 单创建返回 HTTP 成功但对象为 `nil` | Pass | httptest 成功状态空对象被拒绝 |
| BAPI-07 | P0/S | 批创建返回 `nil` 数组 | Pass | httptest 成功状态 nil 数组被拒绝 |
| BAPI-08 | P0/S | 批创建返回数量少于/多于请求 | Pass | 两侧数量不一致均报错并回滚可识别 ID |
| BAPI-09 | P0/S | 批创建数组包含 `nil`、空 ID、重复 ID | Pass | 响应校验及唯一回滚单测通过 |
| BAPI-10 | P1/S | 空 tags | Pass | nil/空 map 均安全 no-op |
| BAPI-11 | P1/S | tag 空 key/value、重复 key、Unicode、超长度/超数量 | Pass | patch0035：map 保证 key 唯一；空 value 合法，空 key 拒绝；Unicode 按字符计数；key 128/value 255/tags 20 接受，129/256/21 拒绝；单测通过 |
| BAPI-12 | P0/S | finalize 第 1/N 个网关解析失败 | Pass | 首项失败后 N 个已创建 ID 全部触发回滚 |
| BAPI-13 | P0/S | finalize 最后一个打标签失败 | Pass | 末项标签失败后全部创建项回滚 |
| BAPI-14 | P1/S | 回滚多个 Delete 同时失败 | Pass | 两个删除错误均保留在聚合错误中 |
| BAPI-15 | P0/S | Show/List 返回对象缺 ID/IP/MAC/VLAN/subnet/parent | Pass | 公共对象校验逐字段负例通过 |
| BAPI-16 | P0/S | Wait 状态为 `BUILD`/`DOWN`/未知值 | Pass | BUILD/DOWN 继续等待，未知/ERROR 明确失败 |
| BAPI-17 | P0/S | Wait 首次遇到最终一致性 404 | Pass | 404 后继续轮询，BUILD 后 ACTIVE 返回，单测通过 |
| BAPI-18 | P0/S | Wait 恰好在 60 秒转为 ACTIVE | Pass | patch0036：超时边界执行最终一次状态读取，消除 ticker/timeout 调度竞争；deadline 转 ACTIVE 单测通过 |
| BAPI-19 | P1/S | List 页 `PageInfo=nil`/`NextMarker=nil`/空串 | Pass | 三种终止形式单测通过 |
| BAPI-20 | P0/S | List 服务端重复同一 marker | Pass | 第二次重复 marker 立即报错，无死循环 |
| BAPI-21 | P1/S | List 某页 items 为 nil 但有 next marker | Pass | 正常进入下一页并终止 |
| BAPI-22 | P1/S | server 分页恰好 999/1000/1001 条 | Pass | patch0036：真实 SDK/httptest 覆盖 999 单页、1000 终止空页、1001 两页，数量及请求数断言通过 |
| BAPI-23 | P1/S | server `Count=nil`、小于实际、超过实际 | Pass | patch0036：nil/较大 Count 正确分页；Count 小于已返回数量明确 fail closed，不接受不一致响应；单测通过 |
| BAPI-24 | P0/S | SubENI private IP 命中辅助 IPv4 CIDR | Pass | 多 CIDR 中按 private IP 命中正确辅助网段 |
| BAPI-25 | P0/S | private IP 不属于任何返回 CIDR | Pass | 不再回退首个 IPv4 CIDR，明确报错 |
| BAPI-26 | P1/S | subnet 仅有 IPv6、空 CIDR、非法 CIDR | Pass | IPv4 CIDR/网关联合校验负例通过 |
| BAPI-27 | P0/S | router port 查询返回 0 个 | Pass | 明确报错，不再静默保留空 MAC |
| BAPI-28 | P1/S | router port 查询返回多个 MAC | Pass | 多个冲突 MAC 明确报错 |
| BAPI-29 | P0/S | SG API 返回多个 VPC 的组 | Pass | patch0027 `TestSecurityGroupTagSelectionIsScopedToVPC` 验证跨 VPC SG 不泄漏，未知 VPC 条目在同步阶段被排除 |
| BAPI-30 | P1/S | API 20 QPS/40 burst 前后边界 | Pass | patch0036：前 40 个请求无等待，第 41 个按 20 QPS 延迟且记录限流指标；连续 10 轮单测通过 |
| BAPI-31 | P0/S | `0010` V1/V2 子网容量页为 0/1/1999/2000/2001 条 | Pass | 五个分页边界 httptest 均通过 |
| BAPI-32 | P0/S | 容量 API 连续返回满 2000 条且末项 ID/marker 不前进 | Pass | 重复满页被重复 ID/marker 守卫终止 |
| BAPI-33 | P0/S | 容量 API 返回 nil、错误类型、HTTP 成功但 `subnets=nil` | Pass | nil/异常响应均明确失败；原有错误类型覆盖保留 |
| BAPI-34 | P0/S | 容量 API 返回空 subnet ID 或同一 ID 重复且容量冲突 | Pass | 空 ID 和重复 ID 均明确失败 |
| BAPI-35 | P1/S | 容量为 0、1、`MaxInt32` 或负数 | Pass | 三个合法边界保真，负数拒绝 |
| BAPI-36 | P0/S | V3 Virsubnet 在 V1/V2 容量表缺失，或容量表包含 V3 不存在的 ID | Pass | V3 项缺容量时明确失败且不发布结果；容量表孤儿项被忽略，匹配项容量保真 |
| BAPI-37 | P1/S | 容量 API 和 Virsubnet API 分页期间 context 取消/限流 | Pass | 分页间取消立即终止；429 明确报错且不发布半份结果；audit18 全量定向测试通过 |
| BAPI-38 | P0/S | 容量 API 403/404/429/5xx、超时后恢复 | Pass | 四种状态均报错；context 超时后同 client 再请求成功 |
| BCFG-01 | P0/S | flavor limit 为 `0` | Pass | 修复为必须大于 0，单测通过 |
| BCFG-02 | P0/S | flavor limit 为 `1` 且最小预分配为 2 | Pass | patch 0026：`calculateNeededIPs(0,0,2,0,1)=1`，实例上限仍为硬上限，不会因预分配 2 超配 |
| BCFG-03 | P0/S | flavor limit 为负数 | Pass | 负数明确拒绝 |
| BCFG-04 | P0/S | flavor limit 为空、空格、非数字、溢出整数 | Pass | 四类解析负例全部通过 |
| BCFG-05 | P1/S | flavor 通过 ID 命中、通过 Name 命中、均不命中 | Pass | ID/Name 各返回 8，不命中明确失败 |
| BCFG-06 | P1/S | 动态 limit 查询超时但静态表有值 | Pass | patch 0026：动态查询返回 DeadlineExceeded 后回退最近缓存值 16 |
| BCFG-07 | P0/S | 动态 limit 查询失败且静态表无值 | Pass | patch 0026：未知 flavor 且动态查询失败返回 0/不可分配，不猜测容量 |
| BCFG-08 | P1/S | 动态 limit 在运行中降低到当前已用数以下 | Pass | patch 0026：动态 8→1 立即生效，同时 4 个 Used 项保持完整、不被截断 |
| BCFG-09 | P1/S | 动态 limit 提高 | Pass | patch 0026：动态 1→16 立即生效；后续超时回退新缓存值 16 |
| BCFG-10 | P0/S | `toAllocate` 为负、0、1、10、11 | Pass | API 边界测试：-1/0/11 明确拒绝，1/10 返回精确数量；audit25b clean suite 通过 |
| BCFG-11 | P0/S | subnet `AvailableAddresses=-1`、`0`、`1`、N | Pass | 负数在 API 转换层拒绝；0/1/MaxInt32 保真；容量不足候选不会被选择 |
| BCFG-12 | P1/S | 两个候选子网可用地址数完全相同 | Pass | patch 0018 同容量按 subnet ID 稳定决胜，100 轮均选择 `subnet-a` |
| BCFG-13 | P1/S | subnet tags 为空 map 与 nil | Pass | patch0027 `TestFindOneSubnetTreatsNilAndEmptyTagsIdentically` 验证两者均按自动候选选择最大剩余容量子网 |
| BCFG-14 | P0/S | 显式 subnet 列表含空 ID、重复 ID | Pass | patch 0018 按 ID 直接查找，空/未知/重复项安全跳过且不重复云调用 |
| BCFG-15 | P0/S | 显式 subnet 列表跨 VPC/AZ | Pass | VPC/AZ 不符候选被拒绝，不能借显式优先绕过归属校验 |
| BCFG-16 | P0/S | 第一个显式子网容量不足、第二个正常 | Pass | patch 0018 严格按配置顺序选择首个合法且容量足够的候选，单测验证 fallback 到第二项 |
| BCFG-17 | P1/S | 第一个显式子网 404/403/5xx | Pass | 新增表驱动边界测试：首个显式子网分别返回 404、403、500 时保留原始错误并立即停止，不错误回退第二子网；普通测试连续 10 轮及 race 通过；单一合并 patch 干净重放并与 squash tree 等价 |
| BCFG-18 | P0/S | SG 显式 ID、SG tags、trunk 继承同时存在 | Pass | patch 0019 单测证明显式 ID > tags > trunk；结果去空、去重并排序 |
| BCFG-19 | P0/S | 配置了 SG tags 但 0 个匹配 | Pass | patch 0019 改为 fail-closed，返回可诊断错误且不再静默继承 trunk 扩权 |
| BCFG-20 | P1/S | SG tags 匹配数量超过云端附加上限 | Pass | patch0037：tags 匹配 101 个 SG 在创建前 fail closed；同时覆盖显式列表和 trunk 继承路径，100 为允许上限；普通/race 测试通过 |
| BCFG-21 | P1/S | trunk 无 SG，现有 SubENI 有重复/空 SG | Pass | trunk 与历史 SubENI 两条路径均忽略空 ID、去重、排序，单测覆盖稳定集合 |
| BCFG-22 | P0/S | 首次启动无 `TrunkInterfaceID` 且无历史 SubENI | Pass | patch0027 扩展 `TestSecurityGroupPrecedenceValidationAndNormalization`，验证无 trunk/历史 SubENI 时安全组解析 fail closed |
| BCFG-23 | P1/S | `.conflist` plugins 为空、包含 `null`、无 cilium-cni | Pass | patch 0022 定向测试：空/全 null/无 cilium-cni 均 fail-closed；单个有效插件正常解析 |
| BCFG-24 | P1/S | `.conflist` 含多个 cilium-cni | Pass | patch 0022 定向测试：多个 cilium-cni 被判为歧义并拒绝 |
| BCFG-25 | P1/S | JSON 重复键、未知键、超大文件 | Pass | patch 0022：递归拒绝重复键、未知键保持兼容、超过 1 MiB 拒绝；定向测试与 race 测试通过 |
| BCFG-26 | P1/S | `prevResult` 版本为空、不支持、malformed | Pass | patch 0022 定向测试覆盖空版本、不支持版本和 malformed，均返回错误且不 panic |
| BCFG-27 | P1/S | CNI `preAllocate=-1/0/1/极大值` | Pass | patch 0022：负值被拒绝；0/1/极大值解析覆盖，实际创建量仍由 IPAM/实例容量上限约束 |
| BCFG-28 | P1/S | CNI map/slice 后续被调用方修改 | Pass | patch 0022 nodediscovery 测试证明写入 CiliumNode 前深拷贝，调用方后续修改不污染规格 |
| BCFG-29 | P0/S | `AvailableAddresses` 小于/等于/大于 `toAllocate` | Pass | 小于时拒绝，等于和大于时可选；0 不再作为未知容量放行 |
| BCFG-30 | P0/S | 多个候选的剩余容量不同、相同或同步期间变化 | Pass | patch0018/0027 覆盖最大容量、同容量稳定 ID 次序及 Resync 后容量反转重新选择 |
| BIPAM-01 | P0/S | CiliumNode/spec/HuaweiCloud 为 nil | Pass | patch 0020 对 nil node/manager/allocation/status 显式安全返回；不 panic、不创建资源 |
| BIPAM-02 | P0/S | instance ID 为空或运行中变化 | Pass | patch0038：所有资源/status/resync 路径统一使用最新 CiliumNode instance ID；old→new 立即切换到新实例快照，空/nil update fail closed，不回退陈旧构造 ID；普通/race 测试通过 |
| BIPAM-03 | P0/S | Resync 返回 SubENI 空 private IP | Pass | 空 IP 计入接口状态但不进入 AllocationMap；有效资源不受影响 |
| BIPAM-04 | P0/S | 两个 SubENI 返回相同 private IP | Pass | patch 0020 检测不同 SubENI 的重复 IP，拒绝发布部分新快照并保留旧状态 |
| BIPAM-05 | P1/S | Resync 中单个资源类型错误 | Pass | 非 SubENI 资源被告警跳过，其他合法资源正常发布 |
| BIPAM-06 | P0/S | BatchCreate 成功但返回空列表 | Pass | 0 个有效结果返回 `unableToCreateSubENI`，不再假报满足 allocation |
| BIPAM-07 | P0/S | BatchCreate 返回含 nil 项 | Pass | nil 被忽略，返回计数和缓存仅包含真实非 nil SubENI；全 nil 明确失败 |
| BIPAM-08 | P1/S | `excessIPs=-1`、`0`、大于全部空闲数 | Pass | 负数/0 不产生候选；大值最多返回全部已确认空闲项 |
| BIPAM-09 | P0/S | Used 状态缺失/滞后 | Pass | Used map 为 nil 时 fail-safe，不生成任何释放候选 |
| BIPAM-10 | P0/S | Used 状态在 Prepare 与 Release 间变为在用 | Pass | Delete 前在锁内重新读取 Used；新变为 used 的 SubENI 被保留 |
| BIPAM-11 | P1/S | release 请求包含未知 IP | Pass | 未知 IP 安全跳过，后续合法释放继续执行 |
| BIPAM-12 | P1/S | release 请求包含重复 IP | Pass | 按 SubENI ID 去重，只执行一次 Delete，不产生第二次 404 |
| BIPAM-13 | P0/S | 批量 release 第 N 个 Delete 失败 | Pass | patch 0024：第 2 个删除注入失败，确认第 1 个已提交、第 2/3 个保留且立即停止；ENI 定向测试通过 |
| BIPAM-14 | P1/S | release 期间上下文取消 | Pass | patch 0024：第 2 个删除前取消 context，返回 context.Canceled，第 1 个已提交且第 2 个保留；ENI 定向测试通过 |
| BIPAM-15 | P1/S | 空闲候选 IP 为 `.2`、`.10` 等 | Pass | 明确按字符串排序并在重复调谐中保持稳定；单测验证 `.10`、`.2` 固定顺序 |
| BIPAM-16 | P0/S | `releaseExcessIPs` 运行中 false→true→false | Pass | audit75从已验证false基线重启Operator加载true并只在该窗口完成池8→6释放握手，再重启恢复false；最终池补回8、工作负载/路由/健康全恢复，无关闭后继续删除 |
| BIPAM-17 | P0/S | `AllocateStaticIP` 被调用 | Pass | 明确返回 unsupported 和空 IP，不创建随机资源 |
| BIPAM-18 | P0/S | prefix delegation 被误启用 | Pass | `IsPrefixDelegated()` 始终 false，单测锁定能力边界 |
| BIPAM-19 | P1/S | SubENI 同时带 IPv4/IPv6 | Pass | patch0039：双栈 SubENI resync 仅将 IPv4 发布到当前 IPv4 allocation map，IPv6 不泄漏，同时 IPv6 metadata 在 SubENI status 缓存中保留；普通/race 测试通过 |
| BIPAM-20 | P1/S | VPC primary/extended CIDR 为空、非法、重复、重叠 | Pass | patch0033 强制 IPv4 primary；primary 无效时不派生 secondary；过滤空/非法/IPv6/重复及任意方向重叠 extended CIDR，保留稳定输入顺序 |
| BIPAM-21 | P1/C | CiliumNode 被删除后立即重建 | Pass | audit25b 实机先证实删除后 120s 不重建；修复为 Agent 每10s只读核验本地对象并仅在 NotFound 时重建。audit49 canary 在 Agent Pod 不重启下删除对象，1s 产生新 UID，随后 pool/status 恢复8/8，5/5 Node Ready |
| BIPAM-22 | P1/C | 节点名相同但 provider/instance ID 已变化 | Pass | `TestUpdatedNodeTracksInstanceIDChangesAndRejectsEmpty` 在同一 Node 对象从 old→new instance ID 后只发布新实例资源，空 ID fail closed；连续 10 轮通过 |
| BMAP-01 | P0/S | endpoint 为 nil、ID=0、ifindex=0、IPv4 为空 | Pass | patch0028 `TestEndpointValidationBoundaries` 覆盖 nil/typed nil、零 ID/ifindex 与空 IPv4，均 fail closed |
| BMAP-02 | P0/S | endpoint IPv4 非法或为 IPv6 | Pass | patch0028 覆盖非法字符串与 IPv6，Ready/Delete 均拒绝 |
| BMAP-03 | P0/S | SubENI MAC 为空、短、长、multicast、非法字符 | Pass | patch0028 扩展 API 响应校验并覆盖 map 边界：仅接受 6 字节非零单播 MAC |
| BMAP-04 | P0/S | VLAN `-1`、`0`、`1`、`4094`、`4095`、`65536` | Pass | patch0028 覆盖完整边界，仅 1 与 4094 被接受 |
| BMAP-05 | P0/S | endpoint ID `65535`、`65536`、`>65536` | Pass | patch0028 验证 65535 可写入，0/65536 拒绝；大于 65536 同一上界分支拒绝 |
| BMAP-06 | P1/S | 同 source IP 绑定不同 SubENI | Pass | patch0029 验证同 endpoint 重绑时原 VLAN+MAC 清理、新键生效；另一 endpoint 复用 source IP 被拒绝 |
| BMAP-07 | P1/S | 两 endpoint 使用相同 VLAN+MAC | Pass | patch0029 在写入前校验 ingress 键所有者，冲突时回滚 source map |
| BMAP-08 | P1/S | 第一个 map lookup 返回非 ENOENT | Pass | patch0029 注入 lookup failure，错误原样传播且不继续写入 |
| BMAP-09 | P1/S | 第二个 map 更新失败且第一张回滚也失败 | Pass | patch0029 注入双重失败，返回同时包含更新与 rollback 证据的组合错误 |
| BMAP-10 | P1/S | endpoint delete 的 map 删除失败 | Pass | patch0029 验证两张 map 均失败时保持 best-effort 语义、均记录警告且调用不崩溃 |
| BMAP-11 | P1/S | Close 与 Ready/Delete 并发 | Pass | patch0029 为 Close 加互斥和幂等 closed 状态；并发测试在 `-race` 下通过，Close 后写入 fail closed |
| BMAP-12 | P1/S | CiliumNode status 中 0/2 个 SubENI 匹配同一 IP | Pass | patch0030 `TestSubENIInfoRequiresExactlyOneIPMatch`：0 匹配不写 map，2 匹配确定性报错，不再受 map 遍历顺序影响 |
| BMAP-13 | P0/S | gateway IP 有值但 MAC 空，或反之 | Pass | patch0030 `TestSubENIInfoRejectsNarrowingAndGatewayBoundaries` 验证 gateway IP/MAC 必须成对，且存在时 trunk 必填 |
| BMAP-14 | P1/S | trunkInterface 为空/不存在 | Pass | patch0030 已验证 gateway metadata 下空 trunk fail closed；patch0040 验证不存在的 link 在 neighbor 安装前明确返回 `resolve trunk interface`，普通/race 测试通过 |
| BMAP-15 | P1/C | 已有同 gateway IP、不同 MAC 的 permanent neighbor | Pass | audit60 在 dummy trunk 预置同 gateway、不同 MAC 的 permanent neighbor；Agent fail closed、原 neighbor 未变，且 neighbor 失败时不写 BPF map/缓存；privileged100轮及 race20轮通过 |
| BMAP-16 | P1/R | 两个子网 gateway IP 相同但 VLAN/MAC 不同 | Pass | audit60 验证同一 trunk 上同 gateway/不同 MAC 明确拒绝且不污染首项；不同 trunk 上同 gateway/不同 MAC 分别安装并保持正确，满足“不支持时阻断配置”；privileged100轮及 race20轮通过 |
| BVLAN-01 | P0/S | Ethernet header 不完整 | Pass | audit58 BPF `truncated_headers_are_rejected` 覆盖 ETH_HLEN-1/ETH_HLEN 边界，源码审核确认读 ethhdr 前 fail closed；对象严格编译并内核加载执行20次 |
| BVLAN-02 | P0/S | 802.1Q/802.1ad header 只有部分字节 | Pass | audit58 BPF 覆盖 ETH_HLEN+VLAN_HLEN-1/完整边界，802.1Q/802.1ad 共用同一严格长度分支，内核 verifier/执行20次通过 |
| BVLAN-03 | P0/S | VLAN TCI 含 PCP/DEI 位 | Pass | `pcp_dei_do_not_pollute_vlan_id` 验证 `0xb123` 仅生成 VLAN ID `0x123`；map key 使用掉码后 ID，BPF 内核执行20次通过 |
| BVLAN-04 | P0/S | 线内 VLAN ID=0/4095 | Pass | `vlan_id_boundaries` 验证仅1..4094有效，0/4095 在 map lookup 前 `DROP_INVALID`；BPF 严格编译/内核执行20次通过 |
| BVLAN-05 | P0/S | 线内 VLAN 与 metadata VLAN ID 相同 | Pass | audit59 `SETUP/CHECK` 构造由内核预解析的线内 802.1Q 帧，再叠加相同 ID metadata；命中 map 后断言 handled、metadata 清除、双 pop 后长度为 ETH+IPv4 且 ethertype=IPv4，内核执行20次通过 |
| BVLAN-06 | P0/S | 线内 VLAN 与 metadata VLAN ID 不同 | Pass | `inline_and_metadata_must_match` 覆盖 PCP/DEI 不影响相同 ID 及 0x123/0x124 不一致；不一致在 map lookup 前 `DROP_INVALID`，内核执行20次通过 |
| BVLAN-07 | P0/S | 线内未知 VLAN+MAC 且无 metadata | Pass | packet-level `huaweicloud_unknown_inline_vlan` 构造 802.1ad+IPv4 未知键，直接调用 `hwc_from_netdev` 断言 `DROP_INVALID` 且 handled=false；内核执行20次通过 |
| BVLAN-08 | P0/S | map miss 后 metadata VLAN | Pass | `inline_map_miss_is_fail_closed` 明确验证 metadata-only miss 返回 `CTX_ACT_OK` 交给通用 VLAN 逻辑，而 inline miss 为 `DROP_INVALID`；内核执行20次通过 |
| BVLAN-09 | P1/S | 内层非 IPv4（ARP/IPv6/LLDP） | Pass | audit59 直接 packet tests 覆盖 ARP/IPv6/LLDP：线内 VLAN fail closed，metadata-only 返回通用 VLAN 路径且可清除 metadata；内核执行20次通过 |
| BVLAN-10 | P1/S | 三层或更多 VLAN/QinQ | Pass | audit59 直接构造 QinQ 与三层 VLAN packet，均在 map lookup 前 `DROP_INVALID` 且 handled=false；内核执行20次通过 |
| BROUTE-01 | P0/S | gateway 为 IPv6、空、非法字符串 | Pass | patch0031 `TestHuaweiCloudRoutingInfoBoundaries` 强制 IPv4 gateway，覆盖空、IPv6 与既有非法字符串路径 |
| BROUTE-02 | P0/S | CIDR nil/空，masquerade true/false 矩阵 | Pass | patch0031 验证 masquerade=true 拒绝 nil/空，false 接受 nil；既有表驱动测试覆盖空 slice |
| BROUTE-03 | P0/S | CIDR IPv6、非法、重复、重叠 | Pass | patch0031 强制 IPv4 CIDR，并对 HuaweiCloud 重复/任意方向包含的重叠网段 fail closed |
| BROUTE-04 | P0/S | MAC 为空/非法/multicast | Pass | patch0031 覆盖空/非法/零/组播 MAC；HuaweiCloud 仅接受 6 字节非零单播地址 |
| BROUTE-05 | P0/S | MTU 为 0、负数、与 trunk 当前 MTU 不同 | Pass | patch0031 拒绝非正 MTU；privileged netns 测试验证当前 1500 与请求 1400 不同时正确调谐至 1400 |
| BROUTE-06 | P0/S | 同机已有表 10001～14094 的非 Cilium 路由 | Pass | patch0032 在任何 rule/route 变更前审计专用表；privileged netns 注入外部路由后 Configure fail closed 且原路由保持唯一、未被覆盖 |
| BROUTE-07 | P0/S | VLAN ID 在不同 trunk 上重复 | Pass | patch0032 以现有 gateway/ifindex 校验表所有权；两个 trunk 复用 VLAN 时第二次配置被拒绝，第一条默认路由保持 |
| BROUTE-08 | P0/S | 新 rule 成功、nexthop route 失败 | Pass | 注入首个 nexthop `RouteReplace` 失败，验证 ingress/egress rule 与专用表 route 全部回滚为空；privileged 100 轮及 race 10 轮通过 |
| BROUTE-09 | P0/S | nexthop 成功、default route 失败 | Pass | 注入第二个 default `RouteReplace` 失败，验证已装 nexthop 与两类 rule 逆序清理；privileged 100 轮及 race 10 轮通过 |
| BROUTE-10 | P0/S | 新表完整但 stale rule 删除失败 | Pass | 注入第二条 stale rule 删除失败，验证已删 stale rule 恢复且新 rule/route 全部回滚；privileged 100 轮及 race 10 轮通过 |
| BROUTE-11 | P1/S | stale rule 有 mark/mask/to 字段 | Pass | privileged netns 创建带 mark=0x123/mask=0xfff/to CIDR 的 stale rule，Configure 精确删除且保留正确新路由；100 轮及 race 10 轮通过 |
| BROUTE-12 | P1/S | 同源同优先级存在多个规则 | Pass | 同源同旧优先级注入 table 401/402 两条 rule，成功配置后两条均清理且新 rule 可删除；100 轮及 race 10 轮通过 |
| BROUTE-13 | P1/R | Pod 删除后 route table 保留、VLAN 后续复用新 gateway | Pass | 修复无活跃 rule 时对完整旧 default+/32 nexthop 对的事务化回收；新 gateway 替换成功且旧 nexthop 消失，活跃/外部表仍 fail closed |
| BROUTE-14 | P1/R | host=true 与普通 endpoint | Pass | 同一 netns 同表配置 host 与普通 endpoint；host 不生成 `to host/32 lookup main`，普通 endpoint 精确生成一条；100 轮及 race 10 轮通过 |
| BSEC-01 | P0/S | `existingSecret=""` 与仅空格 | Pass | patch0041：值先 trim，再执行非空校验；远端 Helm 3.14.4 验证空串/3 个空格均 template 失败，合法值双 secretKeyRef 一致渲染 |
| BSEC-02 | P0/R | Secret 键存在但值为空 | Pass | 实机隔离 Pod 确认 Kubernetes 会把存在但空的 AK/SK 注入为空字符串；patch0042 使 Operator API client 对 AK/SK/project 空串或纯空白立即 fail closed；普通/race 测试通过，隔离 namespace 已清理 |
| BSEC-03 | P1/R | Secret 类型 Opaque/非 Opaque | Pass | 五节点集群隔离 namespace：Opaque 与 `example.com/hwc-test` 自定义类型 Secret 均通过 secretKeyRef 注入 dummy AK/SK，两个校验 Pod 均 Succeeded |
| BSEC-04 | P1/R | Secret 为 immutable | Pass | immutable=true Opaque Secret 可正常通过 secretKeyRef 注入并使校验 Pod Succeeded；随后替换 AK 被 API server 明确拒绝；隔离 namespace 已清理 |
| BSEC-05 | P0/C | Operator 运行中删除 Secret | Pass | 五节点集群隔离运行态等价测试：删除 Secret 后已注入环境变量的现有 Pod 保持 Running；同 spec 新 Pod 因 Secret 缺失进入 CreateContainerConfigError。namespace 完整清理，5/5 Node Ready |
| BSEC-06 | P1/C | Secret 更新但不重启 Operator | Pass | 五节点隔离运行态测试：Secret old→new 后现有 Pod 环境仍为 old（不热更新）；新建 Pod 读取 new。行为确定，说明凭据轮换必须触发 Operator rollout；namespace 已清理 |
| BSEC-07 | P1/S | Secret 名含 DNS 非法字符/超长 | Pass | patch0041：按 DNS-1123 subdomain 总长253/单 label63 校验；合法 63/253 接受，大小写+下划线、首尾连字符、非法分段、label64、总长254 全部拒绝；lint 通过 |
| BSEC-08 | P1/R | Helm release 与外部 Secret 同名资源冲突 | Pass | 五节点控制面隔离 namespace 预建同名外部 Secret；单 patch Chart 渲染不生成该凭据 Secret，只生成 AK/SK 两个 secretKeyRef；渲染前后 Secret UID/resourceVersion/data 完全不变，namespace 清理后 5/5 Node Ready |
| BRACE-01 | P0/S | Resync 与 CreateInterface 并发 | Pass | 修复 InstancesManager：SubENI 创建后的本地 inventory 更新与全量 Resync 通过 resyncLock 串行化，避免旧快照覆盖新创建项；定向阻塞测试、10 轮普通/race 及干净单 patch 重放测试通过 |
| BRACE-02 | P0/S | Resync 与 ReleaseIPs 并发 | Pass | Release 成功后同步删除 manager inventory，并与全量 Resync 通过 resyncLock 串行化，避免删除前旧快照重新发布已释放项；定向阻塞测试、10 轮普通/race 及干净单 patch 重放测试通过 |
| BRACE-03 | P1/S | UpdatedNode 与 getLimits/Create 并发 | Pass | 修复 CreateInterface 在一次锁内快照 CiliumNode+instance ID，并以该 revision 贯穿 limits、云请求和 inventory 归属；阻塞云创建期间切换 old→new 的确定性测试证明请求/归属不混代；100 轮普通、50 轮 race 通过 |
| BRACE-04 | P1/S | 两个调谐同时为同一节点扩容 | Pass | 新增节点级 createLock，并在锁内按实时 subENI 数重新裁剪可创建量；两个并发调谐持同一 stale allocation 时实例上限1仅创建1个。100轮普通、50轮race及干净单patch全套受影响测试通过 |
| BRACE-05 | P1/S | endpoint Ready 与 Delete 乱序 | Pass | 修复 SubENI map delete 为先核验 src/VLAN 两图完整 owner；旧绑定 Delete 晚于新 Ready 时不再删除新绑定。乱序定向测试、10 轮普通/race 及干净重放通过 |
| BRACE-06 | P1/S | endpoint Restore 与新 Create 同 IP | Pass | 定向状态机测试：旧 Restore 持有 IP 时新 endpoint owner fail closed 且旧图不变；旧 owner 删除后新 Create 才能接管，两图 owner 一致；普通/race 及干净重放通过 |
| BRACE-07 | P1/S | Operator leader 切换时 API 请求在途 | Pending | 待执行 |
| BRACE-08 | P1/C | Pod delete、Agent 重启、Operator 回收同时发生 | Pending | 待执行 |
| BRACE-09 | P1/S | 配置从 subnet IDs 切到 tags 的调谐边界 | Pass | 同一 Node 首次以显式 subnet-old 创建，UpdatedNode 后清空 IDs 并切到 role=new 标签，下一次创建精确选择 subnet-new；无旧配置残留。100轮普通、50轮race及单patch干净重放复测通过 |
| BRACE-10 | P1/S | 配置从 SG A 切到 SG B | Pass | 与 subnet transition 同步验证：首次云请求仅含 sg-a，UpdatedNode 后下一请求仅含 sg-b；记录型 fake API 精确断言请求序列。100轮普通、50轮race及干净重放通过 |
| BRACE-11 | P1/S | context cancel 发生在 limiter 等待后、API 调用前 | Pass | patch0043：limiter 改为单次 reservation、可取消 timer，并返回 context error；所有 HuaweiCloud API 在限流后检查错误。20ms deadline 测试确认 HTTP 请求数为0；10轮普通及 race 测试通过 |
| BRACE-12 | P1/S | 24 小时并发 churn + resync | Pending | 待执行 |
