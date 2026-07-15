#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/admin.conf}
CHART=${CHART:-/root/audit91-cilium-chart/install/kubernetes/cilium}
NAMESPACE=${NAMESPACE:-cilium-audit91-helm-secret}
RELEASE=${RELEASE:-cilium-audit91}
SECRET=${SECRET:-external-huawei-credentials}

exec 9>/var/lock/cilium-audit91-helm-secret.lock
flock -n 9

cleanup_required=true
cleanup() {
  if $cleanup_required; then
    helm uninstall "$RELEASE" -n "$NAMESPACE" --wait >/dev/null 2>&1 || true
    kubectl delete namespace "$NAMESPACE" --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

[[ -f $CHART/Chart.yaml ]]
! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1
kubectl create namespace "$NAMESPACE" >/dev/null
kubectl -n "$NAMESPACE" create secret generic "$SECRET" \
  --from-literal=CILIUM_HUAWEI_CLOUD_ACCESS_KEY=audit91-nonsecret-ak \
  --from-literal=CILIUM_HUAWEI_CLOUD_SECRET_KEY=audit91-nonsecret-sk >/dev/null

secret_field() {
  kubectl -n "$NAMESPACE" get secret "$SECRET" -o json | jq -r "$1"
}

assert_secret_unchanged() {
  [[ $(secret_field '.metadata.uid') == "$secret_uid" ]]
  [[ $(secret_field '.metadata.resourceVersion') == "$secret_resource_version" ]]
  [[ $(secret_field '.data | to_entries | sort_by(.key) | @json' | sha256sum | awk '{print $1}') == "$secret_data_hash" ]]
  [[ $(secret_field '.metadata.labels["app.kubernetes.io/managed-by"] // ""') == "" ]]
  [[ $(secret_field '.metadata.annotations["meta.helm.sh/release-name"] // ""') == "" ]]
}

secret_uid=$(secret_field '.metadata.uid')
secret_resource_version=$(secret_field '.metadata.resourceVersion')
secret_data_hash=$(secret_field '.data | to_entries | sort_by(.key) | @json' | sha256sum | awk '{print $1}')

common_values=(
  --set agent=false
  --set operator.enabled=false
  --set huaweicloud.enabled=true
  --set-string "huaweicloud.existingSecret=$SECRET"
)

helm install "$RELEASE" "$CHART" -n "$NAMESPACE" "${common_values[@]}" --set debug=false --wait
[[ $(helm list -n "$NAMESPACE" -o json | jq -r '.[0].revision') == 1 ]]
! helm get manifest "$RELEASE" -n "$NAMESPACE" | grep -Fq "name: $SECRET"
assert_secret_unchanged
echo 'install revision=1 secret=unchanged'

helm upgrade "$RELEASE" "$CHART" -n "$NAMESPACE" "${common_values[@]}" --set debug=true --wait
[[ $(helm list -n "$NAMESPACE" -o json | jq -r '.[0].revision') == 2 ]]
! helm get manifest "$RELEASE" -n "$NAMESPACE" | grep -Fq "name: $SECRET"
assert_secret_unchanged
echo 'upgrade revision=2 secret=unchanged'

helm rollback "$RELEASE" 1 -n "$NAMESPACE" --wait
[[ $(helm list -n "$NAMESPACE" -o json | jq -r '.[0].revision') == 3 ]]
assert_secret_unchanged
echo 'rollback revision=3 target=1 secret=unchanged'

helm uninstall "$RELEASE" -n "$NAMESPACE" --wait
[[ $(helm list -n "$NAMESPACE" -o json | jq 'length') -eq 0 ]]
assert_secret_unchanged
echo 'uninstall release=absent secret=retained'

kubectl -n "$NAMESPACE" delete secret "$SECRET" --wait=true >/dev/null
kubectl delete namespace "$NAMESPACE" --wait=true >/dev/null
cleanup_required=false
trap - EXIT INT TERM
echo AUDIT91_HELM_EXTERNAL_SECRET_LIFECYCLE_PASS
