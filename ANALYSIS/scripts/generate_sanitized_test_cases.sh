#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SOURCE=${SOURCE:-$ROOT/ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_TEST_SCENARIOS.md}
OUTPUT=${OUTPUT:-$ROOT/TEST-CASES.md}

[[ -f "$SOURCE" ]] || {
	echo "test-case source not found: $SOURCE" >&2
	exit 1
}

tmp=$(mktemp)
ids="${tmp}.ids"
trap 'rm -f "$tmp" "$ids"' EXIT

awk '
	/^## 5\. 场景目录/ {
		copy = 1
		print "## 4. 功能、部署与实机用例"
		next
	}
	/^## 6\. 源码边界审核补充场景/ {
		print "## 5. 源码与边界用例"
		next
	}
	/^## 7\. 发布门禁/ { exit }
	copy {
		line = $0
		sub(/^### 5\./, "### 4.", line)
		sub(/^### 6\./, "### 5.", line)
		gsub(/\| ID \| P\/类型 \| 场景 \| 预期与证据 \|/,
		     "| ID | 优先级/类型 | 测试内容 | 预期结果 |", line)
		gsub(/\| ID \| P\/类型 \| 边界输入或状态 \| 必须断言 \|/,
		     "| ID | 优先级/类型 | 测试条件或输入 | 预期结果 |", line)
		gsub(/客户环境/, "目标环境", line)
		gsub(/本轮分配/, "当前分配请求", line)
		gsub(/本轮/, "当前操作", line)
		gsub(/\| STAB-01 \| P1\/R \| 24 小时持续探测 \|/, "| STAB-01 | P2/O | 持续探测（可选时长） |", line)
		gsub(/\| STAB-02 \| P1\/R \| 24 小时 Pod churn \|/, "| STAB-02 | P2/O | 持续 Pod churn（可选时长） |", line)
		gsub(/\| STAB-03 \| P2\/R \| 72 小时发布候选 \|/, "| STAB-03 | P2/O | 长期发布候选验证（可选） |", line)
		gsub(/\| BRACE-12 \| P1\/S \| 24 小时并发 churn \+ resync \|/, "| BRACE-12 | P2/O | 持续并发 churn + resync（可选时长） |", line)
		print line
	}
' "$SOURCE" > "$tmp"

sed -i -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}' "$tmp"

awk -F'|' '/^\| [A-Z][A-Z0-9-]*-[0-9]+ / {
	id = $2
	gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
	print id
}' "$tmp" > "$ids"

count=$(wc -l < "$ids")
[[ "$count" -eq 451 ]] || {
	echo "unexpected test-case count: got $count, want 451" >&2
	exit 1
}

duplicates=$(sort "$ids" | uniq -d)
[[ -z "$duplicates" ]] || {
	echo "duplicate test-case IDs:" >&2
	printf '%s\n' "$duplicates" >&2
	exit 1
}

if grep -En '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|/(home|root|tmp)/' "$tmp" >&2; then
	echo "test cases contain a possible private address, resource ID, credential, key, or local path" >&2
	exit 1
fi

if grep -Eni '(password|passwd|token|secret[_ -]?key|access[_ -]?key)[[:space:]]*[:=][[:space:]]*[^<[:space:]]+' "$tmp" >&2; then
	echo "test cases contain a possible credential value" >&2
	exit 1
fi

{
	cat <<'EOF'
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

EOF
	cat "$tmp"
} > "$OUTPUT"

printf 'generated %s (%d cases)\n' "$OUTPUT" "$count"
