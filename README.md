# HuaweiCloud Cilium v1.12.19 Patch

本仓库保存 HuaweiCloud SubENI 对 Cilium `v1.12.19` 的适配 patch，不包含完整的
Cilium 源码。使用时先检出固定的 upstream commit，再按 `series` 顺序应用全部 patch。

## 基线与交付结构

| 项目 | 值 |
| --- | --- |
| upstream tag | `v1.12.19` |
| upstream commit | `a1d7fbd43b563c809330b1c3e28165a3e7ff43aa` |
| archive tag | `v1.1.2` |
| patch 数量 | 4 |
| 控制面 patch | `0001-huaweicloud-control-plane.patch` |
| 数据面 patch | `0002-huaweicloud-data-plane.patch` |
| 测试 patch | `0003-huaweicloud-tests.patch` |
| 修复 patch | `0004-huaweicloud-fixes.patch` |

前 3 个 patch 分别承载云 API、IPAM 和 Operator 等控制面实现，BPF、路由和 Endpoint
运行时数据面实现，以及配套测试。`0004` 预留给后续 bug 修复和需求优化。按 `series`
顺序应用，不能跳过或交换顺序。

## 更新记录

- 2026-08-07：清理 `0001-huaweicloud-control-plane.patch` 中的行尾空格、空白行
  Tab、混合缩进和 hunk 末尾多余空行；使用 `git apply --check
  --whitespace=error-all` 验证 patch 不再产生 whitespace 告警。
- 2026-08-04：HuaweiCloud gateway 静态邻居增加 `NUD_PERMANENT +
  NTF_EXT_LEARNED`，并通过当前 endpoint 的精确 `(trunk, IP, MAC)` 归属集合与
  Cilium 通用邻居清理隔离；补齐旧表项修复、stale 表项回收和启动顺序保护；archive
  tag 升级到 `v1.1.2`。
- 2026-07-29：新增 `0004-huaweicloud-fixes.patch`，把 HuaweiCloud Sub-ENI 启动阶段
  的 gateway 查询改成批量查询；`series` 扩展为 4 个 patch；archive tag 升级到
  `v1.1.1`。

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

应用成功后应新增 4 个提交，工作区保持干净：

```bash
test "$(git rev-list --count a1d7fbd43b563c809330b1c3e28165a3e7ff43aa..HEAD)" -eq 4
git status --short
```

`apply.sh` 会检查目标仓库、工作区和固定基线。基线不匹配或工作区有未提交修改时，
脚本会在应用 patch 前退出。

## 功能范围

| Patch | 内容 |
| --- | --- |
| `0001` 控制面 | HuaweiCloud SDK/vendor、API、metadata、SubENI IPAM、Operator、CiliumNode、配置、Helm、镜像和构建接入 |
| `0002` 数据面 | Daemon/CNI 运行时接线、BPF VLAN 处理、SubENI map、Endpoint 生命周期、策略路由、iptables 和 Service 源地址语义 |
| `0003` 测试 | 控制面、数据面、边界、并发、故障注入、BPF、特权路由和实机辅助测试 |
| `0004` 修复 | 批量 gateway 查询、静态邻居归属和 Agent 启动清理保护，以及对应回归测试 |

HuaweiCloud 数据面只在配置的 trunk 网卡上处理 SubENI VLAN。报文回到 Cilium 原生
datapath 后，连接跟踪、Service 和 NetworkPolicy 仍由 Cilium 负责。

## 仓库内容

```text
.
├── 0001-huaweicloud-control-plane.patch
├── 0002-huaweicloud-data-plane.patch
├── 0003-huaweicloud-tests.patch
├── 0004-huaweicloud-fixes.patch
├── series                 # patch 应用顺序
├── apply.sh               # 基线检查和 patch 重放
├── build-local.sh         # 测试、镜像构建和离线导出
├── huaweicloud-values.example.yaml
├── INSTALL-DEPLOY.md
├── TEST-CASES.md
└── 测试过程问题整理.md
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
- [完整测试用例](TEST-CASES.md)：460 项脱敏测试内容和预期结果，不包含现场执行信息。
- [测试过程问题整理](测试过程问题整理.md)：按问题场景、根因和解决方案整理测试中发现的问题。
- [示例 values](huaweicloud-values.example.yaml)：不含凭据，可复制后填写环境参数。

## 修改 patch

不要直接编辑 `.patch` 文件。正确流程是：

1. 在独立的 Cilium 源码工作树修改代码并运行相关测试。
2. 按控制面、数据面、测试三个边界修改对应提交，不把生产修复放进测试 patch。
3. 重新生成 patch 后，在固定 upstream commit 上运行 `apply.sh`。
4. 比较重放后的 Git tree 与已验证源码树，并重新执行受影响测试。

完整构建和部署步骤见 [INSTALL-DEPLOY.md](INSTALL-DEPLOY.md)。
