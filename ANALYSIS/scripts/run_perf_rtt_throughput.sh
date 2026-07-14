#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NS=${NS:-cilium-matrix}
BYTES_MB=${BYTES_MB:-256}
BYTES=$((BYTES_MB * 1024 * 1024))
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP")

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

throughput() {
  local label=$1 source=$2 destination=$3 destination_ip=$4 port=$5
  # BusyBox nc has no -z and its -k mode only works with -e. Accept exactly
  # two connections: one readiness probe and one measured transfer.
  "${SSH[@]}" "kubectl --kubeconfig=/etc/kubernetes/admin.conf -n $NS exec $destination -- sh -c 'timeout 120 sh -c \"for attempt in 1 2; do nc -l -p $port >/dev/null || exit \\\$?; done\"'" &
  local listener=$!
  local ready=false
  for _ in $(seq 1 20); do
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
    "start=\$(cut -d' ' -f1 /proc/uptime); dd if=/dev/zero bs=1048576 count=$BYTES_MB status=none | nc -w 2 $destination_ip $port; rc=\$?; end=\$(cut -d' ' -f1 /proc/uptime); [ \$rc -eq 0 ] || exit \$rc; awk -v start=\$start -v end=\$end 'BEGIN { printf \"%.0f\\n\", (end-start)*1000 }'"); then
    kill "$listener" 2>/dev/null || true
    wait "$listener" 2>/dev/null || true
    return 1
  fi
  wait "$listener"
  [[ "$elapsed_ms" =~ ^[0-9]+$ && "$elapsed_ms" -gt 0 ]]
  local mbps
  mbps=$(awk -v bytes="$BYTES" -v ms="$elapsed_ms" 'BEGIN { printf "%.2f", bytes * 8 / (ms * 1000) }')
  echo "$label run_port=$port bytes=$BYTES elapsed_ms=$elapsed_ms throughput_mbps=$mbps"
}

read -r same_source _ < <(pod_on_node a ecs-4b3b-6555-0001)
read -r same_destination same_ip < <(pod_on_node b ecs-4b3b-6555-0001)
read -r cross_destination cross_ip < <(pod_on_node a ecs-4b3b-6555-0002)

echo "same_node source=$same_source destination=$same_destination ip=$same_ip"
for run in 1 2 3; do
  echo "same_node ping_run=$run"
  k exec "$same_source" -- ping -c 100 -i 0.05 -W 2 "$same_ip" | tail -2
done
echo "cross_node source=$same_source destination=$cross_destination ip=$cross_ip"
for run in 1 2 3; do
  echo "cross_node ping_run=$run"
  k exec "$same_source" -- ping -c 100 -i 0.05 -W 2 "$cross_ip" | tail -2
done

for run in 1 2 3; do
  throughput same_node "$same_source" "$same_destination" "$same_ip" "$((19000 + run))"
  throughput cross_node "$same_source" "$cross_destination" "$cross_ip" "$((19100 + run))"
done

echo PERF_RTT_THROUGHPUT_PASS
