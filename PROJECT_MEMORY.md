# Project Memory

## Scope

This file records durable facts for the HuaweiCloud Cilium v1.12.19 patch validation project.

## Confirmed Project Facts

- [2026-07-14] Agent images must include the matching BPF install tree
  Value: Replacing only `/usr/bin/cilium-agent` leaves the base image's `/var/lib/cilium/bpf` data plane behind. The audited OCI builder now requires both the Agent binary and a Makefile `install-bpf` source directory; runtime acceptance must verify both hashes on every node.
  Source: audit57 image-content mismatch and verified audit58 remediation.
  Status: active

- [2026-07-14] Plugin-focused validation scope
  Rule: Test every scenario that exercises the HuaweiCloud Cilium plugin or its direct dependency chain, including SubENI/IPAM, HuaweiCloud VLAN/BPF datapath, policy routing, CNI configuration, Agent/Operator lifecycle, customer dataplane, upgrade, rollback, recovery, capacity, and plugin observability. Do not spend validation time on unrelated generic Kubernetes or generic Cilium functionality unless it is required as a control or regression oracle for a plugin scenario.
  Scope: HuaweiCloud Cilium five-node validation and the 451-case ledger.
  Source: user instruction.
  Status: active

- [2026-07-14] Build artifact cleanup rule
  Rule: Before each compilation, remove obsolete build outputs that the new build will overwrite. After compilation or packaging, delete superseded temporary builds/images when they are no longer needed; retain an older artifact only when it is still required for rollback, comparison, or evidence.
  Scope: HuaweiCloud Cilium build, image packaging, and deployment workflow.
  Source: user instruction.
  Status: active

- [2026-07-13] Incremental validation workflow
  Rule: During live validation, test continuously; whenever a problem is found, modify the code immediately, compile the affected components, and rerun the failed case plus relevant regression cases before proceeding. Do not defer fixes, builds, or retests until the end.
  Scope: HuaweiCloud Cilium live-test and repair workflow.
  Source: user instruction.
  Status: active

- [2026-07-13] Five-machine live environment
  Value: `/home/l30002999/huawei-md.md` defines five fresh HuaweiCloud HCE 2.0 x86_64 ECS instances in `cn-south-1`, AZ7, VPC `192.168.0.0/16`, subnet `192.168.1.0/24`. Their private IPs are `192.168.1.65`, `.93`, `.238`, `.126`, and `.49`; all are mutually reachable and metadata is available. The machines initially have no container runtime, Kubernetes, kubectl, or Helm. Key-based root SSH was installed and verified on all five without storing the supplied password.
  Source: `huawei-md.md` and five-node SSH preflight.
  Status: active

- [2026-07-13] Live topology decision
  Value: Use `ecs-4b3b-6555-0005` (`192.168.1.65`) as control-plane and the remaining four ECS instances as workers for the current acceptance run. All five supplied machines are in AZ7, so genuine cross-AZ cases require additional machines and may be recorded as Block/Skip under the user's exception.
  Source: current environment inventory and user authorization to skip cases requiring new machine purchases or human decisions.
  Status: active

- [2026-07-14] Patch archive and baseline
  Value: `/home/l30002999/huawei-cilium-v1.19.1` targets upstream Cilium v1.12.19 commit `a1d7fbd43b563c809330b1c3e28165a3e7ff43aa`. Per the corrected delivery requirement, the earliest 14 functional patches remain separate and later validation bug fixes are consolidated in `0015-fix-huaweicloud-consolidate-validation-bug-fixes.patch`; `series` and the directory both contain exactly 15 patches. Audit64 clean replay commit `c5b51a316fc945163b5f9b65c8634f0e14c847ad` and authoritative source `36aa1e6c901b127da6ed3ef277e45fec12820e26` share tree `99bf4f10a82852390846d1b0cc74d0f45527b334`; patch 0015 SHA256 is `38338f0326ce862c12b8896591deb6e859ba85c2d2c95cdade19f161338b9702`. The latest patch/evidence changes remain local until the user explicitly requests another push.
  Source: user correction plus current Git/series inspection.
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

