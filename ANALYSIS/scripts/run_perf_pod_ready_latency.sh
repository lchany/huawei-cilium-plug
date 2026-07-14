#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NS=${NS:-cilium-matrix}
NODE=${NODE:-ecs-4b3b-6555-0004}
SET=${SET:-b}
ROUNDS=${ROUNDS:-20}
SSH=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP")

"${SSH[@]}" \
  "NS=$(printf %q "$NS") NODE=$(printf %q "$NODE") SET=$(printf %q "$SET") ROUNDS=$(printf %q "$ROUNDS") bash -s" <<'REMOTE'
set -euo pipefail

K=(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n "$NS")
selector="app=cilium-matrix,set=$SET"
samples=$(mktemp /tmp/audit70-ready-ms.XXXXXX)
trap 'rm -f "$samples"' EXIT

exec 9>/tmp/huaweicloud-customer25.lock
flock -w 30 9

for round in $(seq 1 "$ROUNDS"); do
  read -r old_name old_uid < <("${K[@]}" get pod -l "$selector" \
    --field-selector "spec.nodeName=$NODE" \
    -o 'jsonpath={.items[0].metadata.name} {.items[0].metadata.uid}{"\n"}')
  [[ -n "$old_name" && -n "$old_uid" ]]

  start_ms=$(date +%s%3N)
  "${K[@]}" delete pod "$old_name" --wait=false >/dev/null

  deadline=$((SECONDS + 180))
  while :; do
    row=$("${K[@]}" get pod -l "$selector" --field-selector "spec.nodeName=$NODE" \
      -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{.metadata.uid}{" "}{.metadata.creationTimestamp}{" "}{.status.containerStatuses[0].state.running.startedAt}{" "}{range .status.conditions[?(@.type=="Ready")]}{.status}{" "}{.lastTransitionTime}{end}{"\n"}{end}' \
      | awk -v old="$old_uid" '$2 != old && $5 == "True" {print; exit}')
    if [[ -n "$row" ]]; then
      break
    fi
    if (( SECONDS >= deadline )); then
      echo "round=$round old=$old_name timeout_waiting_ready" >&2
      exit 1
    fi
    sleep 0.2
  done

  end_ms=$(date +%s%3N)
  elapsed_ms=$((end_ms - start_ms))
  echo "$elapsed_ms" >>"$samples"
  read -r new_name new_uid created_at started_at ready_status ready_at <<<"$row"
  echo "round=$round old=$old_name new=$new_name elapsed_ms=$elapsed_ms created_at=$created_at container_started_at=$started_at ready_at=$ready_at"
done

sort -n "$samples" -o "$samples"
awk '
  { value[NR]=$1; sum+=$1 }
  END {
    p50=int((NR*50+99)/100); p95=int((NR*95+99)/100); p99=int((NR*99+99)/100)
    printf "summary samples=%d min_ms=%d avg_ms=%.2f p50_ms=%d p95_ms=%d p99_ms=%d max_ms=%d\n", NR, value[1], sum/NR, value[p50], value[p95], value[p99], value[NR]
  }
' "$samples"
echo PERF_POD_READY_LATENCY_PASS
REMOTE
