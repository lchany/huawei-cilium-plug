#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NODE2=${NODE2:-139.159.210.143}
NS=${NS:-cilium-customer-test}
PORT=30234
ssh_opts=(-i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no)
ssh_cp() { ssh "${ssh_opts[@]}" root@"$CP" "$@"; }
ssh_node2() { ssh "${ssh_opts[@]}" root@"$NODE2" "$@"; }
encode() { printf '%s' "$1" | base64 -w0; }
CILIUM_HOST_IP=$(ssh_cp "ip -4 -o addr show dev cilium_host | awk '{print \$4}' | cut -d/ -f1")

start_server() {
  local host=$1 bind=$2
  ssh "${ssh_opts[@]}" root@"$host" "nohup socat TCP-LISTEN:${PORT},bind=${bind},reuseaddr,fork EXEC:/bin/cat >/tmp/customer-${PORT}.log 2>&1 </dev/null & echo \$!"
  sleep 1
}
stop_server() {
  local host=$1 bind=$2
  ssh "${ssh_opts[@]}" root@"$host" "pkill -f '[s]ocat TCP-LISTEN:${PORT},bind=${bind}' || true"
}
pod_rounds() {
  local id=$1 ip=$2 cmd i token out
  cmd="i=1; while [ \$i -le 5 ]; do token='${id}-'\$i; out=\$(printf '%s\\n' \"\$token\" | nc -w 5 '$ip' '$PORT') || exit 30; [ \"\$out\" = \"\$token\" ] || exit 31; i=\$((i+1)); done"
  ssh_cp "echo '$(encode "$cmd")' | base64 -d | kubectl --kubeconfig=/etc/kubernetes/admin.conf -n '$NS' exec -i pod2 -- sh"
  echo "$id PASS 5/5 bidirectional-echo"
}
host_rounds() {
  local id=$1 ip=$2 cmd
  cmd="i=1; while [ \$i -le 5 ]; do token='${id}-'\$i; out=\$(printf '%s\\n' \"\$token\" | socat - TCP:'$ip':'$PORT',connect-timeout=5) || exit 30; [ \"\$out\" = \"\$token\" ] || exit 31; i=\$((i+1)); done"
  ssh_cp "echo '$(encode "$cmd")' | base64 -d | sh"
  echo "$id PASS 5/5 bidirectional-echo"
}

start_server "$CP" 192.168.1.65 >/dev/null
pod_rounds CUST-DP-02 192.168.1.65
stop_server "$CP" 192.168.1.65

start_server "$CP" "$CILIUM_HOST_IP" >/dev/null
pod_rounds CUST-DP-03 "$CILIUM_HOST_IP"
stop_server "$CP" "$CILIUM_HOST_IP"

start_server "$NODE2" 192.168.1.93 >/dev/null
pod_rounds CUST-DP-14 192.168.1.93
host_rounds CUST-DP-23 192.168.1.93
stop_server "$NODE2" 192.168.1.93

echo 'CUSTOMER_TCP_SUMMARY PASS 4/4 each=5/5'
