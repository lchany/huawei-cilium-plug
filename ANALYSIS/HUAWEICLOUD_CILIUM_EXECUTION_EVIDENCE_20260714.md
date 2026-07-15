# HuaweiCloud Cilium execution evidence — 2026-07-14

This file records concise, credential-free evidence from the five-node run. Raw
command output was reviewed during execution; only stable conclusions are kept
here. A failed or methodologically invalid probe is never counted as Pass.

## Build and archive

- Wrong baseline was rejected with exit code 1 without changing HEAD.
- A forced `git am` failure was aborted; the worktree returned clean and all 15
  patches then replayed successfully (`replay_commits=15`).
- `make -C bpf clean all` completed with the HuaweiCloud host option in the
  compile matrix and zero compiler errors.
- Agent, CNI, generic Operator, and HuaweiCloud Operator binaries all rebuilt
  successfully in the pinned builder image.
- Every node is `x86_64`; every deployed Agent image reports `linux/amd64`.
- The running Operator command is `cilium-operator-huaweicloud`; both
  `/usr/bin/cilium-operator` and `/usr/bin/cilium-operator-huaweicloud` execute
  and report Cilium 1.12.19.

## Five-node preflight and installation

- Kubernetes is v1.24.17; five nodes are Ready, with one control-plane and four
  workers. All five are in `cn-south-1g`, so cross-AZ is the approved Skip.
- All nodes run HCE2 kernel `5.10.0-182...`, containerd 1.6.36, synchronized
  clocks, configured resolvers, and the required network diagnostic tools.
- Metadata returned a non-empty UUID and AZ on every node. HuaweiCloud IPAM
  discovered five instance IDs and active SubENI pools.
- Agent is 5/5 healthy and Operator is 1/1 Ready. Five CiliumNodes retain
  `pre-allocate=4`, `min-allocate=8`, and stable instance IDs.
- The CNI JSON and CNI binary are valid on all five nodes. The five JSON files
  have the same SHA256 `af66deee...e7490`.
- All 14 shipped CRDs passed Kubernetes server-side dry-run.
- Helm lint passed. HuaweiCloud-enabled rendering referenced a custom external
  Secret exactly twice, disabled rendering had no HuaweiCloud credential env,
  an empty `existingSecret` was rejected, and rendered output contained no
  credential values.
- Missing Secret, missing AK key, and missing SK key each produced the expected
  `CreateContainerConfigError`; the temporary namespace was removed.
- Running resources and the last 500 Operator log lines passed the credential
  leakage scan. Only Secret key names, never values, were recorded.

## IPAM, routing, data plane, and recovery

- Two DaemonSets created eight unique SubENI Pod IPs concurrently across four
  workers: `8/8 Running`, two per worker.
- Eight Pods completed a full ICMP mesh: `56/56` paths passed.
- All eight Pod source rules used isolated tables in 10001–14094. Every table
  had the expected default and gateway route; two Pods on each worker used
  distinct tables.
- Deleting an entire four-Pod DaemonSet removed all four old endpoints and all
  four BPF endpoint-map entries. Reapplying it restored `4/4` endpoints/maps.
- Deleting one Agent restored both local matrix endpoints and connectivity.
  A subsequent full DaemonSet rollout ended with Agent `5/5 OK` and another
  `56/56` endpoint mesh.
- Deleting the Operator produced a new Ready Pod; five CiliumNode identities and
  watermarks remained byte-for-byte stable and traffic remained healthy.
- ClusterIP TCP and UDP and NodePort TCP and UDP all returned application-level
  responses using the stable `agnhost netexec` fixture.
- Cluster DNS UDP, an explicit DNS-over-TCP query (108 response bytes), an
  eight-address Headless Service, and public DNS all passed.
- With the explicit external-egress prerequisite (SNAT only for destinations
  outside `192.168.0.0/16`), public HTTPS passed from `8/8` matrix Pods. VPC
  customer paths remain excluded from that rule.
- Interface MTU was 1500. Payload 1472 with DF passed; payload 1473 with DF was
  rejected locally with `message too long, mtu=1500`, proving the PMTU boundary.

## Network policy

- Under the customer value `policy-audit-mode=true`, default deny left traffic
  allowed and endpoints reported `Disabled (Audit)`, as designed.
- The test temporarily set audit mode to false and rolled all Agents. Default
  deny then blocked same-node and cross-node HTTP/UDP `4/4`.
- Label-based L3 plus TCP/UDP port allows passed same-node and cross-node `4/4`;
  a wrong label and an unlisted port remained blocked.
- DNS-only egress allowed cluster DNS and blocked other egress.
- All policies were removed, `policy-audit-mode=true` was restored, Agents
  returned `5/5 OK`, and baseline connectivity passed.
- After all matrix changes and policy-mode rollouts, the 21 customer HTTP
  scenarios were rerun and each again passed `100/100`, including T11 and both
  `169.254.42.1` hairpin cases.

## Invalid probes discarded

- A single-Pod endpoint deletion probe was discarded because IPAM immediately
  reused the same IP and a negated shell assertion was not reliable.
- BusyBox persistent UDP `nc` was discarded after it proved unreliable across
  repeated requests; the affected Service and policy tests were rerun from
  baseline with `agnhost netexec`.

## Metadata boundary batch

- Added direct `httptest` coverage for empty required fields, malformed AZ
  forms, empty and placeholder network links, HTTP error statuses, null/empty
  JSON, unknown fields, response-size limits, and cancelled contexts.
- Fixed silent AZ truncation, empty leading-link handling, and the prior 1 MiB
  response truncation behavior. The focused metadata package test passed.
- Link-order invariance now passes synthetically using MAC-based selection;
  true multi-NIC trunk identity remains Pending until exercised on real NICs.

## Patch 0016 metadata and API boundary batch

- Live metadata on the control-plane and a worker reports a link MAC equal to
  the configured host `eth0` MAC. Patch 0016 now resolves the trunk port by
  configured-interface MAC and is invariant to metadata link order; the true
  multi-NIC real-machine case remains Pending.
- Added response/request validation for create counts, required IDs, SubENI
  identity/IP/MAC/VLAN/subnet/parent fields, batch cardinality and uniqueness,
  subnet CIDR/gateway consistency, router-port ambiguity, and flavor limits.
- Rollback now attempts every unique created ID and retains every delete error.
  Focused tests prove first gateway failure and last tag failure both roll back
  all returned resources.
- Pagination now rejects repeated markers across SubENI, subnet, VPC, security
  group and server listings. Capacity pagination passed 0/1/1999/2000/2001
  boundaries and rejects nil, duplicate, empty-ID, negative and non-advancing
  responses.
- Patch 0016 applied cleanly after patches 0001-0015 in the final replay tree.
  The full HuaweiCloud/IPAM/Operator tagged Go test set passed from that replay.

## audit17 clean build and five-node regression

- Replayed patches 0001-0017 from upstream `a1d7fbd43` in a fresh worktree and
  passed the full tagged HuaweiCloud/IPAM/Operator/NodeDiscovery suite plus
  race tests for `pkg/huaweicloud/api` and `pkg/huaweicloud/metadata`.
- Built linux/amd64 Agent and HuaweiCloud Operator images. Their exported tar
  SHA256 values are `dbc6421e5f60737827378288457b613a7add988d60a2b165886382c570ed6ad3`
  and `d92bb1677068c9aaf82f3e4b44a018060e6ec8bb216d064afaab26610042d490`.
- Imported audit17 on all five nodes, rolled the Agent DaemonSet and Operator
  Deployment, and verified Agent `5/5 OK`, Operator `1/1 Ready`, with zero
  container restarts.
- Reran all customer data-plane cases after that rollout. The 21 HTTP cases
  each passed `100/100`, the four bidirectional TCP cases each passed `5/5`,
  and 21 independent SYN captures on the destination Pod veth proved every
  strict source-IP contract, including both `169.254.42.1` hairpin paths.
- Reran the eight-Pod full mesh after audit17: all `56/56` directed paths
  passed. All five agents returned `cilium status --brief = OK`, and all 13
  workload endpoints remained represented by CiliumEndpoint resources.
- Reusable evidence runners are
  `ANALYSIS/scripts/run_customer25_audit17_http.sh`,
  `ANALYSIS/scripts/run_customer25_audit17_tcp.sh`, and
  `ANALYSIS/scripts/run_customer25_audit17_source_ip.sh`.

## Patch 0018 subnet-selection boundary batch

- Found that equal-capacity automatic candidates depended on randomized Go map
  iteration and explicit candidates were selected by maximum capacity instead
  of configured order. Patch 0018 makes automatic ties deterministic by subnet
  ID and makes explicit lists honor their configured order.
- Non-positive allocation requests now select no subnet. Empty, missing,
  duplicate, cross-VPC, cross-AZ and insufficient explicit entries are skipped
  safely before the first valid capacity-sufficient entry is selected.
- Unit tests cover negative/zero allocation, lower/equal/higher capacity,
  100 deterministic tie iterations, explicit order, invalid entries and
  ordered fallback. A new clean upstream replay applied all 18 patches, and the
  full tagged HuaweiCloud/IPAM/Operator/NodeDiscovery suite passed.

## Patch 0019 security-group and capacity-set audit

- Added V1/V2 capacity versus V3 Virsubnet set-mismatch coverage. A V3 subnet
  without capacity now proves a hard failure, while an orphan capacity entry is
  ignored without contaminating the returned subnet map.
- Found that configured security-group tags with zero matches silently fell
  through to trunk inheritance, which could broaden permissions. Patch 0019
  makes this path fail closed.
- Explicit IDs, tag results, trunk groups and historical SubENI fallback groups
  are normalized by trimming, dropping empty IDs, deduplicating and sorting.
  Tests prove precedence `explicit > tags > trunk > historical` and stable
  results for dirty input lists.
- A fresh upstream worktree replayed all 19 patches, and the full tagged
  HuaweiCloud/IPAM/Operator/NodeDiscovery suite passed.

## Patch 0020 IPAM reconciliation and release audit

- Fixed false BatchCreate success: empty/all-nil responses now fail, while a
  mixed response counts and caches only real SubENIs.
- Resync now builds a temporary snapshot, rejects duplicate private IPs without
  publishing partial state, keeps empty-IP interfaces in quota accounting, and
  warns while skipping unexpected interface resource types.
- Release preparation is fail-safe when Used state is unknown. Release now
  checks context and current Used state immediately before each delete, skips
  unknown entries, and deduplicates SubENIs so repeated IPs cannot cause a
  second delete/404.
- Nil node/manager/allocation paths, static-IP unsupported behavior, prefix
  delegation, negative/zero/oversized excess counts and lexical candidate
  stability have direct tests. The package passes both normal and race tests.
- A fresh upstream worktree replayed all 20 patches; the full tagged
  HuaweiCloud/IPAM/Operator/NodeDiscovery suite and ENI race test passed.

## Patches 0021-0023 local-service collision audit

- CUST-DP-13 exposed a real intermittent failure when one pod accessed a local
  NodePort after ClusterIP traffic to the same backend. Destination-veth capture
  proved that the backend SYN-ACK was occasionally reverse-translated to the
  ClusterIP frontend, so the pod reset it and the request timed out.
- Patch 0021 added `--random-fully`, but audit21 real-machine repetition proved
  that unconstrained randomization is not sufficient: a random SNAT port can
  collide with stale reverse-NAT state from another frontend. Failures were
  reproduced at iterations 6, 11, and 16, with a capture showing a NodePort
  SYN-ACK rewritten as `10.104.240.167:80`.
- Diagnostic removal of the custom rule proved that Cilium already performs
  pod ClusterIP self-hairpin SNAT as `169.254.42.1` while a local NodePort uses
  the node IP. Patch 0023 therefore leaves ClusterIP pod hairpin to Cilium and
  confines local NodePort SNAT to `169.254.42.1:1024-32767`. Host-originated
  local NodePort is marked in mangle OUTPUT and uses router-IP ports
  `1024-32767`; host ClusterIP uses router-IP ports `32768-65535`.
- With the exact provisional audit23 rules, fresh BPF/Linux conntrack state
  passed pod ClusterIP 1000/1000, pod NodePort 1000/1000, pod alternating
  ClusterIP/NodePort 500x2, and host alternating 500x2. Conntrack showed router
  IP `192.168.1.7` with NodePort reply ports in the low partition and ClusterIP
  reply ports in the high partition.
- The 23-patch series replayed cleanly from upstream `a1d7fbd43` to
  `35b699194`. The audit23 amd64 Agent/CNI image built successfully, and the
  modified iptables package passed on the amd64 control-plane with Go 1.20.14.
  Five-node image deployment and full customer regression remain required
  before these provisional live results are treated as final acceptance.

## Patch 0022 CNI configuration-boundary audit

- The parser rejects empty/all-null/no-Cilium conflists and ambiguous multiple
  Cilium plugins, rejects recursive duplicate JSON keys and inputs over 1 MiB,
  and retains unknown-key compatibility.
- Empty, unsupported, and malformed `prevResult` values return errors without
  panic. Negative CNI pre-allocation is rejected; zero, one, and large values
  parse while runtime IPAM/capacity limits remain authoritative.
- HuaweiCloud CNI maps and slices are deep-copied before updating CiliumNode,
  preventing caller mutation from changing the published specification.
- Focused normal and race tests passed in the clean audit22 replay; ledger rows
  BCFG-23 through BCFG-28 now have direct evidence.

## Audit23-audit25b deployment, reboot recovery, and restart audit

- Audit23 was imported with SHA256 verification on all five nodes. On the real
  rules, all 21 HTTP cases passed 100/100, all four bidirectional TCP cases
  passed 5/5, all 21 destination-veth source assertions passed, and the eight
  Pod matrix passed 56/56. Pod self ClusterIP/NodePort stress passed 1000/1000
  each plus 500x2 alternating; host alternating passed 500x2.
- A deliberate control-plane recovery cycle exposed a bootstrap dependency:
  Worker Agents tried to reach the API through `10.96.0.1` while their service
  datapath was unavailable. Setting `k8s-api-server` to the direct control-plane
  endpoint `https://192.168.1.65:6443` restored Agent 5/5 and Operator 1/1.
  Customer and mesh regressions then passed. This closes REC-10 with a concrete
  recovery configuration rather than treating eventual recovery as implicit.
- Reboot also changed the control-plane `cilium_host` address from
  `192.168.1.7` to `192.168.1.175`. The TCP and source-IP evidence runners were
  corrected to discover the address dynamically; this prevented a stale test
  fixture from masquerading as a datapath failure.
- Audit23 restart testing found that mangle OUTPUT rules accumulated from two
  to four. Patch 0025 moves them into managed `CILIUM_OUTPUT_mangle` and removes
  every legacy direct OUTPUT duplicate during migration. Audit25b removed all
  legacy rules and two consecutive Agent restarts held invariant at one feeder,
  two custom-chain rules, and zero direct legacy rules.
- The final 25-patch series replayed cleanly to `24ebfb5c7`; the complete
  HuaweiCloud/IPAM/Operator/NodeDiscovery/iptables/CNI suite and focused race
  tests passed. The deployed audit25b Agent reports commit `24ebfb5c7`, is 5/5
  Ready, and the audit20 Operator remains 1/1 Ready.

## Patch 0024 release failure boundaries

- A three-item release with an injected failure on delete 2 proves fail-fast
  partial progress: delete 1 remains committed, items 2 and 3 remain present,
  and no third API call is made.
- Mid-batch context cancellation before delete 2 returns `context.Canceled`,
  retains item 2, and preserves the already committed first delete. Both tests
  pass in the clean replay and close BIPAM-13/BIPAM-14.

## Patches 0026-0030 boundary and transactional-map audit

- Patch 0026 proves dynamic SubENI limits at 8→1 and 1→16, preserves four
  already-used addresses when the limit shrinks, and falls back to the cached
  static limit on dynamic lookup timeout. Generic IPAM also caps requested
  preallocation at the physical maximum.
- Patch 0027 proves nil/empty subnet tags are equivalent, subnet choice follows
  refreshed capacity, first startup without trunk/history fails closed, and SG
  tag selection cannot import groups from another VPC.
- Patch 0028 rejects nil endpoints, invalid/IPv6 addresses, zero ifindex,
  endpoint IDs outside 1-65535, VLANs outside 1-4094, and non-six-byte,
  zero, or multicast MACs before narrowing values into BPF map structures.
- Patch 0029 makes the two BPF map updates transactional: lookup errors and
  VLAN+MAC ownership collisions roll back the source map; same-endpoint SubENI
  rebind removes the old ingress key; dual update/rollback failures retain both
  error causes. Close is serialized, idempotent, and rejects later operations.
  The concurrency suite passes under the Go race detector.
- Patch 0030 rejects two CiliumNode SubENIs matching the same endpoint IP,
  validates endpoint ID/ifindex before narrowing, and requires gateway IP,
  gateway MAC, and trunk interface as a coherent tuple.
- All 30 patches replay cleanly from upstream `a1d7fbd43`; final replay commit
  is `d60ec5291`. The full scoped Go suite, now including endpointmanager, and
  affected race suites pass. Ledger state after this audit is 186 Pass,
  261 Pending, 4 approved Skip, and 0 Fail.

## Live hostNetwork and CoreDNS recovery audit

- A temporary hostNetwork BusyBox HTTP server was pinned to node0005. From the
  hostNetwork Pod, HTTP to the node0002 SubENI-backed `pod3` returned `pod3`;
  from `pod3`, HTTP to `192.168.1.65:18084` returned `hostnet-ok`. The temporary
  Pod was deleted after both directions passed.
