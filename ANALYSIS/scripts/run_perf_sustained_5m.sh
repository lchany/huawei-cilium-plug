#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NS=${NS:-cilium-matrix}
DURATION=${DURATION:-300}
RUNS=${RUNS:-3}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP")
TMP=$(mktemp -d /tmp/audit70-sustained.XXXXXX)
RESULTS="$TMP/results.tsv"
trap 'rm -rf "$TMP"' EXIT
: >"$RESULTS"

k() {
  local remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf -n "$NS" "$@"
  "${SSH[@]}" "$remote"
}

pod_on_node() {
  local set=$1 node=$2
  k get pod -l "app=cilium-matrix,set=$set" --field-selector "spec.nodeName=$node,status.phase=Running" \
    -o 'jsonpath={.items[0].metadata.name} {.items[0].status.podIP}'
  echo
}

sustained() {
  local label=$1 source=$2 destination=$3 destination_ip=$4 port=$5 run=$6
  local received="$TMP/$label.$run.bytes"
  "${SSH[@]}" "kubectl --kubeconfig=/etc/kubernetes/admin.conf -n $NS exec $destination -- sh -c 'timeout $((DURATION + 90)) sh -c \"nc -l -p $port >/dev/null; nc -l -p $port | wc -c\"'" >"$received" &
  local listener=$!

  local ready=false
  for _ in $(seq 1 30); do
    if k exec "$source" -- sh -c "printf x | nc -w 1 $destination_ip $port" >/dev/null 2>&1; then
      ready=true
      break
    fi
    if ! kill -0 "$listener" 2>/dev/null; then
      wait "$listener"
      return 1
    fi
    sleep 1
  done
  if [[ $ready != true ]]; then
    kill "$listener" 2>/dev/null || true
    wait "$listener" 2>/dev/null || true
    return 1
  fi
  sleep 1

  local elapsed_ms
  if ! elapsed_ms=$(k exec "$source" -- sh -c \
    "pipe_pid=; cleanup() { [ -z \"\$pipe_pid\" ] || kill \"\$pipe_pid\" 2>/dev/null || true; }; trap cleanup EXIT INT TERM; start=\$(cut -d' ' -f1 /proc/uptime); dd if=/dev/zero bs=1048576 status=none 2>/dev/null | nc -w 2 $destination_ip $port 2>/dev/null & pipe_pid=\$!; sleep $DURATION; kill \"\$pipe_pid\"; wait \"\$pipe_pid\" 2>/dev/null || true; pipe_pid=; end=\$(cut -d' ' -f1 /proc/uptime); awk -v start=\$start -v end=\$end 'BEGIN { printf \"%.0f\\n\", (end-start)*1000 }'"); then
    kill "$listener" 2>/dev/null || true
    wait "$listener" 2>/dev/null || true
    return 1
  fi
  wait "$listener"

  local bytes mbps
  bytes=$(tr -cd '0-9\n' <"$received" | tail -1)
  [[ "$elapsed_ms" =~ ^[0-9]+$ && "$elapsed_ms" -ge $((DURATION * 1000 - 2000)) ]]
  [[ "$bytes" =~ ^[0-9]+$ && "$bytes" -gt 0 ]]
  mbps=$(awk -v bytes="$bytes" -v ms="$elapsed_ms" 'BEGIN { printf "%.2f", bytes * 8 / (ms * 1000) }')
  echo "$label $mbps" >>"$RESULTS"
  echo "$label run=$run port=$port duration_target_s=$DURATION elapsed_ms=$elapsed_ms bytes=$bytes throughput_mbps=$mbps"
}

read -r same_source _ < <(pod_on_node a ecs-4b3b-6555-0001)
read -r same_destination same_ip < <(pod_on_node b ecs-4b3b-6555-0001)
read -r cross_destination cross_ip < <(pod_on_node a ecs-4b3b-6555-0002)

for run in $(seq 1 "$RUNS"); do
  sustained same_node "$same_source" "$same_destination" "$same_ip" "$((19200 + run))" "$run"
  sustained cross_node "$same_source" "$cross_destination" "$cross_ip" "$((19300 + run))" "$run"
done

for label in same_node cross_node; do
  awk -v label="$label" '$1 == label { print $2 }' "$RESULTS" | sort -n >"$TMP/$label.sorted"
  awk -v label="$label" '
    { value[NR]=$1; sum+=$1 }
    END {
      median=value[int((NR+1)/2)]
      maxdev=0
      for (i=1; i<=NR; i++) {
        dev=value[i]-median; if (dev<0) dev=-dev
        if (dev>maxdev) maxdev=dev
      }
      printf "%s summary runs=%d min_mbps=%.2f avg_mbps=%.2f median_mbps=%.2f max_mbps=%.2f max_deviation_pct=%.3f\n", label,NR,value[1],sum/NR,median,value[NR],maxdev*100/median
    }
  ' "$TMP/$label.sorted"
done

echo PERF_SUSTAINED_5M_PASS
