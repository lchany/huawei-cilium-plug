#!/usr/bin/env bash
set -euo pipefail

KEY=${KEY:-/root/.ssh/id_ed25519_github_leicheng}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOSTS=(116.63.65.212 110.41.85.148)
SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no)
LOCK_FILE=${CUSTOMER25_LOCK_FILE:-/tmp/huaweicloud-customer25.lock}
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
	echo "another destructive/customer suite is already running (lock: $LOCK_FILE)" >&2
	exit 75
fi

set_features() {
	local settings=$1 host
	for host in "${HOSTS[@]}"; do
		ssh "${SSH_OPTS[@]}" root@"$host" "ethtool -K eth0 $settings"
	done
}

restore() {
	set_features "tx on sg on tso on gso on gro on" >/dev/null 2>&1 || true
}
trap restore EXIT

feature_value() {
	local host=$1 feature=$2
	ssh "${SSH_OPTS[@]}" root@"$host" \
		"ethtool -k eth0 | awk -F': ' '\$1 == \"$feature\" {print \$2}' | awk '{print \$1}'"
}

assert_feature() {
	local feature=$1 expected=$2 host actual
	for host in "${HOSTS[@]}"; do
		actual=$(feature_value "$host" "$feature")
		[[ "$actual" == "$expected" ]]
	done
}

run_state() {
	local state=$1 settings=$2
	shift 2
	restore
	[[ -z "$settings" ]] || set_features "$settings" >/dev/null
	while (( $# )); do
		assert_feature "$1" "$2"
		shift 2
	done
	echo "state=$state feature_assertions=pass"
	CUSTOMER25_LOCK_HELD=1 ROUNDS=0 "$SCRIPT_DIR/run_matrix_recreate_10.sh"
	BYTES_MB=8 "$SCRIPT_DIR/run_perf_rtt_throughput.sh"
}

for host in "${HOSTS[@]}"; do
	features=$(ssh "${SSH_OPTS[@]}" root@"$host" "ethtool -k eth0")
	grep -q '^rx-checksumming: on \[fixed\]$' <<<"$features"
	grep -q '^rx-vlan-offload: off \[fixed\]$' <<<"$features"
	grep -q '^tx-vlan-offload: off \[fixed\]$' <<<"$features"
done

run_state baseline "" \
	generic-receive-offload on generic-segmentation-offload on \
	tx-checksumming on
run_state gro-off "gro off" generic-receive-offload off
run_state gso-off "gso off" generic-segmentation-offload off
run_state checksum-off "tx off" tx-checksumming off
run_state all-software "gro off gso off tso off sg off tx off" \
	generic-receive-offload off generic-segmentation-offload off \
	tcp-segmentation-offload off scatter-gather off tx-checksumming off

restore
assert_feature generic-receive-offload on
assert_feature generic-segmentation-offload on
assert_feature tcp-segmentation-offload on
assert_feature scatter-gather on
assert_feature tx-checksumming on
CUSTOMER25_LOCK_HELD=1 ROUNDS=0 "$SCRIPT_DIR/run_matrix_recreate_10.sh"
trap - EXIT
echo OFFLOAD_MATRIX_PASS
