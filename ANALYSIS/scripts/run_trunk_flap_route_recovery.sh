#!/usr/bin/env bash
set -euo pipefail

exec 9>/tmp/huaweicloud-customer25.lock
flock -n 9 || exit 75

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
TARGET=${TARGET:-110.41.85.148}
NODE=${NODE:-ecs-4b3b-6555-0002}
TEST_ID=${TEST_ID:-audit64}
PREFIX=${PREFIX:-/tmp/${TEST_ID}-trunk-flap}
K='kubectl --kubeconfig=/etc/kubernetes/admin.conf'
SSH=(-i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8)

cp_run() { ssh "${SSH[@]}" root@"$CP" "$@"; }
target_run() { ssh "${SSH[@]}" root@"$TARGET" "$@"; }

agent_pod=$(cp_run "$K -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=$NODE,status.phase=Running -o jsonpath='{.items[0].metadata.name}'")
restart_before=$(cp_run "$K -n kube-system get pod $agent_pod -o jsonpath='{.status.containerStatuses[0].restartCount}'")
map_before=$(cp_run "$K -n kube-system exec $agent_pod -c cilium-agent -- sh -c 'bpftool -j map dump pinned /sys/fs/bpf/tc/globals/cilium_hwc_vlan_mac | sha256sum'")
echo "agent=$agent_pod restart_before=$restart_before map_before=$map_before"

for round in 1 2 3; do
  unit="${TEST_ID}-trunk-flap-$round"
  echo "round=$round preflight"
  cp_run "$K -n cilium-customer-test exec pod2 -- ping -c 5 -W 2 192.168.1.199" > "${PREFIX}-r${round}-pre.out"

  cp_run "$K -n cilium-customer-test exec pod2 -- ping -c 150 -W 1 -i 0.2 192.168.1.199" > "${PREFIX}-r${round}-during.out" 2>&1 &
  ping_pid=$!
  sleep 1
  target_run "systemd-run --unit=$unit --on-active=2s /bin/sh -c 'ip link set dev eth0 down; sleep 5; ip link set dev eth0 up'" > "${PREFIX}-r${round}-schedule.out"
  wait "$ping_pid" || true

  reachable=false
  for _ in $(seq 1 60); do
    if target_run 'ip -br link show dev eth0; systemctl show -p Result -p ExecMainStatus '"$unit"'.service' > "${PREFIX}-r${round}-service.out" 2>&1; then
      reachable=true
      break
    fi
    sleep 1
  done
  "$reachable"
  grep -q '^Result=success$' "${PREFIX}-r${round}-service.out"
  grep -q '^ExecMainStatus=0$' "${PREFIX}-r${round}-service.out"
  grep -q 'eth0.*UP' "${PREFIX}-r${round}-service.out"

  cp_run "$K -n cilium-customer-test exec pod2 -- ping -c 20 -W 2 192.168.1.199" > "${PREFIX}-r${round}-post.out"
  grep -q '20 packets transmitted, 20 packets received, 0% packet loss' "${PREFIX}-r${round}-post.out"

  received=$(sed -n 's/.*, \([0-9][0-9]*\) packets received,.*/\1/p' "${PREFIX}-r${round}-during.out" | tail -1)
  [[ -n "$received" && "$received" -ge 115 ]]

  recovered=false
  for poll in $(seq 1 60); do
    node_ready=$(cp_run "$K get node $NODE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" 2>/dev/null || true)
    agent_ready=$(cp_run "$K -n kube-system get pod $agent_pod -o jsonpath='{.status.containerStatuses[0].ready}'" 2>/dev/null || true)
    route_audit=$(target_run 'set -eu; rules=$(ip -4 rule show | awk '\''$1 == "111:" {print $3, $NF}'\''); count=$(printf "%s\n" "$rules" | sed "/^$/d" | wc -l); test "$count" -ge 1; while read -r source table; do test -n "$source"; test "$(ip -4 route show table "$table" | wc -l)" -eq 2; ip -4 route show table "$table" | grep -q "^default via 192.168.1.1 dev eth0"; ip -4 route show table "$table" | grep -q "^192.168.1.1 dev eth0 scope link"; done <<< "$rules"; test "$(ip neigh show dev eth0 nud permanent | grep -c "^192.168.1.1 ")" -eq 1; echo "rules=$count routes=complete neighbor=permanent"' 2>/dev/null || true)
    if [[ "$node_ready" == True && "$agent_ready" == true && "$route_audit" == *routes=complete* ]]; then
      recovered=true
      break
    fi
    sleep 1
  done
  "$recovered"

  restart_now=$(cp_run "$K -n kube-system get pod $agent_pod -o jsonpath='{.status.containerStatuses[0].restartCount}'")
  [[ "$restart_now" == "$restart_before" ]]
  map_now=$(cp_run "$K -n kube-system exec $agent_pod -c cilium-agent -- sh -c 'bpftool -j map dump pinned /sys/fs/bpf/tc/globals/cilium_hwc_vlan_mac | sha256sum'")
  [[ "$map_now" == "$map_before" ]]

  summary=$(tail -n 2 "${PREFIX}-r${round}-during.out" | tr '\n' ' ')
  echo "round=$round recovery=PASS node_ready=$node_ready agent_ready=$agent_ready restart=$restart_now received=$received route_audit=[$route_audit] during=[$summary]"
  target_run "systemctl reset-failed $unit.service >/dev/null 2>&1 || true; systemctl stop $unit.timer $unit.service >/dev/null 2>&1 || true"
done

echo TRUNK_FLAP_ROUTE_RECOVERY_SUMMARY_PASS
