# HuaweiCloud Cilium v1.12.19 Patch

本仓库保存 HuaweiCloud SubENI 对 Cilium `v1.12.19` 的适配 patch，不包含完整的
Cilium 源码。使用时先检出固定的 upstream commit，再按 `series` 顺序应用全部 patch。

## 基线与交付结构

| 项目 | 值 |
| --- | --- |
| upstream tag | `v1.12.19` |
| upstream commit | `a1d7fbd43b563c809330b1c3e28165a3e7ff43aa` |
| patch 数量 | 15 |
| 功能 patch | `0001`～`0014` |
| 测试阶段修复 patch | `0015-fix-huaweicloud-consolidate-validation-bug-fixes.patch` |

前 14 个 patch 保留功能演进和模块边界；后续测试发现的缺陷及相应回归测试统一放在
`0015`。不要把这 15 个文件重新压成单一 patch。

## 快速开始

```bash
export WORKDIR=/mnt/cilium-v1.12.19-huaweicloud
mkdir -p "$WORKDIR"
cd "$WORKDIR"

git clone --branch patch-archive/huaweicloud-v1.12.19 \
  https://github.com/lchany/huawei-cilium-v1.19.1.git \
  huawei-cilium-patches

git clone --branch v1.12.19 --depth 1 \
  https://github.com/cilium/cilium.git cilium

cd cilium
test "$(git rev-parse HEAD)" = \
  a1d7fbd43b563c809330b1c3e28165a3e7ff43aa
"$WORKDIR/huawei-cilium-patches/apply.sh"
```

应用成功后应新增 15 个提交，工作区保持干净：

```bash
test "$(git rev-list --count a1d7fbd43b563c809330b1c3e28165a3e7ff43aa..HEAD)" -eq 15
git status --short
```

`apply.sh` 会检查目标仓库、工作区和固定基线。基线不匹配或工作区有未提交修改时，
脚本会在应用 patch 前退出。

## 功能范围

| Patch | 内容 |
| --- | --- |
| `0001` | HuaweiCloud API、metadata、SubENI IPAM、Operator、CiliumNode 和 Helm 接入 |
| `0002` | CNI、Daemon、HuaweiCloud BPF map 和 VLAN 数据面接线 |
| `0003` | Go SDK、vendor、生成文件、测试和构建依赖 |
| `0004`～`0005` | 修复 Operator 默认命令，同时保留 Helm 使用的云厂商 variant 二进制 |
| `0006` | 支持按标签选择 SubENI 子网，保留显式 subnet ID 的高优先级 |
| `0007` | 每个 SubENI 使用 `10000 + VLAN ID` 的独立策略路由表 |
| `0008` | 处理线内 802.1Q/802.1ad、skb VLAN metadata 及双表示入口流量 |
| `0009` | Operator 从预创建的外部 Secret 读取 AK/SK，Chart 不再生成凭据 Secret |
| `0010` | 同步子网真实可用地址数并按容量选择候选子网 |
| `0011`～`0014` | CNI `min-allocate`、NodePort probe、endpoint route 源地址和本地 Service 源地址语义 |
| `0015` | 后续缺陷修复、边界测试、并发测试和回归测试 |

HuaweiCloud 数据面只在配置的 trunk 网卡上处理 SubENI VLAN。报文回到 Cilium 原生
datapath 后，连接跟踪、Service 和 NetworkPolicy 仍由 Cilium 负责。

## 仓库内容

```text
.
├── 0001-*.patch … 0014-*.patch  # 功能 patch
├── 0015-*.patch           # 合并后的缺陷修复和回归测试
├── series                 # patch 应用顺序
├── apply.sh               # 基线检查和 patch 重放
├── build-local.sh         # 测试、镜像构建和离线导出
├── huaweicloud-values.example.yaml
├── INSTALL-DEPLOY.md
└── TEST-CASES.md
```

## 使用前须知

- 构建目录和 Docker data-root 必须位于同一块非系统盘。`build-local.sh` 不满足此条件
  时会退出。
- 构建脚本会清理旧 Go 缓存、临时文件、镜像导出和 BuildKit 缓存；不要把需要保留的
  文件放进这些目录。
- HuaweiCloud 凭据只能保存在预创建的 Kubernetes Secret 中。不要把 AK/SK 写入
  values、命令行、日志或 Git。
- `operator.image.repository` 填写不带 `-huaweicloud` 的基础仓库名；Chart 会自动追加
  云厂商后缀。
- 本适配以 IPv4 SubENI 为目标。HuaweiCloud IPAM 模式不能同时启用 IPv6。
- 高风险和故障注入用例必须使用隔离的测试资源，并准备恢复方案。

## 文档

- [安装与部署](INSTALL-DEPLOY.md)：前置条件、构建、镜像分发、Helm 安装、验收、升级和回滚。
- [完整测试用例](TEST-CASES.md)：451 项脱敏测试内容和预期结果，不包含现场执行信息。
- [示例 values](huaweicloud-values.example.yaml)：不含凭据，可复制后填写环境参数。

## 修改 patch

不要直接编辑 `.patch` 文件。正确流程是：

1. 在独立的 Cilium 源码工作树修改代码并运行相关测试。
2. 保留 `0001`～`0014` 的功能边界；测试阶段发现的修复更新到 `0015`。
3. 重新生成 patch 后，在固定 upstream commit 上运行 `apply.sh`。
4. 比较重放后的 Git tree 与已验证源码树，并重新执行受影响测试。

完整构建和部署步骤见 [INSTALL-DEPLOY.md](INSTALL-DEPLOY.md)。
