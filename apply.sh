#!/usr/bin/env bash
set -euo pipefail

BASE_COMMIT="a1d7fbd43b563c809330b1c3e28165a3e7ff43aa"
NO_BASE_CHECK=0

usage() {
  cat <<'EOF'
Usage: apply.sh [--no-base-check]

Run this script from the root of a clean Cilium source repository. Patches are
applied in the order listed in the series file next to this script.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-base-check)
      NO_BASE_CHECK=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERIES_FILE="${PATCH_DIR}/series"

if [[ ! -f "${SERIES_FILE}" ]]; then
  echo "series file not found: ${SERIES_FILE}" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT}" ]]; then
  echo "not inside a git repository" >&2
  exit 1
fi

if [[ "$(cd "${ROOT}" && pwd -P)" != "$(pwd -P)" ]]; then
  echo "apply.sh must be run from the target Cilium repository root: ${ROOT}" >&2
  exit 1
fi

if ! git diff --quiet --ignore-submodules -- || ! git diff --cached --quiet --ignore-submodules --; then
  echo "refusing to apply patches on a dirty worktree" >&2
  exit 1
fi

if [[ "${NO_BASE_CHECK}" -eq 0 ]]; then
  CURRENT_COMMIT="$(git rev-parse HEAD^{commit})"
  if [[ "${CURRENT_COMMIT}" != "${BASE_COMMIT}" ]]; then
    echo "wrong baseline: got ${CURRENT_COMMIT}, expected ${BASE_COMMIT}" >&2
    echo "use --no-base-check only when intentionally rebasing the patch series" >&2
    exit 1
  fi
else
  echo "warning: skipping baseline commit check; clean worktree check remains enforced" >&2
fi

GIT_AM=(git am)
if ! git config user.name >/dev/null || ! git config user.email >/dev/null; then
  GIT_AM=(git -c user.name="lchany" -c user.email="lchany@users.noreply.github.com" am)
fi

while IFS= read -r patch || [[ -n "${patch}" ]]; do
  [[ -z "${patch}" || "${patch}" =~ ^# ]] && continue
  patch_path="${PATCH_DIR}/${patch}"
  if [[ ! -f "${patch_path}" ]]; then
    echo "patch not found: ${patch}" >&2
    exit 1
  fi

  echo "checking ${patch}"
  if ! git apply --check --3way "${patch_path}"; then
    echo "patch check failed: ${patch}" >&2
    exit 1
  fi

  echo "applying ${patch}"
  if ! "${GIT_AM[@]}" --3way "${patch_path}"; then
    echo "patch apply failed: ${patch}" >&2
    exit 1
  fi
done < "${SERIES_FILE}"
