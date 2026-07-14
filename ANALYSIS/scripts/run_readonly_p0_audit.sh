#!/usr/bin/env bash
set -euo pipefail

SSH_SUITE=${SSH_SUITE:-/root/.codex/skills/ssh-connection/connect/scripts/ssh-exec.sh}
OUT=${1:-/tmp/huaweicloud-readonly-p0-audit.txt}
profiles=(huawei-cp huawei-w1 huawei-w2 huawei-w3 huawei-w4)

rexec() { bash "$SSH_SUITE" "$1" "$2"; }
section() { printf '\n### %s\n' "$1"; }

exec > >(tee "$OUT") 2>&1

section "control-plane inventory"
rexec huawei-cp 'set -euo pipefail; export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl version --short
kubectl get nodes -o custom-columns=NAME:.metadata.name,ROLES:.metadata.labels.node-role\\.kubernetes\\.io/control-plane,READY:.status.conditions[-1].status,INTERNAL_IP:.status.addresses[0].address,KERNEL:.status.nodeInfo.kernelVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion
kubectl -n kube-system get ds cilium -o custom-columns=DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady,IMAGE:.spec.template.spec.containers[0].image
kubectl -n kube-system get deploy cilium-operator -o custom-columns=DESIRED:.spec.replicas,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image
kubectl get ciliumnodes -o custom-columns=NAME:.metadata.name,INSTANCE:.spec.instance-id,PREALLOC:.spec.ipam.pre-allocate,MINALLOC:.spec.ipam.min-allocate,POOL:.status.ipam.operator-status.error
kubectl -n kube-system get cm cilium-config -o jsonpath="ipam={.data.ipam}{\"\\n\"}tunnel={.data.tunnel}{\"\\n\"}enable-ipv4={.data.enable-ipv4}{\"\\n\"}enable-ipv6={.data.enable-ipv6}{\"\\n\"}enable-node-port={.data.enable-node-port}{\"\\n\"}kube-proxy-replacement={.data.kube-proxy-replacement}{\"\\n\"}identity-allocation-mode={.data.identity-allocation-mode}{\"\\n\"}"'

section "agent and operator health"
rexec huawei-cp 'set -euo pipefail; export KUBECONFIG=/etc/kubernetes/admin.conf
for p in $(kubectl -n kube-system get pod -l k8s-app=cilium -o name); do printf "%s " "$p"; kubectl -n kube-system exec "$p" -- cilium status --brief; done
op=$(kubectl -n kube-system get pod -l io.cilium/app=operator -o name | head -1)
kubectl -n kube-system get "$op" -o jsonpath="operator={.metadata.name} ready={.status.containerStatuses[0].ready} command={.spec.containers[0].command} args={.spec.containers[0].args}{\"\\n\"}"
kubectl -n kube-system exec "$op" -- /usr/bin/cilium-operator --version
kubectl -n kube-system exec "$op" -- /usr/bin/cilium-operator-huaweicloud --version
echo operator-binaries=both-executable'

section "secret shape and leak scans"
rexec huawei-cp 'set -euo pipefail; export KUBECONFIG=/etc/kubernetes/admin.conf
sec=$(kubectl -n kube-system get deploy cilium-operator -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"CILIUM_HUAWEI_CLOUD_ACCESS_KEY\")].valueFrom.secretKeyRef.name}")
test -n "$sec"
printf "referenced-secret=%s keys=" "$sec"
kubectl -n kube-system get secret "$sec" -o json | jq -r ".data|keys|join(\",\")"
test -z "$(kubectl -n kube-system get deploy cilium-operator -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"CILIUM_HUAWEI_CLOUD_ACCESS_KEY\")].value}")" && echo access-key-inline=absent
test -z "$(kubectl -n kube-system get deploy cilium-operator -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"CILIUM_HUAWEI_CLOUD_SECRET_KEY\")].value}")" && echo secret-key-inline=absent
if kubectl -n kube-system get cm,deploy,ds,sts -o yaml | grep -Eiq "(access[_-]?key|secret[_-]?key):[[:space:]]+[A-Za-z0-9/+]{12,}"; then echo rendered-secret-scan=FAIL; exit 1; else echo rendered-secret-scan=clean; fi
if kubectl -n kube-system logs deploy/cilium-operator --tail=500 | grep -Eiq "(AKIA|HUAWEICLOUD_ACCESS_KEY=|HUAWEICLOUD_SECRET_KEY=)"; then echo log-secret-scan=FAIL; exit 1; else echo log-secret-scan=clean; fi'

for p in "${profiles[@]}"; do
  section "$p host preflight"
  rexec "$p" 'set -euo pipefail
printf "host="; hostname
printf "arch="; uname -m
printf "kernel="; uname -r
printf "cgroup="; stat -fc %T /sys/fs/cgroup
printf "runtime="; crictl --runtime-endpoint unix:///run/containerd/containerd.sock version | awk "/RuntimeName|RuntimeVersion/{printf \"%s=%s \",\$1,\$2} END{print \"\"}"
printf "clock="; timedatectl show -p NTPSynchronized -p TimeUSec --value | paste -sd, -
printf "resolvers="; awk "/^nameserver/{printf \"%s,\",\$2} END{print \"\"}" /etc/resolv.conf
printf "default-route="; ip -4 route show default
printf "links="; ip -br link | tr "\\n" ";"; echo
printf "vlan-links="; ip -d -o link show type vlan | wc -l
printf "tools="; for x in ip tcpdump ethtool conntrack; do command -v "$x" >/dev/null && printf "%s=present," "$x" || printf "%s=missing," "$x"; done; echo
printf "metadata-instance="; curl -fsS --max-time 3 http://169.254.169.254/openstack/latest/meta_data.json | jq -c "{uuid,availability_zone,name}" 
printf "metadata-network-count="; curl -fsS --max-time 3 http://169.254.169.254/openstack/latest/network_data.json | jq ".networks|length"
printf "policy-rules="; ip -4 rule show | grep -Ec "lookup (main|1[0-4][0-9]{3})"
printf "vlan-routes="; ip -4 route show table all | grep -Ec "table 1[0-4][0-9]{3}" || true
printf "cilium-image="; ctr -n k8s.io images ls -q | grep -x "localhost/huaweicloud/cilium:v1.12.19-huaweicloud"
platform=$(ctr -n k8s.io images ls | grep "^localhost/huaweicloud/cilium:v1.12.19-huaweicloud " | grep -oE "linux/[a-z0-9]+" | head -1)
test -n "$platform"; printf "cilium-platform=%s\\n" "$platform"'
done

section "endpoint readiness"
rexec huawei-cp 'set -euo pipefail; export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl -n kube-system exec ds/cilium -- cilium endpoint list -o json | jq -r "group_by(.status.state)|map(\"\(.[0].status.state)=\(length)\")|join(\",\")"
kubectl -n cilium-customer-test get pod -o wide
kubectl -n cilium-customer-test get svc,endpoints'

echo "READONLY_P0_AUDIT=PASS"