- [2026-07-14] Normal-resource builds are allowed
  Previous wrong assumption: Future builds on the current build machine should default to `GOMAXPROCS=1`, `GOFLAGS=-p=1`, `nice`, and `ionice` because an earlier high-load attempt temporarily affected node readiness.
  Correct value: The user confirmed the current machine has sufficient resources, so subsequent compilations may use normal build parallelism and do not need low-resource throttling by default.
  Future rule: Keep removing overwritten outputs before compilation, but do not impose low-resource build flags unless current measurements show real contention or the user asks for them.
  Source: user correction.
  Status: active

- [2026-07-14] Preserve functional patch history
  Previous wrong assumption: The user wanted all functional and bug-fix work squashed into one delivery patch.
  Correct value: Preserve the original 14 functional patches and consolidate only later test-discovered bug fixes into patch 0015.
  Future rule: Do not replace the 14+1 Git-managed patch layout with a single all-in-one patch.
  Source: user correction.
  Status: active

- [2026-07-13] Resource-dependent boundary cases may be skipped
  Previous wrong assumption: Cross-AZ validation and physically reaching `min-allocate=10` had to be completed before accepting the current five-machine run.
  Correct value: The user approved skipping both because all five purchased machines are in one AZ and the current ECS flavor supports at most 8 SubENI IPv4 addresses.
  Future rule: Record these two cases as environment-limited `Skip`, retain the evidence, and do not treat them as current release failures or request additional machines unless the user reopens them.
  Source: user correction.
  Status: active

## Invalidated Assumptions

- [2026-07-14] Do not describe the delivery as one all-in-one patch.
  Reason: That layout incorrectly erased the original feature-patch structure.
  Superseded by: Exactly 14 original functional patches plus one consolidated bug-fix patch.
  Status: active

- [2026-07-13] Do not treat cross-AZ and physical `min-allocate=10` attainment as mandatory for this run.
  Reason: The user explicitly approved skipping cases that require a different AZ or a larger ECS flavor.
  Superseded by: Preserve configuration-propagation and capacity-limit evidence, but classify the unavailable physical cases as environment-limited `Skip`.
  Status: active

- [2026-07-13] Do not assume the patch archive is a complete Cilium source tree.
  Reason: README explicitly states that patches must be applied to a clean upstream v1.12.19 checkout.
  Superseded by: fixed baseline and `apply.sh` workflow.
  Status: active

## Current Task State

- Current goal: Execute and independently audit all 451 catalogued cases, fixing, rebuilding, deploying, and retesting until no executable case remains Pending or Fail.
- Last verified: The ledger contains 336 Pass, 110 Pending, 5 approved Skip, and 0 recorded Fail. Audit72 completed three 100000-exchange runs for same-node and same-AZ cross-node TCP/UDP. Median request rates were 49427.20/53527.51 PPS on the same node and 14536.28/15416.17 PPS across nodes, with zero loss. Participating host and Pod interfaces had zero new errors/drops, both hosts had zero softnet drop/time-squeeze delta, and participating Agent CPU averaged 2.195–2.220 mcore. Final mesh passed 56/56 with five exact audit64 Agents, zero restarts/severe logs, Operator 1/1, and no probe residue. Audit71's retained audit60 comparison also remains valid. Audit64 source/replay/tree/patch identities remain unchanged, and audit60 remains the rollback image.
- Next likely step: continue executing the remaining P0/P1 recovery, failure-injection, upgrade, capacity, observability, and stability rows, repairing and repeating the complete regression/audit cycle after any defect.
- Immediate live step: continue with the remaining P1 scale and cloud-API rate cases, preserving independent final mesh/identity/route/health checks after each fault or load phase.
- Blockers: Only the two user-approved environment-limit classes may be recorded as Skip: cross-AZ cases and physical `min-allocate=10` attainment. Full L7 Envoy coverage requires an image containing the Envoy layer and remains Pending, not implicitly passed.

