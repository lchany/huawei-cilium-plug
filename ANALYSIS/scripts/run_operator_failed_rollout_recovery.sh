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
GOOD_IMAGE=${GOOD_IMAGE:-localhost/huaweicloud/operator-huaweicloud:v1.12.19-audit76}
BAD_IMAGE=${BAD_IMAGE:-localhost/huaweicloud/operator-huaweicloud:v1.12.19-audit76-missing}
OUT=${1:-/tmp/operator-failed-rollout-recovery.out}
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
}

pool_state() {
  kube get ciliumnodes -o json | jq -Sc \
    '[.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}] | sort_by(.name)'
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

restore() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  set_operator_image "$GOOD_IMAGE"
  kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
  kube -n kube-system patch deployment cilium-operator --type=merge \
    -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":1}}}}' >/dev/null
  exit "$status"
}
trap restore EXIT INT TERM

[[ $(kube -n kube-system get deployment cilium-operator \
  -o 'jsonpath={.spec.template.spec.containers[0].image}') == "$GOOD_IMAGE" ]]
[[ $(kube -n kube-system get deployment cilium-operator \
  -o 'jsonpath={.spec.strategy.rollingUpdate.maxSurge}/{.spec.strategy.rollingUpdate.maxUnavailable}') == 1/1 ]]
[[ $(kube -n kube-system get configmap cilium-config \
  -o 'jsonpath={.data.huawei-cloud-release-excess-ips}') == false ]]
before=$(pool_state)
printf 'pool-before-sha256=%s\n' "$(sha256sum <<<"$before" | awk '{print $1}')"

kube -n kube-system patch deployment cilium-operator --type=merge \
  -p '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":0}}}}' >/dev/null
set_operator_image "$BAD_IMAGE"
if kube -n kube-system rollout status deployment/cilium-operator --timeout=45s; then
  echo 'invalid image unexpectedly rolled out' >&2
  exit 1
fi

ready_good=$(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  --arg image "$GOOD_IMAGE" '[.items[] | select(.spec.containers[0].image==$image and .status.containerStatuses[0].ready==true)] | length')
waiting_bad=$(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  --arg image "$BAD_IMAGE" '[.items[] | select(.spec.containers[0].image==$image and (.status.containerStatuses[0].state.waiting.reason=="ErrImagePull" or .status.containerStatuses[0].state.waiting.reason=="ImagePullBackOff"))] | length')
[[ $ready_good -eq 1 && $waiting_bad -eq 1 ]]
printf 'failed-rollout ready-good=%d waiting-bad=%d\n' "$ready_good" "$waiting_bad"
mesh
[[ $(pool_state) == "$before" ]]
echo 'failed-rollout-pool=unchanged'

set_operator_image "$GOOD_IMAGE"
kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
kube -n kube-system patch deployment cilium-operator --type=merge \
  -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":1}}}}' >/dev/null
[[ $(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  --arg image "$GOOD_IMAGE" '[.items[] | select(.spec.containers[0].image==$image and .status.containerStatuses[0].ready==true and .status.containerStatuses[0].restartCount==0)] | length') -eq 1 ]]
[[ $(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  --arg image "$BAD_IMAGE" '[.items[] | select(.spec.containers[0].image==$image)] | length') -eq 0 ]]
[[ $(kube -n kube-system logs deployment/cilium-operator --since=10m 2>&1 \
  | grep -Eic 'panic|fatal|level=(error|fatal)|reconcil.*fail' || true) -eq 0 ]]
mesh
[[ $(pool_state) == "$before" ]]
echo 'recovered-pool=unchanged'

trap - EXIT INT TERM
echo 'OPERATOR_FAILED_ROLLOUT_RECOVERY_PASS'
