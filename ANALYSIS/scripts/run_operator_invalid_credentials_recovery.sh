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
BACKUP=${BACKUP:-/tmp/audit79-huaweicloud-secret-backup.json}
OUT=${1:-/tmp/operator-invalid-credentials-recovery.out}
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

restart_operator() {
  kube -n kube-system rollout restart deployment/cilium-operator >/dev/null
}

restore() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  "${SSH[@]}" "test -s '$BACKUP' && kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f '$BACKUP' >/dev/null"
  restart_operator
  kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
  kube -n kube-system patch deployment cilium-operator --type=merge \
    -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":1}}}}' >/dev/null
  "${SSH[@]}" "rm -f '$BACKUP'"
  exit "$status"
}
trap restore EXIT INT TERM

[[ $(kube -n kube-system get deployment cilium-operator \
  -o 'jsonpath={.spec.template.spec.containers[0].image}') == "$GOOD_IMAGE" ]]
[[ $(kube -n kube-system get deployment cilium-operator \
  -o 'jsonpath={.spec.strategy.rollingUpdate.maxSurge}/{.spec.strategy.rollingUpdate.maxUnavailable}') == 1/1 ]]
[[ $(kube -n kube-system get configmap cilium-config \
  -o 'jsonpath={.data.huawei-cloud-release-excess-ips}') == false ]]

secret_name=$(kube -n kube-system get deployment cilium-operator -o json | jq -er \
  '[.spec.template.spec.containers[0].env[] | select(.name=="CILIUM_HUAWEI_CLOUD_ACCESS_KEY").valueFrom.secretKeyRef.name][0]')
secret_name_sk=$(kube -n kube-system get deployment cilium-operator -o json | jq -er \
  '[.spec.template.spec.containers[0].env[] | select(.name=="CILIUM_HUAWEI_CLOUD_SECRET_KEY").valueFrom.secretKeyRef.name][0]')
[[ $secret_name == "$secret_name_sk" ]]

"${SSH[@]}" "umask 077; kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get secret '$secret_name' -o json | jq '{apiVersion,kind,metadata:{name:.metadata.name,namespace:.metadata.namespace},data}' >'$BACKUP'; test -s '$BACKUP'"
before=$(pool_state)
printf 'pool-before-sha256=%s secret-ref=%s\n' \
  "$(sha256sum <<<"$before" | awk '{print $1}')" "$secret_name"

kube -n kube-system patch deployment cilium-operator --type=merge \
  -p '{"spec":{"strategy":{"rollingUpdate":{"maxUnavailable":0}}}}' >/dev/null
kube -n kube-system patch secret "$secret_name" --type=merge -p \
  '{"stringData":{"CILIUM_HUAWEI_CLOUD_ACCESS_KEY":"audit79-invalid-ak","CILIUM_HUAWEI_CLOUD_SECRET_KEY":"audit79-invalid-sk"}}' >/dev/null
restart_operator
if kube -n kube-system rollout status deployment/cilium-operator --timeout=45s >/dev/null 2>&1; then
  echo 'invalid-credential rollout reported Ready'
else
  echo 'invalid-credential rollout did not become Ready'
fi
sleep 30

auth_matches=$(kube -n kube-system logs -l io.cilium/app=operator --all-containers --prefix --since=3m 2>&1 \
  | grep -Eic 'unauthorized|status.?code.?[:= ]+(401|403)|APIGW\.' || true)
[[ $auth_matches -gt 0 ]]
printf 'invalid-credential-auth-matches=%d\n' "$auth_matches"
mesh
[[ $(pool_state) == "$before" ]]
echo 'invalid-credential-pool=unchanged'

"${SSH[@]}" "kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f '$BACKUP' >/dev/null"
restart_operator
kube -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
kube -n kube-system patch deployment cilium-operator --type=merge \
  -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":1}}}}' >/dev/null
[[ $(kube -n kube-system get pods -l io.cilium/app=operator -o json | jq -r \
  --arg image "$GOOD_IMAGE" '[.items[] | select(.spec.containers[0].image==$image and .status.containerStatuses[0].ready==true and .status.containerStatuses[0].restartCount==0)] | length') -eq 1 ]]
[[ $(kube -n kube-system logs deployment/cilium-operator --since=2m 2>&1 \
  | grep -Eic 'unauthorized|status.?code.?[:= ]+(401|403)|APIGW\.' || true) -eq 0 ]]
mesh
[[ $(pool_state) == "$before" ]]
echo 'recovered-credential-pool=unchanged'

"${SSH[@]}" "rm -f '$BACKUP'"
trap - EXIT INT TERM
echo 'OPERATOR_INVALID_CREDENTIALS_RECOVERY_PASS'
