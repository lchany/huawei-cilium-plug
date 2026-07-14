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
CUSTOM_SECRET=${CUSTOM_SECRET:-cilium-huaweicloud-audit80-custom}
WRONG_NS_SECRET=${WRONG_NS_SECRET:-cilium-huaweicloud-audit80-wrong-ns}
OUT=${1:-/tmp/operator-secret-reference-recovery.out}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "root@$CP")

exec > >(tee "$OUT") 2>&1

kube() {
  local remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
  "${SSH[@]}" "$remote"
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

set_secret_ref() {
  local name=$1 patch
  patch=$(jq -nc --arg name "$name" --argjson ak "$ak_index" --argjson sk "$sk_index" '
    [
      {op:"replace",path:("/spec/template/spec/containers/0/env/"+($ak|tostring)+"/valueFrom/secretKeyRef/name"),value:$name},
      {op:"replace",path:("/spec/template/spec/containers/0/env/"+($sk|tostring)+"/valueFrom/secretKeyRef/name"),value:$name}
    ]')
  kube -n kube-system patch deployment cilium-operator --type=json -p "$patch" >/dev/null
}

current_secret_ref() {
  kube -n kube-system get deployment cilium-operator -o json | jq -er \
    '[.spec.template.spec.containers[0].env[] | select(.name=="CILIUM_HUAWEI_CLOUD_ACCESS_KEY").valueFrom.secretKeyRef.name][0]'
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  set_secret_ref "$ORIGINAL_SECRET"
  kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
  kube -n kube-system patch deployment cilium-operator --type=merge \
    -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":1}}}}' >/dev/null
  kube -n kube-system delete secret "$CUSTOM_SECRET" --ignore-not-found >/dev/null
  kube -n default delete secret "$WRONG_NS_SECRET" --ignore-not-found >/dev/null
  exit "$status"
}

deployment=$(kube -n kube-system get deployment cilium-operator -o json)
ak_index=$(jq -er '.spec.template.spec.containers[0].env | to_entries[] | select(.value.name=="CILIUM_HUAWEI_CLOUD_ACCESS_KEY").key' <<<"$deployment")
sk_index=$(jq -er '.spec.template.spec.containers[0].env | to_entries[] | select(.value.name=="CILIUM_HUAWEI_CLOUD_SECRET_KEY").key' <<<"$deployment")
ORIGINAL_SECRET=$(jq -er '[.spec.template.spec.containers[0].env[] | select(.name=="CILIUM_HUAWEI_CLOUD_ACCESS_KEY").valueFrom.secretKeyRef.name][0]' <<<"$deployment")
[[ $(jq -er '[.spec.template.spec.containers[0].env[] | select(.name=="CILIUM_HUAWEI_CLOUD_SECRET_KEY").valueFrom.secretKeyRef.name][0]' <<<"$deployment") == "$ORIGINAL_SECRET" ]]
[[ $(jq -r '.spec.strategy.rollingUpdate.maxSurge|tostring' <<<"$deployment")/$(jq -r '.spec.strategy.rollingUpdate.maxUnavailable|tostring' <<<"$deployment") == 1/1 ]]
[[ $(kube -n kube-system get configmap cilium-config \
  -o 'jsonpath={.data.huawei-cloud-release-excess-ips}') == false ]]
trap cleanup EXIT INT TERM

before=$(pool_state)
printf 'pool-before-sha256=%s original-ref=%s\n' \
  "$(sha256sum <<<"$before" | awk '{print $1}')" "$ORIGINAL_SECRET"
kube -n kube-system patch deployment cilium-operator --type=merge \
  -p '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":0}}}}' >/dev/null

"${SSH[@]}" "set -e; export KUBECONFIG=/etc/kubernetes/admin.conf; kubectl -n kube-system get secret '$ORIGINAL_SECRET' -o json | jq --arg name '$CUSTOM_SECRET' '.metadata={name:\$name,namespace:\"kube-system\"} | del(.status)' | kubectl apply -f - >/dev/null"
set_secret_ref "$CUSTOM_SECRET"
kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
[[ $(current_secret_ref) == "$CUSTOM_SECRET" ]]
[[ $(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  --arg secret "$CUSTOM_SECRET" '[.items[] | select(.status.containerStatuses[0].ready==true and .status.containerStatuses[0].restartCount==0)] | length') -eq 1 ]]
[[ $(kube -n kube-system logs deployment/cilium-operator --since=2m 2>&1 \
  | grep -Eic 'unauthorized|status.?code.?[:= ]+(401|403)|APIGW\.' || true) -eq 0 ]]
mesh
[[ $(pool_state) == "$before" ]]
echo 'custom-secret-reference=pass pool=unchanged'

"${SSH[@]}" "set -e; export KUBECONFIG=/etc/kubernetes/admin.conf; kubectl -n kube-system get secret '$ORIGINAL_SECRET' -o json | jq --arg name '$WRONG_NS_SECRET' '.metadata={name:\$name,namespace:\"default\"} | del(.status)' | kubectl apply -f - >/dev/null; ! kubectl -n kube-system get secret '$WRONG_NS_SECRET' >/dev/null 2>&1"
set_secret_ref "$WRONG_NS_SECRET"
if kube -n kube-system rollout status deployment/cilium-operator --timeout=45s >/dev/null 2>&1; then
  echo 'wrong-namespace Secret unexpectedly rolled out' >&2
  exit 1
fi
ready_old=$(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  '[.items[] | select(.status.containerStatuses[0].ready==true)] | length')
waiting_bad=$(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  '[.items[] | select(.status.containerStatuses[0].state.waiting.reason=="CreateContainerConfigError")] | length')
[[ $ready_old -eq 1 && $waiting_bad -eq 1 ]]
printf 'wrong-namespace ready-old=%d waiting-bad=%d\n' "$ready_old" "$waiting_bad"
mesh
[[ $(pool_state) == "$before" ]]
echo 'wrong-namespace-pool=unchanged'

set_secret_ref "$ORIGINAL_SECRET"
kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
kube -n kube-system patch deployment cilium-operator --type=merge \
  -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":1}}}}' >/dev/null
kube -n kube-system delete secret "$CUSTOM_SECRET" --ignore-not-found >/dev/null
kube -n default delete secret "$WRONG_NS_SECRET" --ignore-not-found >/dev/null
[[ $(current_secret_ref) == "$ORIGINAL_SECRET" ]]
[[ $(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  '[.items[] | select(.status.containerStatuses[0].ready==true and .status.containerStatuses[0].restartCount==0)] | length') -eq 1 ]]
mesh
[[ $(pool_state) == "$before" ]]
echo 'original-secret-restored pool=unchanged'

trap - EXIT INT TERM
echo 'OPERATOR_SECRET_REFERENCE_RECOVERY_PASS'