- One of two CoreDNS Pods was deleted. `pod2` resolved the customer Service
  FQDN before and after replacement and completed 30/30 one-second interval
  lookups while replacement was in progress. CoreDNS returned to 2/2 Ready.

## Session affinity feature-gate audit and baseline restoration

- Setting Service `sessionAffinity=ClientIP` while the customer baseline kept
  `enable-node-port=false` did not provide affinity: the Agent explicitly
  reported Session Affinity Disabled and 20 requests reached both backends.
  Enabling only `enable-session-affinity` did not change that state.
- Enabling both NodePort/KPR and session affinity made the Agent report the
  feature Enabled. With two healthy endpoints, 50/50 requests from `pod2`
  stayed on `pod1`, proving the supported feature combination.
- The Service was restored to `sessionAffinity=None`; ConfigMap was restored to
  `enable-node-port=false` with no affinity override; all five Agents rolled
  successfully. Post-restore customer regression passed HTTP 21/21 at 100
  requests each, TCP 4/4 at five bidirectional exchanges each, and strict
  source-IP assertions 21/21. Nodes and Agents ended 5/5 Ready.

## Service rolling-update and ExternalIP audit

- A temporary two-replica HTTP Deployment was exposed by ClusterIP and rolled
  from response `v1` to `v2` while `pod2` issued 240 requests. There were zero
  request failures; 23 responses came from v1 and 217 from v2, and the rollout
  ended 2/2 Ready. Deployment and Service were deleted.
- A temporary Service exposed `192.168.1.65:18085` as ExternalIP. `pod2`
  reached backend pod1 and remote node0004 reached backend pod3 through the
  ExternalIP. The Service was deleted after both paths passed.

## CIDR, Service, dynamic, and namespace policy audit

- Agents were temporarily restarted with `policy-audit-mode=false`. A managed
  Pod IP did not match `fromCIDR`, correctly demonstrating that Cilium endpoint
  identity takes precedence over CIDR identity. The CIDR test was therefore
  corrected to use a temporary node0005 network namespace at `198.18.0.2` plus
  an explicit return route in the server SubENI table. An unrelated CIDR
  denied the request; `198.18.0.2/32` allowed it and returned `policy-ok`.
- The policy was dynamically replaced with a namespace selector allowing only
  np-a. Its client reached the server through both PodIP and Service FQDN;
  the np-c client was denied on both paths. Deleting the policy restored both
  clients, covering live add/replace/delete convergence.
- The temporary route, netns, CNP, Service, Pods, and all three namespaces were
  removed. Policy audit mode was restored to true and Agents rolled 5/5.
  Post-restore regression passed HTTP 21x100, TCP 4x5, and source-IP 21/21;
  nodes and Agents ended 5/5 Ready.

## Established TCP connection policy-change audit

- In enforcement mode, a BusyBox TCP echo connection returned `before`, then
  slept while a valid CIDR-deny ingress rule was applied. A new connection was
  denied and the established connection ended without returning its delayed
  `after` payload, proving the policy revision invalidated the live flow.
- An initial empty `ingress: []` CNP was observed not to enable an enforcement
  direction in this Cilium version; it was not counted as a deny test. The
  corrected nonmatching-CIDR policy provided the authoritative result.
- The temporary namespace and policy were deleted, audit mode was restored,
  Agents returned 5/5, and customer HTTP regression passed 21x100.

## Connection stress audit

- `pod2` ran 50 concurrent workers with 20 HTTP connections each against the
  two-backend customer ClusterIP. All 1000 short connections succeeded and no
  worker failed.
- Four matrix source Pods concurrently requested 1000 UDP netexec dials each.
  All 4000 application responses returned and covered all four UDP backends.
- A separate single TCP echo connection is running a 30-minute validation with
  61 ticks at 30-second intervals; CONN-01 remains Pending until the final tick
  and cleanup are observed.
# Patch 0035 cloud request-boundary audit

- Huawei Cloud official VPC v3 limits were rechecked before implementation: a supplementary network interface supports at most 100 security groups; port tag batches support at most 20 pairs, with 128-character keys and 255-character values.
- Added fail-fast request validation and boundary tests for SG count, empty/duplicate SG IDs, empty tag key, empty tag value, Unicode character counting, key/value length, and tag count.
- Clean replay from upstream `a1d7fbd43` applied all 35 patches successfully; final commit `0c22135ba02cef7c50f6388e39df06c2deda5dc9` and clean worktree.
- Full scoped Go suite and privileged routing suite passed on the clean replay.

# Observability and evidence-permission audit

- Cluster-wide events were sorted by last timestamp and reviewed after the latest Agent rollout. All five nodes were Ready and all five Cilium Agents were Running with zero restarts. The only warnings were transient startup-probe connection refusals during container initialization; all affected Pods subsequently became healthy and no warning remained active.
- `ANALYSIS/` ownership/mode was `root:root 0755`; the execution ledger and evidence file were `root:root 0644`. Recursive permission checks found no group- or other-writable evidence file/directory.
- All five Agents reported `cilium status --brief=OK`; forward/drop metric families were readable on every node. During 30 successful pod2-to-ClusterIP HTTP requests, a 10-second monitor capture on pod2's actual node recorded 385 trace events, 357 containing pod2 IP `192.168.1.7`, and zero drop events. The trace showed request DNAT to pod1 and reply reverse-NAT back from the ClusterIP.

# Patch 0036 API timing, pagination, and rate-limit audit

- Fixed the exact-deadline state race by performing one final SubENI observation when the 60-second timer fires; an interface becoming ACTIVE at the boundary is accepted.
- Added real SDK/HTTP boundary coverage for ECS server pages of 999, 1000, and 1001 entries. Nil and oversized Count hints remain safe; a Count smaller than the number already returned is rejected as an inconsistent cloud response.
- Verified the HuaweiCloud API limiter boundary: requests 1-40 consume the burst without waiting; request 41 is delayed at 20 QPS and emits the limiter metric. The API package passed ten consecutive repetitions.
- Clean replay from upstream `a1d7fbd43` applied all 36 patches and ended at `c7dd65ceaadb5cb44e207b7139f8f0740ac9541a` with a clean worktree. The full scoped suite, privileged routing suite, and affected-package race suite all passed.

# Patches 0037-0038 SG and instance identity audit

- Patch 0037 enforces the HuaweiCloud 100-security-group attachment ceiling before API creation for all three resolution paths: explicit IDs, tag selection, and trunk inheritance. Each 101-entry case fails closed; ordinary and race tests passed.
- Patch 0038 removes stale constructor-instance-ID use after CiliumNode updates. Resync/status/resource lookup now use the current CiliumNode ID; old-to-new transitions select only the new instance snapshot, while empty and nil updates fail closed.
- Clean replay from upstream applied all 38 patches and ended at `b12d2ffa1e3831929360bf75fa1704b66ff25628` with a clean worktree. Full scoped, privileged routing, and affected-package race suites passed.

# Thirty-minute TCP connection

- A single cross-node TCP echo connection remained open while sending one application frame every 30 seconds. The client received every frame from `tick-0` through `tick-60`: exactly 61/61 frames over 30 minutes, with the first/last/count assertions and process exit code all successful.
- The temporary `connlong` namespace was deleted and all five nodes remained Ready.

# Patches 0039-0041 dual-stack, trunk, and Helm Secret audit

- Patch 0039 verifies a dual-stack SubENI publishes only IPv4 into the IPv4 allocation map while preserving IPv6 metadata in status. Patch 0040 verifies empty and nonexistent trunk interfaces fail before neighbor programming.
- Patch 0041 trims and validates the external HuaweiCloud Secret name as a Kubernetes DNS-1123 subdomain. Helm 3.14.4 accepted valid lengths 63 and 253, rejected empty/whitespace, invalid characters/segments, a 64-character label, and total length 254.
- Clean replay applied all 41 patches and ended at `09c77d128e291e380981a8e082255bb0687c0020`. Full scoped, privileged routing, affected-package race, clean-chart lint, valid render, and whitespace-negative render tests passed.
- In an isolated live namespace, Opaque, custom-type, and immutable Secrets each injected two dummy credential keys into a Pod and all three Pods reached Succeeded. Updating the immutable Secret was rejected by the API server; the namespace was then deleted.

# Credential and limiter fixes, then patch consolidation

- Patch 0042 rejects empty/whitespace access key, secret key, and project ID before SDK construction; an isolated live Secret confirmed Kubernetes otherwise injects present-but-empty values as empty strings. Opaque credential punctuation remains accepted.
- Patch 0043 corrects the shared API limiter to use one cancellable reservation and propagates limiter errors through every HuaweiCloud API call. A deadline expiring while queued returned in about 20 ms and the test HTTP server observed zero cloud requests; ten ordinary repetitions and race tests passed.
- At the user's request, the complete final tree represented by the former 43 development/fix patches was squashed into one delivery patch: `0001-huaweicloud-add-production-SubENI-IPAM-and-datapath-.patch`. `series` now contains exactly this one line and the old individual patch files were removed.
- A new upstream replay applied the single patch successfully and ended at `4fe5a9a8b0025285d75930e51de1a9bf57c79cc9`. Its tree is byte-for-byte Git-equivalent to the pre-squash final tree (`git diff --exit-code` returned 0). Full scoped, privileged routing, affected race, Helm lint, valid render, and invalid-whitespace render tests all passed from the consolidated replay.
- Live Secret deletion semantics were verified in isolation: after deletion, the already-running Pod retained its injected environment and stayed Running, while an identical replacement Pod entered `CreateContainerConfigError`. The namespace was fully deleted and all five nodes stayed Ready.
- Live Secret update semantics were also verified: an existing Pod kept the old environment value after Secret old-to-new update, while a newly created Pod received the new value. This proves credential rotation requires an explicit Operator rollout; isolated resources were removed.

# Patch layout correction: preserve functional patches, consolidate only bug fixes

- The prior one-patch delivery layout was based on a misunderstanding of “put bug fixes in one patch”: it also squashed the original management/control-plane, data-plane, dependency, image, subnet, and routing feature patches.
- Restored the original 14-patch functional series from archive commit `00fb232`. Generated one additional patch, `0015-fix-huaweicloud-consolidate-validation-bug-fixes.patch`, containing only the delta from the 14-patch functional tip to the final validated source.
- A clean sequential replay of patches 0001 through 0015 ends at Git tree `72e74d045f08d16acdce4648847b7a556cd12f3c`, exactly equal to authoritative source commit `71f5ef1a1`. Regression test results for this corrected layout are recorded below after execution.

# External Secret ownership audit

- In an isolated namespace on the five-node control plane, a pre-created `cilium-huaweicloud` Secret was present before rendering the consolidated chart.
- The rendered manifests did not contain a HuaweiCloud credential Secret object and contained exactly the expected access-key and secret-key references to the external Secret. The Secret UID, resourceVersion, and both dummy data fields were unchanged across the render audit.
- The isolated namespace was deleted and all five nodes remained Ready. This closes BSEC-08 without transferring Secret ownership to Helm.

# Explicit-subnet cloud-error boundary and consolidated patch refresh

- Added a table-driven BCFG-17 test for the first explicit subnet returning representative 404, 403, and 500 errors. Each error is preserved, allocation returns zero, and the second subnet is not attempted; only the dedicated insufficient-capacity sentinel permits fallback.
- The affected ordinary test ran for ten repetitions and the race-enabled test passed with native arm64 Go 1.20.14.
- Regenerated the single delivery patch after the test addition. The new squash tree is `86b32e8e81a948177209364181c90bf6bf2ef61c`; a fresh `apply.sh` replay produced `9b9e88faf05d0f3168cfef9489bd6dbb201dc8a5` with an equivalent Git tree. `series` still contains one patch only.

# Resync and endpoint-event race repair

- Independent concurrency review found two semantic races not detected by the Go race detector: a full Resync snapshot could overwrite a newly created SubENI inventory entry, and a pre-delete snapshot could republish an already released entry. Creation/deletion inventory mutations now share the manager resync lock; successful release also removes the interface from the manager inventory.
- Independent endpoint-event review found that a stale Delete notification could remove a newer Ready binding for the same IP. Delete now verifies the complete source-map owner (VLAN, MAC, endpoint ID) and ingress-map owner (ifindex, endpoint ID) before deleting either key.
- Deterministic tests hold the resync write lock and prove create/delete inventory mutations block until it finishes. Endpoint tests prove stale old-binding deletion preserves a newer rebind and prove Restore/new-Create same-IP ownership transitions fail closed until the old owner is deleted.
- Affected packages passed ten ordinary and race-enabled repetitions. The refreshed sole delivery patch has squash tree `55693349aba0c153dc924bb80e69547061c9129c`; clean `apply.sh` replay `98b59f29cd1e994954e187c14e1b9db5ac970469` is tree-equivalent and passed ordinary/race retests.

# Node revision and duplicate-expansion race repair

- Review found that `UpdatedNode` could change the instance ID between the limits lookup, the copied node spec, and post-create inventory update, mixing two node revisions in one cloud operation. `CreateInterface` now snapshots the CiliumNode and instance ID together and uses that revision through limits, request construction, and inventory attribution.
- Review also found that two reconciliation calls carrying the same stale allocation action could both expand a node. A node-level create lock now serializes expansion and re-clamps the request against the current cached SubENI count while holding that lock.
- A blocking fake cloud call proves an old-to-new node update during creation keeps the old trunk/subnet/SG request and attributes the returned interface only to the old instance. Two simultaneous expansion calls against an IPv4 limit of one create exactly one interface.
- These tests passed 100 ordinary repetitions and 50 race-enabled repetitions. The sole patch was regenerated: squash `8d3a5bbc33d7e88aae423ab3264c27e076e2972c`, clean replay `f0ba7de74c211825ed36215e5271b612f3791001`; full affected HuaweiCloud/IPAM/endpoint/nodediscovery ordinary and race suites passed from the replay.

# Runtime subnet and security-group configuration transition

- A recording cloud API exercised one node across two revisions. The first revision used explicit `subnet-old` and `sg-a`; the second cleared explicit subnet IDs, selected `subnet-new` by tag, and used only `sg-b`.
- The two recorded create requests matched the respective revisions exactly, proving neither the explicit subnet nor the old security group leaked into the next reconciliation.
- The transition test passed 100 ordinary and 50 race-enabled repetitions. The sole patch was regenerated again: squash `64f9f24a37a15e22f596a6492e1018d69a0a6ed0`, clean replay `a39eb03a7790ff9f73af4b5e21964464e03313e7`; targeted ordinary/race tests passed from the clean replay.

# CiliumNode deletion and nested-CIDR canary findings

- Live BIPAM-21 exposed that deleting one worker CiliumNode did not recreate it within 120 seconds while the Agent remained running. Restarting that node's Agent recreated the object with a new UID and restored its instance ID, pool, and eight SubENIs. The code now runs a low-cost 10-second existence controller and recreates only a missing local CiliumNode; normal intervals do not update an existing object.
- The first repaired Agent canary then exposed a startup regression from an earlier strict routing check: the valid SubENI subnet `192.168.1.0/24` nested inside VPC `192.168.0.0/16` was rejected as overlap. The canary node was immediately rolled back and the cluster returned to five Ready nodes.
- Routing validation now rejects exact duplicate CIDRs but accepts legitimate nested VPC/subnet routes. Ordinary, race, and privileged routing tests pass. The latest sole patch squash is `9d59fa44afd168d254d14a88548b1c3edc9b2186`; clean replay `5bdcce5c8b31dd30843468903f4d28dd8c99b03b` is tree-equivalent and all affected ordinary/race/privileged tests pass.
- The repaired audit49 Agent was built as an amd64 static binary with the project Makefile and `ipam_provider_huaweicloud` tag. Its canary started successfully and reported `cilium status --brief=OK`.
- With the canary Agent Pod unchanged, deleting its local CiliumNode produced a new UID in one second. The Operator then restored allocation pool and HuaweiCloud SubENI status to 8/8; the same Agent Pod remained Ready and all five nodes stayed Ready. BIPAM-21 therefore passes.
- After both fixes, the authoritative sole patch squash is `aad23e15fe7895ccf42024b886ff7c4e66baa7d8`; clean replay `a87fe7f898b3a688a8a92da9a2fe90a6b6069517` is tree-equivalent and its full affected ordinary/race plus privileged routing suites pass.

# Full audit49 rollout and customer 25 regression

- All five nodes have the finalized audit49 archive SHA256 `4f5c38b4e5eb3d62b1d87b33bd6f20c4af65ed83358e0506fb3eb27ef6d93f0a`. Every running Cilium Agent binary reports SHA256 `c180be81dcb5287ba7138d73cdd2c2353d1b74891b181735155b1881c53cac30`; all five `cilium status --brief` results are `OK`, all Kubernetes nodes are Ready, and the Operator is healthy.
- The customer HTTP matrix passed all 21 HTTP scenarios with 100/100 successful requests per scenario after selecting a unique intended backend.
- The four raw TCP scenarios passed 5/5 bidirectional echo connections each. Strict tcpdump source-address validation passed all 19 applicable service/backend directions, including the `169.254.42.1` hairpin expectations.
- The source-IP runner was corrected to assert only the 19 cases for which the customer's acceptance table specifies a source address; direct Pod scenarios 1 and 4 require connectivity only. This removed a false test-harness failure without weakening any customer assertion.
- Final packaging was rechecked after an older multi-patch layout reappeared in the delivery directory. The directory now contains exactly one patch and one `series` entry. Patch SHA256 is `f344ee8ca99709b2399283142dbce8a6a4e5b7c8628b6ee80e1dd8d695a3c765`; clean replay commit `45c785da1f0cd44b8c17fa14242b3b261abcc053` has tree `72e74d045f08d16acdce4648847b7a556cd12f3c`, identical to authoritative source `71f5ef1a1`.

