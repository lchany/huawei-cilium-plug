#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 IMAGE_URL IMAGE_TAR_SHA256 SOURCE_IMAGE TARGET_IMAGE" >&2
  exit 2
fi

image_url=$1
expected_sha=$2
source_image=$3
target_image=$4
archive=/var/tmp/cilium-image-import.tar

rm -f "$archive"
trap 'rm -f "$archive"' EXIT

curl -fsS --retry 3 --connect-timeout 10 -o "$archive" "$image_url"
actual_sha=$(sha256sum "$archive" | cut -d' ' -f1)
if [[ $actual_sha != "$expected_sha" ]]; then
  echo "image checksum mismatch: got $actual_sha, expected $expected_sha" >&2
  exit 1
fi

ctr -n k8s.io images import "$archive"
ctr -n k8s.io images tag --force "$source_image" "$target_image"
ctr -n k8s.io images ls | grep -F "$target_image"
