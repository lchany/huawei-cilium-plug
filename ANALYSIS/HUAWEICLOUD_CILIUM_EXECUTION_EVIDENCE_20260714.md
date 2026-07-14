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
- The repaired audit49 Agent was built as an amd64 static binary with the project Makefile and `ipam_provider_huaweicloud` tag. Live BIPAM-21 remains Pending until audit49 canary/full rollout and deletion/recreation retest complete.
