# HuaweiCloud Cilium v1.12.19 边界场景覆盖审核

## 1. 审核结论

审核基线为 patch 归档提交 `ea34077`、upstream Cilium v1.12.19 提交
`a1d7fbd43b563c809330b1c3e28165a3e7ff43aa` 和 `series` 中 14 个 patch。

原有 287 个场景对功能主路径、常见异常、五节点网络矩阵、`0007` 路由隔离、`0008` VLAN
表示、`0009` 外部 Secret 和 `0010` 子网真实容量已纳入审核，但按源码条件分支反查后，
边界覆盖仍不完整。主要缺口
集中在：空/部分 API 成功响应、分页无进展、metadata 多网卡顺序、辅助 CIDR 网关选择、显式
子网归属、SG fallback、动态 limit、回收竞态、整数截断、未知 VLAN fail-closed、路由部分安装
和配置/调谐并发。

本轮已向 `HUAWEICLOUD_CILIUM_5_NODE_TEST_SCENARIOS.md` 增加 164 个源码派生边界场景，
通用场景共 451 个。客户专项另有 13 个配置修正门禁、25 个数据面验收和 15 个配置/容量
边界场景；整个测试集共 504 个唯一场景或门禁。新增场景只代表“测试要求已补齐”，不代表
对应实现已经通过验证。

## 2. 审核方法

按以下函数和配置路径逐项提取边界：

1. 输入验证：空值、纯空格、非法格式、最小/最大值、溢出和类型截断；
2. 集合边界：nil、空集合、重复项、顺序、同分候选、跨 VPC/AZ；
3. API 边界：空成功响应、部分成功、最终一致性、分页终止、错误码和回滚；
4. 状态边界：CiliumNode/spec/status 缺失、缓存陈旧、Used 状态延迟；
5. 数据面边界：短包、非法 VLAN、双表示不一致、map miss、邻居缺失；
6. 时序边界：Agent/Operator/endpoint 事件乱序、resync/create/release 并发；
7. 生命周期边界：升级、回滚、部分安装、重复删除和外部 Secret 所有权。

## 3. 新增边界场景分布

| 类别 | 新增数量 | 主要覆盖 |
| --- | ---: | --- |
| `BMETA` | 14 | metadata 必填字段、1 MiB、region 推导、多网卡/links 顺序 |
| `BAPI` | 38 | batch、空/部分响应、双 API 分页、容量合并、网关 CIDR、跨 VPC SG |
| `BCFG` | 30 | flavor limit、toAllocate、真实容量、fallback、CNI conflist、SG 优先级 |
| `BIPAM` | 22 | nil 状态、重复 IP、Used 延迟、重复/部分释放、不支持能力 |
| `BMAP` | 16 | VLAN/LXC ID 截断、键冲突、回滚失败、邻居边界 |
| `BVLAN` | 10 | 短包、PCP/DEI、非法 VLAN、双表示不一致、unknown map miss |
| `BROUTE` | 14 | gateway/CIDR/MAC/MTU、表冲突、部分安装、stale rule、VLAN 复用 |
| `BSEC` | 8 | 空白 Secret 名、空值、immutable、删除/轮换、资源所有权 |
| `BRACE` | 12 | resync/create/release、endpoint 乱序、leader 切换、配置切换 |
| 合计 | 164 | 代码边界和并发补充 |

## 4. 需要优先验证的高风险边界

以下是从实现读取出的风险假设，不应在测试前直接定性为缺陷。

### RISK-B01：多网卡 trunk 选择依赖 `links[0]`

- 代码锚点：`metadata.GetTrunkInterfaceID`。
- 观察：实现直接返回 `network_data.links[0].vif_id`，没有使用系统 trunk MAC 与 metadata
  link 做匹配。
- 风险：多网卡或 links 顺序变化时，可能把 SubENI 创建到错误 parent port。
- 覆盖：`BMETA-07`～`BMETA-09`、`PRE-07`、`PRE-08`。
- 门禁：五台机器必须逐台做系统 MAC、metadata port、云控制台三方核对。

### RISK-B02：跨 VPC Security Group 缓存归属

