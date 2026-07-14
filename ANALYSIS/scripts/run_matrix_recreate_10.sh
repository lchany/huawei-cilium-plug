#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE=${CUSTOMER25_LOCK_FILE:-/tmp/huaweicloud-customer25.lock}
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "another destructive/customer suite is already running (lock: $LOCK_FILE)" >&2
  exit 75
fi

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NS=${NS:-cilium-matrix}
ROUNDS=${ROUNDS:-10}
SSH=(ssh -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "root@$CP")

k() {
  local remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf -n "$NS" "$@"
  "${SSH[@]}" "$remote"
}

pod_rows() {
  k get pods -l app=cilium-matrix \
    -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{.status.podIP}{" "}{.spec.nodeName}{"\n"}{end}' \
    | sort
}

wait_matrix() {
  k rollout status daemonset/matrix-a --timeout=180s >/dev/null
  k rollout status daemonset/matrix-b --timeout=180s >/dev/null
  local ready
  ready=$(k get pods -l app=cilium-matrix \
    -o 'jsonpath={range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' \
    | grep -c '^true$')
  [[ "$ready" -eq 8 ]]
}

mesh() {
  local remote
  read -r -d '' remote <<'REMOTE' || true
set -euo pipefail
ns=$1
K=(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n "$ns")
mapfile -t rows < <("${K[@]}" get pods -l app=cilium-matrix \
  -o 'jsonpath={range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}' | sort)
ok=0
total=0
for source_row in "${rows[@]}"; do
  read -r source source_ip <<<"$source_row"
  for destination_row in "${rows[@]}"; do
    read -r _ destination_ip <<<"$destination_row"
    [[ "$source_ip" == "$destination_ip" ]] && continue
    total=$((total + 1))
    if "${K[@]}" exec "$source" -- ping -c 1 -W 2 "$destination_ip" >/dev/null; then
      ok=$((ok + 1))
    else
      echo "mesh failure source=$source destination=$destination_ip" >&2
    fi
  done
done
[[ "$total" -eq 56 && "$ok" -eq 56 ]]
echo "mesh=$ok/$total"
REMOTE
  "${SSH[@]}" "bash -s -- $(printf '%q' "$NS")" <<<"$remote"
}

previous=$(pod_rows)
if [[ "$ROUNDS" -eq 0 ]]; then
  printf 'round=baseline '
  mesh
  echo "MATRIX_RECREATE_SUMMARY PASS rounds=0 mesh_each=56/56"
  exit 0
fi
for round in $(seq 1 "$ROUNDS"); do
  k delete pods -l app=cilium-matrix --wait=false >/dev/null
  wait_matrix
  current=$(pod_rows)
  [[ "$(wc -l <<<"$current")" -eq 8 ]]
  [[ "$current" != "$previous" ]]
  printf 'round=%d ' "$round"
  mesh
  previous=$current
done

echo "MATRIX_RECREATE_SUMMARY PASS rounds=$ROUNDS mesh_each=56/56"
