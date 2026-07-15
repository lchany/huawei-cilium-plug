#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}
NAMESPACE=${NAMESPACE:-kube-system}
CONFIGMAP=${CONFIGMAP:-cilium-config}
DEPLOYMENT=${DEPLOYMENT:-cilium-operator}
EXPECTED_IMAGE=${EXPECTED_IMAGE:-localhost/huaweicloud/operator-huaweicloud:v1.12.19-audit90}

exec 9>/var/lock/cilium-audit90-invalid-api-config.lock
flock -n 9

cm_json=$(kubectl -n "$NAMESPACE" get configmap "$CONFIGMAP" -o json)
endpoint_present=$(jq -r '.data | has("huawei-cloud-endpoint")' <<<"$cm_json")
region_present=$(jq -r '.data | has("huawei-cloud-region")' <<<"$cm_json")
endpoint_value=$(jq -r '.data["huawei-cloud-endpoint"] // ""' <<<"$cm_json")
region_value=$(jq -r '.data["huawei-cloud-region"] // ""' <<<"$cm_json")

set_key() {
  local key=$1 value=$2 patch
  patch=$(jq -cn --arg key "$key" --arg value "$value" '{data:{($key):$value}}')
  kubectl -n "$NAMESPACE" patch configmap "$CONFIGMAP" --type=merge -p "$patch" >/dev/null
}

remove_key() {
  local key=$1 escaped
  escaped=${key//\~/~0}
  escaped=${escaped//\//~1}
  if kubectl -n "$NAMESPACE" get configmap "$CONFIGMAP" -o json | jq -e --arg key "$key" '.data | has($key)' >/dev/null; then
    kubectl -n "$NAMESPACE" patch configmap "$CONFIGMAP" --type=json \
      -p "[{\"op\":\"remove\",\"path\":\"/data/$escaped\"}]" >/dev/null
  fi
}

restore_config() {
  if $endpoint_present; then set_key huawei-cloud-endpoint "$endpoint_value"; else remove_key huawei-cloud-endpoint; fi
  if $region_present; then set_key huawei-cloud-region "$region_value"; else remove_key huawei-cloud-region; fi
}

pool_hash() {
  kubectl get ciliumnodes -o json | jq -cS '[.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}] | sort_by(.name)' | sha256sum | awk '{print $1}'
}

assert_production_operator() {
  local expected_pod=$1
  [[ $(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o jsonpath='{.spec.template.spec.containers[0].image}') == "$EXPECTED_IMAGE" ]]
  [[ $(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o jsonpath='{.status.readyReplicas}') -eq 1 ]]
  [[ $(kubectl -n "$NAMESPACE" get pod "$expected_pod" -o jsonpath='{.status.containerStatuses[0].ready}') == true ]]
  [[ $(kubectl -n "$NAMESPACE" get pod "$expected_pod" -o jsonpath='{.status.containerStatuses[0].restartCount}') -eq 0 ]]
}

run_invalid_case() {
  local case_name=$1 expected=$2 test_namespace="cilium-audit90-$1" pod="cilium-operator-audit90-$1"
  kubectl create namespace "$test_namespace" >/dev/null

  kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o json | jq \
    --arg name "$pod" --arg namespace "$NAMESPACE" --arg leader_namespace "$test_namespace" '
      {
        apiVersion:"v1",
        kind:"Pod",
        metadata:{
          name:$name,
          namespace:$namespace,
          labels:{"audit.cilium.io/case":"audit90-invalid-api-config"}
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
    logs=$(kubectl -n "$NAMESPACE" logs "$pod" --tail=120 2>&1 || true)
    if grep -Fq "$expected" <<<"$logs"; then
      phase=$(kubectl -n "$NAMESPACE" get pod "$pod" -o jsonpath='{.status.phase}')
      if [[ $phase != Failed ]]; then
        sleep 2
        continue
      fi
      echo "case=$case_name pod=$pod phase=$phase reason=$expected"
      assert_production_operator "$production_pod"
      [[ $(pool_hash) == "$before_hash" ]]
      kubectl -n "$NAMESPACE" delete pod "$pod" --wait=true >/dev/null
      kubectl delete namespace "$test_namespace" --wait=true >/dev/null
      return 0
    fi
    sleep 2
  done
  echo "isolated candidate did not fail with expected reason: $expected" >&2
  return 1
}

restore_required=true
cleanup() {
  if $restore_required; then
    restore_config || true
    kubectl -n "$NAMESPACE" delete pods -l audit.cilium.io/case=audit90-invalid-api-config --wait=false >/dev/null 2>&1 || true
    kubectl delete namespaces cilium-audit90-endpoint cilium-audit90-region --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

production_pod=$(kubectl -n "$NAMESPACE" get pods -l name=cilium-operator -o json | jq -r '.items[] | select(.status.containerStatuses[0].ready == true) | .metadata.name' | head -1)
[[ -n $production_pod ]]
assert_production_operator "$production_pod"
before_hash=$(pool_hash)

set_key huawei-cloud-endpoint '://invalid'
run_invalid_case endpoint 'invalid HuaweiCloud endpoint'
if $endpoint_present; then set_key huawei-cloud-endpoint "$endpoint_value"; else remove_key huawei-cloud-endpoint; fi

set_key huawei-cloud-region 'cn south 1'
run_invalid_case region 'invalid HuaweiCloud region'
if $region_present; then set_key huawei-cloud-region "$region_value"; else remove_key huawei-cloud-region; fi

assert_production_operator "$production_pod"
[[ $(pool_hash) == "$before_hash" ]]
[[ $(kubectl get ciliumnodes -o json | jq '[.items[].status.ipam.operatorStatus.error | select(. != null and . != "")] | length') -eq 0 ]]
restore_required=false
trap - EXIT INT TERM
echo "pool_hash=$before_hash"
echo AUDIT90_INVALID_API_CONFIG_PASS
