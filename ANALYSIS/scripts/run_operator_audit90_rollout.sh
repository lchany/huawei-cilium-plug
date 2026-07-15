#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}
OLD_IMAGE=${OLD_IMAGE:-localhost/huaweicloud/operator-huaweicloud:v1.12.19-audit81}
NEW_IMAGE=${NEW_IMAGE:-localhost/huaweicloud/operator-huaweicloud:v1.12.19-audit90}
DEPLOYMENT=${DEPLOYMENT:-cilium-operator}
NAMESPACE=${NAMESPACE:-kube-system}

exec 9>/var/lock/cilium-audit90-operator-rollout.lock
flock -n 9

current_image() {
  kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o jsonpath='{.spec.template.spec.containers[0].image}'
}

pool_hash() {
  kubectl get ciliumnodes -o json | jq -cS '
    [.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}] | sort_by(.name)
  ' | sha256sum | awk '{print $1}'
}

assert_health() {
  [[ $(kubectl get nodes --no-headers | awk '$2 == "Ready" {n++} END {print n+0}') -eq 5 ]]
  [[ $(kubectl -n "$NAMESPACE" get pods -l k8s-app=cilium -o json | jq '[.items[] | select(.status.phase == "Running" and .status.containerStatuses[0].ready == true)] | length') -eq 5 ]]
  [[ $(kubectl -n "$NAMESPACE" get pods -l k8s-app=cilium -o json | jq '[.items[].status.containerStatuses[0].restartCount] | add') -eq 0 ]]
  [[ $(kubectl get ciliumnodes -o json | jq '[.items[].spec.ipam.pool | length] | add') -eq 40 ]]
  [[ $(kubectl get ciliumnodes -o json | jq '[.items[].status.ipam.operatorStatus.error | select(. != null and . != "")] | length') -eq 0 ]]
}

restore_required=true
cleanup() {
  if $restore_required; then
    kubectl -n "$NAMESPACE" set image deployment/"$DEPLOYMENT" "cilium-operator=$OLD_IMAGE" >/dev/null || true
    kubectl -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT" --timeout=300s || true
  fi
}
trap cleanup EXIT INT TERM

[[ $(current_image) == "$OLD_IMAGE" ]]
assert_health
before_hash=$(pool_hash)
echo "before_pool_hash=$before_hash"

kubectl -n "$NAMESPACE" set image deployment/"$DEPLOYMENT" "cilium-operator=$NEW_IMAGE"
kubectl -n "$NAMESPACE" rollout status deployment/"$DEPLOYMENT" --timeout=300s

[[ $(current_image) == "$NEW_IMAGE" ]]
[[ $(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o jsonpath='{.status.readyReplicas}') -eq 1 ]]
[[ $(kubectl -n "$NAMESPACE" get pods -l name=cilium-operator -o json | jq '[.items[].status.containerStatuses[0].restartCount] | add') -eq 0 ]]
assert_health

after_hash=$(pool_hash)
echo "after_pool_hash=$after_hash"
[[ $after_hash == "$before_hash" ]]

operator_pod=$(kubectl -n "$NAMESPACE" get pods -l name=cilium-operator -o jsonpath='{.items[0].metadata.name}')
echo "operator_pod=$operator_pod"
kubectl -n "$NAMESPACE" get pod "$operator_pod" -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,IMAGE:.spec.containers[0].image --no-headers

restore_required=false
trap - EXIT INT TERM
echo AUDIT90_OPERATOR_ROLLOUT_PASS
