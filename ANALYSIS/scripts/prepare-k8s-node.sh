#!/usr/bin/env bash
set -Eeuo pipefail

KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.24.17}
CONTAINERD_VERSION=${CONTAINERD_VERSION:-1.6.36}
RUNC_VERSION=${RUNC_VERSION:-v1.1.15}
CNI_PLUGINS_VERSION=${CNI_PLUGINS_VERSION:-v1.1.1}
CRICTL_VERSION=${CRICTL_VERSION:-v1.24.2}
ARTIFACT_DIR=${ARTIFACT_DIR:-/root/k8s-artifacts}

if [[ ${EUID} -ne 0 ]]; then
  echo "must run as root" >&2
  exit 1
fi

NODE_IP=${NODE_IP:-$(ip -4 route get 169.254.169.254 | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')}
if [[ -z ${NODE_IP} ]]; then
  echo "unable to determine NODE_IP" >&2
  exit 1
fi

dnf install -y curl tar gzip socat conntrack-tools iproute iptables ethtool jq >/tmp/k8s-dnf-install.log 2>&1 || {
  tail -20 /tmp/k8s-dnf-install.log >&2
  exit 1
}

swapoff -a
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/tmp/k8s-sysctl.log

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

get_artifact() {
  local name=$1
  local url=$2
  local output=$3
  if [[ -s ${ARTIFACT_DIR}/${name} ]]; then
    cp "${ARTIFACT_DIR}/${name}" "$output"
  else
    curl -fsSL --retry 5 --retry-delay 2 -o "$output" "$url"
  fi
}

get_artifact "containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz" \
  "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz" \
  "$tmp_dir/containerd.tgz"
tar -C /usr/local -xzf "$tmp_dir/containerd.tgz"

get_artifact "runc.amd64" \
  "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.amd64" \
  /usr/local/sbin/runc
chmod 0755 /usr/local/sbin/runc

mkdir -p /opt/cni/bin
get_artifact "cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz" \
  "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz" \
  "$tmp_dir/cni.tgz"
tar -C /opt/cni/bin -xzf "$tmp_dir/cni.tgz"

get_artifact "crictl-${CRICTL_VERSION}-linux-amd64.tar.gz" \
  "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz" \
  "$tmp_dir/crictl.tgz"
tar -C /usr/local/bin -xzf "$tmp_dir/crictl.tgz"

for binary in kubeadm kubelet kubectl; do
  get_artifact "${binary}-${KUBERNETES_VERSION}" \
    "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/${binary}" \
    "/usr/local/bin/${binary}"
  chmod 0755 "/usr/local/bin/${binary}"
done

mkdir -p /etc/containerd
/usr/local/bin/containerd config default >/etc/containerd/config.toml
sed -ri 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -ri 's#sandbox_image = ".*"#sandbox_image = "registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.7"#' /etc/containerd/config.toml

cat >/etc/systemd/system/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/kubelet.service <<'EOF'
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/
Wants=network-online.target
After=network-online.target containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /etc/systemd/system/kubelet.service.d /etc/sysconfig /var/lib/kubelet
cat >/etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<'EOF'
[Service]
Environment="KUBELET_KUBEADM_ARGS="
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/sysconfig/kubelet
ExecStart=
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
printf 'KUBELET_EXTRA_ARGS=--node-ip=%s\n' "$NODE_IP" >/etc/sysconfig/kubelet

cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

systemctl daemon-reload
systemctl enable --now containerd
systemctl enable --now kubelet

containerd --version
runc --version | head -1
kubeadm version -o short
kubelet --version
crictl version | sed -n '1,6p'
printf 'prepared node=%s ip=%s\n' "$(hostname)" "$NODE_IP"
