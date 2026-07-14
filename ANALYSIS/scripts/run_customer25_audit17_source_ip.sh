#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NODE2=${NODE2:-139.159.210.143}
NODE4=${NODE4:-110.41.85.148}
NS=${NS:-cilium-customer-test}
ssh_opts=(-i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no)
ssh_cp() { ssh "${ssh_opts[@]}" root@"$CP" "$@"; }
ssh_node2() { ssh "${ssh_opts[@]}" root@"$NODE2" "$@"; }
k() { ssh_cp "kubectl --kubeconfig=/etc/kubernetes/admin.conf -n '$NS' $*"; }
POD1_IP=$(k get pod pod1 -o "jsonpath='{.status.podIP}'")
POD2_IP=$(k get pod pod2 -o "jsonpath='{.status.podIP}'")
POD3_IP=$(k get pod pod3 -o "jsonpath='{.status.podIP}'")
SVC_IP=$(k get svc mynginx-nodeport -o "jsonpath='{.spec.clusterIP}'")
NP=$(k get svc mynginx-nodeport -o "jsonpath='{.spec.ports[0].nodePort}'")
NODE1_IP=192.168.1.65
NODE2_IP=192.168.1.93
NODE3_IP=192.168.1.126
CILIUM_HOST_IP=$(ssh_cp "ip -4 -o addr show dev cilium_host | awk '{print \$4}' | cut -d/ -f1")

set_backend() {
  local backend=$1 policy=$2 ip
  k patch svc mynginx-nodeport --type merge -p "'{\"spec\":{\"externalTrafficPolicy\":\"${policy}\",\"selector\":{\"app\":\"customer-web\",\"customer.cilium/backend\":\"${backend}\"}}}'" >/dev/null
  [[ $backend == pod1 ]] && ip=$POD1_IP || ip=$POD3_IP
  for _ in $(seq 1 30); do
    [[ "$(k get endpoints mynginx-nodeport -o "jsonpath='{.subsets[0].addresses[0].ip}'" 2>/dev/null || true)" == "$ip" ]] && return
    sleep 1
  done
  return 1
}
request() {
  local source=$1 url=$2 expected=$3 out
  case $source in
    pod1|pod2) out=$(k exec "$source" -- wget -qO- -T 10 "$url") ;;
    node1) out=$(ssh_cp "curl -fsS --connect-timeout 3 --max-time 10 '$url'") ;;
    node2) out=$(ssh_node2 "curl -fsS --connect-timeout 3 --max-time 10 '$url'") ;;
  esac
  [[ $out == *"$expected"* ]]
}
assert_source() {
  local id=$1 target=$2 dst=$3 expected_src=$4 source=$5 url=$6 backend=$7 policy=$8 log
  log="/tmp/${id}.tcpdump"
  set_backend "$backend" "$policy"
  iface=$(ssh "${ssh_opts[@]}" root@"$target" "ip route get '$dst' | awk '{for(i=1;i<=NF;i++) if(\$i==\"dev\"){print \$(i+1); exit}}'")
  [[ -n $iface ]]
  ssh "${ssh_opts[@]}" root@"$target" "rm -f '$log'; nohup timeout 10 tcpdump -nn -l -i '$iface' 'tcp dst port 80 and dst host $dst and tcp[tcpflags] & tcp-syn != 0' -c 1 >'$log' 2>&1 </dev/null &"
  sleep 1
  request "$source" "$url" "$backend"
  for _ in $(seq 1 20); do
    line=$(ssh "${ssh_opts[@]}" root@"$target" "cat '$log' 2>/dev/null || true")
    if grep -F "$expected_src." <<<"$line" | grep -Fq " > $dst.80:"; then
      printf '%s PASS source=%s dst=%s\n' "$id" "$expected_src" "$dst"
      return 0
    fi
    sleep 0.25
  done
  echo "$id FAIL expected-source=$expected_src capture=$line" >&2
  return 1
}

assert_source CUST-DP-01 "$CP" "$POD1_IP" "$POD2_IP" pod2 "http://${POD1_IP}:80" pod1 Cluster
assert_source CUST-DP-04 "$NODE4" "$POD3_IP" "$POD2_IP" pod2 "http://${POD3_IP}:80" pod3 Cluster
assert_source CUST-DP-05 "$NODE4" "$POD3_IP" "$POD2_IP" pod2 "http://${SVC_IP}:80" pod3 Cluster
assert_source CUST-DP-06 "$CP" "$POD1_IP" "$POD2_IP" pod2 "http://${SVC_IP}:80" pod1 Cluster
assert_source CUST-DP-07 "$CP" "$POD1_IP" 169.254.42.1 pod1 "http://${SVC_IP}:80" pod1 Cluster
assert_source CUST-DP-08 "$NODE4" "$POD3_IP" "$NODE3_IP" pod2 "http://${NODE3_IP}:${NP}" pod3 Cluster
assert_source CUST-DP-09 "$CP" "$POD1_IP" "$NODE3_IP" pod2 "http://${NODE3_IP}:${NP}" pod1 Cluster
assert_source CUST-DP-10 "$CP" "$POD1_IP" "$NODE3_IP" pod1 "http://${NODE3_IP}:${NP}" pod1 Cluster
assert_source CUST-DP-11 "$NODE4" "$POD3_IP" "$POD2_IP" pod2 "http://${NODE1_IP}:${NP}" pod3 Cluster
assert_source CUST-DP-12 "$CP" "$POD1_IP" "$POD2_IP" pod2 "http://${NODE1_IP}:${NP}" pod1 Local
assert_source CUST-DP-13 "$CP" "$POD1_IP" 169.254.42.1 pod1 "http://${NODE1_IP}:${NP}" pod1 Local
assert_source CUST-DP-15 "$CP" "$POD1_IP" "$CILIUM_HOST_IP" node1 "http://${POD1_IP}:80" pod1 Cluster
assert_source CUST-DP-16 "$NODE4" "$POD3_IP" "$NODE1_IP" node1 "http://${POD3_IP}:80" pod3 Cluster
assert_source CUST-DP-17 "$NODE4" "$POD3_IP" "$NODE1_IP" node1 "http://${SVC_IP}:80" pod3 Cluster
assert_source CUST-DP-18 "$CP" "$POD1_IP" "$CILIUM_HOST_IP" node1 "http://${SVC_IP}:80" pod1 Cluster
assert_source CUST-DP-19 "$NODE4" "$POD3_IP" "$NODE3_IP" node1 "http://${NODE3_IP}:${NP}" pod3 Cluster
assert_source CUST-DP-20 "$CP" "$POD1_IP" "$NODE3_IP" node1 "http://${NODE3_IP}:${NP}" pod1 Cluster
assert_source CUST-DP-21 "$NODE4" "$POD3_IP" "$NODE1_IP" node1 "http://${NODE1_IP}:${NP}" pod3 Cluster
assert_source CUST-DP-22 "$CP" "$POD1_IP" "$CILIUM_HOST_IP" node1 "http://${NODE1_IP}:${NP}" pod1 Local
assert_source CUST-DP-24 "$CP" "$POD1_IP" "$NODE2_IP" node2 "http://${NODE1_IP}:${NP}" pod1 Local
assert_source CUST-DP-25 "$NODE4" "$POD3_IP" "$NODE1_IP" node2 "http://${NODE1_IP}:${NP}" pod3 Cluster

set_backend pod3 Cluster
echo 'CUSTOMER_SOURCE_IP_SUMMARY PASS 21/21'
