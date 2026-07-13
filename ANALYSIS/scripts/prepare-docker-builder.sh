#!/usr/bin/env bash
set -Eeuo pipefail

ARTIFACT_DIR=${ARTIFACT_DIR:-/root/docker-artifacts}

if [[ ${EUID} -ne 0 ]]; then
  echo "must run as root" >&2
  exit 1
fi

for file in docker-24.0.9.tgz docker-buildx; do
  if [[ ! -s ${ARTIFACT_DIR}/${file} ]]; then
    echo "missing artifact: ${ARTIFACT_DIR}/${file}" >&2
    exit 1
  fi
done

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
tar -C "$tmp_dir" -xzf "${ARTIFACT_DIR}/docker-24.0.9.tgz"
for binary in docker dockerd docker-proxy docker-init; do
  install -m 0755 "$tmp_dir/docker/$binary" "/usr/local/bin/$binary"
done

mkdir -p /root/.docker/cli-plugins /etc/docker
install -m 0755 "${ARTIFACT_DIR}/docker-buildx" /root/.docker/cli-plugins/docker-buildx

cat >/etc/docker/daemon.json <<'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://docker.m.daocloud.io", "https://dockerproxy.net"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "20m", "max-file": "3"},
  "storage-driver": "overlay2"
}
EOF

cat >/etc/systemd/system/docker.service <<'EOF'
[Unit]
Description=Docker Application Container Engine
After=network-online.target firewalld.service containerd.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/dockerd --host=unix:///var/run/docker.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now docker
docker version --format 'client={{.Client.Version}} server={{.Server.Version}}'
docker buildx version
