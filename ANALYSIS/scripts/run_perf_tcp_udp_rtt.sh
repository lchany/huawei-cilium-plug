#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NS=${NS:-cilium-matrix}
BIN=${BIN:-}
COUNT=${COUNT:-10000}
RUNS=${RUNS:-3}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP")
TMP=$(mktemp -d /tmp/audit70-rtt.XXXXXX)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

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

cleanup() {
  local pod
  for pod in ${PODS_TO_CLEAN:-}; do
    k exec "$pod" -- rm -f /tmp/net-rtt >/dev/null 2>&1 || true
  done
  "${SSH[@]}" rm -f /tmp/net-rtt-audit70 >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

rtt_run() {
  local label=$1 network=$2 source=$3 destination=$4 destination_ip=$5 port=$6 run=$7
  local server_log="$TMP/$label.$network.$run.server"
  "${SSH[@]}" "kubectl --kubeconfig=/etc/kubernetes/admin.conf -n $NS exec $destination -- /tmp/net-rtt -mode server -network $network -addr :$port -count $COUNT -timeout 120s" >"$server_log" &
  local server=$!
  local ready=false
  for _ in $(seq 1 60); do
    if rg -q '^READY ' "$server_log" 2>/dev/null; then
      ready=true
      break
    fi
    if ! kill -0 "$server" 2>/dev/null; then
      wait "$server"
      return 1
    fi
    sleep 0.2
  done
  if [[ $ready != true ]]; then
    kill "$server" 2>/dev/null || true
    wait "$server" 2>/dev/null || true
    return 1
  fi

  local result
  if ! result=$(k exec "$source" -- /tmp/net-rtt -mode client -network "$network" \
    -addr "$destination_ip:$port" -count "$COUNT" -timeout 2s); then
    kill "$server" 2>/dev/null || true
    wait "$server" 2>/dev/null || true
    return 1
  fi
  wait "$server"
  rg -q "^SERVER_PASS network=$network exchanges=$COUNT$" "$server_log"
  echo "$label run=$run destination_ip=$destination_ip $result"
}

if [[ -z "$BIN" ]]; then
  BIN="$TMP/net-rtt-audit70"
  GO_BIN=${GO_BIN:-/usr/lib/golang/bin/go}
  rm -f "$BIN"
  HOME=${HOME:-/root} GOPATH=${GOPATH:-/root/go} GOCACHE=${GOCACHE:-/root/.cache/go-build} \
    GO111MODULE=off CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    "$GO_BIN" build -trimpath -ldflags='-s -w' -o "$BIN" "$SCRIPT_DIR/../tools/net_rtt.go"
fi
[[ -x "$BIN" ]]
read -r same_source _ < <(pod_on_node a ecs-4b3b-6555-0001)
read -r same_destination same_ip < <(pod_on_node b ecs-4b3b-6555-0001)
read -r cross_destination cross_ip < <(pod_on_node a ecs-4b3b-6555-0002)
PODS_TO_CLEAN="$same_source $same_destination $cross_destination"

scp -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
  "$BIN" root@"$CP":/tmp/net-rtt-audit70 >/dev/null
for pod in $PODS_TO_CLEAN; do
  "${SSH[@]}" "kubectl --kubeconfig=/etc/kubernetes/admin.conf -n $NS cp /tmp/net-rtt-audit70 $pod:/tmp/net-rtt && kubectl --kubeconfig=/etc/kubernetes/admin.conf -n $NS exec $pod -- chmod 0755 /tmp/net-rtt" >/dev/null
done

for run in $(seq 1 "$RUNS"); do
  rtt_run same_node tcp "$same_source" "$same_destination" "$same_ip" "$((19400 + run))" "$run"
  rtt_run cross_node tcp "$same_source" "$cross_destination" "$cross_ip" "$((19500 + run))" "$run"
  rtt_run same_node udp "$same_source" "$same_destination" "$same_ip" "$((19600 + run))" "$run"
  rtt_run cross_node udp "$same_source" "$cross_destination" "$cross_ip" "$((19700 + run))" "$run"
done

echo PERF_TCP_UDP_RTT_PASS
