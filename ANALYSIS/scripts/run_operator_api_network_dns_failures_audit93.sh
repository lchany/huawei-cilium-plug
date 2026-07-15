#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}
NAMESPACE=${NAMESPACE:-kube-system}
CONFIGMAP=${CONFIGMAP:-cilium-config}
DEPLOYMENT=${DEPLOYMENT:-cilium-operator}
EXPECTED_IMAGE=${EXPECTED_IMAGE:-localhost/huaweicloud/operator-huaweicloud:v1.12.19-audit90}

exec 9>/var/lock/cilium-audit93-api-network-dns.lock
flock -n 9

cm_json=$(kubectl -n "$NAMESPACE" get configmap "$CONFIGMAP" -o json)
endpoint_present=$(jq -r '.data | has("huawei-cloud-endpoint")' <<<"$cm_json")
endpoint_value=$(jq -r '.data["huawei-cloud-endpoint"] // ""' <<<"$cm_json")

set_endpoint() {
  local value=$1 patch
  patch=$(jq -cn --arg value "$value" '{data:{"huawei-cloud-endpoint":$value}}')
  kubectl -n "$NAMESPACE" patch configmap "$CONFIGMAP" --type=merge -p "$patch" >/dev/null
}

restore_endpoint() {
  if $endpoint_present; then
    set_endpoint "$endpoint_value"
  elif kubectl -n "$NAMESPACE" get configmap "$CONFIGMAP" -o json | jq -e '.data | has("huawei-cloud-endpoint")' >/dev/null; then
    kubectl -n "$NAMESPACE" patch configmap "$CONFIGMAP" --type=json \
      -p '[{"op":"remove","path":"/data/huawei-cloud-endpoint"}]' >/dev/null
  fi
}

pool_hash() {
  kubectl get ciliumnodes -o json | jq -cS '[.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}] | sort_by(.name)' | sha256sum | awk '{print $1}'
}

assert_production() {
  [[ $(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o jsonpath='{.spec.template.spec.containers[0].image}') == "$EXPECTED_IMAGE" ]]
  [[ $(kubectl -n "$NAMESPACE" get pod "$production_pod" -o jsonpath='{.status.containerStatuses[0].ready}') == true ]]
  [[ $(kubectl -n "$NAMESPACE" get pod "$production_pod" -o jsonpath='{.status.containerStatuses[0].restartCount}') -eq 0 ]]
  [[ $(pool_hash) == "$before_hash" ]]
}

run_failure_case() {
  local case_name=$1 endpoint=$2 pattern=$3 test_namespace="cilium-audit93-$1" pod="cilium-operator-audit93-$1"
  set_endpoint "$endpoint"
  kubectl create namespace "$test_namespace" >/dev/null

  kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o json | jq \
    --arg name "$pod" --arg namespace "$NAMESPACE" --arg leader_namespace "$test_namespace" '
      {
        apiVersion:"v1",
        kind:"Pod",
        metadata:{
          name:$name,
          namespace:$namespace,
          labels:{"audit.cilium.io/case":"audit93-api-connectivity"}
        },
        spec:.spec.template.spec
      }
      | .spec.restartPolicy="Never"
      | .spec.hostNetwork=false
      | .spec.dnsPolicy="ClusterFirst"
      | .spec.containers[0].env=(((.spec.containers[0].env // []) | map(select(.name != "CILIUM_K8S_NAMESPACE"))) + [{name:"CILIUM_K8S_NAMESPACE",value:$leader_namespace}])
      | del(.spec.containers[0].readinessProbe,.spec.containers[0].livenessProbe)
    ' | kubectl create -f - >/dev/null

  for _ in $(seq 1 90); do
    logs=$(kubectl -n "$NAMESPACE" logs "$pod" --tail=160 2>&1 || true)
    phase=$(kubectl -n "$NAMESPACE" get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ $phase == Failed ]] && grep -Eiq "$pattern" <<<"$logs"; then
      echo "case=$case_name phase=Failed error=attributed"
      assert_production
      kubectl -n "$NAMESPACE" delete pod "$pod" --wait=true >/dev/null
      kubectl delete namespace "$test_namespace" --wait=true >/dev/null
      restore_endpoint
      return 0
    fi
    sleep 2
  done
  echo "isolated $case_name candidate did not fail with expected attribution" >&2
  return 1
}

cleanup_required=true
cleanup() {
  if $cleanup_required; then
    restore_endpoint || true
    kubectl -n "$NAMESPACE" delete pods -l audit.cilium.io/case=audit93-api-connectivity --wait=false >/dev/null 2>&1 || true
    kubectl delete namespaces cilium-audit93-network cilium-audit93-dns --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

production_pod=$(kubectl -n "$NAMESPACE" get pods -l name=cilium-operator -o json | jq -r '.items[] | select(.status.containerStatuses[0].ready == true) | .metadata.name' | head -1)
[[ -n $production_pod ]]
before_hash=$(pool_hash)
assert_production

run_failure_case network 'http://192.0.2.1:9' 'connect: connection refused|i/o timeout|no route to host|client\.timeout exceeded|deadline exceeded'
run_failure_case dns 'https://audit93-does-not-exist.invalid' 'no such host|server misbehaving|temporary failure in name resolution'

restore_endpoint
assert_production
[[ $(kubectl get ciliumnodes -o json | jq '[.items[].status.ipam.operatorStatus.error | select(. != null and . != "")] | length') -eq 0 ]]
cleanup_required=false
trap - EXIT INT TERM
echo "pool_hash=$before_hash"
echo AUDIT93_API_NETWORK_DNS_FAILURES_PASS