- 代码锚点：`api.GetSecurityGroups`、`eni.FindSecurityGroupByTags`。
- 观察：ListSecurityGroups 请求未显式按 VPC 过滤，返回项的 `VPCID` 使用调用参数填充。
- 风险：若 API 返回跨 VPC SG，标签选择可能把其误认为当前 VPC。
- 覆盖：`BAPI-29`、`IPAM-17`、`BCFG-18`～`BCFG-20`。
- 门禁：使用两个 VPC 的同标签 SG 做 fake API 测试；实机确认最终 SubENI 只引用目标 VPC SG。

### RISK-B03：批创建空/部分成功响应

- 代码锚点：`api.BatchCreateSubNetworkInterfaces`、`eni.Node.CreateInterface`。
- 观察：nil 数组会返回空成功；调用方按实际返回长度报告创建数，未校验是否等于请求数。
- 风险：调谐可能反复补齐或掩盖云端异常响应；多出资源可能成为孤儿。
- 覆盖：`BAPI-07`～`BAPI-09`、`BIPAM-06`、`BIPAM-07`。

### RISK-B04：Wait Active 与最终一致性 404

- 代码锚点：`api.WaitSubENIActive`。
- 观察：任意 Get 错误立即返回，暂时 404 不会继续等待。
- 风险：Create 已成功但 Show 尚不可见时，上层可能重复创建或进入回滚。
- 覆盖：`BAPI-16`～`BAPI-18`、`API-17`。

### RISK-B05：显式 subnet fallback 不在本地复核 VPC/AZ

- 代码锚点：`eni.Node.createSubENIWithFallback`。
- 观察：显式 ID 列表按顺序直接调用创建 API；只有容量不足错误会尝试下一项。
- 风险：跨 VPC/AZ、空 ID、重复 ID 完全依赖云 API 拒绝，且会阻断后续有效候选。
- 覆盖：`BCFG-14`～`BCFG-17`、`IPAM-10`、`IPAM-11`。

### RISK-B06：SG tags 无匹配时继续回退

- 代码锚点：`eni.Node.getSecurityGroupIDs`。
- 观察：配置了 SG tags 但匹配为 0 时，会继续尝试 trunk SG 或历史 SubENI SG。
- 风险：操作者以为标签是强约束，但实际可能扩大为继承安全组。
- 覆盖：`BCFG-19`、`IPAM-17`～`IPAM-19`。
- 门禁：必须先明确产品语义；安全语义未确认前按 fail-closed 验收。

### RISK-B07：private IP 不命中任何 CIDR时回退第一个 IPv4 CIDR

- 代码锚点：`api.selectIPv4SubnetCIDRAndGateway`。
- 观察：没有匹配 private IP 时回退第一个 IPv4 CIDR。
- 风险：多 CIDR 子网或异常 API 数据可能选择错误 gateway，形成单向通或黑洞。
- 覆盖：`BAPI-24`～`BAPI-28`、`ROUTE-17`。

### RISK-B08：Used 状态与 release 的时间窗口

- 代码锚点：`eni.Node.PrepareIPRelease`、`eni.Node.ReleaseIPs`。
- 观察：Prepare 根据 CiliumNode Used 生成 IP 列表，Release 按该列表删除，没有在 Delete 前
  重新读取 Used。
- 风险：Prepare 后 IP 再次被使用时可能发生误删，取决于 generic IPAM 握手机制是否保证互斥。
- 覆盖：`BIPAM-09`、`BIPAM-10`、`BRACE-02`、`BRACE-08`。

### RISK-B09：VLAN ID 和 endpoint ID 类型截断

- 代码锚点：`SubENIMapManager.OnEndpointReady`。
- 观察：VLAN `int32→uint16`、endpoint ID `uint32→uint16` 通过直接转换完成。
- 风险：非法 VLAN 或超范围 endpoint ID 可能与其他 map key/value 冲突。
- 覆盖：`BMAP-04`、`BMAP-05`、`BPF-07`。

### RISK-B10：线内未知 VLAN 在 map miss 后的 fail-closed 语义

- 代码锚点：`hwc_from_netdev`、`bpf_host.c:from_netdev`（`0008`）。
- 观察：线内 VLAN map miss 返回未处理；若同时没有 skb metadata，后续通用逻辑未必看到
  `vlan_present`。
