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
- No product change or rebuild was required. This closes PRE-12 and REC-16. The ledger is now 318 Pass, 129 Pending, 4 approved environment Skips, and 0 Fail.
