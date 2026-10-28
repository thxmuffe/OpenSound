# Preliminary development plan

Created: 2026-10-23. Status: proposal for discussion and experimentation.

Update 2026-10-26: the newer [Parvi handover](notes%2020261026.md) introduces a
chat-first feasibility phase before these audio milestones. The Mac OTP chat
baseline is now implemented; iPhone execution is verified on the physical phone. Follow
[the progress log](PROGRESS.md) and [decision 0001](decisions/0001-chat-first-and-ios-feasibility.md)
for current scope and next steps. The audio targets below remain unvalidated.

## Current implementation plan — accepted 2026-10-28

This section governs the immediate Parvi app and connectivity work. The original
audio milestones below remain research proposals; their stable-device-identity
and LAN-first assumptions do not govern the current swarm protocol.

### Architecture decision: BEAM/OTP on server and in browser

Use Phoenix with its Cowboy adapter for the server host, and Popcorn 1.0 with
LocalLiveView for the browser app. Keep the shared swarm/chat core in Erlang/OTP;
use Elixir for web components and integration where it reduces work. The priority
is BEAM processes, message passing and OTP supervision, rather than a particular
source language. This is an accepted direction, not an implemented stack.

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

### Implementation update: native relay first

The browser BEAM/full WebApp experiment is deferred. The first native relay is
implemented in `Services/ReceptionDesk`, with Windows integration and shared Apple
configuration/packaging sources. See [protocol](RELAY_PROTOCOL.md) for the actual
wire contract and limits. Public deployment and the Windows-iPhone test across
separate internet connections remain acceptance work; they are not yet proven.

### Next steps and acceptance checks

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
