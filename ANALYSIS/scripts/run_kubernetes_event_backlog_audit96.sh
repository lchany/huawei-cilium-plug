#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NS=${NS:-audit96-event-backlog}
EVENT_COUNT=${EVENT_COUNT:-1000}
OUT=${1:-/tmp/audit96-event-backlog.out}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "root@$CP")

[[ $EVENT_COUNT =~ ^[1-9][0-9]*$ ]]
(( EVENT_COUNT <= 5000 ))

exec > >(tee "$OUT") 2>&1

"${SSH[@]}" "NS=$(printf '%q' "$NS") EVENT_COUNT=$(printf '%q' "$EVENT_COUNT") bash -s" <<'REMOTE'
set -euo pipefail
K=(kubectl --kubeconfig=/etc/kubernetes/admin.conf)
exec 9>/tmp/huaweicloud-customer25.lock
flock -w 30 9

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  "${K[@]}" delete namespace "$NS" --wait=true --timeout=180s >/dev/null 2>&1
  exit "$status"
}
trap cleanup EXIT INT TERM

! "${K[@]}" get namespace "$NS" >/dev/null 2>&1
"${K[@]}" create namespace "$NS" >/dev/null

agent_before=$("${K[@]}" -n kube-system get pods -l k8s-app=cilium \
  -o 'jsonpath={range .items[*]}{.metadata.uid}{":"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | sort)
operator_before=$("${K[@]}" -n kube-system get pods -l io.cilium/app=operator \
  -o 'jsonpath={range .items[*]}{.metadata.uid}{":"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | sort)
pool_before=$("${K[@]}" get ciliumnodes -o json | jq -S '[.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}]' | sha256sum | awk '{print $1}')

timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg ns "$NS" --arg timestamp "$timestamp" --argjson count "$EVENT_COUNT" '
  {
    apiVersion:"v1",
    kind:"List",
    items:[range(0; $count) | {
      apiVersion:"v1",
      kind:"Event",
      metadata:{name:("audit96-" + (. | tostring)), namespace:$ns},
      involvedObject:{apiVersion:"v1", kind:"ConfigMap", name:"audit96-target", namespace:$ns},
      reason:"Audit96Backlog",
      message:("synthetic HuaweiCloud isolation audit event " + (. | tostring)),
      source:{component:"audit96"},
      firstTimestamp:$timestamp,
      lastTimestamp:$timestamp,
      count:1,
      type:"Normal"
    }]
  }
' | "${K[@]}" create -f - >/dev/null

actual=$("${K[@]}" -n "$NS" get events --field-selector reason=Audit96Backlog --no-headers | wc -l)
[[ $actual -eq $EVENT_COUNT ]]

start=$(date +%s%N)
listed=$("${K[@]}" -n "$NS" get events --field-selector reason=Audit96Backlog --chunk-size=50 -o name | wc -l)
elapsed_ms=$(( ($(date +%s%N) - start) / 1000000 ))
[[ $listed -eq $EVENT_COUNT && $elapsed_ms -lt 10000 ]]

agent_after=$("${K[@]}" -n kube-system get pods -l k8s-app=cilium \
  -o 'jsonpath={range .items[*]}{.metadata.uid}{":"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | sort)
operator_after=$("${K[@]}" -n kube-system get pods -l io.cilium/app=operator \
  -o 'jsonpath={range .items[*]}{.metadata.uid}{":"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | sort)
pool_after=$("${K[@]}" get ciliumnodes -o json | jq -S '[.items[] | {name:.metadata.name,pool:(.spec.ipam.pool // {})}]' | sha256sum | awk '{print $1}')
[[ $agent_before == "$agent_after" && $operator_before == "$operator_after" && $pool_before == "$pool_after" ]]

mapfile -t rows < <("${K[@]}" -n cilium-matrix get pods -l app=cilium-matrix \
  -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}' | sort)
[[ ${#rows[@]} -eq 8 ]]
ok=0
for source_row in "${rows[@]}"; do
  read -r source source_ip <<<"$source_row"
  for destination_row in "${rows[@]}"; do
    read -r _ destination_ip <<<"$destination_row"
    [[ $source_ip == "$destination_ip" ]] && continue
    "${K[@]}" -n cilium-matrix exec "$source" -- ping -c 1 -W 2 "$destination_ip" >/dev/null
    ok=$((ok + 1))
  done
done
[[ $ok -eq 56 ]]
printf 'events=%d list_elapsed_ms=%d agent_identity_restart=unchanged operator_identity_restart=unchanged pool_sha256=%s mesh=%d/56\n' \
  "$actual" "$elapsed_ms" "$pool_after" "$ok"

"${K[@]}" delete namespace "$NS" --wait=true --timeout=180s >/dev/null
trap - EXIT INT TERM
! "${K[@]}" get namespace "$NS" >/dev/null 2>&1
echo 'KUBERNETES_EVENT_BACKLOG_PASS'
REMOTE
