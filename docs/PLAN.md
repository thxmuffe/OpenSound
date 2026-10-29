# Development plan

Created: 2026-10-23. Current development order revised: 2026-10-29.

Update 2026-10-26: the newer [Parvi handover](notes%2020261026.md) introduces a
chat-first feasibility phase before these audio milestones. The Mac OTP chat
baseline is now implemented; iPhone execution is verified on the physical phone. Follow
[the progress log](PROGRESS.md) and [decision 0001](decisions/0001-chat-first-and-ios-feasibility.md)
for current scope and next steps. The audio targets below remain unvalidated.

## Current implementation plan — accepted 2026-10-28

This section governs the immediate Parvi app and connectivity work. The original
audio milestones below remain research proposals; their stable-device-identity
and LAN-first assumptions do not govern the current swarm protocol.

### Implementation approach — revised 2026-10-29

Build small, useful increments and continue implementation without a separate
testing phase or a comprehensive recovery programme as a prerequisite. Check
behavior when a change needs evidence, something seems wrong, or the next
implementation decision depends on it. Ask before adding automated tests or
hardening; routine builds, deployments and repeated regression runs are not
default tasks. Record what is implemented and what remains unverified.

Use the single Render-hosted Reception Desk for development, testing and
production. Service changes and interruptions are authorized; no separate desk
or environment is required.

**Next implementation:** integrate the existing native carrier, trust worker
and desk connector into the Mac app, reusing the shared OTP runtime. Make one
invitation/join/chat path usable first. Check that path through Render when
needed to make the integration work, then extend the packaging to iPhone.
Address recovery and TURN when actual use or the next feature requires them.

### Architecture decision: BEAM/OTP on server and in browser

Use Phoenix with its Cowboy adapter for the server host, and Popcorn 1.0 with
LocalLiveView for the browser app. Keep the shared swarm/chat core in Erlang/OTP;
use Elixir for web components and integration where it reduces work. The priority
is BEAM processes, message passing and OTP supervision, rather than a particular
source language. This is an accepted direction, not an implemented stack.

Update 2026-10-28: prefer Erlang for our own implementation. The direct peer
worker now calls `ex_webrtc` from Erlang; the custom Elixir peer module was
removed. Upstream Elixir libraries and the existing Phoenix service remain
dependencies, so this is not a plan to reimplement WebRTC or rewrite the working
Reception Desk merely to remove a source language. The browser experiment
remains deferred.

- `Services/ReceptionDesk`: independent service for rendezvous, permission-checked
  mailboxes and relay mechanisms. Its Erlang workers can run inside the
  Phoenix/Cowboy BEAM application without another server-language runtime.
- `Apps/WebApp`: a browser-local node, using Popcorn's WebAssembly BEAM runtime
  and LocalLiveView for rendering and events. The Reception Desk does not own
  browser nodes or swarms. Both components may share hosting without merging
  their responsibilities.
- `control/`: shared Erlang/OTP swarm and chat logic. Reuse compatible modules
  in native apps, server and browser; isolate platform/network adapters. Browser
  compatibility must be demonstrated, not assumed.
- Communication: an explicit, versioned WebSocket message protocol usable by
  browser and native nodes. Browser BEAM is not ordinary distributed Erlang;
  browser sockets, filesystem and native extensions have different constraints.
- Direct connections are preferred; the Reception Desk introduces nodes and
  relays only when required. For native apps, networking and negotiation belong
  in BEAM, using third-party `ex_webrtc`/`ex_sctp`, not Swift UI/runtime transport
   code. An isolated Mac prototype survives desk shutdown; integrate Mac first
  and address iPhone packaging in its own increment.
- Keep UI behavior direct and simple. Runtime code validates invitations and
  operations; ordinary editing, selection, copy and paste remain available.

Phoenix/LiveView supplies established components, rendering and connection
machinery. Popcorn 1.0's move to actual BEAM substantially improves the fit with
our OTP priority, while LocalLiveView avoids writing a custom browser UI engine.
Do not add a separate React app, database, accounts or broad scaffolding before
the current functionality requires them. Retain the existing native apps.

