#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
IDLE_SECONDS=${IDLE_SECONDS:-30}
BURST_SECONDS=${BURST_SECONDS:-30}
SETTLE_SECONDS=${SETTLE_SECONDS:-60}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d /tmp/audit70-resources.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

NODES=(
  'node0005 115.175.145.64'
  'node0001 116.63.65.212'
  'node0002 110.41.85.148'
  'node0003 139.159.246.181'
  'node0004 139.159.210.143'
)

snapshot() {
  local label=$1 output=$2
  : >"$output"
  local jobs=()
  for entry in "${NODES[@]}"; do
    read -r node host <<<"$entry"
    ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$host" \
      "crictl stats -o json 2>/dev/null | jq -r --arg node '$node' --arg label '$label' '.stats[] | select((.attributes.metadata.name == \"cilium-agent\" or .attributes.metadata.name == \"cilium-operator\") and .cpu.usageCoreNanoSeconds.value != null) | [\$label,\$node,.attributes.metadata.name,.attributes.labels[\"io.kubernetes.pod.name\"],.cpu.timestamp,.cpu.usageCoreNanoSeconds.value,.memory.workingSetBytes.value,.memory.rssBytes.value] | @tsv'" \
      >"$TMP/$label.$node" &
    jobs+=("$!")
  done
  for job in "${jobs[@]}"; do
    wait "$job"
  done
  cat "$TMP/$label".* | sort -k2,2 -k3,3 >"$output"
  [[ $(wc -l <"$output") -eq 6 ]]
}

report_delta() {
  local phase=$1 before=$2 after=$3
  awk -F '\t' -v phase="$phase" '
    NR==FNR {
      key=$2 SUBSEP $3; ts[key]=$5; cpu[key]=$6; mem[key]=$7; next
    }
    {
      key=$2 SUBSEP $3
      dt=$5-ts[key]; dcpu=$6-cpu[key]
      if (!(key in ts) || dt <= 0 || dcpu < 0) exit 2
      mcpu=dcpu*1000/dt
      printf "phase=%s node=%s container=%s pod=%s cpu_mcores=%.3f working_set_mib=%.2f memory_delta_mib=%.2f rss_mib=%.2f\n", phase,$2,$3,$4,mcpu,$7/1048576,($7-mem[key])/1048576,$8/1048576
    }
  ' "$before" "$after"
}

snapshot idle_start "$TMP/idle_start.tsv"
sleep "$IDLE_SECONDS"
snapshot idle_end "$TMP/idle_end.tsv"
report_delta idle "$TMP/idle_start.tsv" "$TMP/idle_end.tsv"

snapshot burst_start "$TMP/burst_start.tsv"
burst_log="$TMP/burst-mesh.out"
(
  deadline=$((SECONDS + BURST_SECONDS))
  passes=0
  while (( SECONDS < deadline )); do
    ROUNDS=0 "$SCRIPT_DIR/run_matrix_recreate_10.sh" >>"$burst_log"
    passes=$((passes + 1))
  done
  echo "burst_mesh_passes=$passes"
) &
burst_job=$!
sleep "$BURST_SECONDS"
wait "$burst_job"
snapshot burst_end "$TMP/burst_end.tsv"
report_delta burst "$TMP/burst_start.tsv" "$TMP/burst_end.tsv"
[[ $(rg -c 'MATRIX_RECREATE_SUMMARY PASS' "$burst_log") -gt 0 ]]

snapshot settled_start "$TMP/settled_start.tsv"
sleep "$SETTLE_SECONDS"
snapshot settled_end "$TMP/settled_end.tsv"
report_delta settled "$TMP/settled_start.tsv" "$TMP/settled_end.tsv"

echo PERF_COMPONENT_RESOURCES_PASS
