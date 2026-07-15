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
OUT=${1:-/tmp/route-compat-toggle.out}
CONFIG_KEY=egress-multi-home-ip-rule-compat
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

restart_target_agent() {
  local old_agent new_agent
  old_agent=$(kube -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=$TARGET_NODE" \
    -o json | jq -er '.items[]|select(.metadata.deletionTimestamp==null and .status.containerStatuses[0].ready==true)|.metadata.name')
  kube -n kube-system delete pod "$old_agent" --wait=false >/dev/null
  kube -n kube-system rollout status daemonset/cilium --timeout=300s >/dev/null
  new_agent=$(kube -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=$TARGET_NODE" \
    -o json | jq -er '.items[]|select(.metadata.deletionTimestamp==null and .status.containerStatuses[0].ready==true and .status.containerStatuses[0].restartCount==0)|.metadata.name')
  [[ $new_agent != "$old_agent" ]]
  kube -n kube-system exec "$new_agent" -- cilium status --brief | grep -qx OK
  printf 'agent=%s ready=true restart=0\n' "$new_agent"
}

target_agent() {
  kube -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=$TARGET_NODE" \
    -o json | jq -er '.items[]|select(.metadata.deletionTimestamp==null and .status.containerStatuses[0].ready==true)|.metadata.name'
}

wait_config_projection() {
  local expected=$1 deadline pod value
  deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    pod=$(target_agent)
    if [[ $expected == absent ]]; then
      if ! kube -n kube-system exec "$pod" -- test -e "/tmp/cilium/config-map/$CONFIG_KEY" >/dev/null 2>&1; then
        return 0
      fi
    else
      value=$(kube -n kube-system exec "$pod" -- cat "/tmp/cilium/config-map/$CONFIG_KEY" 2>/dev/null || true)
      [[ $value == "$expected" ]] && return 0
    fi
    sleep 2
  done
  echo "timed out waiting for projected config $CONFIG_KEY=$expected" >&2
  return 1
}

set_config() {
  local value=$1 patch
  patch=$(jq -nc --arg key "$CONFIG_KEY" --arg value "$value" '{data:{($key):$value}}')
  kube -n kube-system patch configmap cilium-config --type=merge -p "$patch" >/dev/null
}

restore_config() {
  if [[ $original_present == true ]]; then
    set_config "$original_value"
  else
    kube -n kube-system patch configmap cilium-config --type=json \
      -p "[{\"op\":\"remove\",\"path\":\"/data/$CONFIG_KEY\"}]" >/dev/null 2>&1 || true
  fi
}

verify_priority() {
  local expected=$1 rejected=$2 rows tables pod_ips ip
  rows=$("${NODE_SSH[@]}" "ip -4 rule show | awk -v p=$(printf '%q' "$expected:") '\$1==p {n++} END{print n+0}'")
  [[ $rows -ge 2 ]]
  pod_ips=$(kube -n "$NS" get pods --field-selector "spec.nodeName=$TARGET_NODE" \
    -o 'jsonpath={range .items[*]}{.status.podIP}{"\n"}{end}')
  [[ $(wc -l <<<"$pod_ips") -eq 2 ]]
  while read -r ip; do
    [[ $("${NODE_SSH[@]}" "ip -4 rule show | awk -v p=$(printf '%q' "$expected:") -v ip=$(printf '%q' "$ip") '\$1==p && \$2==\"from\" && \$3==ip {n++} END{print n+0}'") -eq 1 ]]
    [[ $("${NODE_SSH[@]}" "ip -4 rule show | awk -v p=$(printf '%q' "$rejected:") -v ip=$(printf '%q' "$ip") '\$1==p && \$2==\"from\" && \$3==ip {n++} END{print n+0}'") -eq 0 ]]
  done <<<"$pod_ips"
  tables=$("${NODE_SSH[@]}" "ip -4 rule show | awk -v p=$(printf '%q' "$expected:") '\$1==p {print \$5}' | sort -nu")
  while read -r table; do
    [[ $table =~ ^1[0-4][0-9]{3}$ ]]
    [[ $("${NODE_SSH[@]}" "ip -4 route show table $(printf '%q' "$table") | wc -l") -eq 2 ]]
  done <<<"$tables"
  printf 'priority=%s rules=%s active-pods=2 tables=complete active-rejected-priority=%s/0\n' "$expected" "$rows" "$rejected"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  restore_config
  if [[ $original_present == true ]]; then
    wait_config_projection "$original_value"
  else
    wait_config_projection absent
  fi
  restart_target_agent
  exit "$status"
}

configmap=$(kube -n kube-system get configmap cilium-config -o json)
original_present=$(jq -r --arg key "$CONFIG_KEY" '.data|has($key)' <<<"$configmap")
original_value=$(jq -r --arg key "$CONFIG_KEY" '.data[$key] // ""' <<<"$configmap")
[[ $original_present == false || $original_value == false ]]
[[ $(kube -n kube-system get daemonset cilium -o 'jsonpath={.status.numberReady}/{.status.desiredNumberScheduled}') == 5/5 ]]
before_pool=$(kube get ciliumnodes -o json | jq -Sc '[.items[]|{name:.metadata.name,pool:(.spec.ipam.pool//{})}]|sort_by(.name)')
mesh
trap cleanup EXIT INT TERM

set_config true
wait_config_projection true
restart_target_agent
verify_priority 110 111
[[ $(kube get ciliumnodes -o json | jq -Sc '[.items[]|{name:.metadata.name,pool:(.spec.ipam.pool//{})}]|sort_by(.name)') == "$before_pool" ]]
mesh
echo 'compat=true pool=unchanged'

restore_config
if [[ $original_present == true ]]; then
  wait_config_projection "$original_value"
else
  wait_config_projection absent
fi
restart_target_agent
verify_priority 111 110
[[ $(kube get ciliumnodes -o json | jq -Sc '[.items[]|{name:.metadata.name,pool:(.spec.ipam.pool//{})}]|sort_by(.name)') == "$before_pool" ]]
mesh
echo 'compat=restored pool=unchanged'

trap - EXIT INT TERM
echo 'ROUTE_COMPAT_TOGGLE_PASS'