# Recovery audit53, startup BPF-map repair, and corrected 14+1 package

- Restarting kubelet and containerd on worker node0002 recovered normally. A subsequent full worker reboot exposed a real startup ordering defect: restored endpoint events ran before `cilium_hwc_srcip4` and `cilium_hwc_vlan_mac` existed, and the failed updates were not retried although Kubernetes reported the node and Agent Ready.
- The Agent now creates and pins both maps with their exact ABI and flags before registering the endpoint subscriber, then opens them through the typed map specification. Ordinary, race, and isolated privileged bpffs tests passed; the privileged test proves both maps are pinned and writable before endpoint events.
- Audit53 was built and deployed to all five nodes. Every running `/usr/bin/cilium-agent` has SHA256 `90ead2e05c346171e2115f3dee5ad09328d3dd11832b20415ad7834a448c175a`; five Nodes and five Agents are Ready, Operator is 1/1, and the last 30 minutes of Agent logs contain no pinned-map open, flag mismatch, or property-upgrade error.
- The serialized post-reboot customer regression passed HTTP `21/21` with `100/100` requests per scenario, TCP `4/4` with `5/5` bidirectional exchanges, and all `19/19` required source-IP assertions. This closes ROUTE-08 and REC-06 through REC-08.
- Delivery preserves the original 14 functional patches and consolidates all later validation repairs into the single `0015-fix-huaweicloud-consolidate-validation-bug-fixes.patch`. `series` contains exactly 15 entries. A fresh upstream replay applied all 15 commits and produced tree `bb47f9e5ce91512b0b329f5fe91ee98004938d43`, exactly matching authoritative source HEAD `c9acfd98d389efdea3bb71908b76bf94604dd903`.

# Ten-round Pod allocation/reuse audit54

- Added a lock-protected runner that deletes and recreates both four-node matrix DaemonSets for ten consecutive rounds. It requires exactly eight Ready Pods after every round and executes all 56 directed Pod-to-Pod ICMP paths before advancing.
- All ten rounds passed `56/56`; this exercised 80 Pod deletions and 80 replacements. Previously used addresses including `192.168.1.230`, `.75`, `.12`, and `.129` were safely reused by replacement endpoints.
- The post-cycle customer regression passed HTTP `21/21` at `100/100` each, raw TCP `4/4` at `5/5` each, and required source-IP checks `19/19`. Five Nodes/Agents and the Operator remained healthy; all Agent status probes returned OK and the last-30-minute panic/fatal/HuaweiCloud map-error scan was clean.
- This closes IPAM-30, IPAM-37, and BPF-04. The ledger is now 283 Pass, 164 Pending, 4 approved environment Skips, and 0 Fail.
- Patch 0015 SHA256 is `9653624e97697daabcc956bc011c54cbee3be982a6f7517c428ac662ac1ae25f`; clean replay commit is `350e3d88e29f77b8cb3cbc566a13eb05d65cc71a`. The retained audit53 OCI tar SHA256 is `4fdc4db5b4222caef489574a2f2c5be592b450393bd703cc2f48b50af44d6665`.
- After the complete five-node audit53 rollout, the customer matrix was repeated once more without overlapping selector mutations. `/tmp/customer25-audit53-rollout-http.out` records HTTP 21/21 at 100/100, `/tmp/customer25-audit53-rollout-tcp-serial.out` records TCP 4/4 at 5/5, and `/tmp/customer25-audit53-rollout-sourceip-serial.out` records source IP 19/19.
- A separately launched duplicate suite was excluded rather than counted. All three customer runners now acquire one shared non-blocking `flock` before changing the Service selector; shell syntax and rejection of a second runner with exit 75 were verified.

# Transactional HuaweiCloud route installation audit55

- Independent partial-install review found that a successful endpoint rule followed by a nexthop/default-route failure could leave incomplete policy routing behind, and a stale-rule cleanup failure could leave the migration half-switched. HuaweiCloud route configuration is now serialized and transactional: it records newly installed rules and replaced routes, restores prior routes where applicable, and rolls back in reverse order on any error.
- Three privileged network-namespace fault tests inject failure at the nexthop route, default route, and second stale-rule deletion. Each verifies that no new endpoint rules/routes remain; the cleanup case additionally proves all original stale rules are restored. The full privileged routing package passed 100 repetitions, followed by 10 race-enabled repetitions.
- Patch `0015` was refreshed as the sole consolidated bug-fix patch. SHA256 is `9b5ed0e9229fb6878efb0eb80cd1b43347de0d02051e74d1426037478fbcb404`; a clean 15-patch replay ends at `0048e0115202df7312d94d3fc6dadd0e3e33cab3` with tree `9faadd2aa8b2aa517e9d9163b2937764755b5ead`, exactly matching authoritative source `9049d6c7355d1f58a1d01fd67198731f498a5431`.
- The resulting audit55 Agent binary SHA256 is `9452d3a3568e9e997b571a2fdcd2f0abf5df2a5a7eef72c17f9be2fc01fde4da`; OCI tar SHA256 is `5ad59c8bd90a123f277aeae4500ed6fe83349fba334573b753fd29b9774906db`. Canary status and matrix mesh passed, followed by a sequential rollout to all five nodes. Every live binary has the expected hash and reports status OK; Nodes/Agents are 5/5, Operator is 1/1, and the post-rollout Agent error scan is clean.
- The final full-rollout regression passed matrix mesh `56/56`, HTTP `21/21` at `100/100`, TCP `4/4` at `5/5`, and source IP `19/19`. One overlapping evidence attempt was rejected by the shared lock. An independently started source-IP attempt later missed one tcpdump SYN capture despite successful HTTP and was excluded. Review showed that the remote SSH startup/check/request latency could consume the original 10-second capture window, so the runner now waits for tcpdump's explicit `listening on` readiness signal and uses a 30-second capture window. Its isolated full retry then passed the previously missed case and all `19/19`. Final evidence uses only the non-overlapping files `/tmp/audit55-rollout-mesh.out`, `/tmp/customer25-audit55-http-final.out`, `/tmp/customer25-audit55-tcp-final.out`, and `/tmp/customer25-audit55-sourceip-retry2.out`.
- This closes BROUTE-08, BROUTE-09, and BROUTE-10. The ledger is now 286 Pass, 161 Pending, 4 approved environment Skips, and 0 Fail.

# Retained VLAN route reclamation audit56

- BROUTE-13 review reproduced a lifecycle defect: `Delete` intentionally retained a VLAN table, but a later endpoint reusing that VLAN with a different gateway was rejected as a conflicting owner. The repair reclaims only an inactive table with no referring rule and exactly one old default plus one matching link-scoped `/32` nexthop. Active tables, foreign routes, malformed pairs, and cross-trunk ownership remain fail closed.
- Reclamation is part of the existing route transaction. The new nexthop is installed first, the old nexthop is recorded and removed, and any later failure restores deleted and replaced routes safely.
- Privileged netns tests cover exact stale rules with mark/mask/to, multiple same-source/same-priority stale rules, unused VLAN reuse with a different gateway, and simultaneous host/ordinary endpoint semantics. The routing package passed 100 repetitions, race-enabled 10 repetitions, ordinary compilation, and vet.
- Consolidated bugfix patch `0015` has SHA256 `5382722f51a9e2ccc6292896b173fe5c92c434780ea3e2b3a8d2b06a2d44ed0d`. Clean replay `42ff31c7954d5c616f3deb1e9a67b164f27a6d09` has tree `05d3a846c3d6c1e666b1b3d04a01d89841a76b3d`, matching source `f97237b9d68a96c95c95e3f629cd3bc0443ebdb3`.
- Audit56 binary SHA256 is `a768e0d8d71fd0849a72fac7cdfca2fb6597ef3ba59e12f7ee20e1e12855cfc6`; OCI tar SHA256 is `3509abf0e8615758aa8b67143215559db4a4e3e30dc065dd9ae41d84cb3a60a4`. Canary and final rollout matrix each passed 56/56; HTTP 21/21 and TCP 4/4 passed after all five Agents were upgraded.
- Image staging briefly filled node0001 ephemeral storage and evicted its matrix Pods. Old build layouts and staging tars were removed, root usage fell from 88% to 54%, DiskPressure cleared, both DaemonSets returned 8/8, and the mesh rerun passed. The runner now waits for both DaemonSets and filters only Running Pods with exactly eight Ready rows.
- The final source-IP suite was interrupted after its first passing case by a control-plane API TLS handshake timeout. Worker probes show the host responds to ICMP but API and SSH are currently unresponsive. Source-IP 19/19 and final health are pending recovery and are not claimed by this checkpoint.
- This closes BROUTE-11 through BROUTE-14. The ledger is now 290 Pass, 157 Pending, 4 approved environment Skips, and 0 Fail.

# Startup pinned-map reconciliation audit57

- Independent restart review found a real pinned-map leak on the control-plane Agent: `cilium_hwc_srcip4` and `cilium_hwc_vlan_mac` still contained source `192.168.1.80` owned by deleted endpoint ID `1847`, while the live health endpoint had moved to a different IP and ID. The older Agent logged an ownership conflict instead of repairing the stale pair.
- The repair adds transactional startup reconciliation of both HuaweiCloud maps. Desired VLAN owners are installed before source-IP owners; stale source entries are removed before stale VLAN entries; duplicate desired owners fail before mutation; and any update/delete failure restores both snapshots. Endpoint events arriving during startup reconciliation are queued, and delete processing retains cached SubENI metadata when CiliumNode status has already removed the allocation.
- Unit, race, privileged pinned-map, routing, and HuaweiCloud BPF tests passed before packaging. Patch `0015` SHA256 is `192be03223921e3ba87b3c39c1a0b28e0ef199ccaa4f5c3fb851c08e9d257062`; the clean 15-patch replay commit is `91ff609e2a984725c8a96059ed15afaa93b048db` and its tree `6a49a7e168494972380f9c959190dfb881c00655` exactly matches authoritative source commit `a8aefe325e8c7a6e295949424db46dd96ea08ca1`.
- The amd64 static audit57 Agent was built with the project Makefile and `ipam_provider_huaweicloud`; binary SHA256 is `a87281faf18dce561060ec1f0738d4786336c1093eb6d05904c402e2701ca9ef`. The OCI tar SHA256 is `18c1196df1d665dc3e747d5b8499c7a691b5c9fbaf16fac5efffa64221bfbb64`.
- Canary restart provided direct repair evidence: the stale endpoint ID `1847` count changed from `1` before startup to `0` after startup, the new Agent reported `OK`, and ten consecutive recreate-and-mesh rounds passed `56/56` each. The image was then imported with SHA verification and rolled out sequentially to all five nodes; each intermediate mesh check passed `56/56`.
- Final full-rollout regression passed ten additional recreate rounds at `56/56`, customer HTTP `21/21` at `100/100`, TCP `4/4` at `5/5`, and source-IP assertions `19/19`. All five live Agent binaries have the expected hash and status `OK`; every raw pinned-map LxcID is a member of the corresponding live endpoint set, with zero stale owners and zero matching panic/fatal/ownership/reconciliation errors. Five Nodes, five Agents, and the Operator are healthy with no DiskPressure.
- A clean second Makefile build produced the identical amd64 static Agent SHA256 `a87281faf18dce561060ec1f0738d4786336c1093eb6d05904c402e2701ca9ef`, closing BASE-12. The first map-audit parser was deliberately rejected because two nodes omitted `bpftool`'s optional `formatted` JSON object; the corrected audit decodes raw little-endian values and proves exact endpoint/source-map/VLAN-map ID equality on all five nodes.
- Evidence files: `/tmp/audit57-agent-build.out`, `/tmp/audit57-agent-rebuild.out`, `/tmp/audit57-agent-rebuild.sha`, `/tmp/audit57-canary-rollout.out`, `/tmp/audit57-canary-mesh.out`, `/tmp/audit57-rollout-mesh.out`, `/tmp/customer25-audit57-http-final.out`, `/tmp/customer25-audit57-tcp-final.out`, `/tmp/customer25-audit57-sourceip-final.out`, and `/tmp/audit57-final-agent-map-audit-v2.out`.
- This closes BASE-12 and strengthens the existing Agent restart, endpoint restore, BPF map, and observability Pass evidence. The ledger is now 291 Pass, 156 Pending, 4 approved environment Skips, and 0 Fail.

# Source-map deletion recovery audit57

- REC-18 used matrix Pod `192.168.1.246` on node0004 as a disposable fault target. Baseline cross-node ping passed and the exact source-map key existed once. Deleting only that key made the same cross-node ping fail, directly proving the fault was active rather than a no-op.
- Restarting only node0004's Agent restored the exact source-map key during startup reconciliation. The replacement Agent had the expected audit57 hash and status `OK`; the same directed ping and the full `56/56` mesh passed afterward. Evidence: `/tmp/audit57-rec18-map-delete-recovery.out`.
- This closes REC-18. The ledger is now 292 Pass, 155 Pending, 4 approved environment Skips, and 0 Fail.

# Five-node route/map/neighbor residue audit

- CLEAN-05 captured each node's CiliumNode/SubENI inventory, live endpoints, both raw HuaweiCloud pinned maps, IPv4 policy rules, all route tables, and neighbor table in one consistent post-audit57 snapshot.
- The independent verifier decoded raw map keys and little-endian values rather than relying on optional `bpftool formatted` output. It required exact source-map/VLAN-map ownership-set equality, current IP allocation and endpoint membership, complete priority-20 ingress/router CIDR rules, no legacy priority-110 rule, and exact priority-111 source-to-`10000+VLAN` mappings.
- Every active table contained exactly one matching default route and one link-scoped gateway route on the CiliumNode trunk. Unreferenced tables were accepted only when they belonged to an allocated SubENI, had no rule, and retained exactly the intentional reusable route pair. Invalid VLAN boundary tables, foreign routes, and malformed pairs were rejected. Permanent gateway neighbors matched the CiliumNode gateway IP/MAC/trunk set exactly.
- All five nodes passed with `stale=0` and `malformed=0`. Retained exact pairs were 4, 4, 5, 5, and 1 respectively; these are safe reusable tables for allocated but currently unreferenced SubENIs, not reachable stale rules. Evidence: `/tmp/audit57-clean05-snapshot.json` and `/tmp/audit57-clean05-audit.out`.
- The temporary Python verifier passed syntax checks and a correctness review after its ownership-set, CIDR-rule, invalid-boundary, and permanent-neighbor assertions were strengthened. No code-review finding remained; IPv6 residue is outside this baseline because the customer configuration explicitly disables IPv6.
- CLEAN-05 is now Pass. The ledger is 292 Pass, 155 Pending, 4 approved environment Skips, and 0 Fail.

# Node label and taint restoration audit

- CLEAN-06 inspected the complete label and taint sets after all audit57 canary, rollout, matrix, customer, and residue checks. All four workers have zero taints. The control-plane retains only the two kubeadm `node-role.kubernetes.io/master:NoSchedule` and `node-role.kubernetes.io/control-plane:NoSchedule` taints and its expected role/external-load-balancer labels.
- No label or taint key matching the test namespaces or transient markers (`customer`, `matrix`, `audit`, `test`, `temporary`, or `canary`) remains on any node. Cilium Agents remain 5/5 Running. Evidence: `/tmp/audit57-clean06-labels-taints.out`.
- CLEAN-06 is now Pass. The ledger is 293 Pass, 154 Pending, 4 approved environment Skips, and 0 Fail.

# Complete Agent and BPF data-plane image audit58

- A post-rollout image audit found that audit57 correctly replaced `/usr/bin/cilium-agent` but retained the base image's older `/var/lib/cilium/bpf/lib/huaweicloud.h` (`3b15da82...` instead of authoritative `8dae79a6...`). Therefore audit57's control-plane, map-reconciliation, and customer traffic evidence remains valid, but it is not used as proof that the newest malformed-VLAN BPF code was deployed.
- The OCI-layer builder now requires a fifth `BPF_SOURCE_DIR` argument and refuses binary-only packaging. It installs the Makefile `install-bpf` tree alongside the Agent. Shell syntax, missing-argument rejection, image mount inspection, and exact content hashes were verified. This prevents recurrence instead of relying on operator memory.
- audit58 retains Agent SHA256 `a87281faf18dce561060ec1f0738d4786336c1093eb6d05904c402e2701ca9ef`, adds the complete 165-file install-state BPF tree, and has OCI tar SHA256 `a57a99bb976e9c68e8384dfe4e69cbe3a39396df956bfce68a6b5fc2de02203e`. Mounting the image before deployment proved the Agent hash and `huaweicloud.h` SHA256 `8dae79a6000869b26469accbd48c7ef84b669b7a10d313d2e3a1e08ed0cbab83` exactly match authoritative artifacts.
- Canary and all four sequential node upgrades verified both hashes inside the running container, Agent status `OK`, and an intermediate `56/56` mesh. Canary additionally passed three recreate rounds. The final full rollout passed ten recreate rounds at `56/56`, HTTP `21/21` at `100/100`, TCP `4/4` at `5/5`, and source-IP `19/19`.
- Final audit reports five Nodes Ready, five Agents Ready/OK, Operator 1/1, identical Agent/BPF hashes, all raw HuaweiCloud map owners current (`stale=0`), no matching BPF compile/panic/fatal/ownership/reconciliation error, and no DiskPressure. Evidence: `/tmp/audit58-image-content-audit.out`, `/tmp/audit58-package.out`, `/tmp/audit58-canary-rollout.out`, `/tmp/audit58-canary-mesh.out`, `/tmp/audit58-rollout-*.out`, `/tmp/audit58-rollout-mesh.out`, `/tmp/customer25-audit58-http-final.out`, `/tmp/customer25-audit58-tcp-final.out`, `/tmp/customer25-audit58-sourceip-final.out`, and `/tmp/audit58-final-agent-bpf-map-log-audit.out`.
- CLEAN-09 is now Pass. The ledger is 295 Pass, 152 Pending, 4 approved environment Skips, and 0 Fail.

