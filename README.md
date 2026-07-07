# HuaweiCloud Cilium Patch Series

本分支是 HuaweiCloud/SubENI 对 upstream Cilium `v1.19.1` 的 **patch-only
归档分支**。

它不是 Cilium 源码分支，也不包含完整 Cilium 源码树。分支中只保留
HuaweiCloud 相关改动的 patch series、应用脚本、校验脚本和运行时检查清单。

## 用途

这个分支用于把 HuaweiCloud 对 Cilium 的改动从完整 Cilium fork 中拆出来管理：

- Cilium 主框架源码不作为本分支的交付主体。
- HuaweiCloud 改动以编号 patch 文件归档。
- 需要构建定制版 Cilium 时，将这些 patch 应用到干净的 upstream Cilium
  `v1.19.1` baseline 上。
- 这种方式与 Terway 在 `policy/cilium/*.patch` 中管理 Cilium 修改的思路一致：
  管理方式解耦，但 patch 应用后仍会修改 Cilium 源码。

## Baseline

patch series 目标基线：

- upstream tag: `v1.19.1`
- peeled commit: `d0d0c8792c3420b3a6739fa21e3a182827a0bbc6`

`apply.sh` 默认会校验目标 Cilium 仓库当前 HEAD 是否等于该 commit。

## Patch 列表

patch 顺序由 `series` 文件定义：

```text
0001-huaweicloud-control-plane.patch
0002-huaweicloud-datapath-runtime.patch
0003-huaweicloud-generated-tests-docs.patch
```

分组说明：

- `0001-huaweicloud-control-plane.patch`
  - HuaweiCloud IPAM mode、CRD、云 API、SubENI allocator、node discovery、
    SubENI BPF map manager、operator/Helm/RBAC/build 接线。
- `0002-huaweicloud-datapath-runtime.patch`
  - BPF VLAN datapath、CNI/daemon/datapath runtime wiring、EndpointSlice
    兼容、drop reason 和 monitor API。
- `0003-huaweicloud-generated-tests-docs.patch`
  - `go.mod` / `go.sum`、vendor、generated 文件、CRD yaml、测试和文档。

## 应用方式

准备一个干净的 upstream Cilium 仓库，并切到 baseline commit：

```bash
git clone https://github.com/cilium/cilium.git cilium-v1.19.1
cd cilium-v1.19.1
git checkout d0d0c8792c3420b3a6739fa21e3a182827a0bbc6
```

从目标 Cilium 仓库根目录执行本分支中的 `apply.sh`：

```bash
/path/to/huawei-cilium-v1.19.1/apply.sh
```

脚本会：

- 拒绝在 dirty worktree 上应用 patch。
- 校验目标仓库 HEAD 是否为指定 baseline。
- 按 `series` 顺序先执行 `git apply --check --3way`。
- 再使用 `git am --3way` 应用每个 patch。

如果是在明确 rebase patch series 的场景，可以跳过 baseline commit 校验：

```bash
/path/to/huawei-cilium-v1.19.1/apply.sh --no-base-check
```

该参数只跳过 commit 校验，仍然要求目标 worktree 干净。

## 校验方式

在本 patch-only 分支仓库根目录执行：

```bash
./check.sh
```

`check.sh` 会准备一个干净的临时 Cilium baseline worktree，逐个检查并应用
`series` 中的 patch。

如果本地已有 Cilium baseline clone，可以指定缓存目录：

```bash
CILIUM_BASE_DIR=/path/to/cilium-cache ./check.sh
```

## 运行时检查

patch 应用并部署定制版 Cilium 后，按 `runtime-checklist.md` 做基础验证，包括：

- HuaweiCloud operator 是否正常启动。
- `CiliumNode.spec/status.huawei-cloud` 是否正确写入。
- SubENI 分配和释放是否正常。
- `cilium_hwc_srcip4` / `cilium_hwc_vlan_mac` BPF map 是否写入。
- Pod 访问 Kubernetes API、ClusterIP、DNS、跨节点流量是否正常。

## 注意事项

- 本分支只解决“Cilium 修改管理方式解耦”，不是运行时完全插件化。
- patch 应用后仍会修改 Cilium 源码，包括 Go 代码、BPF 代码、Helm/RBAC、
  generated 文件和 vendor。
- 更新 patch 时应保持 `series` 顺序可应用，并重新运行 `./check.sh`。
