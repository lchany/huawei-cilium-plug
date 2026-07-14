#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
TARGET_TAG=${TARGET_TAG:?set TARGET_TAG, for example audit60 or audit64}
EXPECTED_SHA=${EXPECTED_SHA:?set the expected cilium-agent SHA256}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SSH_CP=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP")
NODES=(
  'ecs-4b3b-6555-0005 115.175.145.64'
  'ecs-4b3b-6555-0001 116.63.65.212'
  'ecs-4b3b-6555-0002 110.41.85.148'
  'ecs-4b3b-6555-0003 139.159.246.181'
  'ecs-4b3b-6555-0004 139.159.210.143'
)

for entry in "${NODES[@]}"; do
  read -r node host <<<"$entry"
  ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$host" \
    "ctr -n k8s.io images tag --force localhost/huaweicloud/cilium:v1.12.19-$TARGET_TAG localhost/huaweicloud/cilium:v1.12.19-audit25b >/dev/null"

  "${SSH_CP[@]}" \
    "NODE=$(printf %q "$node") EXPECTED_SHA=$(printf %q "$EXPECTED_SHA") bash -s" <<'REMOTE'
set -euo pipefail
K=(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system)
exec 9>/tmp/huaweicloud-customer25.lock
flock -w 30 9

old=$("${K[@]}" get pod -l k8s-app=cilium --field-selector "spec.nodeName=$NODE" -o jsonpath='{.items[0].metadata.name}')
[[ -n "$old" ]]
"${K[@]}" delete pod "$old" --wait=false >/dev/null
deadline=$((SECONDS + 180))
while :; do
  row=$("${K[@]}" get pod -l k8s-app=cilium --field-selector "spec.nodeName=$NODE,status.phase=Running" \
    -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' \
    | awk -v old="$old" '$1 != old && $2 == "True" {print; exit}')
  [[ -z "$row" ]] || break
  if (( SECONDS >= deadline )); then
    echo "node=$NODE timeout_waiting_agent" >&2
    exit 1
  fi
  sleep 1
done
read -r pod _ <<<"$row"
actual=$("${K[@]}" exec "$pod" -- sha256sum /usr/bin/cilium-agent | awk '{print $1}')
[[ "$actual" == "$EXPECTED_SHA" ]]
"${K[@]}" exec "$pod" -- cilium status --brief | grep -qx 'OK'
restart=$("${K[@]}" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}')
[[ "$restart" == 0 ]]
image_id=$("${K[@]}" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].imageID}')
echo "node=$NODE pod=$pod agent_sha=$actual restart=$restart image_id=$image_id status=OK"
REMOTE

  ROUNDS=0 "$SCRIPT_DIR/run_matrix_recreate_10.sh"
done

echo "AGENT_ALIAS_ROLLOUT_PASS target=$TARGET_TAG expected_sha=$EXPECTED_SHA"