# HuaweiCloud VLAN boundary BPF execution audit

- The exact authoritative `bpf/tests/huaweicloud_test.c` compiled with clang/llc under `-Wall -Wextra -Werror -Wshadow -Wimplicit-int-conversion -Wenum-conversion`; object SHA256 was `3231a1b0aa29ea9eb68e52f0d48ad4ed9ad221ef28bf236ea0e469687659696f`.
- A native amd64 privileged runner loaded the object into the x86 kernel and executed the complete HuaweiCloud suite 20 times. All 20 top-level runs and all scalar/packet subtests passed. Evidence: `/tmp/audit58-huaweicloud-bpf-build.out`, `/tmp/audit58-bpf-runner-build.out`, and `/tmp/audit58-huaweicloud-bpf-run-count20.out`.
- Static integration review confirmed the tested length predicates run before header dereferences, the tested 12-bit TCI extraction feeds the map key, invalid IDs and inline/metadata disagreement drop before lookup, and metadata-only misses return to generic VLAN policy. The packet-level unknown inline 802.1ad test directly exercised `hwc_from_netdev` and proved fail-closed behavior.
- This evidence closes BVLAN-01 through BVLAN-04 and BVLAN-06 through BVLAN-08. BVLAN-05 remains Pending because the current runner checks the two-pop count but does not observe the final packet/ethertype after two helper calls. BVLAN-09 and BVLAN-10 also remain Pending; no QinQ or non-IPv4 claim is inferred from these narrower tests.
- The ledger is 302 Pass, 145 Pending, 4 approved environment Skips, and 0 Fail.

# Direct VLAN packet-boundary completion and audit59 checkpoint

- The remaining VLAN boundary review added kernel-executed packet tests rather than inferring behavior from scalar helpers. A `SETUP/CHECK` pair supplies a kernel-parsed inline 802.1Q frame, adds matching skb VLAN metadata, performs the real map lookup and both pop helpers, and asserts the resulting frame is exactly Ethernet plus IPv4 with IPv4 ethertype and cleared metadata.
- Direct packet cases cover inline and metadata-only ARP, IPv6, and LLDP behavior, plus QinQ and three-tag inputs. Inline non-IPv4 and nested VLAN inputs fail closed before lookup; metadata-only non-IPv4 traffic returns to the generic VLAN path. Unknown inline test data now uses a distinct VLAN ID so pinned test-map state cannot make it a false hit.
- The exact HuaweiCloud object SHA256 is `691f4278b3794989ae461bb5515588f506b47fc7cd2120acc2380c4a8d6ae139`. Strict clang/llc build and 20 complete privileged kernel executions passed. All eight `bpf/tests/*.o` objects then built strictly and each loaded/executed successfully. Evidence: `/tmp/audit59-huaweicloud-bpf-build-final2.out`, `/tmp/audit59-huaweicloud-bpf-run-count20-final2.out`, `/tmp/audit59-bpf-all-build.out`, and `/tmp/audit59-bpf-all-run.out`.
- The single consolidated bug-fix patch `0015` has SHA256 `b99505de69876a80d947d8e37287f4c76c75c17f5cd2557bda351bfed8f7a6a6`. Clean 15-patch replay commit `670450b70f1085db387d17a58269344b9c3bd1aa` has tree `7f745f042434057c2786291f35b2d47bdecf6a7e`, exactly matching authoritative source commit `7c8e2c5d5a8a5f697593d1e378548a5189d544dd`.
- Clean replay validation passed 16 affected Go packages, race tests, privileged routing, and privileged subenimap tests. Two clean Makefile Agent builds were deterministic at SHA256 `54cd5a23932c4f4cb1973b2f9c0b20fddbd362c55b4ff639b4469e36e0da3632`.
- audit59 packages that Agent with the complete 165-file BPF install tree. Pre-deploy image mounting verified exact Agent/BPF/test-source hashes. Canary and four sequential node rollouts each verified runtime hashes, status `OK`, and `56/56` mesh; final ten-round recreate mesh was `56/56` every round, HTTP was `21/21` at `100/100`, TCP was `4/4` at `5/5`, and source-IP was `19/19`.
- The final independent audit proved 5 Nodes Ready, 5 Agents Ready/OK with zero restarts, Operator 1/1, identical Agent/BPF/test-source/image IDs, no stale raw map owner, no matching compile/panic/fatal/ownership/reconciliation error, no DiskPressure, no transient test labels, and only the expected control-plane taints. All five `audit25b` runtime aliases and `audit59` labels resolve to manifest `sha256:2c663cd1629449d0c27d9f1999c84bedb6f5387f2f4588515d879f6f74768f62`; audit58 remains as the rollback image. Obsolete audit55/56/57 refs and temporary build/package trees were removed, then the post-cleanup mesh passed `56/56`. Evidence: `/tmp/customer25-audit59-sourceip-final.out`, `/tmp/audit59-final-agent-bpf-map-log-audit.out`, `/tmp/audit59-five-node-image-alias-audit.out`, and `/tmp/audit59-postcleanup-mesh.out`.
- This closes BVLAN-05, BVLAN-09, and BVLAN-10. The ledger is 305 Pass, 142 Pending, 4 approved environment Skips, and 0 Fail.

# Gateway-neighbor conflict and interface-rename audit60

- Independent BMAP-15/16 review found that unconditional `NeighSet` could overwrite a pre-existing permanent gateway neighbor with a different MAC, after which the Agent would still publish the endpoint into the HuaweiCloud BPF maps. The repair serializes neighbor reconciliation, lists permanent IPv4 neighbors on the selected trunk, accepts an exact existing match, and rejects a same-link gateway/MAC conflict without changing it. A neighbor failure now blocks BPF-map and cache publication; initial reconciliation fails closed instead of starting with a partial datapath.
- Privileged dummy-link tests prove the conflicting permanent neighbor is preserved, same gateway/different MAC on one trunk is rejected, and the same gateway with different MACs on two different trunks remains independently valid. Endpointmanager targeted tests passed 100 repetitions, race-enabled 20 repetitions, privileged 100 repetitions, and privileged race-enabled 20 repetitions. The complete package passed one normal and one race run. Repeating the entire upstream package five times exposed the pre-existing generic `TestHasGlobalCT` suite-state leak on the clean audit59 baseline as well; it is excluded rather than attributed to this HuaweiCloud change.
- BMETA-14 uses a real privileged dummy link and metadata HTTP server. It resolves the initial explicit trunk name, takes the link down, renames and restores it, proves the stale name is rejected, and proves the new name recovers the same stable metadata port ID by MAC. Normal testing passed 100 repetitions; the privileged executable passed 100 repetitions and its race-enabled build passed 20 repetitions. The first test draft incorrectly tried to rename an UP link and was rejected with `EBUSY`; only the corrected down/rename/up evidence is counted.
- The source commit is `931e23f0bf3dd8aa45da223c6af409d24399cbec`. The sole consolidated bug-fix patch `0015` has SHA256 `ecc925d913d63e2230475ab675e35d800624387bcec3a8994d30ca7e10ef6ec5`; clean replay commit `6fab161f86061c72ed55088349ab66a53f99ffe1` has tree `e1d395fc44c13d4a8eb1d4ff47369a80ce603b44`, exactly matching the authoritative source tree. Evidence: `/tmp/audit60-clean-replay.out`, `/tmp/audit60-replay-affected-normal.out`, `/tmp/audit60-replay-endpoint-race20.out`, `/tmp/audit60-endpointmanager-target100.out`, `/tmp/audit60-endpointmanager-target-race20.out`, `/tmp/audit60-endpointmanager-privileged100.out`, `/tmp/audit60-endpointmanager-privileged-race20.out`, `/tmp/audit60-metadata-normal100.out`, `/tmp/audit60-metadata-privileged100.out`, and `/tmp/audit60-metadata-privileged-race20.out`.
- Two clean Makefile builds produced identical amd64 static Agent SHA256 `06c7efa73edd0e31860221fe0641d3cf3901e89441624d3ec7f524d51a472133`. audit60 OCI manifest digest is `sha256:c51d18fd9c81a8b26cec8b8aef83a6a0c279e2953e259c08c2cae6cc37ad4f92`, tar SHA256 is `ce166b3466d887c89c81b78a01be076f5114a9a707a4f5ec9b19fe969615494e`, and pre-deploy mounting verified the Agent plus the unchanged 165-file BPF tree.
- Canary passed three recreate rounds at `56/56`; every subsequent node upgrade passed an intermediate `56/56` mesh. The final ten-round recreate matrix passed `56/56` each, HTTP passed `21/21` at `100/100`, TCP passed `4/4` at `5/5`, and source-IP passed `19/19`. The final audit proved five Nodes Ready, five Agents Ready/OK with zero restarts, Operator 1/1, identical Agent/BPF/test-source/image IDs, all raw HuaweiCloud map owners current, no matching Agent errors, no DiskPressure, and no transient label/taint residue. `audit25b` and `audit60` resolve to the new manifest on all nodes; audit59 is the sole retained rollback image, audit58 and temporary build/package trees were removed, and post-cleanup mesh remained `56/56`. Evidence: `/tmp/audit60-agent-build.out`, `/tmp/audit60-agent-rebuild.out`, `/tmp/audit60-package.out`, `/tmp/audit60-image-content-audit.out`, `/tmp/audit60-canary-rollout.out`, `/tmp/audit60-rollout-*.out`, `/tmp/audit60-rollout-mesh.out`, `/tmp/customer25-audit60-http-retry.out`, `/tmp/customer25-audit60-tcp-final.out`, `/tmp/customer25-audit60-sourceip-final.out`, `/tmp/audit60-final-agent-bpf-map-log-audit.out`, `/tmp/audit60-image-alias-cleanup.out`, and `/tmp/audit60-postcleanup-mesh.out`.
- This closes BMAP-15, BMAP-16, and BMETA-14. The ledger is now 308 Pass, 139 Pending, 4 approved environment Skips, and 0 Fail.

# Explicit non-default trunk selection audit61

- PRE-07/08 were verified without changing the host route table. The current host default IPv4 route uses `vpneth0`; the privileged metadata test creates a separate dummy trunk, resolves its configured name and MAC to the stable metadata port ID, then performs down/rename/up. The stale name fails immediately and the updated explicit name succeeds. The complete default route text was identical before and after 20 privileged repetitions, proving the helper neither falls back to nor mutates the default-route interface.
- A separate 100-repetition metadata test places the real trunk MAC in the second link entry and reverses link order, always returning the same `trunk-port`. Together these tests prove selection is by explicitly configured OS interface name plus MAC, not the first OS NIC, the first metadata link, or the default-route interface. Evidence: `/tmp/audit61-pre07-pre08-privileged.out` and `/tmp/audit61-pre07-multilink100.out`.
- No product change was required, so audit60 remains the authoritative five-node runtime. This closes PRE-07 and PRE-08. The ledger is now 310 Pass, 137 Pending, 4 approved environment Skips, and 0 Fail.

# Live 802.1Q ingress/egress and protocol-boundary audit61

- pod2 (`192.168.1.7`, SubENI MAC `fa:16:3e:ba:13:19`, VLAN 1443) and pod3 (`192.168.1.199`, SubENI MAC `fa:16:3e:ba:13:d9`, VLAN 662) were exercised across node0005 and node0002. Both hosts report RX/TX VLAN offload `off [fixed]`, so the captured 802.1Q headers are real inline frames rather than hardware-offload metadata reconstruction.
- Physical-ingress captures show the gateway MAC delivering a single 802.1Q frame to the exact destination SubENI MAC and VLAN on each node. The corresponding live pinned `cilium_hwc_vlan_mac` and `cilium_hwc_srcip4` dumps contain the same IP/VLAN/MAC and current endpoint IDs. Twenty ICMP and twenty HTTP requests succeeded with zero capture drops. This proves live inline ingress, one-representation handling, and exact destination MAC+VLAN lookup; it does not claim the unavailable metadata-only or inline-plus-metadata runtime paths.
- Physical `-Q out` captures contain ten pod2 request frames with source MAC `fa:16:3e:ba:13:19`/VLAN 1443 and ten pod3 reply frames with source MAC `fa:16:3e:ba:13:d9`/VLAN 662, all directed to the trunk gateway MAC. With TX VLAN offload fixed off, this directly proves the Cilium egress path emitted the expected inline VLAN and rewritten SubENI source MAC. The ten exchanges completed without loss.
- The protocol/size matrix passed bidirectionally: 1 MiB TCP streams produced identical SHA256 on both receivers, and 100-line UDP payloads produced identical SHA256 in both directions. ICMP passed at 56, 1400, 1472, 2000, and 4000-byte payload sizes; 4000-byte requests and replies were fragmented into 1518/1086-byte VLAN frames and completed 5/5 in each direction. An additional HTTP run passed 20/20, both physical captures had zero kernel drops, and temporary listeners/files were removed.
- The post-test control passed a fresh `56/56` full pod mesh. All five Nodes remained Ready, all five Agents and the Operator remained Ready with zero restarts. Evidence: `/tmp/audit61-vlan-node0005.cap`, `/tmp/audit61-vlan-node0002.cap`, `/tmp/audit61-vlan-traffic.out`, `/tmp/audit61-live-maps.out`, `/tmp/audit61-vlan-node0005-out.cap`, `/tmp/audit61-vlan-node0002-out.cap`, `/tmp/audit61-vlan-egress-traffic.out`, `/tmp/audit61-vlan16-node0005-frag.cap`, `/tmp/audit61-vlan16-node0002-frag.cap`, `/tmp/audit61-vlan16-validated.out`, `/tmp/audit61-vlan16-node0005.cap`, `/tmp/audit61-vlan16-node0002.cap`, `/tmp/audit61-vlan16-protocols.out`, and `/tmp/audit61-postvlan-mesh.out`.
- No product defect was found and no source, patch, build, image, or deployment changed. The filtered two-node physical captures also close OBS-05 without recording unrelated payloads. This closes VLAN-02, VLAN-05, VLAN-07, VLAN-08, VLAN-16, and OBS-05. The ledger is now 316 Pass, 131 Pending, 4 approved environment Skips, and 0 Fail.

# Real trunk link-flap recovery audit62

- On worker node0002, a transient systemd service performed three independent cycles of `eth0` down for five seconds followed by up. Scheduling the recovery inside PID 1 ensured the interface was restored even while SSH was unavailable. Every service ended with `Result=success`/`ExecMainStatus=0`, and `eth0` returned to `UP,LOWER_UP`; no audit timer or service remained active.
- Each cycle first passed 5/5 pod2-to-pod3 ICMP. A 150-packet, 200 ms interval probe spanning the flap then received 125/150 packets, showing the intended bounded outage rather than a false no-op. Immediately afterward, each cycle passed 20/20 with zero loss.
- After every recovery, node0002 and its Agent were Ready, the same Agent Pod retained restart count zero, and the live pinned VLAN map still contained VLAN 662 plus pod3 MAC `fa:16:3e:ba:13:d9`. The final `cilium status --brief` returned `OK`; the last 15 minutes contained no matching panic/fatal/BPF/reconciliation/datapath error.
- A fresh post-fault full pod mesh passed `56/56`. Evidence: `/tmp/audit61-trunk-flap.out`, `/tmp/audit61-trunk-flap-r{1,2,3}-{pre,during,schedule,service,post}.out`, and `/tmp/audit61-trunk-flap-mesh.out`.
- This first audit established the bounded traffic outage and basic recovery, but its post-flap check covered only readiness and BPF ownership. The later independent audit found that NetworkManager had removed every custom table route and the permanent gateway neighbor while leaving the priority-111 rules present. Therefore the original “no product change required” conclusion was rejected; PRE-12 and REC-16 use the superseding audit64 evidence below.

# Route, neighbor, and router recovery audit64

