#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE=${CUSTOMER25_LOCK_FILE:-/tmp/huaweicloud-customer25.lock}
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "another destructive/customer suite is already running (lock: $LOCK_FILE)" >&2
  exit 75
fi

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
TARGET_HOST=${TARGET_HOST:-139.159.246.181}
TARGET_NODE=${TARGET_NODE:-ecs-4b3b-6555-0003}
NS=${NS:-cilium-matrix}
OUT=${1:-/tmp/legacy-route-migration.out}
SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no)
CP_SSH=(ssh "${SSH_OPTS[@]}" "root@$CP")
NODE_SSH=(ssh "${SSH_OPTS[@]}" "root@$TARGET_HOST")

exec > >(tee "$OUT") 2>&1

kube() {
  local remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
  "${CP_SSH[@]}" "$remote"
}

mesh() {
  local remote
  read -r -d '' remote <<'REMOTE' || true
set -euo pipefail
ns=$1
K=(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n "$ns")
mapfile -t rows < <("${K[@]}" get pods -l app=cilium-matrix \
  -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}' | sort)
[[ ${#rows[@]} -eq 8 ]]
ok=0
for source_row in "${rows[@]}"; do
  read -r source source_ip <<<"$source_row"
  for destination_row in "${rows[@]}"; do
    read -r _ destination_ip <<<"$destination_row"
    [[ $source_ip == "$destination_ip" ]] && continue
    "${K[@]}" exec "$source" -- ping -c 1 -W 2 "$destination_ip" >/dev/null
    ok=$((ok + 1))
  done
done
[[ $ok -eq 56 ]]
printf 'mesh=%d/56\n' "$ok"
REMOTE
  "${CP_SSH[@]}" "bash -s -- $(printf '%q' "$NS")" <<<"$remote"
}

delete_legacy_rule() {
  "${NODE_SSH[@]}" "ip -4 rule del priority 111 from $(printf '%q' "$pod_ip/32") table $(printf '%q' "$legacy_table") 2>/dev/null || true"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  delete_legacy_rule
  kube -n kube-system rollout status daemonset/cilium --timeout=300s >/dev/null
  exit "$status"
}

[[ $(kube get node "$TARGET_NODE" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}') == True ]]
[[ $(kube -n kube-system get daemonset cilium -o 'jsonpath={.status.numberReady}/{.status.desiredNumberScheduled}') == 5/5 ]]
pod_ip=$(kube -n "$NS" get pod -l app=cilium-matrix --field-selector "spec.nodeName=$TARGET_NODE" \
  -o 'jsonpath={.items[0].status.podIP}')
[[ -n $pod_ip ]]
legacy_table=$("${NODE_SSH[@]}" 'cat /sys/class/net/eth0/ifindex')
current_table=$("${NODE_SSH[@]}" "ip -4 rule show | awk -v ip=$(printf '%q' "$pod_ip") '\$1==\"111:\" && \$2==\"from\" && \$3==ip {print \$5}'")
[[ $legacy_table =~ ^[0-9]+$ && $current_table =~ ^1[0-4][0-9]{3}$ && $legacy_table != "$current_table" ]]
before_pool=$(kube get ciliumnodes -o json | jq -Sc '[.items[]|{name:.metadata.name,pool:(.spec.ipam.pool//{})}]|sort_by(.name)')
mesh
trap cleanup EXIT INT TERM

old_agent=$(kube -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=$TARGET_NODE" \
  -o json | jq -er '.items[]|select(.metadata.deletionTimestamp==null and .status.containerStatuses[0].ready==true)|.metadata.name')
"${NODE_SSH[@]}" "bash -s -- $(printf '%q' "$old_agent") $(printf '%q' "$pod_ip") $(printf '%q' "$legacy_table")" <<'REMOTE'
set -euo pipefail
pod=$1
ip=$2
table=$3
runtime=unix:///run/containerd/containerd.sock
container=$(crictl --runtime-endpoint "$runtime" ps --label "io.kubernetes.pod.name=$pod" -q)
[[ -n $container ]]
trap 'systemctl start kubelet' EXIT
systemctl stop kubelet
crictl --runtime-endpoint "$runtime" stop "$container" >/dev/null
ip -4 rule add priority 111 from "$ip/32" table "$table"
[[ $(ip -4 rule show | awk -v ip="$ip" -v t="$table" '$1=="111:" && $2=="from" && $3==ip && $5==t {n++} END{print n+0}') -eq 1 ]]
REMOTE
printf 'legacy-rule-injected-with-agent-stopped source=%s table=%s current-table=%s\n' "$pod_ip" "$legacy_table" "$current_table"

deadline=$((SECONDS + 300))
while (( SECONDS < deadline )); do
  agent_state=$(kube -n kube-system get pod "$old_agent" -o json 2>/dev/null | jq -r \
    'if .status.containerStatuses[0].ready==true and .status.containerStatuses[0].restartCount>=1 then "ready" else "waiting" end' || true)
  [[ $agent_state == ready ]] && break
  sleep 2
done
[[ $agent_state == ready ]]
kube -n kube-system exec "$old_agent" -- cilium status --brief | grep -qx OK

[[ $("${NODE_SSH[@]}" "ip -4 rule show | awk -v ip=$(printf '%q' "$pod_ip") -v t=$(printf '%q' "$legacy_table") '\$1==\"111:\" && \$2==\"from\" && \$3==ip && \$5==t {n++} END{print n+0}'") -eq 0 ]]
[[ $("${NODE_SSH[@]}" "ip -4 rule show | awk -v ip=$(printf '%q' "$pod_ip") -v t=$(printf '%q' "$current_table") '\$1==\"111:\" && \$2==\"from\" && \$3==ip && \$5==t {n++} END{print n+0}'") -eq 1 ]]
[[ $("${NODE_SSH[@]}" "ip -4 route show table $(printf '%q' "$current_table") | wc -l") -eq 2 ]]
[[ $(kube get ciliumnodes -o json | jq -Sc '[.items[]|{name:.metadata.name,pool:(.spec.ipam.pool//{})}]|sort_by(.name)') == "$before_pool" ]]
mesh
echo 'legacy-rule=removed current-route=complete pool=unchanged'

# Replace the deliberately restarted Pod so the retained baseline has zero restarts.
kube -n kube-system delete pod "$old_agent" --wait=false >/dev/null
kube -n kube-system rollout status daemonset/cilium --timeout=300s >/dev/null
new_agent=$(kube -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=$TARGET_NODE" \
  -o json | jq -er '.items[]|select(.metadata.deletionTimestamp==null and .status.containerStatuses[0].ready==true and .status.containerStatuses[0].restartCount==0)|.metadata.name')
[[ $new_agent != "$old_agent" ]]
kube -n kube-system exec "$new_agent" -- cilium status --brief | grep -qx OK
mesh
echo 'fresh-agent=ready restart=0'

trap - EXIT INT TERM
echo 'LEGACY_ROUTE_MIGRATION_PASS'
