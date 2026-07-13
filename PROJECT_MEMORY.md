# Project Memory

## Scope

This file records durable facts for the HuaweiCloud Cilium v1.12.19 patch validation project.

## Confirmed Project Facts

- [2026-07-13] Five-machine live environment
  Value: `/home/l30002999/huawei-md.md` defines five fresh HuaweiCloud HCE 2.0 x86_64 ECS instances in `cn-south-1`, AZ7, VPC `192.168.0.0/16`, subnet `192.168.1.0/24`. Their private IPs are `192.168.1.65`, `.93`, `.238`, `.126`, and `.49`; all are mutually reachable and metadata is available. The machines initially have no container runtime, Kubernetes, kubectl, or Helm. Key-based root SSH was installed and verified on all five without storing the supplied password.
  Source: `huawei-md.md` and five-node SSH preflight.
  Status: active

- [2026-07-13] Live topology decision
  Value: Use `ecs-4b3b-6555-0005` (`192.168.1.65`) as control-plane and the remaining four ECS instances as workers for the current acceptance run. All five supplied machines are in AZ7, so genuine cross-AZ cases require additional machines and may be recorded as Block/Skip under the user's exception.
  Source: current environment inventory and user authorization to skip cases requiring new machine purchases or human decisions.
  Status: active

- [2026-07-13] Patch archive and baseline
  Value: `/home/l30002999/huawei-cilium-v1.19.1` contains fourteen patches for upstream Cilium v1.12.19 commit `a1d7fbd43b563c809330b1c3e28165a3e7ff43aa`. Live validation added `0011` CNI watermarks, `0012` explicit NodePort disable under probe mode, `0013` HuaweiCloud endpoint-route source, and `0014` local-Service source semantics.
  Source: repository README, series, and verified Git state.
  Status: active

- [2026-07-13] Test-plan scope
  Value: Analyze existing deployment acceptance and patch code, identify missing tests, and maintain the local plan at `ANALYSIS/HUAWEICLOUD_CILIUM_TEST_PLAN.md`.
  Source: user instruction.
  Status: active

- [2026-07-13] Five-node live validation
  Value: The customer has purchased five HuaweiCloud ECS machines for real-environment validation. The comprehensive scenario catalog is `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_TEST_SCENARIOS.md`, and the executable core cases are in `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_LIVE_TEST_CASES.md`; they assume 1 control-plane plus 4 workers across two AZs unless the actual topology requires 3 plus 2.
  Source: user instruction and current test design.
  Status: active

- [2026-07-13] Policy-routing isolation fix
  Value: Patch `0007-huaweicloud-isolate-SubENI-policy-routing-tables.patch` stops auto-enabling HuaweiCloud compat mode and maps each SubENI to table `10000 + VLAN ID` after validating VLAN 1-4094. It installs isolated routes and cleans stale shared-table rules only after the replacement path is complete. Unit, full routing privileged network-namespace, daemon, CNI compile, and routing vet checks pass on a clean seven-patch replay. Live HuaweiCloud validation remains required by `TC-IPAM-07`.
  Source: clean replay tree `/mnt/disk2t/l30002999/cilium-v1.12.19-routing-replay2` and local test results.
  Status: code-verified-live-pending

## User Corrections

None.

## Invalidated Assumptions

- [2026-07-13] Do not assume the patch archive is a complete Cilium source tree.
  Reason: README explicitly states that patches must be applied to a clean upstream v1.12.19 checkout.
  Superseded by: fixed baseline and `apply.sh` workflow.
  Status: active

## Current Task State

- Current goal: Finalize, audit, commit, and push the completed five-node HuaweiCloud live validation changes.
- Last verified: Kubernetes v1.24.17 has five Ready nodes; Cilium Agent is 5/5 and HuaweiCloud Operator is 1/1. Of the 25 customer data-plane cases, 24 pass with functional and tcpdump source-IP evidence. Case 11 is Block: kube-proxy `externalTrafficPolicy=Cluster` necessarily node-SNATs a local Pod request forwarded through node1 NodePort to a remote backend, producing node1 source rather than the customer's requested Pod source; `Local` cannot select the remote backend. Results are in `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_LIVE_RESULTS.md`. Five-node CiliumNodes use `pre-allocate=4`, and the live small-instance profile uses `min-allocate=8` because HuaweiCloud reports an immutable per-instance IPv4 limit of 8. The original customer value 10 was proven to propagate but cannot become Ready on this hardware; exhaustion returns a controlled `No more IPs available` error.
- Next likely step: Run final patch replay/tests, update patch-count references, commit the archive, and push the branch.
- Blockers: Customer case 11 requires a customer decision because its requested source-IP behavior conflicts with kube-proxy Cluster policy. All five supplied machines are in one AZ, so genuine cross-AZ cases require another-AZ resource. Full L7 Envoy validation is not part of the live image because the required public base layer was unavailable; the tested L3/L4 cases are unaffected.

## Evidence Pointers

- Relevant files: `README.md`, `INSTALL-DEPLOY.md`, `TROUBLESHOOTING.md`, `build-local.sh`, `0001` through `0014` patches, `ANALYSIS/HUAWEICLOUD_CILIUM_TEST_PLAN.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_BOUNDARY_COVERAGE_REVIEW.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_TEST_SCENARIOS.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_LIVE_TEST_CASES.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_CUSTOMER_ACCEPTANCE_CASES.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_LIVE_RESULTS.md`.
- Relevant commands: patch numstat inspection; extraction of added test functions; review of build-local test commands.
- Saved outputs or logs: none; durable conclusions are summarized above.

## Archive Candidates

- Five-node HuaweiCloud Cilium v1.12.19 customer data-plane validation, after final replay and push verification.
