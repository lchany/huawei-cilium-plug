#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
TARGET_NODE=${TARGET_NODE:-ecs-4b3b-6555-0003}
TARGET_MIN_ALLOCATE=${TARGET_MIN_ALLOCATE:-4}
RELEASE_TIMEOUT=${RELEASE_TIMEOUT:-480}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP")

"${SSH[@]}" \
  "TARGET_NODE=$(printf %q "$TARGET_NODE") TARGET_MIN_ALLOCATE=$(printf %q "$TARGET_MIN_ALLOCATE") RELEASE_TIMEOUT=$(printf %q "$RELEASE_TIMEOUT") bash -s" <<'REMOTE'
set -euo pipefail
K=(kubectl --kubeconfig=/etc/kubernetes/admin.conf)
exec 9>/tmp/huaweicloud-customer25.lock
flock -w 30 9

original_release=$("${K[@]}" -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-release-excess-ips}')
original_min=$("${K[@]}" get ciliumnode "$TARGET_NODE" -o jsonpath='{.spec.ipam.min-allocate}')
[[ "$original_release" == false ]]
[[ "$original_min" =~ ^[0-9]+$ && "$original_min" -gt "$TARGET_MIN_ALLOCATE" ]]

restore() {
  set +e
  "${K[@]}" -n kube-system patch configmap cilium-config --type merge -p \
    '{"data":{"huawei-cloud-release-excess-ips":"false"}}' >/dev/null
  "${K[@]}" -n kube-system rollout restart deployment/cilium-operator >/dev/null
  "${K[@]}" -n kube-system rollout status deployment/cilium-operator --timeout=240s >/dev/null
  "${K[@]}" patch ciliumnode "$TARGET_NODE" --type merge -p \
    "{\"spec\":{\"ipam\":{\"min-allocate\":$original_min}}}" >/dev/null
  for ds in matrix-a matrix-b; do
    expression_count=$("${K[@]}" -n cilium-matrix get daemonset "$ds" -o json | jq '.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions | length')
    if [[ "$expression_count" -gt 1 ]]; then
      "${K[@]}" -n cilium-matrix patch daemonset "$ds" --type json -p \
        '[{"op":"remove","path":"/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/1"}]' >/dev/null
    fi
  done
  "${K[@]}" -n cilium-matrix rollout status daemonset/matrix-a --timeout=300s >/dev/null
  "${K[@]}" -n cilium-matrix rollout status daemonset/matrix-b --timeout=300s >/dev/null
  deadline=$((SECONDS + 360))
  while :; do
    pool=$("${K[@]}" get ciliumnode "$TARGET_NODE" -o json | jq '.spec.ipam.pool | length')
    [[ "$pool" -eq "$original_min" ]] && break
    (( SECONDS < deadline )) || break
    sleep 2
  done
  set -e
}
trap restore EXIT

baseline=$("${K[@]}" get ciliumnode "$TARGET_NODE" -o json)
baseline_pool=$(jq -c '.spec.ipam.pool | to_entries | sort_by(.key)' <<<"$baseline")
baseline_pool_count=$(jq '.spec.ipam.pool | length' <<<"$baseline")
[[ "$baseline_pool_count" -eq "$original_min" ]]
old_operator_uid=$("${K[@]}" -n kube-system get pod -l io.cilium/app=operator -o jsonpath='{.items[0].metadata.uid}')
[[ -n "$old_operator_uid" ]]

"${K[@]}" -n kube-system patch configmap cilium-config --type merge -p \
  '{"data":{"huawei-cloud-release-excess-ips":"true"}}' >/dev/null