The accepted risk is the youth of the browser port and LocalLiveView. Popcorn's
BEAM transition was announced on 2026-10-27; examples and the language tour had
used that runtime for about a month. This is not evidence of mature production
adoption for the combined stack. Pin compatible versions and verify on the
actual target browsers before expanding the implementation.

### Trusted native OTP cluster direction accepted 2026-10-28

Aim to carry native Erlang distribution over WebRTC for mutually trusted Parvi
devices, supporting remote processes and later distributed DSP execution. This
supersedes the assumption that all native inter-node traffic must remain an
application-level protocol. Retain the working relay/application transport until
the carrier and admission model are verified. Cluster trust and logical swarm
membership are distinct: overlapping swarms must not silently extend VM access.
The current easy invitation/mutual-removal policy remains the user-facing goal;
secure cluster admission and removal are explicit implementation work.

1. **Isolated carrier proof (passed 2026-10-28):** two independent desktop BEAM VMs,
   OTP 29.1.2 / ERTS 17.1.1, using a reliable ordered binary WebRTC DataChannel.
   Reuse OTP `dist_util` and process distribution-controller APIs. Verify real
   remote PIDs, messages/binaries, remote execution, links, monitors and
   disconnection notifications. Use only local test introductions and temporary
   credentials; do not modify the working apps, Windows or any graph code.
   The isolated smoke check passes native RPC/spawn, 256 KiB binary round trips,
   ordered messaging, remote links/monitors, idle ticks, silent-loss node-down
   detection and mismatched-cookie rejection. See
   [the experiment](../control/transport/experiments/otp_dist/README.md).
2. **Trusted admission (isolated checks passed 2026-10-28):** expiring invitations
   pin the inviter's ephemeral public key. Signed challenges/proofs bind the
   device key and native name to actual DTLS fingerprints and fresh nonces;
   pairwise OTP cookies travel inside the encrypted channel. An explicit gate
   denies distribution before authorization and after revocation, independently
   of cached cookies or OTP's non-removable allow-list entries. A cluster-local
   OTP admission actor serializes current membership and capability hashes; any
   member can invite, and the actor moves to a survivor if its host is removed.
   The user chose **cluster-wide remove both**: both VMs lose cluster access,
   including access through their other logical swarms. Their issued invitations
   and the invitations used to enter expire globally; fresh invitations can
   readmit them, without permanent banned-device identities. Surviving links
   remain usable. One VM has one native trust domain; unrelated populated domains
   cannot silently merge. This native policy supersedes the old swarm-scoped
   removal choice when the apps adopt it; existing app UI/relay behavior is not
   changed by the isolated implementation. See the experiment README for tested
   attacks, bounds and the full-VM trust assumption.
2a. **OTP foundation alignment (passed isolated checks 2026-10-29):** behavior and reuse take
   priority over renaming. Keep current `parvi`/`swarm` source identifiers and UI
   labels until later; do not add a replacement room/session framework. The
   native runtime uses standard node connections, remote PIDs, links/monitors,
   OTP supervisors and `pg` process groups. Reuse the existing shared chat worker
   instead of another native chat implementation. Do not start custom swarm
   membership gossip, per-swarm transport routing, node-health polling or topology
   workers in that runtime. Admission state records permission to reconnect, not
   live process membership; `pg` and ERTS provide the latter. Keep only the WebRTC
   carrier, invitation/revocation policy and application data/history as custom
   behavior. Replace manual local observer monitoring with `pg` where suitable.
   Verify real chat, process-group discovery, worker/scope restart, subscriptions,
   native disconnects and cluster-wide removal over the proven carrier. Preserve
   the existing app path until native app integration: legacy swarm modules may
   remain for compatibility but must not be dependencies of the native runtime.
   No Windows or graph edits; no broad UI/source renaming in this step.
