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
TARGET_NODE=${TARGET_NODE:-ecs-4b3b-6555-0003}
NS=${NS:-cilium-matrix}
REMOTE_PROBE=${REMOTE_PROBE:-/root/audit81-huaweicloud-cloud-crud}
OUT=${1:-/tmp/cloud-crud-recovery.out}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "root@$CP")
operator_scaled=false
node_cordoned=false

exec > >(tee "$OUT") 2>&1

kube() {
  local remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
  "${SSH[@]}" "$remote"
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
total=0
for source_row in "${rows[@]}"; do
  read -r source source_ip <<<"$source_row"
  for destination_row in "${rows[@]}"; do
    read -r _ destination_ip <<<"$destination_row"
    [[ $source_ip == "$destination_ip" ]] && continue
    total=$((total + 1))
    "${K[@]}" exec "$source" -- ping -c 1 -W 2 "$destination_ip" >/dev/null
    ok=$((ok + 1))
  done
done
[[ $total -eq 56 && $ok -eq 56 ]]
printf 'mesh=%d/%d\n' "$ok" "$total"
REMOTE
  "${SSH[@]}" "bash -s -- $(printf '%q' "$NS")" <<<"$remote"
}

scale_operator() {
  local replicas=$1 remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system \
    scale deployment/cilium-operator "--replicas=$replicas"
  "${SSH[@]}" "flock -w 30 /tmp/huaweicloud-customer25.lock $remote" >/dev/null
}

run_probe() {
  local mode=$1 pool_ids=$2 delete_ids=${3:-} remote
  printf -v remote '%q ' "$REMOTE_PROBE"
  "${SSH[@]}" "set -euo pipefail
export KUBECONFIG=/etc/kubernetes/admin.conf
secret=\$(kubectl -n kube-system get deployment cilium-operator -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"CILIUM_HUAWEI_CLOUD_ACCESS_KEY\")].valueFrom.secretKeyRef.name}')
export HUAWEI_CLOUD_ACCESS_KEY=\$(kubectl -n kube-system get secret \"\$secret\" -o jsonpath='{.data.CILIUM_HUAWEI_CLOUD_ACCESS_KEY}' | base64 -d)
export HUAWEI_CLOUD_SECRET_KEY=\$(kubectl -n kube-system get secret \"\$secret\" -o jsonpath='{.data.CILIUM_HUAWEI_CLOUD_SECRET_KEY}' | base64 -d)
export HUAWEI_CLOUD_PROJECT_ID=\$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-project-id}')
export HUAWEI_CLOUD_REGION=\$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-region}')
export HUAWEI_CLOUD_ENDPOINT=\$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-endpoint}')
export AUDIT_MODE='$mode'
export POOL_RESOURCE_IDS='$pool_ids'
export DELETE_RESOURCE_IDS='$delete_ids'
$remote"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if $operator_scaled; then
    scale_operator 1
    kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
  fi
  if $node_cordoned; then
    kube uncordon "$TARGET_NODE" >/dev/null
  fi
  "${SSH[@]}" "rm -f '$REMOTE_PROBE'"
  exit "$status"
}
trap cleanup EXIT INT TERM

[[ -x $REMOTE_PROBE ]] || "${SSH[@]}" "test -x '$REMOTE_PROBE'"
[[ $(kube get node "$TARGET_NODE" -o 'jsonpath={.spec.unschedulable}') != true ]]
[[ $(kube -n kube-system get deployment cilium-operator -o 'jsonpath={.spec.replicas}/{.status.readyReplicas}') == 1/1 ]]
[[ $(kube -n kube-system get configmap cilium-config \
  -o 'jsonpath={.data.huawei-cloud-release-excess-ips}') == false ]]
mesh

kube cordon "$TARGET_NODE" >/dev/null
node_cordoned=true
scale_operator 0
operator_scaled=true
for _ in $(seq 1 60); do
  [[ $(kube -n kube-system get pods -l io.cilium/app=operator --no-headers 2>/dev/null | wc -l) -eq 0 ]] && break
  sleep 2
done
[[ $(kube -n kube-system get pods -l io.cilium/app=operator --no-headers 2>/dev/null | wc -l) -eq 0 ]]

node_json=$(kube get ciliumnode "$TARGET_NODE" -o json)
[[ $(jq '(.spec.ipam.pool // {}) | length' <<<"$node_json") -eq 8 ]]
[[ $(jq '[((.status.ipam.used // {}) | keys[]) as $ip | select(((.spec.ipam.pool // {}) | has($ip)) | not)] | length' <<<"$node_json") -eq 0 ]]
mapfile -t pool_ids_array < <(jq -r '(.spec.ipam.pool // {}) | to_entries | sort_by(.key)[] | .value.resource' <<<"$node_json")
mapfile -t delete_ids_array < <(jq -r '
  (.spec.ipam.pool // {}) as $pool |
  (.status.ipam.used // {}) as $used |
  [$pool | to_entries | sort_by(.key)[] as $entry | select(($used | has($entry.key)) | not) | $entry.value.resource][0:2][]
' <<<"$node_json")
[[ ${#pool_ids_array[@]} -eq 8 && ${#delete_ids_array[@]} -eq 2 ]]
pool_ids=$(IFS=,; echo "${pool_ids_array[*]}")
delete_ids=$(IFS=,; echo "${delete_ids_array[*]}")
printf 'paused-operator pool=8 free-delete-count=2 pool-sha256=%s\n' \
  "$(sha256sum <<<"$pool_ids" | awk '{print $1}')"

run_probe crud "$pool_ids" "$delete_ids"

scale_operator 1
kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
operator_scaled=false
recovered=false
for _ in $(seq 1 90); do
  current=$(kube get ciliumnode "$TARGET_NODE" -o json)
  pool_count=$(jq '(.spec.ipam.pool // {}) | length' <<<"$current")
  used_outside=$(jq '[((.status.ipam.used // {}) | keys[]) as $ip | select(((.spec.ipam.pool // {}) | has($ip)) | not)] | length' <<<"$current")
  deleted_present=$(jq --arg a "${delete_ids_array[0]}" --arg b "${delete_ids_array[1]}" \
    '[.spec.ipam.pool[]?.resource | select(.==$a or .==$b)] | length' <<<"$current")
  operator_error=$(jq -r '.status.ipam["operator-status"].error // ""' <<<"$current")
  if [[ $pool_count -eq 8 && $used_outside -eq 0 && $deleted_present -eq 0 && -z $operator_error ]]; then
    recovered=true
    break
  fi
  sleep 5
done
$recovered

mapfile -t recovered_ids_array < <(jq -r '(.spec.ipam.pool // {}) | to_entries | sort_by(.key)[] | .value.resource' <<<"$current")
[[ ${#recovered_ids_array[@]} -eq 8 ]]
recovered_ids=$(IFS=,; echo "${recovered_ids_array[*]}")
run_probe verify "$recovered_ids"
mesh

kube uncordon "$TARGET_NODE" >/dev/null
node_cordoned=false
[[ $(kube -n kube-system get deployment cilium-operator -o 'jsonpath={.spec.replicas}/{.status.readyReplicas}') == 1/1 ]]
[[ $(kube -n kube-system logs deployment/cilium-operator --since=10m 2>&1 \
  | grep -Eic 'panic|fatal|level=(error|fatal)|reconcil.*fail' || true) -eq 0 ]]
"${SSH[@]}" "rm -f '$REMOTE_PROBE'"
trap - EXIT INT TERM
echo 'CLOUD_CRUD_RECOVERY_PASS'
