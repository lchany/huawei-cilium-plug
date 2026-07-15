#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}
PROBE=${PROBE:-/root/audit92-huaweicloud-invalid-sg}
TARGET_NODE=${TARGET_NODE:-ecs-4b3b-6555-0003}

exec 9>/tmp/huaweicloud-customer25.lock
flock -n 9

operator_scaled=false
node_cordoned=false
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if $operator_scaled; then
    kubectl -n kube-system scale deployment/cilium-operator --replicas=1 >/dev/null
    kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
  fi
  if $node_cordoned; then
    kubectl uncordon "$TARGET_NODE" >/dev/null
  fi
  unset HUAWEI_CLOUD_ACCESS_KEY HUAWEI_CLOUD_SECRET_KEY
  exit "$status"
}
trap cleanup EXIT INT TERM

[[ -x $PROBE ]]
[[ $(kubectl -n kube-system get deployment cilium-operator -o jsonpath='{.spec.replicas}/{.status.readyReplicas}') == 1/1 ]]
[[ $(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-release-excess-ips}') == false ]]
[[ $(kubectl get node "$TARGET_NODE" -o jsonpath='{.spec.unschedulable}') != true ]]

node_json=$(kubectl get ciliumnode "$TARGET_NODE" -o json)
[[ $(jq '(.spec.ipam.pool // {}) | length' <<<"$node_json") -eq 8 ]]
delete_id=$(jq -er '
  (.spec.ipam.pool // {}) as $pool |
  (.status.ipam.used // {}) as $used |
  [$pool | to_entries | sort_by(.key)[] as $entry | select(($used | has($entry.key)) | not) | $entry.value.resource][0]
' <<<"$node_json")
before_pool_hash=$(kubectl get ciliumnodes -o json | jq -cS '[.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}] | sort_by(.name)' | sha256sum | awk '{print $1}')
secret=$(kubectl -n kube-system get deployment cilium-operator -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="CILIUM_HUAWEI_CLOUD_ACCESS_KEY")].valueFrom.secretKeyRef.name}')

export HUAWEI_CLOUD_ACCESS_KEY
export HUAWEI_CLOUD_SECRET_KEY
export HUAWEI_CLOUD_PROJECT_ID
export HUAWEI_CLOUD_REGION
export HUAWEI_CLOUD_ENDPOINT
export DELETE_FREE_RESOURCE_ID=$delete_id
HUAWEI_CLOUD_ACCESS_KEY=$(kubectl -n kube-system get secret "$secret" -o jsonpath='{.data.CILIUM_HUAWEI_CLOUD_ACCESS_KEY}' | base64 -d)
HUAWEI_CLOUD_SECRET_KEY=$(kubectl -n kube-system get secret "$secret" -o jsonpath='{.data.CILIUM_HUAWEI_CLOUD_SECRET_KEY}' | base64 -d)
HUAWEI_CLOUD_PROJECT_ID=$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-project-id}')
HUAWEI_CLOUD_REGION=$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-region}')
HUAWEI_CLOUD_ENDPOINT=$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-endpoint}')

kubectl cordon "$TARGET_NODE" >/dev/null
node_cordoned=true
kubectl -n kube-system scale deployment/cilium-operator --replicas=0 >/dev/null
operator_scaled=true
for _ in $(seq 1 60); do
  [[ $(kubectl -n kube-system get pods -l name=cilium-operator --no-headers 2>/dev/null | wc -l) -eq 0 ]] && break
  sleep 2
done
[[ $(kubectl -n kube-system get pods -l name=cilium-operator --no-headers 2>/dev/null | wc -l) -eq 0 ]]

AUDIT_MODE=invalid "$PROBE"

kubectl -n kube-system scale deployment/cilium-operator --replicas=1 >/dev/null
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=300s >/dev/null
operator_scaled=false

recovered=false
for _ in $(seq 1 90); do
  current=$(kubectl get ciliumnode "$TARGET_NODE" -o json)
  pool_count=$(jq '(.spec.ipam.pool // {}) | length' <<<"$current")
  deleted_present=$(jq --arg id "$delete_id" '[.spec.ipam.pool[]?.resource | select(. == $id)] | length' <<<"$current")
  used_outside=$(jq '[((.status.ipam.used // {}) | keys[]) as $ip | select(((.spec.ipam.pool // {}) | has($ip)) | not)] | length' <<<"$current")
  error=$(jq -r '.status.ipam.operatorStatus.error // ""' <<<"$current")
  if [[ $pool_count -eq 8 && $deleted_present -eq 0 && $used_outside -eq 0 && -z $error ]]; then
    recovered=true
    break
  fi
  sleep 5
done
$recovered

pool_ids=$(jq -r '(.spec.ipam.pool // {}) | to_entries | sort_by(.key)[] | .value.resource' <<<"$current" | paste -sd, -)
AUDIT_MODE=verify POOL_RESOURCE_IDS="$pool_ids" "$PROBE"

kubectl uncordon "$TARGET_NODE" >/dev/null
node_cordoned=false
unset HUAWEI_CLOUD_ACCESS_KEY HUAWEI_CLOUD_SECRET_KEY

all_nodes=$(kubectl get ciliumnodes -o json)
[[ $(jq '[.items[].spec.ipam.pool | length] | add' <<<"$all_nodes") -eq 40 ]]
[[ $(jq '[.items[].status.ipam.operatorStatus.error | select(. != null and . != "")] | length' <<<"$all_nodes") -eq 0 ]]
[[ $(kubectl -n kube-system get pods -l name=cilium-operator -o json | jq '[.items[].status.containerStatuses[0].restartCount] | add') -eq 0 ]]
after_pool_hash=$(jq -cS '[.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}] | sort_by(.name)' <<<"$all_nodes" | sha256sum | awk '{print $1}')
echo "before_pool_hash=$before_pool_hash after_pool_hash=$after_pool_hash pool=40 deleted_resource_replaced=true"
trap - EXIT INT TERM
echo AUDIT92_INVALID_SG_LIVE_PASS