## Evidence Pointers

- Relevant files: `README.md`, `INSTALL-DEPLOY.md`, `TROUBLESHOOTING.md`, `build-local.sh`, functional patches 0001-0014 plus consolidated bug-fix patch 0015, `ANALYSIS/HUAWEICLOUD_CILIUM_TEST_PLAN.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_BOUNDARY_COVERAGE_REVIEW.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_TEST_SCENARIOS.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_LIVE_TEST_CASES.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_CUSTOMER_ACCEPTANCE_CASES.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_5_NODE_LIVE_RESULTS.md`, `ANALYSIS/HUAWEICLOUD_CILIUM_451_CASE_EXECUTION.md`, and the three `run_customer25_audit17_*.sh` evidence runners.
- Relevant commands: patch numstat inspection; extraction of added test functions; review of build-local test commands.
- Saved outputs or logs: none; durable conclusions are summarized above.

## Archive Candidates

- Five-node HuaweiCloud Cilium v1.12.19 customer data-plane validation, after final replay and push verification.
- 2026-07-14 patch0035 validates HuaweiCloud request limits (100 SGs; 20 tags; key 128/value 255 Unicode characters). Clean 35-patch replay final commit is `0c22135ba02cef7c50f6388e39df06c2deda5dc9`; full scoped and privileged routing suites passed. Ledger after BAPI-05/BAPI-11 is 211 Pass / 236 Pending / 4 approved Skip / 0 Fail.
- 2026-07-14 patch0036 fixes exact-deadline SubENI wait handling and hardens ECS Count/pagination; BAPI is now fully executed. Clean 36-patch replay final commit `c7dd65ceaadb5cb44e207b7139f8f0740ac9541a`; scoped, privileged, and race suites passed. OBS-07/11 also passed. Ledger: 217 Pass / 230 Pending / 4 approved Skip / 0 Fail.
- 2026-07-14 patches0037-0038 enforce the 100-SG limit across selection paths and follow runtime CiliumNode instance-ID changes without stale fallback. Clean 38-patch replay final commit `b12d2ffa1e3831929360bf75fa1704b66ff25628`; full scoped, privileged, and race suites passed. OBS-06 monitor audit also passed. Ledger: 220 Pass / 227 Pending / 4 approved Skip / 0 Fail.
- 2026-07-14 patches0039-0041 cover dual-stack SubENI publication, nonexistent trunk rejection, and strict Helm Secret DNS validation. Clean 41-patch replay final commit `09c77d128e291e380981a8e082255bb0687c0020`; scoped, privileged, race, and remote Helm clean-chart tests passed. CONN-01 completed 61/61 frames over 30 minutes. Ledger: 225 Pass / 222 Pending / 4 approved Skip / 0 Fail.
- 2026-07-14 isolated live BSEC runtime matrix confirmed Opaque, custom-type, and immutable Secrets all work through secretKeyRef; immutable updates are rejected. Namespace cleaned. Ledger: 227 Pass / 220 Pending / 4 approved Skip / 0 Fail.
- 2026-07-14 user requested a single fix delivery patch. Former 43 patches were squashed into `0001-huaweicloud-add-production-SubENI-IPAM-and-datapath-.patch`; `series` has exactly one entry and old patch files were removed. Single-patch replay final commit `4fe5a9a8b0025285d75930e51de1a9bf57c79cc9`; tree equivalence, scoped, privileged, race, and Helm tests passed. Empty credentials and rate-limit cancellation fixes also passed. Ledger: 229 Pass / 218 Pending / 4 approved Skip / 0 Fail.
- 2026-07-14 BSEC live deletion/update semantics passed in isolated namespaces: running Pods retain injected env after Secret deletion/update, replacements fail on missing Secret or receive updated value. Rotation therefore requires rollout. Ledger: 231 Pass / 216 Pending / 4 approved Skip / 0 Fail.
