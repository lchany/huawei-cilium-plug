#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 BASE_IMAGE NEW_IMAGE BINARY WORK_DIR BPF_SOURCE_DIR" >&2
  exit 2
fi

base_image=$1
new_image=$2
binary=$3
work_dir=$4
bpf_source_dir=$5

command -v ctr >/dev/null
command -v jq >/dev/null
[[ -x $binary ]]
[[ -d $bpf_source_dir ]]
[[ -f $bpf_source_dir/lib/huaweicloud.h ]]

rm -rf "$work_dir"
mkdir -p "$work_dir/layout" "$work_dir/layer/usr/bin"

ctr -n k8s.io images export "$work_dir/base.tar" "$base_image"
tar -C "$work_dir/layout" -xf "$work_dir/base.tar"

manifest_digest=$(jq -er '.manifests[0].digest' "$work_dir/layout/index.json")
manifest_blob="$work_dir/layout/blobs/sha256/${manifest_digest#sha256:}"
config_digest=$(jq -er '.config.digest' "$manifest_blob")
config_blob="$work_dir/layout/blobs/sha256/${config_digest#sha256:}"

install -m 0755 "$binary" "$work_dir/layer/usr/bin/cilium-agent"
mkdir -p "$work_dir/layer/var/lib/cilium/bpf"
cp -a "$bpf_source_dir"/. "$work_dir/layer/var/lib/cilium/bpf/"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$work_dir/layer" -cf "$work_dir/layer.tar" \
  usr/bin/cilium-agent var/lib/cilium/bpf
layer_diff_id="sha256:$(sha256sum "$work_dir/layer.tar" | awk '{print $1}')"
gzip -n -c "$work_dir/layer.tar" > "$work_dir/layer.tar.gz"
layer_digest="sha256:$(sha256sum "$work_dir/layer.tar.gz" | awk '{print $1}')"
layer_size=$(stat -c %s "$work_dir/layer.tar.gz")
cp "$work_dir/layer.tar.gz" "$work_dir/layout/blobs/sha256/${layer_digest#sha256:}"

jq --arg diff_id "$layer_diff_id" \
  --arg created_by "replace cilium-agent and BPF source for ${new_image}" \
  '.rootfs.diff_ids += [$diff_id] |
   .history += [{"created_by":$created_by}]' \
  "$config_blob" > "$work_dir/config.json"
new_config_digest="sha256:$(sha256sum "$work_dir/config.json" | awk '{print $1}')"
new_config_size=$(stat -c %s "$work_dir/config.json")
cp "$work_dir/config.json" "$work_dir/layout/blobs/sha256/${new_config_digest#sha256:}"

jq --arg config_digest "$new_config_digest" \
   --argjson config_size "$new_config_size" \
   --arg layer_digest "$layer_digest" \
   --argjson layer_size "$layer_size" \
  '.config.digest = $config_digest |
   .config.size = $config_size |
   .layers += [{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip",
                "digest":$layer_digest,"size":$layer_size}]' \
  "$manifest_blob" > "$work_dir/manifest.json"
new_manifest_digest="sha256:$(sha256sum "$work_dir/manifest.json" | awk '{print $1}')"
new_manifest_size=$(stat -c %s "$work_dir/manifest.json")
cp "$work_dir/manifest.json" "$work_dir/layout/blobs/sha256/${new_manifest_digest#sha256:}"

jq --arg manifest_digest "$new_manifest_digest" \
   --argjson manifest_size "$new_manifest_size" \
   --arg image "$new_image" \
  '.manifests[0].digest = $manifest_digest |
   .manifests[0].size = $manifest_size |
   .manifests[0].annotations["io.containerd.image.name"] = $image |
   .manifests[0].annotations["org.opencontainers.image.ref.name"] = $image' \
  "$work_dir/layout/index.json" > "$work_dir/index.json"
mv "$work_dir/index.json" "$work_dir/layout/index.json"

tar -C "$work_dir/layout" -cf "$work_dir/image.tar" .
ctr -n k8s.io images import "$work_dir/image.tar"
ctr -n k8s.io images ls | awk -v image="$new_image" '$1 == image { found=1 } END { exit !found }'

printf 'image=%s\n' "$new_image"
printf 'binary_sha256=%s\n' "$(sha256sum "$binary" | awk '{print $1}')"
printf 'image_tar_sha256=%s\n' "$(sha256sum "$work_dir/image.tar" | awk '{print $1}')"
