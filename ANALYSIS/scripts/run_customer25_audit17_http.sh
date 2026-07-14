#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE=${CUSTOMER25_LOCK_FILE:-/tmp/huaweicloud-customer25.lock}
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "another customer25 suite is already running (lock: $LOCK_FILE)" >&2
  exit 75
fi

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NODE2=${NODE2:-139.159.210.143}
NS=${NS:-cilium-customer-test}
ssh_cp() { ssh -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP" "$@"; }
k() { ssh_cp "kubectl --kubeconfig=/etc/kubernetes/admin.conf -n '$NS' $*"; }
POD1_IP=$(k get pod pod1 -o "jsonpath='{.status.podIP}'")
POD3_IP=$(k get pod pod3 -o "jsonpath='{.status.podIP}'")
SVC_IP=$(k get svc mynginx-nodeport -o "jsonpath='{.spec.clusterIP}'")
NP=$(k get svc mynginx-nodeport -o "jsonpath='{.spec.ports[0].nodePort}'")
NODE1_IP=192.168.1.65
NODE3_IP=192.168.1.126

ssh_node2() { ssh -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$NODE2" "$@"; }
encode() { printf '%s' "$1" | base64 -w0; }
set_backend() {
  local backend=$1 policy=$2 ip
  k patch svc mynginx-nodeport --type merge -p "'{\"spec\":{\"externalTrafficPolicy\":\"${policy}\",\"selector\":{\"app\":\"customer-web\",\"customer.cilium/backend\":\"${backend}\"}}}'" >/dev/null
  [[ $backend == pod1 ]] && ip=$POD1_IP || ip=$POD3_IP
  for _ in $(seq 1 30); do
    [[ "$(k get endpoints mynginx-nodeport -o "jsonpath='{.subsets[0].addresses[0].ip}'" 2>/dev/null || true)" == "$ip" ]] && return 0
    sleep 1
  done
  echo "endpoint did not converge to ${backend}" >&2
  return 1
}
host_req() { ssh_cp "curl -fsS --connect-timeout 3 --max-time 10 '$1'"; }
node2_req() { ssh_node2 "curl -fsS --connect-timeout 3 --max-time 10 '$1'"; }
run100() {
  local id=$1 expected=$2 fn=$3 url=$4 remote
  remote="i=1; while [ \$i -le 100 ]; do curl -fsS --connect-timeout 3 --max-time 10 '$url' | grep -q '$expected' || exit 21; i=\$((i+1)); done"
  if [[ $fn == host_req ]]; then
    ssh_cp "echo '$(encode "$remote")' | base64 -d | sh"
  else
    ssh_node2 "echo '$(encode "$remote")' | base64 -d | sh"
  fi
  echo "$id PASS 100/100 backend=$expected"
}
run100_pod() {
  local id=$1 expected=$2 pod=$3 url=$4 remote
  remote="i=1; while [ \$i -le 100 ]; do wget -qO- -T 10 '$url' | grep -q '$expected' || exit 21; i=\$((i+1)); done"
  ssh_cp "echo '$(encode "$remote")' | base64 -d | kubectl --kubeconfig=/etc/kubernetes/admin.conf -n '$NS' exec -i '$pod' -- sh"
  echo "$id PASS 100/100 backend=$expected"
}

set_backend pod1 Cluster
run100_pod CUST-DP-01 pod1 pod2 "http://${POD1_IP}:80"
set_backend pod3 Cluster
run100_pod CUST-DP-04 pod3 pod2 "http://${POD3_IP}:80"
run100_pod CUST-DP-05 pod3 pod2 "http://${SVC_IP}:80"
set_backend pod1 Cluster
run100_pod CUST-DP-06 pod1 pod2 "http://${SVC_IP}:80"
run100_pod CUST-DP-07 pod1 pod1 "http://${SVC_IP}:80"
set_backend pod3 Cluster
run100_pod CUST-DP-08 pod3 pod2 "http://${NODE3_IP}:${NP}"
set_backend pod1 Cluster
run100_pod CUST-DP-09 pod1 pod2 "http://${NODE3_IP}:${NP}"
run100_pod CUST-DP-10 pod1 pod1 "http://${NODE3_IP}:${NP}"
set_backend pod3 Cluster
run100_pod CUST-DP-11 pod3 pod2 "http://${NODE1_IP}:${NP}"
set_backend pod1 Local
run100_pod CUST-DP-12 pod1 pod2 "http://${NODE1_IP}:${NP}"
run100_pod CUST-DP-13 pod1 pod1 "http://${NODE1_IP}:${NP}"
run100 CUST-DP-15 pod1 host_req "http://${POD1_IP}:80"
run100 CUST-DP-16 pod3 host_req "http://${POD3_IP}:80"
set_backend pod3 Cluster
run100 CUST-DP-17 pod3 host_req "http://${SVC_IP}:80"
set_backend pod1 Cluster
run100 CUST-DP-18 pod1 host_req "http://${SVC_IP}:80"
set_backend pod3 Cluster
run100 CUST-DP-19 pod3 host_req "http://${NODE3_IP}:${NP}"
set_backend pod1 Cluster
run100 CUST-DP-20 pod1 host_req "http://${NODE3_IP}:${NP}"
set_backend pod3 Cluster
run100 CUST-DP-21 pod3 host_req "http://${NODE1_IP}:${NP}"
set_backend pod1 Local
run100 CUST-DP-22 pod1 host_req "http://${NODE1_IP}:${NP}"
run100 CUST-DP-24 pod1 node2_req "http://${NODE1_IP}:${NP}"
set_backend pod3 Cluster
run100 CUST-DP-25 pod3 node2_req "http://${NODE1_IP}:${NP}"

set_backend pod3 Cluster
echo "CUSTOMER_HTTP_SUMMARY PASS 21/21 each=100/100"