"${K[@]}" -n kube-system rollout restart deployment/cilium-operator >/dev/null
"${K[@]}" -n kube-system rollout status deployment/cilium-operator --timeout=240s >/dev/null
operator_pod=$("${K[@]}" -n kube-system get pod -l io.cilium/app=operator -o jsonpath='{.items[0].metadata.name}')
[[ -n "$operator_pod" ]]
new_operator_uid=$("${K[@]}" -n kube-system get pod "$operator_pod" -o jsonpath='{.metadata.uid}')
[[ "$new_operator_uid" != "$old_operator_uid" ]]
[[ $("${K[@]}" -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-release-excess-ips}') == true ]]

"${K[@]}" patch ciliumnode "$TARGET_NODE" --type merge -p \
  "{\"spec\":{\"ipam\":{\"min-allocate\":$TARGET_MIN_ALLOCATE}}}" >/dev/null
for ds in matrix-a matrix-b; do
  "${K[@]}" -n cilium-matrix patch daemonset "$ds" --type json -p \
    "[{\"op\":\"add\",\"path\":\"/spec/template/spec/affinity/nodeAffinity/requiredDuringSchedulingIgnoredDuringExecution/nodeSelectorTerms/0/matchExpressions/-\",\"value\":{\"key\":\"kubernetes.io/hostname\",\"operator\":\"NotIn\",\"values\":[\"$TARGET_NODE\"]}}]" >/dev/null
done

deadline=$((SECONDS + 180))
while :; do
  target_pods=$("${K[@]}" -n cilium-matrix get pods --field-selector "spec.nodeName=$TARGET_NODE" --no-headers 2>/dev/null | wc -l)
  [[ "$target_pods" -eq 0 ]] && break
  (( SECONDS < deadline )) || { echo "matrix Pods did not leave target node" >&2; exit 1; }
  sleep 2
done

deadline=$((SECONDS + 180))
while :; do
  current=$("${K[@]}" get ciliumnode "$TARGET_NODE" -o json)
  used_count=$(jq '.status.ipam.used | length' <<<"$current")
  [[ "$used_count" -le 2 ]] && break
  (( SECONDS < deadline )) || { echo "target node used state did not shrink" >&2; exit 1; }
  sleep 2
done
protected_ips=$(jq -c '.status.ipam.used | keys | sort' <<<"$current")
[[ $(jq 'length' <<<"$protected_ips") -gt 0 ]]

release_started=$SECONDS
deadline=$((SECONDS + RELEASE_TIMEOUT))
while :; do
  current=$("${K[@]}" get ciliumnode "$TARGET_NODE" -o json)
  pool_count=$(jq '.spec.ipam.pool | length' <<<"$current")
  [[ "$pool_count" -eq 6 ]] && break
  (( SECONDS < deadline )) || { echo "pool did not converge to six entries" >&2; exit 1; }
  sleep 2
done
release_elapsed=$((SECONDS-release_started))
released_pool=$(jq -c '.spec.ipam.pool | to_entries | sort_by(.key)' <<<"$current")
[[ "$released_pool" != "$baseline_pool" ]]
for ip in $(jq -r '.[]' <<<"$protected_ips"); do
  jq -e --arg ip "$ip" '.spec.ipam.pool[$ip] != null' <<<"$current" >/dev/null
done
[[ $(jq '.status.ipam.used | length' <<<"$current") -eq $(jq 'length' <<<"$protected_ips") ]]

echo "release_enabled=true target_node=$TARGET_NODE original_min=$original_min temporary_min=$TARGET_MIN_ALLOCATE"
echo "baseline_pool_count=$baseline_pool_count released_pool_count=$pool_count protected_used_ips=$protected_ips release_elapsed_seconds=$release_elapsed"
echo "in_use_ips_preserved=true released_pool_changed=true"

restore
trap - EXIT
final=$("${K[@]}" get ciliumnode "$TARGET_NODE" -o json)
final_pool_count=$(jq '.spec.ipam.pool | length' <<<"$final")
final_min=$(jq '.spec.ipam["min-allocate"]' <<<"$final")
[[ "$final_pool_count" -eq "$original_min" && "$final_min" -eq "$original_min" ]]
[[ $("${K[@]}" -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-release-excess-ips}') == false ]]
[[ $("${K[@]}" -n kube-system get deployment cilium-operator -o jsonpath='{.status.readyReplicas}/{.spec.replicas}') == 1/1 ]]
for ds in matrix-a matrix-b; do
  [[ $("${K[@]}" -n cilium-matrix get daemonset "$ds" -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}') == 4/4 ]]
  [[ $("${K[@]}" -n cilium-matrix get daemonset "$ds" -o json | jq '.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions | length') -eq 1 ]]
done
echo "restored_release_enabled=false restored_min=$final_min restored_pool_count=$final_pool_count"
echo RELEASE_ENABLED_CLEANUP_PASS
REMOTE
