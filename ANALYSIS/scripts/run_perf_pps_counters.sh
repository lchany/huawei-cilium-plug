#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
CP=${CP:-115.175.145.64}
NS=${NS:-cilium-matrix}
COUNT=${COUNT:-100000}
RUNS=${RUNS:-3}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d /tmp/audit72-pps.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
SSH_CP=(ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$CP")
HOSTS=(
  'node0001 116.63.65.212'
  'node0002 110.41.85.148'
)

k() {
  local remote
  printf -v remote '%q ' kubectl --kubeconfig=/etc/kubernetes/admin.conf -n "$NS" "$@"
  "${SSH_CP[@]}" "$remote"
}

pod_on_node() {
  local set=$1 node=$2
  k get pod -l "app=cilium-matrix,set=$set" --field-selector "spec.nodeName=$node,status.phase=Running" \
    -o 'jsonpath={.items[0].metadata.name}'
  echo
}

host_snapshot() {
  local output=$1
  : >"$output"
  local jobs=()
  for entry in "${HOSTS[@]}"; do
    read -r node host <<<"$entry"
    ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no root@"$host" \
      "NODE=$(printf %q "$node") bash -s" >"$TMP/host.$node" <<'REMOTE' &
set -euo pipefail
read_counter() { cat "/sys/class/net/eth0/statistics/$1"; }
softnet_drop=0
softnet_squeeze=0
while read -r _ dropped squeezed _; do
  softnet_drop=$((softnet_drop + 16#$dropped))
  softnet_squeeze=$((softnet_squeeze + 16#$squeezed))
done </proc/net/softnet_stat
net_rx=$(awk '/NET_RX:/{for(i=2;i<=NF;i++) n+=$i} END{printf "%.0f",n}' /proc/softirqs)
net_tx=$(awk '/NET_TX:/{for(i=2;i<=NF;i++) n+=$i} END{printf "%.0f",n}' /proc/softirqs)
agent=$(crictl stats -o json 2>/dev/null | jq -r '.stats[] | select(.attributes.metadata.name=="cilium-agent") | [.cpu.timestamp,.cpu.usageCoreNanoSeconds.value] | @tsv')
[[ $(printf '%s\n' "$agent" | sed '/^$/d' | wc -l) -eq 1 ]]
printf 'host\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$NODE" "$(read_counter rx_packets)" "$(read_counter tx_packets)" \
  "$(read_counter rx_dropped)" "$(read_counter tx_dropped)" \
  "$(read_counter rx_errors)" "$(read_counter tx_errors)" \
  "$softnet_drop" "$softnet_squeeze" "$net_rx" "$net_tx" "$agent"
REMOTE
    jobs+=("$!")
  done
  for job in "${jobs[@]}"; do wait "$job"; done
  cat "$TMP"/host.node* | sort >"$output"
  [[ $(wc -l <"$output") -eq 2 ]]
}

pod_snapshot() {
  local output=$1 pod values
  shift
  : >"$output"
  for pod in "$@"; do
    values=$(k exec "$pod" -- sh -c 'for f in rx_packets tx_packets rx_dropped tx_dropped rx_errors tx_errors; do cat /sys/class/net/eth0/statistics/$f; done')
    printf 'pod\t%s\t%s\n' "$pod" "$(tr '\n' '\t' <<<"$values" | sed 's/[[:space:]]*$//')" >>"$output"
  done
  [[ $(wc -l <"$output") -eq $# ]]
}

compare_counters() {
  local kind=$1 before=$2 after=$3
  awk -F '\t' -v kind="$kind" '
    NR==FNR { for(i=3;i<=NF;i++) old[$2,i]=$i; next }
    {
      if (!(($2 SUBSEP 3) in old)) exit 2
      printf "counter_kind=%s target=%s",kind,$2
      for(i=3;i<=NF;i++) { delta=$i-old[$2,i]; if(delta<0) exit 3; printf " delta%d=%.0f",i-2,delta }
      print ""
      if (kind=="host" && (($5-old[$2,5])!=0 || ($6-old[$2,6])!=0 || ($7-old[$2,7])!=0 || ($8-old[$2,8])!=0 || ($9-old[$2,9])!=0 || ($10-old[$2,10])!=0)) exit 4
      if (kind=="pod" && (($5-old[$2,5])!=0 || ($6-old[$2,6])!=0 || ($7-old[$2,7])!=0 || ($8-old[$2,8])!=0)) exit 5
    }
  ' "$before" "$after"
}

report_agent_cpu() {
  local before=$1 after=$2
  awk -F '\t' '
    NR==FNR { ts[$2]=$13; cpu[$2]=$14; next }
    {
      dt=$13-ts[$2]; dcpu=$14-cpu[$2]
      if (!(($2) in ts) || dt<=0 || dcpu<0) exit 2
      printf "agent_cpu node=%s cpu_mcores=%.3f\n",$2,dcpu*1000/dt
    }
  ' "$before" "$after"
}

same_source=$(pod_on_node a ecs-4b3b-6555-0001)
same_destination=$(pod_on_node b ecs-4b3b-6555-0001)
cross_destination=$(pod_on_node a ecs-4b3b-6555-0002)
[[ -n "$same_source" && -n "$same_destination" && -n "$cross_destination" ]]

host_snapshot "$TMP/host.before"
pod_snapshot "$TMP/pod.before" "$same_source" "$same_destination" "$cross_destination"
COUNT="$COUNT" RUNS="$RUNS" "$SCRIPT_DIR/run_perf_tcp_udp_rtt.sh" | tee "$TMP/pps.out"
pod_snapshot "$TMP/pod.after" "$same_source" "$same_destination" "$cross_destination"
host_snapshot "$TMP/host.after"

expected=$((RUNS * 4))
[[ $(rg -c 'CLIENT_PASS .* loss=0 .*exchanges_per_sec=' "$TMP/pps.out") -eq "$expected" ]]
rg -q '^PERF_TCP_UDP_RTT_PASS$' "$TMP/pps.out"

awk '
  /CLIENT_PASS/ {
    label=$1
    for(i=1;i<=NF;i++) {
      if($i~/^network=/){split($i,a,"="); network=a[2]}
      if($i~/^exchanges_per_sec=/){split($i,b,"="); rate=b[2]}
    }
    key=label"_"network; n[key]++; value[key,n[key]]=rate
  }
  END {
    for(key in n) {
      for(i=1;i<=n[key];i++) for(j=i+1;j<=n[key];j++) if(value[key,i]>value[key,j]) {t=value[key,i];value[key,i]=value[key,j];value[key,j]=t}
      median=value[key,int((n[key]+1)/2)]
      printf "pps_summary topology_protocol=%s runs=%d min_exchange_pps=%.2f median_exchange_pps=%.2f max_exchange_pps=%.2f median_message_pps=%.2f\n",key,n[key],value[key,1],median,value[key,n[key]],median*2
    }
  }
' "$TMP/pps.out" | sort

compare_counters host "$TMP/host.before" "$TMP/host.after"
compare_counters pod "$TMP/pod.before" "$TMP/pod.after"
report_agent_cpu "$TMP/host.before" "$TMP/host.after"
echo PERF_PPS_COUNTERS_PASS