- Independent review after audit62 found a real silent-recovery defect: traffic still passed through the main table, but all node0002 source-policy tables were empty and the permanent gateway neighbor was absent. The first audit63 repair restored cached ordinary endpoints, but a canary flap exposed two additional gaps: the `cilium_host` router table was not part of the endpoint cache, and periodic use of startup `Configure` brought an administratively down trunk back up early. That canary evidence was rejected rather than counted.
- The final repair adds a non-mutating routing `Reconcile` path that never changes MTU or administrative link state, reconciles ordinary cached endpoint routes plus the live router allocation every five seconds, restores the permanent neighbor before endpoint routes, serializes reconciliation against deletion, and does not rewrite BPF maps. A privileged network-namespace test deletes endpoint and router rules/routes, verifies reconciliation leaves a down link down, then verifies complete recovery after the link is raised. Full routing/endpointmanager normal, race, privileged, 100-repeat, 50-repeat clean-replay, and vet checks passed.
- Authoritative source commit is `36aa1e6c901b127da6ed3ef277e45fec12820e26`; consolidated patch `0015` SHA256 is `38338f0326ce862c12b8896591deb6e859ba85c2d2c95cdade19f161338b9702`. Clean 15-patch replay commit `c5b51a316fc945163b5f9b65c8634f0e14c847ad` has tree `99bf4f10a82852390846d1b0cc74d0f45527b334`, exactly matching the authoritative source tree.
- Two clean normal-resource Makefile builds produced the identical linux/amd64 static Agent SHA256 `a7b00205e414e0c767ed8ee9ac2df0ff398fb3df4ea147c28b877a99051a446a`. The complete audit64 image has manifest `sha256:86c241725764df7a68de4df3e5919e021fc4f64b70b6147fdfa66ae12560366c`, tar SHA256 `33308e0f705256b646fc800445c7f266a73eeb325acff8ebe830e2eae632ac68`, and the verified 165-file BPF tree.
- Live drift injection removed pod3 and `cilium_host` priority-111 rules, both route pairs, and the permanent neighbor. The final Agent restored all five objects in three seconds without a restart and with both raw HuaweiCloud map hashes unchanged. A fresh three-round real `eth0` down-five-seconds/up test then observed exactly 125/150 responses in every round, followed by 20/20 recovery; after every round all five node0002 priority-111 tables again contained the exact two-route shape and the permanent neighbor was present. The Agent stayed on the same Pod with restart count zero and did not override the intended five-second down interval.
- Canary and every subsequent node rollout passed an intermediate `56/56` mesh. The final ten-round recreate matrix passed `56/56` each; customer HTTP passed `21/21` at `100/100`, raw TCP passed `4/4` at `5/5`, and source-IP assertions passed `19/19`. Final independent audit proved five Nodes and five Agents Ready, Operator 1/1, identical Agent/BPF/test-source hashes and image IDs, exact endpoint-to-map ownership with stale=0, complete policy tables and permanent neighbors on all five nodes, zero matching severe Agent errors, and no DiskPressure. Obsolete audit63/audit59 refs and temporary package/build trees were removed; audit60 remains the rollback image and post-cleanup mesh remained `56/56`.
- Evidence: `/tmp/audit64-clean-replay.out`, `/tmp/audit64-{routing-full,endpoint-full,endpoint-race,endpoint-privileged-full}.out`, `/tmp/audit64-replay-*.out`, `/tmp/audit64-agent-{build,rebuild}.out`, `/tmp/audit64-package.out`, `/tmp/audit64-image-content-audit.out`, `/tmp/audit64-live-drift-reconcile.out`, `/tmp/audit64-trunk-flap.out`, `/tmp/audit64-trunk-flap-r{1,2,3}-*.out`, `/tmp/audit64-rollout-*.out`, `/tmp/audit64-matrix10.out`, `/tmp/customer25-audit64-{http,tcp,sourceip}.out`, `/tmp/audit64-final-agent-map-log-audit.out`, `/tmp/audit64-final-host-route-image-audit.out`, and `/tmp/audit64-postcleanup-mesh.out`.
- This closes ROUTE-15 and REC-17 and supplies complete superseding proof for PRE-12 and REC-16. The ledger is now 320 Pass, 127 Pending, 4 approved environment Skips, and 0 Fail.

# Foreign and legacy policy-rule isolation audit65

- ROUTE-16 injected an unrelated priority-112 rule from `198.51.100.1` to table 50000 plus a blackhole default route. Across four complete five-second HuaweiCloud reconcile intervals, the foreign rule and route remained byte-for-byte unchanged while every active priority-111 table retained its exact two-route shape. The trap removed both injected objects and the post-cleanup mesh passed `56/56`.
- ROUTE-12 injected a legacy priority-110 pod3 rule pointing to a separate table 50001. The periodic reconciler removed that legacy rule within four seconds while preserving pod3's correct priority-111 rule and complete table 10662. The foreign table's blackhole route was deliberately left unchanged, proving cleanup is rule-scoped rather than destructive to an unrelated table; the test trap removed it and the post-cleanup mesh again passed `56/56`.
- One combined wrapper correctly received exit 75 when it attempted to invoke the already lock-protected mesh runner while holding the same non-reentrant lock. That orchestration attempt was excluded; cleanup was verified independently and only the subsequent isolated `56/56` mesh is counted. Evidence: `/tmp/audit65-route16-foreign-policy.out`, `/tmp/audit65-route16-mesh.out`, `/tmp/audit65-route12-legacy-rule.out`, and `/tmp/audit65-route12-mesh.out`.
- This closes ROUTE-12 and ROUTE-16. The ledger is now 322 Pass, 125 Pending, 4 approved environment Skips, and 0 Fail.

# Agent mixed-version rollback and recovery audit66

- Node0004's local `audit25b` alias was moved from audit64 manifest `sha256:86c241...` back to the retained audit60 manifest `sha256:c51d18...`, then only that Agent Pod was recreated. The running binary changed to the exact audit60 SHA256 `06c7efa73edd0e31860221fe0641d3cf3901e89441624d3ec7f524d51a472133`, the BPF tree remained authoritative, status was `OK`, restart count was zero, and the real four-new/one-old mixed cluster passed `56/56` mesh.
- The same node was then moved forward to audit64 without changing the DaemonSet's `audit25b` image string. Its binary returned to `a7b00205...`, status was `OK`, all four current policy tables and the permanent neighbor were complete, and mesh again passed `56/56`. Independent final inspection found all five Nodes Ready, five Agent restart counts zero, one identical audit64 runtime imageID, and one identical Agent hash.
- This live cycle supplements the earlier audit64 sequential rollout, where every intermediate old/new mixture passed `56/56`. Evidence: `/tmp/audit66-upg09-rollback-node0004.out`, `/tmp/audit66-upg09-rollback-mixed-mesh.out`, `/tmp/audit66-upg09-restore-node0004.out`, `/tmp/audit66-upg09-restore-mesh.out`, and `/tmp/audit66-upg09-final-five-node.out`.
- This closes UPG-05, UPG-07, and UPG-09. The ledger is now 325 Pass, 122 Pending, 4 approved environment Skips, and 0 Fail.

# Missing Agent image and isolated upgrade failure audit67

- On node0003 only, the `audit25b` image reference was removed while the content-addressed audit64 rollback source remained. Recreating that Agent produced an explicit `ErrImagePull` followed by `ImagePullBackOff`; Kubernetes events recorded a failed pull from the unavailable localhost registry. This proves the fault was active rather than a no-op cache hit.
- While node0003's Agent was unavailable, exactly the other four Agents remained Ready and the customer pod2-to-pod3 path passed 20/20 with zero loss. Reinstating the local alias and recreating only the failed Pod restored the exact audit64 Agent hash and `cilium status --brief=OK`; the full mesh then passed `56/56`, and node0003 finished with all five current route tables complete plus the permanent neighbor.
- The first orchestration attempt reached the expected `ErrImagePull`, but an unescaped shell `$p` in evidence formatting aborted the wrapper. Its trap restored the image alias and kubelet recovered automatically. That attempt is excluded; only the corrected retry with complete fault, unaffected-path, recovery, and post-mesh evidence is counted. Evidence: `/tmp/audit67-ins10-upg11-image-missing-recovery-retry.out`, `/tmp/audit67-ins10-upg11-recovery-mesh.out`, and `/tmp/audit67-node0003-final-route-image.out`.
- This closes INS-10 and UPG-11. The ledger is now 327 Pass, 120 Pending, 4 approved environment Skips, and 0 Fail.

# Worker maintenance and Agent toleration audit68

- Node0004 was cordoned and drained with DaemonSets explicitly preserved. Kubernetes reported `Ready` plus `SchedulingDisabled`; the existing Agent stayed Ready with restart count zero, and customer pod2-to-pod3 traffic passed 20/20. Uncordon restored `spec.unschedulable` to empty.
- A temporary `huaweicloud.cilium.io/audit68=temporary:NoSchedule` taint was then applied. Deleting only node0004's Agent proved the DaemonSet's `operator: Exists` toleration operationally: a different Agent Pod scheduled on the tainted node, became Ready with the exact audit64 hash, and returned status `OK`. The taint was removed, no unschedulable or taint residue remained, Nodes/Agents were 5/5, and mesh passed `56/56`.
- Evidence: `/tmp/audit68-rec09-cordon-drain.out`, `/tmp/audit68-ins12-taint-toleration.out`, `/tmp/audit68-post-maintenance-mesh.out`, and `/tmp/audit68-residue-health.out`.
- This closes INS-12 and REC-09. The ledger is now 329 Pass, 118 Pending, 4 approved environment Skips, and 0 Fail.

# Operator replica and leader failover audit69

- The Operator Deployment was scaled from one to two replicas; both became Ready while `cilium-operator-resource-lock` retained one holder. Mapping the holder's node-prefixed identity selected the actual leader. Deleting that leader changed the Lease from the node0003 identity to the existing node0004 standby identity, while the Deployment returned to 2/2 Ready.
- During the failover, customer pod2-to-pod3 traffic passed 20/20. Scaling back to one replica safely caused a second Lease transition to the surviving node0002 identity. Final state is exactly one Ready Operator, a nonempty holder, zero matching panic/fatal/leader-election errors, five Ready Nodes, and mesh `56/56`.
- The first identification attempt scaled to two Ready replicas but used `grep -q` on a long SSH log stream; pipe closure prevented reliable leader selection. Its cleanup trap restored one replica, and it is excluded. The corrected retry uses the holder identity's node prefix and supplies complete failure/recovery evidence. Evidence: `/tmp/audit69-operator-leader-failover-retry.out`, `/tmp/audit69-post-failover-mesh.out`, and `/tmp/audit69-final-operator-health.out`.
- This closes INS-14 and REC-22. The ledger is now 331 Pass, 116 Pending, 4 approved environment Skips, and 0 Fail.

# Same-AZ performance, Pod readiness, and component resource audit70

- The current audit64 datapath completed three independent 300-second TCP streams in each topology. Same-node throughput was 1118.84/1120.03/1120.89 Mbps (median 1120.03 Mbps, maximum deviation 0.106%); same-AZ cross-node throughput was 1419.84/1359.81/1405.31 Mbps (median 1405.31 Mbps, maximum deviation 3.238%). Every stream ran for at least 300000 ms and transferred 41.96–53.24 GB. The corrected runner verifies receiver byte counts rather than inferring throughput from sender timing.
- Three additional 100-packet ICMP runs per topology had zero loss. A static amd64 Go request/reply probe then ran TCP and UDP for 10000 exchanges per run, three runs per topology, with payload equality and zero loss required. Same-node TCP/UDP P99 ranges were 39.371–39.951/36.531–38.341 us; same-AZ cross-node ranges were 87.382–94.302/80.502–88.403 us.
- On node0004, twenty consecutive DaemonSet Pod deletions and replacements all became Ready. Delete-to-Ready latency was min/average/P50/P95/P99/max 1881/3860.75/3998/4039/4084/4084 ms. Kubernetes Scheduled event timestamps correlated with Cilium's nanosecond `Create endpoint request` logs show the combined scheduling-to-CNI/IPAM Agent request phase at min/average/P50/P95/max 337/344.20/344/354/354 ms. All twenty image events explicitly reported the image already present, separating image cache hits from download time. The post-churn mesh passed `56/56`.
- `crictl stats` cumulative CPU timestamps and memory counters captured all five Agents plus the Operator across idle, two complete mesh bursts, and a 60-second settled interval. CPU ranges were 1.707–2.635, 2.019–2.799, and 1.880–2.681 mcore respectively; working sets stayed within 35.08–239.98 MiB and the largest absolute within-phase change was 2.04 MiB. Final audit found five Ready Nodes, five audit64 Agents with zero restarts and exact binary hash, one Ready Operator, zero severe Agent log matches, no RTT-tool residue, and mesh `56/56`.
- Early harness attempts are excluded: the first JSONPath reader lacked a newline; BusyBox `nc` does not support the assumed `-z`/`-N` options; a shell timeout left a sender pipeline alive until its two PIDs were explicitly killed; and one otherwise complete 3x300-second attempt was invalidated when the running script was edited before its final summary. The final runners use two-connection readiness, explicit sender cleanup, receiver byte counts, syntax checks, smoke tests, and a clean untouched 3x300-second retry ending in `PERF_SUSTAINED_5M_PASS`.
- Evidence: `/tmp/audit70-perf-rtt-throughput.out`, `/tmp/audit70-perf-sustained-5m-retry.out`, `/tmp/audit70-perf-tcp-udp-rtt.out`, `/tmp/audit70-perf05-ready-latency.out`, `/tmp/audit70-perf05-{events,kubelet,agent-events,phase-decomposition}.out`, `/tmp/audit70-perf06-component-resources.out`, `/tmp/audit70-post-perf05-mesh.out`, `/tmp/audit70-post-performance-mesh.out`, and `/tmp/audit70-final-health.out`.
- This closes PERF-02, PERF-05, and PERF-06. PERF-03 is now the fifth user-approved cross-AZ environment Skip; PERF-01 remains Pending until the retained audit60 old-candidate baseline comparison is complete. The ledger is now 334 Pass, 112 Pending, 5 approved environment Skips, and 0 Fail.

# Retained old-candidate performance baseline audit71

- All five Agents were sequentially moved from audit64 to the retained audit60 image through the unchanged `audit25b` DaemonSet alias. Every node had the exact audit60 Agent hash `06c7efa73edd0e31860221fe0641d3cf3901e89441624d3ec7f524d51a472133`, `cilium status --brief=OK`, zero restarts, and an intermediate mesh of `56/56` before the next node was changed.
- On audit60, same-node sustained TCP was 1118.81/1120.62/1120.02 Mbps (median 1120.02 Mbps, maximum deviation 0.108%) and same-AZ cross-node TCP was 1359.02/1417.19/1369.52 Mbps (median 1369.52 Mbps, maximum deviation 3.481%). All six streams ran for at least 300000 ms. TCP and UDP each completed three 10000-exchange runs per topology with zero loss. Audit60 P99 medians were 46.952/36.791 us for same-node TCP/UDP and 88.302/84.922 us for cross-node TCP/UDP.
- Relative to audit60, audit64 same-node throughput changed by +0.001% and cross-node throughput by +2.613%. Audit64 same-node TCP P99 improved by 15.081%; same-node UDP, cross-node TCP, and cross-node UDP P99 changed by +1.821%, +5.426%, and +1.072%. The customer supplied no numeric performance gate, so this comparison reports the raw values and applies a conservative 10% technical regression guard; every measured current regression remained within that guard and the run-to-run ranges overlap for the largest latency delta. This is a retained old-candidate comparison, not a customer-supplied native-CNI baseline.
- The cluster was then sequentially restored to audit64. Every node again passed the exact Agent hash `a7b00205e414e0c767ed8ee9ac2df0ff398fb3df4ea147c28b877a99051a446a`, status, restart, and intermediate mesh checks. Independent final audit found five Ready Nodes, Operator 1/1, all five `audit25b` aliases at manifest `sha256:86c241725764df7a68de4df3e5919e021fc4f64b70b6147fdfa66ae12560366c`, complete two-route priority-111 tables, permanent neighbors, zero severe Agent log matches, and mesh `56/56`.
- Evidence: `/tmp/audit71-rollout-audit60.out`, `/tmp/audit71-audit60-tcp-udp-rtt.out`, `/tmp/audit71-audit60-sustained-5m.out`, `/tmp/audit71-restore-audit64.out`, and `/tmp/audit71-final-audit64-health.out`.
- This closes PERF-01. The ledger is now 335 Pass, 111 Pending, 5 approved environment Skips, and 0 Fail.

# TCP and UDP packet-rate and counter audit72

- The static request/reply probe now reports wall-clock exchange and bidirectional message rates in addition to latency. Each topology/protocol completed three independent runs of 100000 64-byte exchanges with payload equality and zero loss. Same-node TCP/UDP median request rates were 49427.20/53527.51 exchanges per second (98854.40/107055.02 bidirectional messages per second); same-AZ cross-node medians were 14536.28/15416.17 exchanges per second (29072.56/30832.34 bidirectional messages per second).
- Counter snapshots covered both participating hosts and all three participating Pod interfaces. The source Pod observed exactly 1200033 RX and TX packets and each destination approximately 600000 packets across the complete matrix. Neither host nor Pod gained any RX/TX drop or error. Kernel softnet drop and time-squeeze deltas were also zero on both hosts, while NET_RX processing counters increased as expected. The two participating Agents averaged 2.220 and 2.195 mcore over the measurement interval, consistent with the audit70 idle/burst range rather than an Agent or datapath-control spike.
- A corrected smoke test is retained only as harness validation. Its first version accidentally included the previous snapshot output in the next input glob and stopped before reporting a result; it was fixed to select only per-node snapshot files and is excluded from the acceptance result. The full untouched run ended in `PERF_PPS_COUNTERS_PASS`.
- Independent final audit passed mesh `56/56`, five Ready Nodes, Operator 1/1, five exact audit64 Agent hashes, zero restarts, `status=OK`, zero severe Agent log matches, and no probe-binary residue. Evidence: `/tmp/audit72-pps-smoke3.out`, `/tmp/audit72-perf04-pps-counters.out`, and `/tmp/audit72-final-health.out`.
- This closes PERF-04. The ledger is now 336 Pass, 110 Pending, 5 approved environment Skips, and 0 Fail.

# Five-node concurrent scale audit73