3. **Internet and recovery:** separate access networks, relay-required paths,
   desk outages, network changes, connection arbitration, bounded queues and
   backpressure. Reuse rendezvous/relay facilities rather than rebuilding them.
   Complete admission-actor crash/partition recovery, cancelled-join cleanup,
   partial policy publication and revocation receipts before app integration.
   Step 2 fails closed on authority outage but is not a consensus/recovery design.
   Work incrementally; ask before adding tests or hardening behavior.
   - **3a — Reception Desk introductions (implemented, compilation only,
     2026-10-29):** reuse the authenticated WebSocket/mailbox client with an
     explicit envelope recipient. An isolated Erlang connector exchanges SDP/ICE,
     then uses the existing trust handshake and native carrier. Accept STUN/TURN
     configuration through the third-party library. Keep working apps and the
     public desk unchanged; compilation does not prove connectivity.
   - **3b — Connection proof (pending):** use the single global Reception Desk
     hosted on Render (`wss://parvi-reception-desk.onrender.com/relay/v1`) for
     development and connection checks; do not start a separate test desk.
     First check two nodes through that desk, then across separate access networks;
     configure TURN for a relay-required path. Reception Desk signalling and TURN
     data forwarding are different roles. Verify established traffic with the
     introduction service unavailable. OpenSound currently uses one shared
     development, testing and production environment; the user authorizes
     changes to the Render desk, including interruption for this check.
   - **3c — Recovery (pending):** choose each next behavior with the user before
     hardening: failed/cancelled joins, reconnect and simultaneous attempts,
     connection mesh, backpressure, authority recovery/publication/receipts.
     Do not add a second membership system alongside OTP.
4. **Native Mac/iPhone integration:** package the libraries and carrier, then
   verify real devices, suspension, recovery and failure isolation.
5. **Distributed DSP proof:** one timestamped binary audio stream, a remote DSP
   worker and returned results; measure latency, jitter, CPU and missed deadlines.
   Keep final playback/timing local initially. Native distribution does not fix
   the eventual latency-sensitive audio media path.
6. **Measured scheduling:** explicit worker placement first; later choose workers
   using device capacity, network delay and processing deadlines. OTP remote
   execution is not an automatic DSP load balancer.

The isolated experiment belongs in `control/transport/experiments/otp_dist`,
outside production compilation and app packaging. A passing step 1 authorizes
neither automatic cluster admission nor deployment of the prototype.

### Implementation update: native relay first

The browser BEAM/full WebApp experiment is deferred. The first native relay is
implemented in `Services/ReceptionDesk`, with Windows integration and shared Apple
configuration/packaging sources. See [protocol](RELAY_PROTOCOL.md) for the actual
wire contract and limits. Public deployment and the Windows-iPhone test across
separate internet connections remain acceptance work; they are not yet proven.

### Code reuse audit 2026-10-28

First pass covers the shared Erlang core, Mac/iPhone hosts and shared SwiftUI,
Windows UI and graph, WebApp, Reception Desk, build scripts and smoke helpers.
Prefer existing OTP/platform facilities before adding dependencies. Count
vendored third-party source separately from Parvi logic.

