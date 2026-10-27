# Preliminary development plan

Created: 2026-10-23. Status: proposal for discussion and experimentation.

Update 2026-10-26: the newer [Parvi handover](notes%2020261026.md) introduces a
chat-first feasibility phase before these audio milestones. The Mac OTP chat
baseline is now implemented; iPhone execution remains pending. Follow
[the progress log](PROGRESS.md) and [decision 0001](decisions/0001-chat-first-and-ios-feasibility.md)
for current scope and next steps. The audio targets below remain unvalidated.

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