- A fresh isolated Deployment created ten Pods concurrently with a strict hostname topology-spread constraint and control-plane tolerations. All ten became Ready in 2540 ms and the scheduler placed exactly two Pods on each of the five nodes. This exercises concurrent CNI/IPAM allocation on every Agent, including the otherwise tainted control-plane node, without claiming the unavailable 40-Pod physical-capacity case.
- Per-node CiliumNode IPAM-used counts were captured before the burst, during it, and after namespace deletion. Every node increased during the burst and returned exactly to its own baseline within the bounded cleanup wait. Independent cleanup audit found no test namespace residue, five Ready Nodes, five Running zero-restart Agents, and mesh `56/56`. Evidence: `/tmp/audit73-scale03-five-node-burst.out` and `/tmp/audit73-final-mesh.out`.
- This closes SCALE-03. SCALE-01 and SCALE-04 remain Pending because their literal 40-Pod workload exceeds the currently available endpoint capacity and is not silently converted into the already approved `min-allocate=10` Skip. The ledger is now 337 Pass, 109 Pending, 5 approved environment Skips, and 0 Fail.

# Release-disabled namespace cleanup audit74

- The live Operator configuration was first asserted as `huawei-cloud-release-excess-ips=false` with Operator 1/1. An isolated ten-Pod burst used a strict hostname spread and placed exactly two Pods on every node; all Pods became Ready in 2663 ms. The baseline inventory retained every CiliumNode pool IP together with its cloud resource identifier, rather than comparing counts alone.
- Namespace deletion completed in 42506 ms. The full CiliumNode IPAM-used state returned exactly to its per-node baseline, then the audit waited 210 seconds, exceeding the default 180-second excess-release delay. All 40 pool IP/resource entries remained byte-for-byte identical and every node retained exactly eight entries. This directly proves that the disabled setting does not start delayed SubENI deletion after workload cleanup.
- Independent final audit found no namespace residue, five Ready Nodes, five exact audit64 Agents with status OK and zero restarts/severe logs, Operator 1/1, and mesh `56/56`. Evidence: `/tmp/audit74-release-disabled-cleanup.out` and `/tmp/audit74-final-health.out`.
- This closes IPAM-26, CLEAN-01, and CLEAN-02. The ledger is now 340 Pass, 106 Pending, 5 approved environment Skips, and 0 Fail.

# Release-enabled cleanup and in-use protection audit75

- Starting from the verified false baseline, node0003 was isolated as the only mutation target. The two matrix Pods were removed through reversible DaemonSet affinity, its `min-allocate` was temporarily reduced from eight to four, the ConfigMap was changed to `releaseExcessIPs=true`, and a newly created Ready Operator Pod proved the updated configuration had crossed a restart boundary.
- After endpoint cleanup, the protected used set contained router `192.168.1.167` and health `192.168.1.45`. Within 80 seconds the target pool changed from eight to six entries, directly proving a real release rather than a no-op. Both protected IPs remained in the pool and the used set was unchanged, while two free resources disappeared.
- The procedure then restored `releaseExcessIPs=false`, restarted Operator, restored `min-allocate=8`, removed the temporary affinity clauses, and waited for pool eight and both DaemonSets 4/4. Two early harness attempts are excluded: the first outer `tee` masked the runner status, and the second tried to execute `cat` in the distroless Operator image. Both cleanup traps restored false/min8/DaemonSets before the corrected run; neither produced acceptance evidence.
- Independent final audit found all 40 pool entries present, every used IP a pool member, both protected IPs retained, Operator 1/1, five exact audit64 Agents with zero restarts/severe logs, node0003's four priority-111 tables each containing exactly two routes, a permanent gateway neighbor, and mesh `56/56`. Evidence: `/tmp/audit75-release-enabled-cleanup.out` and `/tmp/audit75-final-health.out`.
- This closes IPAM-27, IPAM-28, CLEAN-03, and BIPAM-16. The ledger is now 344 Pass, 102 Pending, 5 approved environment Skips, and 0 Fail.

# Already-absent SubENI convergence audit76

- Review of API-08 found a real reconciliation defect: `Node.ReleaseIPs` returned immediately when HuaweiCloud reported an already-deleted SubENI as HTTP 404/`ErrNotFound`. The cloud resource had converged, but the stale local manager/node entries remained and later releases in the same batch were skipped. The fix accepts only wrapped `ErrNotFound` as successful convergence, preserves all other delete failures and cancellation behavior, clears both local state stores, and continues the batch.
- `TestReleaseIPsTreatsNotFoundAsConvergedAndContinues` injects wrapped `ErrNotFound` after removing the first cloud object, then proves both delete calls execute and both local/cloud records are absent. The relevant normal tests passed 20 repetitions, the full HuaweiCloud ENI package passed 10 repetitions, the targeted race suite passed 20 repetitions, and `go vet ./pkg/huaweicloud/eni` passed. Existing API normalization coverage separately proves HTTP 404 maps to `ErrNotFound`. Evidence: `/tmp/audit76-targeted20.out`, `/tmp/audit76-eni-full10.out`, `/tmp/audit76-targeted-race20.out`, and `/tmp/audit76-vet.out` on node0001.
- The authoritative source is `1bc1ec0a096347e3d0d5eb3b48708800cf3e6b42`. Consolidated patch 0015 SHA256 is `f8d2f08c3a83cdde1ff6a53f970714c66213e81612b08d7695108ec6b66e894a`; clean 15-patch replay commit `578619ee1c8424f10a6e414052f623a29af8b016` and the source share tree `f0a68079a7b712b536542c361fd5ce70bbe6cabf` exactly.
- The affected Operator binary was rebuilt after deleting the prior output; SHA256 is `f9304624693ea39555f7289287b654b48cc9d6cbdcdbacce55af0a13c90c7067`. All five nodes imported manifest `sha256:f2750f9a94303bb6540ab9acd4f79603c70c80018e668234cf2f4a0f38d8ac98`, and the live Deployment rolled to `v1.12.19-audit76` with one Ready replica, zero restarts, and the mounted image binary matching that exact SHA256. The hardened packaging helper rejects unsafe work directories and unsupported multi-manifest exports; two independent rebuilds produced canonical OCI tar SHA256 `0dc4a40b8ea8ed80af25ceb8efc077615264f87a133bdaa501f2b4406faece2f` and the same manifest.
- Post-rollout acceptance passed matrix `56/56`, all 21 HTTP scenarios at `100/100`, all four bidirectional TCP scenarios at `5/5`, and all 19 source-IP assertions. Independent health review found five Ready nodes, five exact audit64 Agents with status OK and zero restarts/severe logs, Operator 1/1 with zero severe log matches, `releaseExcessIPs=false`, all five pools at eight entries (40 total), every used IP inside its pool, complete two-route priority-111 tables and permanent neighbors. Transferred OCI archives, overwritten build outputs, packaging work trees, and the temporary patch-generation worktree were removed while retaining the audit20 rollback and audit76 runtime images; post-cleanup mesh remained `56/56`. Evidence: `/tmp/audit76-rollout-mesh.out`, `/tmp/audit76-customer-http.out`, `/tmp/audit76-customer-tcp.out`, `/tmp/audit76-customer-sourceip.out`, `/tmp/audit76-final-cluster-health.out`, `/tmp/audit76-final-routes.out`, `/tmp/audit76-operator-package-determinism.out`, `/tmp/audit76-operator-package-negative.out`, and `/tmp/audit76-postcleanup-mesh.out`.
- This closes API-08. The ledger is now 345 Pass, 101 Pending, 5 approved environment Skips, and 0 Fail.

# Operator rollback and restore audit77

- The retained audit20 Operator manifest `sha256:af9cf3c501a48e2d0959bd814329f5dcb8fa7074b4358fe5200b591c8297531f` was verified or stream-imported on all five nodes before mutation. The audit ran only after asserting `huawei-cloud-release-excess-ips=false`; it captured the complete per-node pool/resource mapping as SHA256 `e1f3322be5ac3c3ca21e4ca0041017ec1af5f387764196a2f2d1e97ba863860b` rather than comparing counts alone.
- The live Deployment moved audit76→audit20 and then audit20→audit76. Each side reached exactly one Ready Operator with zero restarts and zero severe log matches; the eight-Pod matrix passed `56/56` in the real old-version window and again after restoration. After a settled wait in each window, the complete pool/resource mapping remained byte-identical to the baseline.
- Final state is audit76 1/1 with zero restarts/severe logs. The scheduled node's mounted binary SHA256 is `f9304624693ea39555f7289287b654b48cc9d6cbdcdbacce55af0a13c90c7067`, matching the reviewed audit76 build. The runner has an EXIT/INT/TERM restoration trap and a shared destructive-suite lock. Evidence: `/tmp/audit77-operator-rollback-restore.out`.
- This closes UPG-06 and UPG-10. The ledger is now 347 Pass, 99 Pending, 5 approved environment Skips, and 0 Fail.

# Failed Operator rollout recovery audit78

- With the live Operator healthy on audit76 and `releaseExcessIPs=false`, the runner captured the exact pool/resource mapping SHA256 `e1f3322be5ac3c3ca21e4ca0041017ec1af5f387764196a2f2d1e97ba863860b`. It temporarily changed only `maxUnavailable` from one to zero so a deliberately invalid candidate could not remove the known-good singleton, while leaving `maxSurge=1`.
- The Deployment was pointed at the nonexistent local tag `v1.12.19-audit76-missing`. Rollout correctly timed out after 45 seconds, with exactly one invalid candidate in ErrImagePull/ImagePullBackOff and exactly one old audit76 Operator still Ready. During that real failed-rollout window, matrix traffic passed `56/56` and the complete pool/resource mapping remained byte-identical.
- Continuing the rollback restored audit76, removed every bad-image Pod/reference, returned strategy to `maxSurge=1,maxUnavailable=1`, and reached exactly one Ready zero-restart Operator with zero severe log matches. Mesh again passed `56/56`, and the complete pool/resource mapping was still identical. The runner uses a shared lock and EXIT/INT/TERM restoration trap. Evidence: `/tmp/audit78-operator-failed-rollout-recovery.out`.
- This closes INS-11 and UPG-12. The ledger is now 349 Pass, 97 Pending, 5 approved environment Skips, and 0 Fail.

# Invalid cloud credential recovery audit79

- The referenced `cilium-huaweicloud` Secret was backed up only on the control-plane host in a mode-0600 temporary file containing the two original data fields; no secret value entered the runner output or evidence. With `releaseExcessIPs=false` and `maxUnavailable` temporarily zero, both fields were replaced by explicit non-secret invalid fixtures and the Operator was restarted.
- The new process reported a concrete cloud authentication failure (`unauthorized`/401/403/APIGW match count one). Kubernetes process readiness still became true, so acceptance intentionally relies on the cloud error signal rather than treating generic Pod readiness as proof of valid credentials. During the invalid window, the eight-Pod matrix passed `56/56` and the exact five-node pool/resource mapping SHA256 `e1f3322be5ac3c3ca21e4ca0041017ec1af5f387764196a2f2d1e97ba863860b` remained unchanged.
- The original Secret data was reapplied, the Operator restarted, and strategy restored to `maxSurge=1,maxUnavailable=1`. Final state is one Ready zero-restart audit76 Operator, all five pools contain eight resources, every CiliumNode operator error is empty, recent authentication/severe log matches are zero, the backup file is absent, mesh again passed `56/56`, and the exact pool mapping is unchanged. The runner has a shared lock and EXIT/INT/TERM restoration trap. Evidence: `/tmp/audit79-operator-invalid-credentials-recovery.out` and `/tmp/audit79-final-health.out`.
- This closes SEC-07 and REC-13. The ledger is now 351 Pass, 95 Pending, 5 approved environment Skips, and 0 Fail.

# Secret reference and namespace boundary audit80

- Without exporting credential values, the original Secret data was copied inside Kubernetes to temporary custom name `cilium-huaweicloud-audit80-custom`. Both Operator secretKeyRefs were changed together. The custom-name rollout reached exactly one Ready zero-restart Operator with no authentication error; matrix passed `56/56`, and the exact pool/resource mapping SHA256 `e1f3322be5ac3c3ca21e4ca0041017ec1af5f387764196a2f2d1e97ba863860b` remained unchanged.
- A second copy was then created only in namespace `default` as `cilium-huaweicloud-audit80-wrong-ns`; no Secret of that name existed in `kube-system`. With `maxUnavailable=0`, changing both references produced exactly one candidate in CreateContainerConfigError while one old Operator remained Ready. During the real namespace failure, matrix stayed `56/56` and the complete pool mapping was unchanged.
- Both references were restored to `cilium-huaweicloud`, strategy returned to `maxSurge=1,maxUnavailable=1`, and both temporary Secrets were deleted. Final audit found one Ready zero-restart Operator, both original refs exact, 40 pool resources, zero recent auth/severe log matches, no temporary Secret residue, matrix `56/56`, and unchanged pool identity. The runner has a shared lock and EXIT/INT/TERM cleanup. Evidence: `/tmp/audit80-operator-secret-reference-recovery.out` and `/tmp/audit80-final-health.out`.
- This closes SEC-15 and SEC-16. The ledger is now 353 Pass, 93 Pending, 5 approved environment Skips, and 0 Fail.

# Real cloud CRUD, inline SubENI tags, and deleted-resource recovery audit81

- The destructive runner first required Operator 1/1, `huawei-cloud-release-excess-ips=false`, an uncordoned target node, an eight-entry target pool, two provably unused pool entries, and matrix `56/56`. It then cordoned node0003, scaled the Operator to zero, and deleted exactly two selected idle SubENIs to remain within the flavor's physical limit. Credentials were read only inside the control-plane host from the referenced Secret and were never printed or copied into evidence.
- The first isolated probe proved that single Create/Get/List succeeds and that the previous `TagSubNetworkInterface` failure occurs only afterward. Both the SDK Port-tag path and the corresponding guessed SubENI tag paths returned APIGW 404 in `cn-south-1`. A follow-up real-cloud request proved that this region accepts tags directly inside both single and batch SubENI creation requests and returns them through Show. The production client was therefore changed to send validated, deterministically ordered tags inline for both endpoints and no longer invoke the region-limited Port-tag endpoint during finalization.
- The fixed production client completed real single Create, BatchCreate count two, Show, exact parent List, inline-tag verification, and Delete/NotFound checks. Cleanup left the expected six original resources. Restarting the audit76 Operator replenished two new resources, removed both deleted IDs, restored an exact eight-resource cloud/CiliumNode set, left every used IP inside the pool with no operator error, and passed matrix `56/56`. The same complete runner was repeated with a probe compiled against the final production client and ended in `CLOUD_CRUD_RECOVERY_PASS`.
- API tests passed 20 normal repetitions and 20 race repetitions. All HuaweiCloud packages passed 10 normal and 10 race repetitions, and `go vet ./pkg/huaweicloud/...` passed. Authoritative source commit `1248ceadd69bc4b4a0307bacf5bc2c9fe22bb61b`, consolidated patch-generation commit `a8e44ef945c9133fec50824e7383c40824b2cceb`, and clean 15-patch replay commit `afa2b04001771132df5cf0c3c4dae83d6e4b19b0` share tree `d116bd05abedd2945e72cc10e574c0238439ddac`. Patch 0015 SHA256 is `0737c4a7c741a512596f86955cfb5cefb4e80a14ef4c573f435773867f5a3c1c`.
- The affected Operator was rebuilt after deleting its old output. Binary SHA256 is `49dd6a943bfad9443e5d1acc5bfadf16ae6c9041426729833229948a8102d8fa`; audit81 OCI tar SHA256 is `ddcfab0af9da770092ec6dcafb45c405df9d64810e35feb51200a0428eb762a6`, and manifest is `sha256:829dd972509cb5a1e527e6023849c310a3595719f2aba6064fee1e0d7e0cffc2`. All five nodes imported the exact image, the Deployment rolled to audit81, and the scheduled node's mounted binary matched the build hash.
- Post-rollout customer acceptance passed all 21 HTTP scenarios at `100/100`, all four bidirectional TCP scenarios at `5/5`, and all 19 source-IP assertions. A corrected independent final audit—not the excluded earlier jq attempt—proved five Ready nodes, five Running Agents, Operator audit81 at 1/1, 40 pool entries, zero used addresses outside their pools, zero CiliumNode operator errors, zero recent severe/authentication log matches, and matrix `56/56`.
- Evidence: `/tmp/audit81-production-client.out`, `/tmp/audit81-customer-http.out`, `/tmp/audit81-customer-tcp.out`, `/tmp/audit81-customer-sourceip.out`, and `/tmp/audit81-final-health.out`. Diagnostic endpoint-attribution runs are retained only as root-cause evidence and are not counted as acceptance passes.
- This closes API-01, API-02, API-03, API-04, API-06, API-07, IPAM-34, and REC-19. The ledger is now 361 Pass, 85 Pending, 5 approved environment Skips, and 0 Fail.

# Current-candidate Operator rollback and restore audit81

- With `huawei-cloud-release-excess-ips=false`, the retained audit76 image and current audit81 image were exercised through a real `audit81 -> audit76 -> audit81` Deployment transition. Both rollout windows had exactly one Ready Operator, zero restarts, no recent severe reconciliation log matches, and matrix `56/56`.
- The exact sorted CiliumNode pool mapping SHA256 remained `0202559d518c2e47dd0c758290b9171ae6d2e0e1298b9640b265cc322425799a` before rollback, after the audit76 window, and after restoring audit81. The cleanup trap left audit81 active. Evidence: `/tmp/audit81-operator-rollback-restore.out`.
- This independently refreshes UPG-06/UPG-10 coverage for the current candidate and closes UPG-01. The ledger is now 362 Pass, 84 Pending, 5 approved environment Skips, and 0 Fail.

# Secret rotation and cleanup audit82