| Priority | Location | Opportunity and limits |
| --- | --- | --- |
| Done | `control/src/parvi_relay.erl` | Removed manual pong replies and enabled Gun's default ping suppression. Gun 2.7 already replies to pings; our handler sent a second reply. No new dependency. |
| Done | `Apps/macOS/Parvi/MacErlangRuntime.swift`, `Apps/iOS/Parvi/IOSErlangRuntime.swift` | Both hosts use a shared reader over Foundation `FileHandle.bytes` and deliver typed snapshots; ChatModel no longer decodes them again. `.lines` was rejected after a regression test showed it splits Unicode paragraph separators inside valid JSON. A small shared LF-only framer preserves the protocol, fragmented UTF-8 and incomplete-record EOF behavior. Windows and graph sources remain unchanged. |
| Separate easy deletion candidate | `Apps/Windows/src/parvi_node_status.erl`, `parvi_topology.erl` | 128 lines of older monitoring workers have no callers outside these two modules in the checked-in sources. The current Windows model uses shared bridge network snapshots. These are candidates for deletion after Windows build/reload checks, rather than reasons to add a library. |
| Largest conditional saving | `Apps/Windows/src/parvi_fgraph_win.erl` | 829-line modified OTP Reltool viewer. The force-layout engine is already reused unchanged. Direct upstream reuse could remove the fork, but would lose Parvi node-click events, pause behavior, labels, arrows and styling unless supported upstream. This is an internal OTP module; the existing graph investigation records the missing hooks. No drop-in replacement is established. |
| Investigate later | `control/src/parvi_relay.erl` | Gun provides retry/retry_fun; our client disables retries and implements backoff. Savings are small, and authentication, mailbox reopening, handshake deadlines and iPhone DNS refresh still belong to Parvi. Do not blindly enable both retry mechanisms. |
| Keep | `Apps/WebApp/public/qrcode.js` | Already the vendored MIT-licensed qrcode-generator library, not 2,297 lines of custom QR logic. Switching to a CDN would remove local source without reducing the code shipped, and would add availability/privacy dependencies. |
| Keep | Core wire/invitation/membership logic and `Apps/iOS/Parvi/parvi_beam.c` | URI/JSON/crypto already use OTP libraries. Swarm authorization and mutual-removal rules are product behavior; no library replacement is established. The 79-line iPhone host is specific static-runtime ABI/startup glue based on Mob, not a hand-written runtime. |

