#!/usr/bin/env bash
set -euo pipefail

BASE_COMMIT="d0d0c8792c3420b3a6739fa21e3a182827a0bbc6"
UPSTREAM_URL="https://github.com/cilium/cilium.git"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CACHE="${XDG_CACHE_HOME:-${HOME}/.cache}/huawei-cilium-patches/cilium"
CACHE_DIR="${CILIUM_BASE_DIR:-${DEFAULT_CACHE}}"

refresh_cache() {
  local cache="$1"
  if [[ -d "${cache}/.git" ]]; then
    if ! git -C "${cache}" diff --quiet --ignore-submodules -- ||
       ! git -C "${cache}" diff --cached --quiet --ignore-submodules --; then
      return 1
    fi
    git -C "${cache}" fetch --tags origin
    git -C "${cache}" checkout --detach "${BASE_COMMIT}"
    git -C "${cache}" reset --hard "${BASE_COMMIT}"
    git -C "${cache}" clean -fdx
    return 0
  fi
  return 1
}

if ! refresh_cache "${CACHE_DIR}"; then
  if [[ "${CACHE_DIR}" == "${DEFAULT_CACHE}" ]]; then
    rm -rf "${CACHE_DIR}"
    mkdir -p "$(dirname "${CACHE_DIR}")"
    git clone "${UPSTREAM_URL}" "${CACHE_DIR}"
    refresh_cache "${CACHE_DIR}"
  else
    echo "cache unusable, rebuilding separate temporary Cilium clone" >&2
    CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cilium-cache.XXXXXX")"
    git clone "${UPSTREAM_URL}" "${CACHE_DIR}"
    refresh_cache "${CACHE_DIR}"
  fi
fi

if [[ "$(git -C "${CACHE_DIR}" rev-parse HEAD^{commit})" != "${BASE_COMMIT}" ]]; then
  echo "cache HEAD is not the expected baseline" >&2
  exit 1
fi

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cilium-patch-check.XXXXXX")"
trap 'rm -rf "${WORK_ROOT}"' EXIT
WORK_TREE="${WORK_ROOT}/cilium"

git clone --shared "${CACHE_DIR}" "${WORK_TREE}"
git -C "${WORK_TREE}" checkout --detach "${BASE_COMMIT}"
git -C "${WORK_TREE}" reset --hard "${BASE_COMMIT}"
git -C "${WORK_TREE}" clean -fdx

while IFS= read -r patch || [[ -n "${patch}" ]]; do
  [[ -z "${patch}" || "${patch}" =~ ^# ]] && continue
  echo "checking ${patch}"
  git -C "${WORK_TREE}" apply --check --3way "${PATCH_DIR}/${patch}"
done < "${PATCH_DIR}/series"

(
  cd "${WORK_TREE}"
  "${PATCH_DIR}/apply.sh"
)

test -L "${WORK_TREE}/Documentation/_api"
test -L "${WORK_TREE}/examples/crds"
git -C "${WORK_TREE}" diff --check "${BASE_COMMIT}"..HEAD

echo "patch series check passed: ${WORK_TREE}"