- The referenced Secret was copied entirely inside Kubernetes to a temporary rotated name without exporting or logging credential data. Both AK/SK references moved atomically to the rotated Secret; the audit81 Operator reached Ready with zero restarts and no authentication errors, matrix passed `56/56`, and the exact pool mapping remained unchanged. The existing wrong-namespace boundary was also rerun while the known-good Operator stayed Ready.
- The original references were restored and both temporary Secrets were deleted. A corrected independent final audit proved the audit81 image active, the original Secret reference exact, one Ready zero-restart Operator, 40 pool resources, zero CiliumNode operator errors, and no audit82 Secret residue. Evidence: `/tmp/audit82-secret-rotation.out`. The earlier malformed jq diagnostic was excluded from acceptance.
- Repository and complete Git-history high-confidence secret scans found zero private-key PEM, AKIA-like key, or inline cloud-secret matches. `ANALYSIS` contains no raw `.out`, `.log`, `.tar`, or `.key` artifacts; archived evidence contains only redacted conclusions and `/tmp` evidence pointers.
- Audit81's production-client cleanup additionally proved the exact cloud parent-port SubENI ID set matched all 40 CiliumNode pool IDs, with no probe/deleted resource IDs remaining. This closes SEC-08, CLEAN-04, CLEAN-07, and CLEAN-08. The ledger is now 366 Pass, 80 Pending, 5 approved environment Skips, and 0 Fail.

# Legacy shared-route migration audit83

- On node0003, the runner selected an active matrix Pod using independent VLAN table `13109`, stopped kubelet and its current Agent container, then injected the exact legacy form: priority `111`, source equal to the Pod `/32`, and route table equal to trunk `eth0` ifindex `2`. Injection was verified while the Agent was stopped, so this was not a no-op race with the running reconciler.
- After kubelet restarted, the same Agent process startup removed the legacy table-2 rule, retained exactly one current source rule to table `13109`, and retained the complete gateway nexthop/default route pair. The full CiliumNode pool mapping was byte-identical and matrix passed `56/56` before and after migration.
- The deliberately restarted Agent Pod was replaced after acceptance; its successor was Ready, `cilium status --brief=OK`, restart count zero, and final matrix again passed `56/56`. The runner has shared locking plus EXIT/INT/TERM cleanup. Evidence: `/tmp/audit83-legacy-route-migration.out`.
- This closes ROUTE-09 and UPG-02. The ledger is now 368 Pass, 78 Pending, 5 approved environment Skips, and 0 Fail.

# VLAN kernel-evidence reconciliation audit84

- Independent review of `/tmp/audit59-huaweicloud-bpf-run-count20-final2.out` counted exactly 20 complete privileged kernel `TestBPF` passes, 20 passes each for the dual inline-plus-metadata case, nested VLAN case, scalar boundary case, and unknown-inline case, with no FAIL or panic marker. The complete all-object kernel run also passed.
- The packet-level dual-representation check starts with an inline 802.1Q frame, adds a matching hardware metadata VLAN, verifies both representations, performs the real map hit, and proves the final skb has `vlan_present=false`, one Ethernet header, no VLAN header, and IPv4 ethertype. The 802.1ad packet enters the inline parser and fails closed on an unknown map key. Separate two-tag QinQ and three-tag packets both fail closed with `handled=false`.
- The authoritative test source SHA256 is `c745e2d62b5dc73700efe439365d0b9890f5a3e3801810fa20f0f89872a608a9`; it remains in the exact authoritative source/15-patch tree used by the deployed Agent BPF payload. This evidence closes VLAN-03, VLAN-04, VLAN-06, and VLAN-13. VLAN-01 and VLAN-11 remain Pending because this audit does not overclaim a standalone IPv4 metadata-only packet or a physically truncated skb. The ledger is now 372 Pass, 74 Pending, 5 approved environment Skips, and 0 Fail.

# Subnet-tag and cloud-consistency reconciliation audit85

- `TestFindOneSubnetTagConjunctionNoMatchAndMultipleCandidates` supplies two fully matching tag candidates, two high-capacity partial matches, and a wrong-AZ full match. Across 100 internal selections it always chooses the highest-capacity complete AND match; changing one requested value to a missing value returns nil. Audit81's complete HuaweiCloud package ran this suite ten times, covering multi-tag AND, no-match, and multiple-eligible selection without nondeterminism.
- The API visibility tests explicitly drive NotFound to BUILD to ACTIVE, accept ACTIVE at the deadline boundary, and stop on timeout/cancel. Audit81's real cloud lifecycle additionally verified post-create Show/List visibility and polled every delete to NotFound before proving the exact final parent-port set.
- Audit81's real single and batch Create requests carried inline resource tags, and subsequent real Show responses returned the exact two expected tags in cn-south-1. This closes API-17, IPAM-05, IPAM-07, IPAM-12, and IPAM-21. Empty/special-character tag values remain Pending under IPAM-06. The ledger is now 377 Pass, 69 Pending, 5 approved environment Skips, and 0 Fail.

# Thirty-minute cleanup re-audit audit86

- At exactly 1801 seconds after the audit81 final-cleanup checkpoint, a fresh independent audit found five Ready Nodes, five Ready zero-restart Agents with `cilium status --brief=OK`, one Ready zero-restart audit81 Operator, 40 pool entries, no used address outside its pool, no CiliumNode operator error, no abnormal Pod, no audit80/audit82 temporary Secret, and no recent severe/authentication log match.
- Every node retained all priority-111 source rules, every referenced independent table contained exactly the gateway nexthop/default pair, and every trunk retained the permanent gateway neighbor. Matrix traffic passed `56/56`. Evidence: `/tmp/audit86-cleanup-30m.out`. This closes CLEAN-10.

# Exact empty and special subnet-tag values audit87

- `TestFindOneSubnetMatchesEmptyAndSpecialTagValuesExactly` proves a requested empty value requires the key to exist: a higher-capacity subnet missing that key cannot match. It also proves key/value punctuation including `:=+_./@-` remains opaque and exact; appending a suffix correctly produces no match.
- The targeted test passed 100 ordinary and 20 race-enabled repetitions. The full ENI package and all HuaweiCloud packages passed ten ordinary and ten race-enabled repetitions, and `go vet ./pkg/huaweicloud/...` passed. Old overwritten test/build outputs were removed after evidence collection.
- The original 14 functional patches remain unchanged. Authoritative source `2752f1f1a5a9088a9cb7e0d3d8b55928d998facf`, consolidated patch-generation commit `596cd3a1366b8e9e2451e3857ba9f0a2089f7339`, and clean 15-patch replay `5a769b24151edfa10884c63fa2c4871d353b4321` share tree `5deb2c9a650a0936d532a5aa67c66a87828496d9`. Patch 0015 SHA256 is `b84beacad977604f5ef431234abdc267e40388086df63e81151472ef96b1323e`; the temporary patch-generation worktree was removed and the clean replay retained.
- This closes IPAM-06. With CLEAN-10, the ledger is now 379 Pass, 67 Pending, 5 approved environment Skips, and 0 Fail. Runtime product code did not change, so the already verified audit81 Operator and audit64 Agent images remain authoritative and no unnecessary image rebuild/rollout was performed.

# Explicit route compatibility and VLAN table boundaries audit88

- The first live attempt restarted too quickly after changing the ConfigMap and correctly failed acceptance because the projected volume still contained the old value. The runner was repaired to wait for the target Agent's projected file before restart; only the final run is counted.
- With explicit `egress-multi-home-ip-rule-compat=true`, node0003's two active matrix Pod source rules moved from priority 111 to compatibility priority 110. Each active Pod had exactly one expected rule and no same-source rejected-priority rule; all referenced per-VLAN tables retained exactly the gateway nexthop/default pair, the pool mapping was unchanged, and matrix passed `56/56`. Removing the temporary key after waiting for projection moved both active Pods back to priority 111 with no priority-110 duplicate, unchanged pool, and another `56/56` pass. The final Agent is Ready/OK with restart zero and the ConfigMap key is absent. Evidence: `/tmp/audit88-route-compat-toggle-final.out`.
- `TestEgressRulePriorityAndTableID` and `TestHuaweiCloudRoutingInfoBoundaries` passed 100 ordinary and 20 race repetitions; the complete privileged routing package passed 20 ordinary and 10 race repetitions, and vet passed. Coverage includes VLAN 1, 244, 4094 with compatibility priority, rejection of 0/4095, nonnumeric/empty interface numbers, invalid gateway/MAC/CIDR, exact priority/table values, and distinct tables for distinct VLANs. Remote overwritten test outputs were removed after evidence collection.
- This closes ROUTE-11, ROUTE-13, and ROUTE-14. The ledger is now 382 Pass, 64 Pending, 5 approved environment Skips, and 0 Fail.

# Concurrent multi-target and public-failure isolation audit89

- From customer pod2, each of 20 rounds launched four requests in the same shell window: a direct cross-node request to pod3, ClusterIP service request, remote-node NodePort request, and public `1.1.1.1` request. All three VPC/service targets passed in every round while the public request consistently timed out under the customer's `enable-ipv4-masquerade=false` configuration.
- Acceptance explicitly required the public request to fail and all three internal requests to succeed before a round passed. Final read-only checks found five Ready zero-restart Agents, 40 pool entries, and no used address outside its pool. Evidence: `/tmp/audit89-public-fail-vpc-ok.out`.
- This closes EGR-03 and EGR-04. The ledger is now 384 Pass, 62 Pending, 5 approved environment Skips, and 0 Fail.

# Bounded Create timeout and fail-fast cloud configuration audit90

- `NewClient` now trims and validates the configured endpoint, region, and project ID before constructing SDK clients. Endpoint validation requires an HTTP(S) URL with a host and rejects embedded credentials, query, and fragment components; region and project IDs reject path/control separators while preserving syntactically valid future region fallback. A wrong but syntactically safe project remains scoped to `/v3/wrong-project/...`; the controlled server returned 404 and no success object.
- `TestCreateSubNetworkInterfaceHTTPTimeout` uses a 20ms SDK transport timeout against a 200ms Create handler. Every timed-out call returned an error with no ID/object, issued exactly one request, and completed under the 500ms guard. This is intentionally evidence for the SDK HTTP bound, not a false claim that the vendor SDK propagates caller cancellation into an in-flight request.
- The four focused configuration/timeout tests passed 100 ordinary and 20 race repetitions. The complete API package passed 20 ordinary and 20 race repetitions; all HuaweiCloud packages passed ten ordinary and ten race repetitions; `go vet ./pkg/huaweicloud/...` passed. Evidence: `/tmp/audit90-target100.out`, `/tmp/audit90-target-race20.out`, `/tmp/audit90-api-full20.out`, `/tmp/audit90-api-race20.out`, `/tmp/audit90-huawei-full10.out`, `/tmp/audit90-huawei-race10.out`, and `/tmp/audit90-vet.out`.
- The affected Operator was rebuilt only after deleting the previous output. Binary SHA256 is `da938ae0b57f367492528cc00e90f68ba37e09872e7d8b56ef3a6d0ece067490`; OCI tar SHA256 is `aae80d7bb11b6be4df5311838e329d35474e92710438227e7b86c7107c542d01`, and all five nodes imported manifest `sha256:dd6c205016d901cebbf4dcf9251b89c3881377b42d1aa369cda9f2f68483455c`. The audit81→audit90 rollout reached one Ready zero-restart Operator while the complete pool mapping remained `0202559d518c2e47dd0c758290b9171ae6d2e0e1298b9640b265cc322425799a`.
- Post-rollout matrix passed `56/56`; all 21 customer HTTP scenarios passed `100/100`, all four bidirectional TCP scenarios passed `5/5`, and all 19 source-IP assertions passed. Isolated live candidates used separate leader-election namespaces so the production singleton was never replaced: invalid endpoint and invalid region each exited `Failed` with the exact fail-fast reason. Both test namespaces and Pods were deleted, endpoint returned absent, region returned `cn-south-1`, production Operator stayed Ready/restart0, and pool identity was unchanged. Evidence: `/tmp/audit90-operator-rollout.out`, `/tmp/audit90-mesh.out`, `/tmp/audit90-customer-http.out`, `/tmp/audit90-customer-tcp.out`, `/tmp/audit90-customer-sourceip.out`, `/tmp/audit90-invalid-api-config-final.out`, `/tmp/audit90-postnegative-mesh.out`, and `/tmp/audit90-final-health.out`.
- The original 14 functional patches remain unchanged. Authoritative source `396adfa0905618c795175dfeafafeb8a4ef7c4a6`, consolidated patch-generation commit `bdc179e3cdf3b5bf3f58d29c2e6525cf52776129`, and clean 15-patch replay `861b1521205d451eea7489b02c98c24ef5faae98` share tree `c95f0c0be77506dea53543b37bc655c2a7ae0c3f`. Patch 0015 SHA256 is `a75efce037f41dfb425b9109c1a144198e1c83c35c9b5d4b26bb4f972bccb176`; superseded build/package outputs and the patch-generation worktree were removed, while the clean audit90 replay and audit81 rollback image were retained.
- This closes API-09 and API-18. The ledger is now 386 Pass, 60 Pending, 5 approved environment Skips, and 0 Fail. Audit90 Operator and audit64 Agents are authoritative.

# External Secret Helm lifecycle audit91

- The exact audit90 committed Chart was exported through Git and installed as an isolated Helm release with Agent and Operator resources disabled, HuaweiCloud enabled, and a pre-created non-secret fixture selected through `huaweicloud.existingSecret`. The release manifest never contained the external Secret and Helm ownership labels/annotations were absent from it.
- Across install revision 1, upgrade revision 2, and rollback-to-1 history revision 3, the Secret's UID, resourceVersion, sorted data hash, and non-Helm ownership state remained exact. After `helm uninstall`, the release was absent while the same Secret still existed unchanged; only then did the runner explicitly delete the fixture and namespace.
- The isolated release, namespace, Secret, transferred Chart, and runner were removed. The production audit90 Operator remained Ready/restart0 with pool40, and a fresh matrix passed `56/56`. Evidence: `/tmp/audit91-helm-external-secret.out` and `/tmp/audit91-post-mesh.out`.
- This closes SEC-13 and SEC-14. The ledger is now 388 Pass, 58 Pending, 5 approved environment Skips, and 0 Fail.

# Request-ID propagation and invalid security-group isolation audit92

- `TestAPIErrorIncludesRequestIDWithoutCredentials` injects a unique `X-Request-Id` for HTTP 400, 401, 403, 404, 429, and 500. Every normalized error retained the exact request ID and excluded the access-key fixture, secret-key fixture, and Authorization header name. The focused test passed 100 ordinary and 20 race repetitions; API full passed 20 ordinary and 20 race repetitions; all HuaweiCloud packages passed ten ordinary and ten race repetitions; vet passed. Evidence: `/tmp/audit92-requestid-target100.out`, `/tmp/audit92-requestid-race20.out`, `/tmp/audit92-api-full20.out`, `/tmp/audit92-api-race20.out`, `/tmp/audit92-huawei-full10.out`, `/tmp/audit92-huawei-race10.out`, and `/tmp/audit92-vet.out`.
- The first real invalid-SG request was intentionally excluded: with the target parent already at eight SubENIs, HuaweiCloud returned `VPC.9905 subeni_attached_to_vm quota exceeded` before validating the SG. The corrected run cordoned node0003, stopped the Operator, and deleted exactly one pool resource independently proven unused. With capacity at seven, a Create using the all-zero invalid SG was rejected specifically as a security-group error and carried a non-empty request ID. The seven-resource parent-set hash was identical before and after the rejected Create, proving no partial resource appeared.
- Restarting audit90 Operator replenished exactly one new resource. The deleted ID was absent, the recovered CiliumNode eight-resource set exactly matched the live cloud parent set, total pool returned 40, every used IP remained in its pool, operator errors were empty, the node was uncordoned, and matrix passed `56/56`. The compiled probes and overwritten build outputs were removed. Evidence: `/tmp/audit92-invalid-sg-live-final.out`, `/tmp/audit92-post-sg-mesh.out`, and `/tmp/audit92-invalid-sg-tool-final-build.out`.
- The original 14 functional patches remain unchanged. Authoritative source `12b37635d79acd25949b4926b61329f5f519513c`, consolidated patch-generation commit `cecd65a10ecba97c47f8705f8dda839e8daf62a5`, and clean 15-patch replay `4e8bb5679e31266405566a9a128eb941265b5e8d` share tree `591aa02eb2826b5d2101e7de468d2907fefd4092`. Patch 0015 SHA256 is `2436c9604202914edc4c66584cc89b1be2fe0cd87f203b317f850000a988e9c1`; the temporary patch-generation worktree and superseded audit90 replay were removed.
- This closes OBS-08 and IPAM-19. The ledger is now 390 Pass, 56 Pending, 5 approved environment Skips, and 0 Fail. Audit90 Operator and audit64 Agents remain authoritative because audit92 changed tests and evidence tooling only.

# Isolated cloud API network and DNS failures audit93

- Two audit90 Operator candidates were started from the live Deployment template with probes removed, restart policy `Never`, pod networking enabled, and independent leader-election namespaces. This let each candidate execute the HuaweiCloud allocator path without joining or replacing the production singleton.
- The network case used a syntactically valid TEST-NET endpoint on a closed/blackholed port and exited `Failed` with a connection/timeout-attributed error. The DNS case used a guaranteed nonexistent `.invalid` endpoint and exited `Failed` with a resolver-attributed error. Neither case was accepted merely from a nonzero exit; the runner required the exact error class in candidate logs.
- During both failures the same production audit90 Pod stayed Ready with restart zero and the complete pool mapping hash remained `21e3d78c6fcd26c2b4ed2e3534bf1112d671c84e6094c289e4dc81209423d1bc`. Both test Pods and leader namespaces were deleted, `huawei-cloud-endpoint` returned absent, pool remained 40 with zero operator errors, and fresh matrix traffic passed `56/56`. Evidence: `/tmp/audit93-api-network-dns.out` and `/tmp/audit93-post-mesh.out`.
- This closes REC-11 and REC-12. The ledger is now 392 Pass, 54 Pending, 5 approved environment Skips, and 0 Fail.

