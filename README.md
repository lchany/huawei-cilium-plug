# HuaweiCloud Cilium v1.12.19 Patch 归档

这个分支保存 HuaweiCloud SubENI 对 Cilium `v1.12.19` 的适配 patch。它不包含
Cilium 源码。构建时先准备干净的 upstream Cilium 源码，再按 `series` 应用 patch。

patch 应用后会修改 Cilium 源码，这是预期行为。这里所说的解耦，是把 upstream 基线
和 HuaweiCloud 改动分开管理，方式与 Terway 的 Cilium patch 管理相同。

## 固定基线

- upstream tag：`v1.12.19`
- upstream commit：`a1d7fbd43b563c809330b1c3e28165a3e7ff43aa`
- 已验证适配提交：`ea640a4709d2f1959ff97dc53d91a8eda20e960a`

`apply.sh` 默认检查完整基线 commit，避免把 patch 应用到其他 Cilium 版本。

## 分支内容

```text
.
├── 0001-huaweicloud-control-plane.patch
├── 0002-huaweicloud-datapath-runtime.patch
├── 0003-huaweicloud-generated-tests-dependencies.patch
├── 0004-images-fix-operator-runtime-command-expansion.patch
├── 0005-images-retain-variant-operator-binary-for-Helm-comma.patch
├── series
├── apply.sh
├── build-local.sh
├── INSTALL-DEPLOY.md
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

## 管理流程

```mermaid
flowchart LR
    base["upstream Cilium v1.12.19"]
    patches["按 series 应用 5 个 patch"]
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

完整步骤见 [INSTALL-DEPLOY.md](INSTALL-DEPLOY.md)。

## 更新 patch

不要直接手改 patch 文件。先在独立开发分支修改和测试源码，再按控制面、数据面、
依赖/生成物/测试和独立修复等职责重新生成 patch。每次更新后都要在干净基线上运行
`apply.sh`，并比较重放结果和已验证源码树。
