#!/usr/bin/env bash
# Build the HuaweiCloud Cilium images without writing build data to the system disk.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-local.sh <workdir>

<workdir> must be on a non-root mount and contain an already patched Cilium
source tree at <workdir>/cilium. All Go caches, temporary files, Docker build
data and exported image archives are kept on the same mount.
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

WORKDIR="$(realpath -m "$1")"
SRC="$WORKDIR/cilium"
TAG="${DOCKER_IMAGE_TAG:-v1.12.19-huaweicloud}"
REGISTRY="${DOCKER_REGISTRY:-localhost}"
ACCOUNT="${DOCKER_DEV_ACCOUNT:-huaweicloud}"
AGENT_IMAGE="$REGISTRY/$ACCOUNT/cilium:$TAG"
OPERATOR_IMAGE="$REGISTRY/$ACCOUNT/operator-huaweicloud:$TAG"

require_same_nonroot_mount() {
  local path=$1 source
  source="$(findmnt -T "$path" -n -o SOURCE)"
  if [[ "$source" == "/dev/vda"* || "$source" == "overlay" || "$source" == "rootfs" ]]; then
    echo "refusing to use system disk for build data: $path ($source)" >&2
    exit 1
  fi
  printf '%s' "$source"
}

[[ -d "$SRC/.git" ]] || {
  echo "patched Cilium source not found: $SRC" >&2
  exit 1
}

mkdir -p "$WORKDIR"
WORK_SOURCE="$(require_same_nonroot_mount "$WORKDIR")"
DOCKER_ROOT="$(docker info --format '{{.DockerRootDir}}')"
DOCKER_SOURCE="$(require_same_nonroot_mount "$DOCKER_ROOT")"

if [[ "$WORK_SOURCE" != "$DOCKER_SOURCE" ]]; then
  echo "Docker data-root and workdir must be on the same mounted disk:" >&2
  echo "  workdir: $WORKDIR ($WORK_SOURCE)" >&2
  echo "  Docker:  $DOCKER_ROOT ($DOCKER_SOURCE)" >&2
  exit 1
fi

export GOCACHE="$WORKDIR/.cache/go-build"
export GOPATH="$WORKDIR/.cache/gopath"
export GOTMPDIR="$WORKDIR/.tmp"
export TMPDIR="$WORKDIR/.tmp"
export DOCKER_CONFIG="$WORKDIR/.docker"
export DOCKER_REGISTRY="$REGISTRY"
export DOCKER_DEV_ACCOUNT="$ACCOUNT"
export DOCKER_IMAGE_TAG="$TAG"
export DOCKER_BUILDKIT=1

# A rebuild must not consume previous binaries, Go objects, image archives or
# BuildKit layers. Every removed path is under the validated mounted workdir.
rm -rf "$WORKDIR/.cache" "$WORKDIR/.tmp" "$WORKDIR/.docker" "$WORKDIR/images"
mkdir -p "$GOCACHE" "$GOPATH" "$GOTMPDIR" "$DOCKER_CONFIG" "$WORKDIR/images" "$WORKDIR/logs"

cd "$SRC"
git clean -fdX
docker image rm -f "$AGENT_IMAGE" "$OPERATOR_IMAGE" 2>/dev/null || true
docker builder prune -af

go test -mod=vendor ./pkg/huaweicloud/... 2>&1 | tee "$WORKDIR/logs/test-huaweicloud.log"
go test -mod=vendor -tags=ipam_provider_huaweicloud ./pkg/ipam/... ./operator/... \
  2>&1 | tee "$WORKDIR/logs/test-ipam-operator.log"

make docker-cilium-image 2>&1 | tee "$WORKDIR/logs/build-agent.log"
make docker-operator-huaweicloud-image 2>&1 | tee "$WORKDIR/logs/build-operator.log"

docker save -o "$WORKDIR/images/cilium-v1.12.19-huaweicloud.tar" "$AGENT_IMAGE"
docker save -o "$WORKDIR/images/operator-huaweicloud-v1.12.19-huaweicloud.tar" "$OPERATOR_IMAGE"
sha256sum "$WORKDIR/images"/*.tar > "$WORKDIR/images/SHA256SUMS"
docker image inspect "$AGENT_IMAGE" "$OPERATOR_IMAGE" > "$WORKDIR/images/image-inspect.json"
docker image inspect "$OPERATOR_IMAGE" --format '{{json .Config.Cmd}}' > "$WORKDIR/images/operator-cmd.txt"
docker run --rm "$OPERATOR_IMAGE" /usr/bin/cilium-operator --help > "$WORKDIR/logs/operator-help-generic.log"
docker run --rm "$OPERATOR_IMAGE" /usr/bin/cilium-operator-huaweicloud --help > "$WORKDIR/logs/operator-help-huaweicloud.log"

printf 'SUCCESS\n' > "$WORKDIR/build.status"
