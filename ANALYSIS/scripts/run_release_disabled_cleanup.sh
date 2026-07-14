#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
WAIT_SECONDS=${WAIT_SECONDS:-210}
NS=${NS:-cilium-release-disabled}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP")

"${SSH[@]}" "WAIT_SECONDS=$(printf %q "$WAIT_SECONDS") NS=$(printf %q "$NS") bash -s" <<'REMOTE'
set -euo pipefail
K=(kubectl --kubeconfig=/etc/kubernetes/admin.conf)
exec 9>/tmp/huaweicloud-customer25.lock
flock -w 30 9

cleanup() {
  "${K[@]}" delete namespace "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

release_enabled=$("${K[@]}" -n kube-system get configmap cilium-config -o jsonpath='{.data.huawei-cloud-release-excess-ips}')
[[ "$release_enabled" == false ]]
operator_ready=$("${K[@]}" -n kube-system get deployment cilium-operator -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')
[[ "$operator_ready" == 1/1 ]]

inventory() {
  "${K[@]}" get ciliumnodes -o json | jq -c '[.items[] | {
    name:.metadata.name,
    pool:(.spec.ipam.pool | to_entries | map({ip:.key,resource:(.value.resource // "")}) | sort_by(.ip)),
    used:(.status.ipam.used | keys | sort)
  }] | sort_by(.name)'
}

pool_inventory() {
  "${K[@]}" get ciliumnodes -o json | jq -c '[.items[] | {
    name:.metadata.name,
    pool:(.spec.ipam.pool | to_entries | map({ip:.key,resource:(.value.resource // "")}) | sort_by(.ip))
  }] | sort_by(.name)'
}

baseline=$(inventory)
baseline_pool=$(pool_inventory)
baseline_pool_count=$("${K[@]}" get ciliumnodes -o json | jq '[.items[].spec.ipam.pool | length] | add')
[[ "$baseline_pool_count" -eq 40 ]]

"${K[@]}" create namespace "$NS" >/dev/null
cat <<'YAML' | "${K[@]}" -n "$NS" apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cleanup-burst
spec:
  replicas: 10
  selector:
    matchLabels:
      app: cleanup-burst
  template:
    metadata:
      labels:
        app: cleanup-burst
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: cleanup-burst
      containers:
      - name: toolbox
        image: m.daocloud.io/docker.io/library/busybox:1.36.1
        command: [sh, -c, 'sleep 3600']
YAML

created_ms=$(date +%s%3N)
"${K[@]}" -n "$NS" rollout status deployment/cleanup-burst --timeout=240s >/dev/null
ready_ms=$(date +%s%3N)
distribution=$("${K[@]}" -n "$NS" get pods -l app=cleanup-burst -o json | jq -r '.items | group_by(.spec.nodeName)[] | "\(.[0].spec.nodeName) \(length)"' | sort)
[[ $(printf '%s\n' "$distribution" | awk '$2 == 2 {n++} END {print n+0}') -eq 5 ]]

delete_started_ms=$(date +%s%3N)
"${K[@]}" delete namespace "$NS" --wait=true >/dev/null
delete_finished_ms=$(date +%s%3N)
trap - EXIT
[[ -z $("${K[@]}" get namespace "$NS" --ignore-not-found -o name) ]]

deadline=$((SECONDS + 120))
while :; do
  current=$(inventory)
  [[ "$current" == "$baseline" ]] && break
  (( SECONDS < deadline )) || { echo "IPAM state did not return to baseline" >&2; exit 1; }
  sleep 2
done

sleep "$WAIT_SECONDS"
final_pool=$(pool_inventory)
[[ "$final_pool" == "$baseline_pool" ]]
final_pool_count=$("${K[@]}" get ciliumnodes -o json | jq '[.items[].spec.ipam.pool | length] | add')
[[ "$final_pool_count" -eq "$baseline_pool_count" ]]
[[ $("${K[@]}" get nodes --no-headers | awk '$2 == "Ready" {n++} END {print n+0}') -eq 5 ]]
[[ $("${K[@]}" -n kube-system get pods -l k8s-app=cilium --no-headers | awk '$2 == "1/1" && $3 == "Running" && $4 == 0 {n++} END {print n+0}') -eq 5 ]]

echo "release_excess_ips=$release_enabled operator_ready=$operator_ready"
echo "burst_ready_ms=$((ready_ms-created_ms)) namespace_delete_ms=$((delete_finished_ms-delete_started_ms))"
printf '%s\n' "$distribution"
echo "baseline_pool_count=$baseline_pool_count final_pool_count=$final_pool_count wait_seconds=$WAIT_SECONDS"
echo "ipam_state_returned_to_exact_baseline=true pool_inventory_unchanged=true namespace_residue=0 nodes_ready=5 agents_ready_zero_restart=5"
echo RELEASE_DISABLED_CLEANUP_PASS
REMOTE