Sources: [Gun 2.7 options and automatic pong behavior](https://ninenines.eu/docs/en/gun/2.7/manual/gun/),
[Foundation asynchronous file reading](https://developer.apple.com/documentation/foundation/filehandle/bytes),
and [the existing graph investigation](NODE_GRAPH_INVESTIGATION.md).

### Next steps and acceptance checks

The application's purpose is **binary audio publish/subscribe**, not text chat.
Any node may publish audio, subscribe to audio from other nodes, or do both.
One stream may have one or many subscribers in a swarm. Subscriptions describe
the audio a node wants and the stream capabilities a publisher actually offers;
they are not limited to selecting a person or joining a chat room.

For example, a subwoofer can request audio below 80 Hz. This can select a
publisher-provided low-pass/band-limited stream, or a full-band stream processed
by the receiver's crossover. Merely labelling a broadband audio packet does not
separate its frequencies. Source-side filtering and receiver-side DSP are design
choices to measure, not an assumption that a packet contains only one frequency.

Chat and the current reliable data-channel experiment prove connectivity and
membership only. They do not determine the eventual media transport. Keep
control/signalling separate from binary media delivery, with explicit sample
format/codec, channel or object descriptions, sequence/sample timestamps,
playback timing, buffering and loss behavior. Do not carry audio through JSON
text/base64 chat messages or assume reliable ordered delivery is appropriate for
live audio. Evaluate the third-party WebRTC library's RTP/media facilities as
well as binary data channels against synchronization and DSP requirements.

1. Keep the source separation already completed: WebApp and ReceptionDesk.
2. Prove browser BEAM startup, a supervised chat worker, message delivery and
   worker restart. Render a small swarm view through LocalLiveView and verify
   normal input-field behavior. Check the shared core's actual compatibility.
3. Prepare the Reception Desk for Render hosting and implement internet
   invitations and transport. Start with outbound encrypted WebSocket connections
   from Mac and iPhone; test across separate internet connections first.
4. Verify admission, scoped chat, node presence, reconnect, leave and mutual
   removal. A node can belong to multiple swarms and has an ephemeral session
   identity. Retain the agreed invitation and removal semantics.
5. Add direct peer paths/NAT traversal and relay fallback as needed. Same-Wi-Fi
   operation is a subsequent test, not a prerequisite for internet connectivity.

The next implementation order may interleave the browser experiment and native
internet transport; neither depends on finishing the other. Audio streaming,
playback synchronization and large-swarm scaling need separate measured work.

Decision evidence: [LiveView history](https://phoenixframework.org/blog/phoenix-liveview-1.0-released),
[Popcorn's BEAM transition](https://swmansion.com/blog/popcorn-1-0-moving-from-atom-vm-to-otp-beam/),
[LocalLiveView examples](https://github.com/software-mansion/popcorn/tree/main/local-live-view).

## Objective

Demonstrate that independently clocked commodity receiver nodes can play subscribed audio in sustained alignment while applying local processing. Use the results to define a small, open, language-independent protocol and an implementation others can reproduce.

Do not begin by attempting a complete home-theatre processor or a universal radio protocol. Synchronized playback is the first deliverable; distributed DSP orchestration and live collaboration follow measured evidence.

## Milestone 0: requirements and reuse assessment

Write down distinct requirements for buffered music playback, same-room multichannel playback, and live monitoring. Specify network assumptions, end-to-end latency, inter-output alignment, drift, recovery, and source-count expectations separately.

Evaluate Snapcast with local DSP, AES67-capable implementations, and RTP libraries. Record whether an extension to existing software can meet the goal more directly than a new transport. Review dependency licenses before selecting code.

**Exit:** a short architecture decision documenting the chosen prototype path, hardware, audio APIs, clock approach, and reasons for any new protocol elements.

## Milestone 1: two receivers, one source, wired LAN

Use two Linux receiver nodes with independent audio devices, one source, and a wired Ethernet switch. Start with a shared reference signal and uncompressed 48 kHz PCM. Assign an explicit clock reference and a common presentation delay.

Implement or integrate stream identification, packet sequencing, sample-time mapping, a bounded jitter buffer, clock-rate estimation, drift correction, and receiver latency reporting. Add local gain and EQ after synchronization works. Late audio must have a defined discard/concealment policy rather than causing an ever-growing buffer.

Measure both analog outputs simultaneously with a common multichannel capture device. Software timestamps alone do not establish synchronized acoustic output. Use repeated impulses or correlation signals to measure alignment, and document capture resolution and uncertainty.

**Provisional engineering targets, not guarantees:** maintain inter-output alignment within one 48 kHz sample (about 20.8 microseconds), after calibration, for a two-hour clean-network run. Begin with a configurable 100 ms presentation delay and measure actual source-to-output latency separately. Report worst-case alignment and excursions, not just the mean. If the target is missed, retain the measurements and revise the design explicitly.

**Exit:** a reproducible setup guide, captured measurements, no unexplained clean-network underruns, and a documented account of any unmet target. Do not declare synchronization solved while a target remains unmet.

## Milestone 2: session control and dynamic membership

Introduce an Erlang/OTP control service and a documented interface to the receiver engine. Keep media delivery independent of the control service's scheduling.

Add device discovery, stable device identities, capability advertisements, source registration, channel-role subscriptions, and health reporting. A receiver must synchronize and fill its buffer before fading in at an agreed presentation time.

Use two concurrent sources and at least four independently clocked receivers. Define whether each subscription selects a source, a channel, or a local mix. Include headroom and limiting when mixing sources.

**Exit:** a source and receiver can each join or leave without interrupting unaffected outputs. Define and demonstrate behavior when the coordinator or clock reference disappears; safe silence is an acceptable initial policy.

## Milestone 3: useful local processing

Integrate an existing DSP engine where practical. Add per-output EQ, delay, channel mixing, FIR convolution, and optional crossovers. Advertise processing capacity and latency rather than assuming every node can run every filter.

Schedule configuration changes against the shared timeline. Define filter transition behavior, delay compensation, version acknowledgement, and rollback. Keep loudspeaker-driver crossovers on one node initially to avoid independently failing network paths between frequency bands.

**Exit:** measured alignment is maintained through different DSP delays and coordinated configuration changes; no uncontrolled gain jumps or audible transition clicks in the documented test cases.

## Milestone 4: Wi-Fi, resilience, and scaling

Test shared Wi-Fi only after establishing a wired baseline. Measure airtime and loss under contention; compare selective unicast and multicast delivery. Do not assume Wi-Fi multicast behaves like switched Ethernet multicast.

Inject packet loss, bursts, reordering, CPU load, receiver restarts, clock changes, and network partitions. Track buffer depth, late packets, drift estimates, output alignment, and total latency. Set limits on queues, sources, bandwidth, and CPU admission.

**Exit:** a published operating envelope and repeatable fault tests. Unsupported latency or capacity requests are rejected clearly. Recovery preserves bounded buffers and safe output behavior.

## Milestone 5: open interoperability draft

Publish a versioned specification with normative language, state machines, message schemas, timing equations, channel-role definitions, capability negotiation, and error handling. Clearly identify experimental extensions and compatibility rules.

Provide packet examples, conformance vectors, a receiver simulator, and a test harness. Arrange an independently developed second implementation before claiming interoperability. Publish results against the same timing and fault tests.

Use public proposals and recorded decisions. Define maintainers, decision-making, release/version policy, and how compatibility disputes are resolved. Discuss standards-body engagement and a suitable contributor patent policy before presenting the protocol as a broadly deployable standard. Apache 2.0 licensing alone does not establish freedom from third-party patents.

**Exit:** two independent implementations exchange streams and control messages successfully, with published limitations and compatibility results.

## Later research

Bluetooth LE Audio gateways, compressed wireless profiles, object-based rendering, room measurement and filter generation, joint subwoofer optimization, arbitrary processing graphs, live collaboration, internet transport, and clock/coordinator failover.

Each needs its own requirements and experiments. A low-latency performance profile must have a separate end-to-end budget; increasing playback buffers cannot solve live-monitoring latency.

## Decisions still open

| Question | Evidence needed |
| --- | --- |
| Extend existing software or build a new media engine? | Reuse assessment and a measured two-node experiment |
| Can software timing meet the alignment target? | Analog-output measurements across selected audio hardware |
| PTP, application clock estimation, or both? | Timestamp support, network asymmetry, and DAC-clock control |
| Which PCM format and packet duration? | Latency, CPU, bandwidth, MTU, and library compatibility |
| Direct delivery or optional relay? | Scaling, topology, access control, and Wi-Fi measurements |
| How much decentralization is useful? | Failure behavior and configuration consistency requirements |
| Which control protocol and identity scheme? | Independent-client implementation and security review |
| What constitutes a safe speaker subscription? | Channel semantics, gain policy, and capability negotiation |

## Security and output safety

An open protocol should not mean arbitrary devices can play through every speaker. Define enrollment, authorization to publish or subscribe, authenticated control, media protection where required, and resource limits. Avoid exposing Erlang distribution as the public device interface.

Design bounded gain, limiting, fades, and explicit mute behavior for invalid configuration, lost synchronization, and node failures. Treat downloaded plugins or remote code execution as outside the initial protocol.

## Repository structure as implementation begins

```text
README.md
Apps/                platform app sources
builds/              generated apps and compiler intermediates (Git-ignored)
docs/PLAN.md
LICENSE
docs/decisions/       architecture decisions
docs/protocol/        experimental specifications and schemas
control/             Erlang/OTP session services
audio/               native audio transport, timing, and DSP integration
tools/               measurement and fault-injection utilities
tests/interop/       protocol vectors and independent-client tests
examples/            reproducible hardware and session configurations
```

`control/` now contains the initial chat application and `docs/` records its
decisions and progress. Add the remaining directories when there is code to put
in them.

## Resuming work

For the current chat-first phase, start with `docs/PROGRESS.md` and decision 0001.
When beginning audio, start with Milestone 0: select receiver and capture hardware
and record the reuse assessment before implementing transport. Preserve measured
failures as useful results and update this plan when evidence changes an assumption.
