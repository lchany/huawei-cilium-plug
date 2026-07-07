# HuaweiCloud Cilium Patch Series

This branch is an archive-only patch series for the HuaweiCloud/SubENI delta
against upstream Cilium `v1.19.1`.

Baseline:

- tag: `v1.19.1`
- peeled commit: `d0d0c8792c3420b3a6739fa21e3a182827a0bbc6`

The patch series is listed in `series` and is intended to be applied to a clean
Cilium checkout at the baseline commit.

## Apply

From the target Cilium repository root:

```bash
/path/to/huawei-cilium-v1.19.1/apply.sh
```

`apply.sh` requires a clean worktree and verifies the baseline commit by
default. `--no-base-check` skips only the commit check; it still refuses dirty
worktrees.

## Check

From this repository:

```bash
./check.sh
```

`check.sh` prepares a clean temporary baseline worktree, checks each patch with
`git apply --check --3way`, then applies the series with `apply.sh`.

Set `CILIUM_BASE_DIR=/path/to/cilium-cache` to use an existing Cilium clone as
the cache source.

Runtime validation notes live in `runtime-checklist.md`; that file is a patch
management document and is not part of the generated patch payload by default.
