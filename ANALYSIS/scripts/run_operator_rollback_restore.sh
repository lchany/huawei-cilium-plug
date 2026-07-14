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
NS=${NS:-cilium-matrix}
OLD_IMAGE=${OLD_IMAGE:-localhost/huaweicloud/operator-huaweicloud:v1.12.19-audit20}
NEW_IMAGE=${NEW_IMAGE:-localhost/huaweicloud/operator-huaweicloud:v1.12.19-audit76}
OUT=${1:-/tmp/operator-rollback-restore.out}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "root@$CP")

exec > >(tee "$OUT") 2>&1

kube() {
  local remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
  "${SSH[@]}" "$remote"
}

set_operator_image() {
  local image=$1 remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system \
    set image deployment/cilium-operator "cilium-operator=$image"
  "${SSH[@]}" "flock -w 30 /tmp/huaweicloud-customer25.lock $remote" >/dev/null
  kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
}

operator_image() {
  kube -n kube-system get deployment cilium-operator \
    -o 'jsonpath={.spec.template.spec.containers[0].image}'
}

pool_state() {
  kube get ciliumnodes -o json | jq -Sc \
    '[.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}] | sort_by(.name)'
}

verify_operator() {
  local expected=$1 rows
  [[ $(operator_image) == "$expected" ]]
  rows=$(kube -n kube-system get pods -l io.cilium/app=operator \
    -o 'jsonpath={range .items[*]}{.status.containerStatuses[0].ready}{" "}{.status.containerStatuses[0].restartCount}{" "}{.spec.containers[0].image}{"\n"}{end}')
  [[ $(wc -l <<<"$rows") -eq 1 ]]
  [[ $rows == "true 0 $expected" ]]
  [[ $(kube -n kube-system logs deployment/cilium-operator --since=10m 2>&1 \
    | grep -Eic 'panic|fatal|level=(error|fatal)|reconcil.*fail' || true) -eq 0 ]]
  printf 'operator=%s ready=true restarts=0 severe=0\n' "$expected"
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

restore_new() {
  local status=$?
  trap - EXIT INT TERM
  if [[ $(operator_image 2>/dev/null || true) != "$NEW_IMAGE" ]]; then
    set +e
    set_operator_image "$NEW_IMAGE"
    verify_operator "$NEW_IMAGE"
  fi
  exit "$status"
}
trap restore_new EXIT INT TERM

[[ $(operator_image) == "$NEW_IMAGE" ]]
[[ $(kube -n kube-system get configmap cilium-config \
  -o 'jsonpath={.data.huawei-cloud-release-excess-ips}') == false ]]
before=$(pool_state)
printf 'pool-before-sha256=%s\n' "$(sha256sum <<<"$before" | awk '{print $1}')"

set_operator_image "$OLD_IMAGE"
verify_operator "$OLD_IMAGE"
mesh
sleep 30
[[ $(pool_state) == "$before" ]]
echo 'old-image-pool=unchanged'

set_operator_image "$NEW_IMAGE"
verify_operator "$NEW_IMAGE"
mesh
sleep 30
[[ $(pool_state) == "$before" ]]
echo 'restored-image-pool=unchanged'

trap - EXIT INT TERM
echo 'OPERATOR_ROLLBACK_RESTORE_PASS'