# Real cloud resource timeline re-audit audit94

- A fresh production-client run cordoned node0003 and stopped the Operator before selecting exactly two unused pool resources. The accepted event order was: delete both existing resources and wait for NotFound; create one SubENI with two inline audit tags and verify its create response, Show, exact parent List, and exact tags; delete it and wait for NotFound; batch-create two resources, verify every response, Show, exact tags, and parent List; delete both and wait for NotFound; verify the cloud parent set contains exactly the six untouched baseline resources.
- Restarting the unchanged audit90 Operator replenished the target CiliumNode to exactly eight resources. A second production-client query proved the live cloud parent set exactly matched those eight CiliumNode resource IDs, both pre- and post-change matrix checks passed `56/56`, and the node was uncordoned. Independent final health found five Ready nodes, Agent `5/5`, Operator `1/1`, pool40, used-outside0, zero operator errors, zero unschedulable nodes, and no remote audit94 probe.
- The x86-64 static evidence probe SHA256 was `1c1affa1bc0d9564bd22af463789da765a773f64c99d1b9bfebe0e5d50516e41`; the accepted timeline output SHA256 was `f51ea1c1155173f8fc83f758384fcca8adb1ee0887b6d0a8fd07d245973de990`. Evidence: `/tmp/audit94-cloud-crud.out` and `/tmp/audit94-final-health.out`. This closes OBS-09. The ledger is now 393 Pass, 53 Pending, 5 approved environment Skips, and 0 Fail.

# HuaweiCloud IPv6 fail-fast boundary and Agent rollout audit95

- Code review found HuaweiCloud IPAM had been excluded from several IPv4-native-routing checks but, unlike ENI mode, did not reject `enable-ipv6=true`; this could let an unsupported address family reach runtime initialization. `DaemonConfig.Validate` now uses a dedicated IPv6/IPAM check that preserves the existing ENI rejection, rejects HuaweiCloud IPv6 explicitly, accepts HuaweiCloud IPv4-only, and leaves cluster-pool IPv6 unchanged. Vet caught the first test revision copying a `DaemonConfig` containing a lock; the test was repaired to use pointers and all final checks were rerun.
- The focused boundary test passed 100 repetitions. The complete option package passed in 20 independent processes, race-enabled in ten independent processes, and vet passed. A clean 15-patch replay repeated the focused test 100 times, the package ten times, race five times, and vet. The earlier in-process `-count=20` run was excluded because an unrelated pre-existing test globally re-registers `node-port-range`; independent-process repetition is the accepted package evidence. Evidence: `/tmp/audit95-ipv6-target100-final.out`, `/tmp/audit95-option-full20-final.out`, `/tmp/audit95-option-race10-final.out`, `/tmp/audit95-vet-final.out`, `/tmp/audit95-replay-target100.out`, `/tmp/audit95-replay-option10.out`, `/tmp/audit95-replay-option-race5.out`, and `/tmp/audit95-replay-vet.out`.
- Two clean normal-resource cross-builds produced the identical static linux/amd64 Agent SHA256 `cd0a6ad1c0788b0325d2b753364dbd5d09b364ce4059e3a7cc07aee633712c6d`. The image includes the complete 165-file BPF install tree and authoritative `huaweicloud.h` SHA256 `8dae79a6000869b26469accbd48c7ef84b669b7a10d313d2e3a1e08ed0cbab83`; full OCI tar SHA256 was `b9a29b61fa245da14afad482f47e6b4d140e9901ccdbd1bcbb58c4cabb48ea70`, manifest `sha256:151f1aa187cda45036beef28ba82db74e8b9c40e865b549b88ad04e1750f7592`, and runtime config/image ID `sha256:3e4981b4729bdb940277a111a7a8d7fa8a9bc84f3e6b63dd144f4294c821c4d1`.
- An isolated privileged audit95 container used its own mount and network namespaces and exited nonzero with the exact fatal reason `invalid daemon configuration: IPv6 cannot be enabled in HuaweiCloud IPAM mode`. The two earlier candidates that stopped first on missing Kubernetes identity configuration or an unprivileged BPF mount were excluded. The live customer configuration remained `ipam=huaweicloud`, `enable-ipv6=false`.
- Every node was then upgraded sequentially; after each Agent reached Ready with the exact binary/image hash, restart zero, and `status=OK`, matrix traffic passed `56/56`. The final ten-round recreate matrix passed `56/56` in every round; all 21 customer HTTP cases passed `100/100`, all four bidirectional TCP cases passed `5/5`, and all 19 source-IP assertions passed. Independent final audit found five Ready nodes, five exact audit95 Agent and BPF hashes, Operator audit90 `1/1`, pool40, used-outside0, zero operator errors, zero severe Agent matches, and no unschedulable node. Superseded build/package transfers and the patch-generation worktree were removed; audit64 is retained as rollback. Evidence: `/tmp/audit95-live-invalid-ipv6-final2.out`, `/tmp/audit95-agent-rollout.out`, `/tmp/audit95-matrix10.out`, `/tmp/audit95-customer-http.out`, `/tmp/audit95-customer-tcp.out`, `/tmp/audit95-customer-sourceip.out`, and `/tmp/audit95-final-health.out`.
- Authoritative source `4c163c22dcb7624db2851636b1a303c563311f89`, consolidated patch-generation commit `2017fefe578973c2cad58de8c0c62cf834d137d9`, and clean 15-patch replay `55a1a7d8dae455113c22a50158eb6fa0a61230a5` share tree `e6566242cca232f0bfe594edb5cbb8e4e2b11a56`. Patch 0015 SHA256 is `57254e282cfb4498d9c0f04d8b0d62ceffa24ad37fddfb780aa602039fcb576f`. This closes IPV6-01. The ledger is now 394 Pass, 52 Pending, 5 approved environment Skips, and 0 Fail. Audit95 Agents and audit90 Operator are authoritative.

# Kubernetes Event backlog isolation audit96

- A reproducible locked runner created an isolated namespace and inserted exactly 1000 unique core/v1 Event objects in one workload. A forced 50-item paginated read returned all 1000 objects in 2110ms, so acceptance did not rely only on successful writes.
- During the full backlog window, the sorted Agent Pod UID/restart set and Operator Pod UID/restart set remained byte-identical, the complete CiliumNode pool mapping SHA256 remained `4e18d2edcacadf39996a1f730314c3ffcd42ee2e35a0559f85b523910483465f`, and matrix traffic passed `56/56`. The runner's EXIT cleanup removed the namespace and all Events. Independent post-cleanup health proved the namespace absent, five Ready nodes, Agent `5/5`, Operator `1/1`, pool40, and zero CiliumNode operator errors.
- Shell syntax, optional shellcheck, and whitespace review passed. Evidence: `/tmp/audit96-event-backlog.out` and `/tmp/audit96-final-health.out`. This closes REC-24. The ledger is now 395 Pass, 51 Pending, 5 approved environment Skips, and 0 Fail.

# Metadata-only IPv4 and VLAN/MAC key-boundary kernel audit97

- A new privileged kernel BPF suite constructs a real IPv4 Ethernet packet with VLAN represented only in skb metadata and no inline VLAN header. With an exact VLAN+destination-MAC map entry, `hwc_from_netdev` returned `CTX_ACT_OK`, set `handled=true`, and removed the metadata tag. Two separate negative cases then held VLAN constant while changing the packet MAC, and held MAC constant while changing VLAN; both returned `CTX_ACT_OK`, kept `handled=false`, retained metadata for the generic VLAN policy path, and never redirected to the wrong endpoint.
- The isolated HuaweiCloud BPF object compiled cleanly and its complete kernel suite passed once with verbose per-case evidence and 20 repetitions. All eight BPF test objects then compiled and ran through the real kernel verifier/executor successfully. A clean 15-patch replay repeated the focused kernel suite 20 times and the complete eight-object run once. Generated `.o`/`.ll` outputs were removed after testing. Evidence: `/tmp/audit97-bpf-compile.out`, `/tmp/audit97-bpf-run.out`, `/tmp/audit97-bpf-run-count20.out`, `/tmp/audit97-bpf-all-compile.out`, `/tmp/audit97-bpf-all-run.out`, `/tmp/audit97-replay-bpf-compile.out`, `/tmp/audit97-replay-bpf-count20.out`, `/tmp/audit97-replay-bpf-all-compile.out`, and `/tmp/audit97-replay-bpf-all-run.out`.
- The test source SHA256 is `b50f28f7a03b4b58824597750e415327c7b09e4fa6507dcb249b473c7f3be640`. Authoritative source `d92e6020da6b57f88e69dc6ba52ba40a6252d852`, consolidated patch-generation commit `0a18e5bd1cb0204be403af389d167e681431d831`, and clean 15-patch replay `d7abec593e28b869489f199f041a460fbd235259` share tree `1820ef8087b7274a37907436f94a1d10a394b4de`. Patch 0015 SHA256 is `2d6caca1a85e26cd3163fd43848d30e432168785035887f506b00631adf73cb1`.
- Runtime product/BPF code did not change, so no unnecessary Agent rebuild occurred. The authoritative audit95 cluster remained healthy and a fresh matrix passed `56/56`. This closes VLAN-01, VLAN-09, and VLAN-10. The ledger is now 398 Pass, 48 Pending, 5 approved environment Skips, and 0 Fail.

# User-approved long-duration stability exclusions

- On 2026-07-15 the user explicitly stated that 24/72-hour stability tests are unnecessary. STAB-01, STAB-02, STAB-03, the same-class long-idle STAB-04, and BRACE-12 are therefore recorded as user-approved `Skip`, not `Pass` and not product failures. Short, bounded functional, recovery, concurrency, and regression cases remain in scope.
- The ledger is now 398 Pass, 43 Pending, 10 user-approved Skips, and 0 Fail.

# Real truncated VLAN skb kernel audit98

- The accepted privileged kernel test builds a 17-byte skb containing a complete Ethernet header whose protocol is 802.1Q, followed by a VLAN header truncated by exactly one byte. `hwc_from_netdev` returned `DROP_INVALID` and left `handled=false`, proving the real packet parser fails closed before reading the incomplete VLAN fields. This supersedes the earlier scalar length-helper-only evidence.
- An excluded first attempt also tried a 13-byte packet, but `BPF_FUNC_skb_change_tail` itself rejects frames shorter than the mandatory Ethernet header, so product code never received that input. The runner was corrected to retain only the realizable, case-relevant truncated VLAN skb; the corrected test passed once with verbose evidence and 20 repeated complete HuaweiCloud object runs. All eight BPF test objects compiled and executed successfully.
- The clean 15-patch replay repeated the HuaweiCloud kernel suite 20 times and ran all eight BPF objects once. Generated `.o`/`.ll` outputs were removed. Test source SHA256 is `8604228bcd5432bb074084f4c1e514bcc3c5e633d98b6ed03868f718da62d5af`. Evidence: `/tmp/audit98-bpf-compile-final.out`, `/tmp/audit98-bpf-run-final.out`, `/tmp/audit98-bpf-count20-final.out`, `/tmp/audit98-bpf-all-compile.out`, `/tmp/audit98-bpf-all-run.out`, `/tmp/audit98-replay-bpf-compile.out`, `/tmp/audit98-replay-bpf-count20.out`, `/tmp/audit98-replay-bpf-all-compile.out`, and `/tmp/audit98-replay-bpf-all-run.out`.
- Authoritative source `74de651a7adb763ef9ad3b05e5b06206c57ce585`, consolidated patch-generation commit `b6f03b494412ef218b0a110a0af43e89fcbf2c12`, and clean 15-patch replay `485db52ed8038161db8c33b233f68fe89f7742dc` share tree `24d9e81b614f4a4309cfaa964e5efc11f9dbef58`. Patch 0015 SHA256 is `9c63bc0d35b067295e5fabe4c0eabf688d06332a9e9adfaed9ab574dfe4619bd`. Product/BPF runtime code did not change, so audit95 Agents remain authoritative; post-test mesh passed `56/56`. This closes VLAN-11. The ledger is now 399 Pass, 42 Pending, 10 user-approved Skips, and 0 Fail.

# Non-trunk VLAN bypass kernel audit99

- A separate privileged kernel BPF object constructs an IPv4 Ethernet skb with VLAN represented in metadata while `ctx->ifindex` is explicitly different from `HWC_TRUNK_IFINDEX`. Before invoking the product path, the test inserts an exact VLAN+destination-MAC entry into `cilium_hwc_vlan_mac`, so a missing lookup cannot mask an erroneous redirect. `hwc_from_netdev` returns `CTX_ACT_OK`, sets `handled=false`, and leaves the VLAN metadata present, proving non-trunk traffic bypasses HuaweiCloud endpoint redirection unchanged.
- The accepted test passed once with verbose evidence and 20 complete focused-object repetitions. All nine BPF test objects compiled and passed the real kernel verifier/executor. A clean 15-patch replay repeated the focused object 20 times and ran all nine objects once. Generated `.o`/`.ll`/`.s` outputs and the superseded audit98 replay were removed. Two earlier verifier attempts were excluded: the test-only stack key/value layout caused a compiler-generated unaligned load and was corrected with verifier-safe aligned backing storage; no product code changed.
- Test source SHA256 is `cbc8a5167e74d2d049a808289a575a5d61c4e69ab8154a34b090105f857fefaf`. Authoritative source `2451099d91eeea13033e38f61c4ec8b5eb704783`, consolidated patch-generation commit `eee1675ac6b7a2a29698eeb2b99498f2c4699ff2`, and clean 15-patch replay `4f14c77b9fa0716485c1d8cdf8e5e71945888055` share tree `67a1ccc15965f77070359b475db763f767822cca`. Patch 0015 SHA256 is `375c7bec721afa11909d988eed6e99e41a3dcb9163667563c135e98b8612b052`. Evidence: `/tmp/audit99-bpf-compile-final.out`, `/tmp/audit99-bpf-run-final.out`, `/tmp/audit99-bpf-count20-final.out`, `/tmp/audit99-bpf-all-compile.out`, `/tmp/audit99-bpf-all-run.out`, `/tmp/audit99-replay-bpf-compile.out`, `/tmp/audit99-replay-bpf-count20.out`, `/tmp/audit99-replay-bpf-all-compile.out`, and `/tmp/audit99-replay-bpf-all-run.out`.
- Runtime product/BPF code did not change, so audit95 Agents and audit90 Operator remain authoritative. Five nodes and five zero-restart Agents remained Ready, Operator remained `1/1`, and the fresh post-test matrix passed `56/56`. Evidence: `/tmp/audit99-post-mesh.out` and `/tmp/audit99-live-health.out`. This closes VLAN-14. The ledger is now 400 Pass, 41 Pending, 10 user-approved Skips, and 0 Fail.

# VLAN pop failure-injection kernel audit100

- A separate privileged kernel BPF object replaces only the test translation unit's `skb_vlan_pop` call with a deterministic failing implementation while compiling and executing the unchanged production `hwc_from_netdev` control flow. The test constructs metadata-only IPv4 VLAN traffic on the trunk ifindex and inserts an exact VLAN+destination-MAC endpoint-map entry, ensuring execution reaches the pop operation rather than an earlier bypass or map miss.
- With the map hit established, `hwc_from_netdev` returned exactly `DROP_HWC_VLAN_POP_FAIL`, never returned success, set `handled=true` only to reflect the already selected endpoint, and left VLAN metadata present because the injected pop did not modify the skb. The focused object passed once verbosely and 20 complete repetitions; all ten BPF objects compiled and passed the real kernel verifier/executor. A clean 15-patch replay repeated the focused object 20 times and ran all ten objects once. Generated `.o`/`.ll`/`.s` outputs and the superseded audit99 replay were removed.
- Test source SHA256 is `4828b1aff161fb9fa7ed3c995c46c9e6b352614d8321911f665149d3cee6a217`. Authoritative source `aa8401248472be5449e53b54eac7e4cbcda322a8`, consolidated patch-generation commit `323d2e1685246e6f56d12092e17a0c2b1570708d`, and clean 15-patch replay `a50404da8b26ad4b950f2ce2218057f074552d17` share tree `a9c7ee2fd85eb516832682287219f731206f0c5a`. Patch 0015 SHA256 is `d85312b46e5972703b613b42336cfcb6778debcb8689b454d24aac721454789e`. Evidence: `/tmp/audit100-bpf-compile.out`, `/tmp/audit100-bpf-run.out`, `/tmp/audit100-bpf-count20.out`, `/tmp/audit100-bpf-all-compile.out`, `/tmp/audit100-bpf-all-run.out`, `/tmp/audit100-replay-bpf-compile.out`, `/tmp/audit100-replay-bpf-count20.out`, `/tmp/audit100-replay-bpf-all-compile.out`, and `/tmp/audit100-replay-bpf-all-run.out`.
- Product/BPF runtime code did not change, so no Agent rebuild or rollout was needed. Five nodes and five zero-restart Agents remained Ready, audit90 Operator remained `1/1`, and a fresh post-test matrix passed `56/56`. Evidence: `/tmp/audit100-post-mesh.out` and `/tmp/audit100-live-health.out`. This closes VLAN-12. The ledger is now 401 Pass, 40 Pending, 10 user-approved Skips, and 0 Fail.