- 风险：未知线内 VLAN 是否可能继续进入后续栈，需要 BPF 单测和实机 drop 证据确认。
- 覆盖：`BVLAN-07`、`VLAN-09`、`VLAN-10`、`TC-NET-11`。

### RISK-B11：策略路由部分安装和表号冲突

- 代码锚点：`RoutingInfo.Configure`、`cleanupStaleHuaweiCloudEgressRules`。
- 观察：rule、nexthop、default route、旧 rule 清理为顺序操作；表范围固定为 10001～14094。
- 风险：中途失败会留下部分状态；节点已有自定义表时可能被 RouteReplace 覆盖。
- 覆盖：`BROUTE-06`、`BROUTE-08`～`BROUTE-13`。

### RISK-B12：CNI conflist malformed 集合

- 代码锚点：`plugins/cilium-cni/types.ReadNetConf`。
- 观察：遍历 plugins 时直接访问 `plugin.Type`；包含 JSON `null` 的插件项需要验证是否 panic。
- 风险：异常 CNI 文件可能导致 Agent 启动/配置读取异常，而不是可诊断失败。
- 覆盖：`BCFG-23`～`BCFG-26`。

### RISK-B13：子网容量双 API 合并和分页无进展

- 代码锚点：`getSubnetAvailableAddresses`、`GetSubnets`、`FindOneSubnet`（`0010`）。
- 观察：容量来自 V1/V2 `/v1/{project_id}/subnets`，标签/VPC/AZ/CIDR 来自 V3
  Virsubnet；容量接口以“返回条数小于 2000”为终止条件并用末项 ID 做 marker。
- 风险：满页重复、重复 ID、两接口数据短暂不一致或容量接口失败会阻断整个 subnet 快照；
  未检测 marker 无进展时可能循环到 context 超时。
- 覆盖：`BAPI-31`～`BAPI-38`、`BCFG-29`、`BCFG-30`、`CUST-EDGE-09`、
  `CUST-EDGE-10`。
- 门禁：先用 fake API 完成页边界、无进展和双 API 不一致测试，再在实机核对云端真实剩余
  地址、CiliumNode/Operator 选择结果和耗尽恢复。

## 5. 审核后的覆盖判定

| 维度 | 当前判定 | 说明 |
| --- | --- | --- |
| 数值上下限 | 已补齐测试要求 | batch 0/1/10/11、VLAN 0/1/4094/4095、limit 和 preAllocate |
| nil/空/非法值 | 已补齐测试要求 | metadata、API 对象、CiliumNode、CNI、Secret、route/map |
| 集合/顺序/重复 | 已补齐测试要求 | subnet/SG、分页、links、map key、release IP |
| 跨 VPC/AZ | 已补齐测试要求 | subnet、SG、metadata、节点身份 |
| API 最终一致性 | 已补齐测试要求 | 空/部分响应、404、marker、Active timeout、回滚 |
| 并发/乱序 | 已补齐测试要求 | resync/create/release、endpoint、leader、配置切换 |
| VLAN/BPF fail-closed | 已补齐测试要求 | 短包、非法/未知 VLAN、双表示不一致、map miss |
| 路由部分状态 | 已补齐测试要求 | rule/route 顺序失败、stale 清理、外部表冲突 |
| 凭据生命周期 | 已补齐测试要求 | 空值、immutable、删除、轮换、Helm 所有权 |
| 实际通过状态 | 尚未验证 | 需执行 S/C/R 场景后逐项更新 Pass/Fail/Block |

## 6. 执行建议

1. 先执行全部 P0/S 边界单测和 fake API 测试，发现实现问题后再上云。
2. 五节点安装前优先完成 `BMETA-08`、`BAPI-29`、`BCFG-15`、`BCFG-19`。
3. 数据面首日完成 `BMAP-04`、`BMAP-05`、`BVLAN-06`、`BVLAN-07` 和 `BROUTE-06`。
4. 回收场景必须在最后执行，并在执行 `BIPAM-09/10/13` 前保存云端和 CiliumNode 快照。
5. 对 RISK-B01～B13 分别建立结果记录；未验证假设不得写成已确认缺陷或已解决经验。
