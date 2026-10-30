# Development plan

Created: 2026-10-23. Current development order revised: 2026-10-30.

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

**Working app path:** on 2026-10-29 the user demonstrated Windows–iPhone swarm
admission and chat through the Render Reception Desk, with Windows on a school
network and iPhone on mobile data. Screenshots show the same two-member swarm
and the phone's message received on Windows. This is user-observed relay
interoperability across separate networks, not a native OTP/WebRTC or audio
timing result. The user also confirmed the Windows status fix took effect.

**Separate native implementation:** Mac and iPhone sources now integrate the native
carrier, trust worker and desk connector with the shared OTP chat runtime and
existing UI. Erlang compilation, Swift checks, Mac dependency packaging and
iPhone device static compilation/linkage pass. Neither new app has been fully
rebuilt, launched or connection-tested. This increment represents one
native cluster per session; voluntary leave, switching and reconnect remain
unimplemented. See the Mac README for usage and limits.

**Next product target — updated 2026-10-30:** audio from an external source
reproduced in sync by two iPhones. Parvi receives, processes and transmits signals;
the upstream player owns songs, decoding and playback controls. Continue
incrementally; the user does not want a
cleanup phase before audio. The binary-stream/remote-DSP increment (step 5)
remains a possible supporting step, with explicit worker placement initially.
Build/use the native apps and check connections through Render when that work
needs evidence. Address recovery and TURN when actual use or the next feature
requires them; no separate testing phase is required. Preserve the wider ideas
in [the audio/calibration idea record below](#audio-and-calibration-ideas--recorded-2026-10-30).

**Immediate next slice — audio entering Parvi:** the user wants an OS-selectable
Parvi output device feeding an input meter, using an existing player/browser as
the source. Work in Windows only; do not edit iOS or Mac app sources in this
increment. A first Windows capture/meter implementation now reads the current
default multimedia output through WASAPI loopback and shows peak/RMS dBFS,
format and captured frames. Following the user's Erlang-first direction, the
native bridge now only calls WASAPI and transfers raw buffers/metadata. The
Erlang worker controls reads and computes the meter from PCM. No built-in OTP
WASAPI/COM binding was found; the small native boundary remains necessary for
these Windows calls. Keep algorithms in Erlang initially; offload only for
measured performance needs. This does not yet create the requested virtual
Parvi device, forward audio between nodes, or show a frequency spectrum.
The [Windows binding trial](decisions/0004-windows-audio-library-trial.md) selected
PortAudio as the strongest reusable audio I/O candidate, but its old Erlaudio
binding failed stream opening in an isolated VM and has native ownership/type
defects. Direct PortAudio loopback capture succeeded. Keep the working WASAPI
adapter; no replacement dependency is integrated. Generic COM/FFI candidates
were not established as ready x64 Windows bindings. A future reusable adapter
must preserve timing metadata and Erlang-owned policy.
Next select/reuse a Windows virtual-audio-device adapter for that selectable
endpoint and connect the existing Erlang sample input to further processing/transmission
path. Keep the device-routing requirement distinct from the working loopback
meter; no virtual driver has been selected or installed.

**Following audio sequence — corrected product boundary:** select the
remaining input/output adapters and the audio-port contract. Inputs supply sample
blocks with format/channel and timing information; outputs consume scheduled
samples. Candidate adapters include audio-device capture/render, a cooperating
app/plugin host, desktop system-audio capture or a network stream. OS audio
integration and network media protocol are separate selections. A virtual audio
driver is one possible adapter, not an assumed requirement for Parvi's core.
Do not add a song library, file decoder, bundled-song playback or transport
controls to Parvi. The earlier preloaded-song recommendation was rejected by
the user on 2026-10-30.

Connect one external source through a chosen input port and deliver its audio
to one iPhone output, then two scheduled iPhone outputs with a common time
mapping and output-delay compensation. Measure acoustic alignment/drift and add
the correction those observations require. Native platform audio handles device
I/O; BEAM coordinates routing, networking and processing work. A temporary common
recording can provide the first measurement; the full distributed microphone
calibration loop is a later option.
Confirm which iPhone runtime profile is actually built/running as part of making
this slice usable; the successful installed relay apps do not validate the newer
native-profile sources. Select the first stream transport for this port-to-port
increment rather than inferring it from the working chat path. Remote DSP and
automatic calibration follow when useful. No Windows NIF port, browser work, broad cleanup or complete
recovery programme is a prerequisite for the two-iPhone goal.

**Windows follow-up requested 2026-10-29:** launch/profile and UI sources now
understand the shared native runtime, cluster-wide removal and pending joins.
Shared/Windows Erlang and the Win32 launcher compile; a Windows OTP VM boots the
native carrier without EPMD. The legacy app is rebuilt. Windows NIF packaging is
still incomplete: the upstream build stops at missing Cargo, and the pinned
DTLS/Unifex/Shmex sources also depend on POSIX facilities. Keep the legacy relay
build available until those dependencies have a supported Windows build/port.
When Windows native distribution is needed: finish that dependency increment,
build the native app, then check invitation/admission/chat through the global
Render desk as needed. The existing Windows relay path already works with the
installed iPhone app across separate networks, as recorded above.
Do not describe this source integration as runnable native Windows support.

Windows status correction: the legacy relay snapshot now reports the local
runtime as Running independently of desk connectivity. The existing reload loop
now unconditionally reloads changed project BEAM modules, including backend and
model, using OTP code-loading functions. No environment mode or state migration.
An app running the previous UI-only watcher needs one restart to install the
expanded watcher; subsequent backend changes reload automatically. Desk
reachability remains a separate status.
The Windows model also clears an obsolete disconnected-action error when a
later snapshot confirms the desk connection; failed messages still need manual
retry. Live health and WSS authentication pass; the earlier outage cause is unknown.

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

- `src/Services/ReceptionDesk`: independent service for rendezvous, permission-checked
  mailboxes and relay mechanisms. Its Erlang workers can run inside the
  Phoenix/Cowboy BEAM application without another server-language runtime.
- `src/Apps/WebApp`: a browser-local node, using Popcorn's WebAssembly BEAM runtime
  and LocalLiveView for rendering and events. The Reception Desk does not own
  browser nodes or swarms. Both components may share hosting without merging
  their responsibilities.
- `src/control/`: shared Erlang/OTP swarm and chat logic. Reuse compatible modules
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
adoption for the combined stack. When browser work resumes, pin compatible
versions and check browser behavior as that implementation develops.

### Trusted native OTP cluster direction accepted 2026-10-28

Aim to carry native Erlang distribution over WebRTC for mutually trusted Parvi
devices, supporting remote processes and later distributed DSP execution. This
supersedes the assumption that all native inter-node traffic must remain an
application-level protocol. Reuse the existing apps while integrating the native
path incrementally. Cluster trust and logical swarm
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
   [the experiment](../src/control/transport/experiments/otp_dist/README.md).
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
3. **Internet connection support (develop alongside app integration):** reuse
   rendezvous/relay facilities rather than rebuilding them. The desk connector
   is implemented; move it into a usable app path next. Separate-network access,
   TURN, desk outages and recovery are targeted follow-up work when needed,
   not a mandatory test matrix before step 4. Step 2 currently fails closed on
   authority outage; crash/partition recovery, cancelled-join cleanup, partial
   policy publication and revocation receipts remain known limitations.
   - **3a — Reception Desk introductions (implemented, compilation only,
     2026-10-29):** reuse the authenticated WebSocket/mailbox client with an
     explicit envelope recipient. An isolated Erlang connector exchanges SDP/ICE,
     then uses the existing trust handshake and native carrier. Accept STUN/TURN
     configuration through the third-party library. This slice did not change
     apps or the public desk; compilation does not prove connectivity.
   - **3b — Connection checks (as needed during integration):** use the global
     Reception Desk on Render (`wss://parvi-reception-desk.onrender.com/relay/v1`) for
     development and connection checks; do not start a separate test desk.
     Check the invitation/join/chat path as it becomes usable. Check separate
     access networks, configure TURN or interrupt the desk when the work needs
     that evidence. Reception Desk signalling and TURN data forwarding are
     different roles. OpenSound currently uses one shared
     development, testing and production environment; the user authorizes
     changes to the Render desk, including interruption for this check.
   - **3c — Recovery (deferred until needed):** fix failures encountered during
     development; discuss broader hardening before adding it. Possible work:
     failed/cancelled joins, reconnect and simultaneous attempts,
     connection mesh, backpressure, authority recovery/publication/receipts.
     Do not add a second membership system alongside OTP.
4. **Native Mac/iPhone integration (sources implemented; execution unverified):**
   Mac build/host sources now package the libraries, carrier, trust worker and
   desk connector, reuse the shared native OTP chat runtime and expose
   invitation/join/chat through the existing UI. App execution is unverified.
   Keep the change focused; no Windows, graph or broad naming cleanup.
   iPhone now has static dependency builds, NIF registration and named-node
   startup. Device native compilation/linkage and resource preparation pass;
   simulator native compilation, full builds and phone execution are unverified.
   Check device behavior as needed; suspension,
   recovery and failure isolation can be separate increments rather than entry
   requirements for using the native path.
5. **Distributed DSP proof (follow-on to the immediate playback slice):** one timestamped binary audio stream, a remote DSP
   worker and returned results; measure latency, jitter, CPU and missed deadlines.
   Keep final playback/timing local initially. Native distribution does not fix
   the eventual latency-sensitive audio media path.
6. **Measured scheduling:** explicit worker placement first; later choose workers
   using device capacity, network delay and processing deadlines. OTP remote
   execution is not an automatic DSP load balancer.

The reusable carrier, trust and desk modules now live in `src/control/src/` and
compile with the shared core. Probe/harness code remains experimental in
`src/control/transport/experiments/otp_dist`. Mac packages the runtime dependencies;
iPhone builds them statically. Both retain explicit invitation-based admission.

### Implementation update: native relay first

The browser BEAM/full WebApp experiment is deferred. The first native relay is
implemented in `src/Services/ReceptionDesk`, with Windows integration and shared Apple
configuration/packaging sources. See [protocol](RELAY_PROTOCOL.md) for the actual
wire contract and limits. The global desk is deployed on Render; public-WSS
checks and physical Mac–iPhone chat are recorded in the progress log. On
2026-10-29 the user also demonstrated Windows–iPhone relay chat between a school
network and mobile data. This closes that relay-connectivity observation; native
distribution, sustained audio and synchronised playback remain separate work.

### Code reuse audit 2026-10-28

First pass covers the shared Erlang core, Mac/iPhone hosts and shared SwiftUI,
Windows UI and graph, WebApp, Reception Desk, build scripts and smoke helpers.
Prefer existing OTP/platform facilities before adding dependencies. Count
vendored third-party source separately from Parvi logic.

| Priority | Location | Opportunity and limits |
| --- | --- | --- |
| Done | `src/control/src/parvi_relay.erl` | Removed manual pong replies and enabled Gun's default ping suppression. Gun 2.7 already replies to pings; our handler sent a second reply. No new dependency. |
| Done | `src/Apps/macOS/Parvi/MacErlangRuntime.swift`, `src/Apps/iOS/Parvi/IOSErlangRuntime.swift` | Both hosts use a shared reader over Foundation `FileHandle.bytes` and deliver typed snapshots; ChatModel no longer decodes them again. `.lines` was rejected after a regression test showed it splits Unicode paragraph separators inside valid JSON. A small shared LF-only framer preserves the protocol, fragmented UTF-8 and incomplete-record EOF behavior. Windows and graph sources remain unchanged. |
| Separate easy deletion candidate | `src/Apps/Windows/src/parvi_node_status.erl`, `parvi_topology.erl` | 128 lines of older monitoring workers have no callers outside these two modules in the checked-in sources. The current Windows model uses shared bridge network snapshots. These are candidates for deletion after Windows build/reload checks, rather than reasons to add a library. |
| Largest conditional saving | `src/Apps/Windows/src/parvi_fgraph_win.erl` | 829-line modified OTP Reltool viewer. The force-layout engine is already reused unchanged. Direct upstream reuse could remove the fork, but would lose Parvi node-click events, pause behavior, labels, arrows and styling unless supported upstream. This is an internal OTP module; the existing graph investigation records the missing hooks. No drop-in replacement is established. |
| Investigate later | `src/control/src/parvi_relay.erl` | Gun provides retry/retry_fun; our client disables retries and implements backoff. Savings are small, and authentication, mailbox reopening, handshake deadlines and iPhone DNS refresh still belong to Parvi. Do not blindly enable both retry mechanisms. |
| Keep | `src/Apps/WebApp/public/qrcode.js` | Already the vendored MIT-licensed qrcode-generator library, not 2,297 lines of custom QR logic. Switching to a CDN would remove local source without reducing the code shipped, and would add availability/privacy dependencies. |
| Keep | Core wire/invitation/membership logic and `src/Apps/iOS/Parvi/parvi_beam.c` | URI/JSON/crypto already use OTP libraries. Swarm authorization and mutual-removal rules are product behavior; no library replacement is established. The 79-line iPhone host is specific static-runtime ABI/startup glue based on Mob, not a hand-written runtime. |

Sources: [Gun 2.7 options and automatic pong behavior](https://ninenines.eu/docs/en/gun/2.7/manual/gun/),
[Foundation asynchronous file reading](https://developer.apple.com/documentation/foundation/filehandle/bytes),
and [the existing graph investigation](NODE_GRAPH_INVESTIGATION.md).

### Audio direction and deferred browser work

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
src/control/signalling separate from binary media delivery, with explicit sample
format/codec, channel or object descriptions, sequence/sample timestamps,
playback timing, buffering and loss behavior. Do not carry audio through JSON
text/base64 chat messages or assume reliable ordered delivery is appropriate for
live audio. Evaluate the third-party WebRTC library's RTP/media facilities as
well as binary data channels against synchronization and DSP requirements.

WebApp and ReceptionDesk are already separate, and the global desk is hosted.
Browser BEAM/LocalLiveView work remains deferred; it does not precede native
integration. When resumed, start with one supervised worker and a small view,
checking shared-core compatibility and ordinary input behavior as needed.
Audio streaming follows the native integration path above. Measure timing when
implementing synchronized playback; large-swarm scaling can wait for a need.

Decision evidence: [LiveView history](https://phoenixframework.org/blog/phoenix-liveview-1.0-released),
[Popcorn's BEAM transition](https://swmansion.com/blog/popcorn-1-0-moving-from-atom-vm-to-otp-beam/),
[LocalLiveView examples](https://github.com/software-mansion/popcorn/tree/main/local-live-view).

### Audio and calibration ideas — recorded 2026-10-30

This records the discussion, including speculative or potentially impractical
ideas, so they are not forgotten. These are product goals, hypotheses and
candidate approaches, not implemented behavior or proven performance. They do
not require a new framework, cleanup programme or implementation all at once.

**Goals and priorities**

- Near term: two iPhones reproduce the same externally supplied audio and remain
  in sync. The earlier idea of a song preloaded into each Parvi app was rejected
  on 2026-10-30: player functionality belongs upstream. Buffering received signal
  blocks for scheduled rendering remains part of Parvi's signal path.
- A useful subsequent target is 10–100 speakers on commodity devices, with
  distributed playback, DSP and acoustic calibration. Buffered home listening
  can accept substantial startup/presentation delay in exchange for reliable
  delivery; minimal-latency large-concert operation is a longer-term ambition.
- Explore stereo-to-surround upmixing and immersive/spatial playback, including
  the user's Dolby Surround/Atmos vision. An original spatial renderer/upmixer
  and actual Dolby compatibility are separate possibilities; neither is
  implemented or implied by playing stereo through many speakers.
- Reuse ordinary devices, native audio facilities and existing DSP/protocol
  libraries, with Erlang/OTP coordinating devices and workers. The hope is a
  simpler, cheaper system; comparable professional performance/cost remains a
  hypothesis. Standards such as AES67 may guide transport/timing and eventual
  interoperability without requiring specialised equipment as an initial goal.

**Proposed acoustic feedback loop during music playback**

1. Know the upcoming source audio and its intended sample/presentation timeline.
   Analyse the song ahead of playback for recognisable features: drum kicks,
   sharp peaks/transients, frequency patterns or other suitable passages.
2. Alternatively insert small known probe sounds/audio samples into the media
   stream, potentially with distinct signatures for different speakers. A probe
   must actually be rendered as sound to be acoustically detectable; packet
   metadata alone is insufficient. Audibility and reliable detectability remain
   open questions; do not assume a probe can be inaudible and still work.
3. Schedule short microphone-recording windows around the expected arrival,
   using microphones on nearby devices, potentially all participating devices.
   Include enough timing context and surrounding audio to accommodate unknown
   offsets. The aim is useful feedback while songs continue playing.
4. Send recordings and the corresponding known reference/timing information to
   an available or idle node for analysis. Distributing this mathematics is a
   candidate use of the remote-DSP workers. Start with explicit placement;
   automatic scheduling by spare capacity can follow when useful.
5. Compare the expected and recorded signals, for example using correlation,
   to estimate relative arrival offsets and their change over time. Explore
   whether these observations can also support room-response/EQ calibration,
   speaker placement and listening-position optimisation.
6. Feed the estimates back into scheduled output-delay and, where needed,
   playback-rate/resampling corrections. Re-estimate periodically or when the
   acoustic/device situation changes. A little user input (such as identifying
   the listening position/devices) or heuristics may help resolve ambiguity.

**Hypotheses and unresolved details to retain**

- Model timing initially as clock offset plus rate difference, with output-path
  delay. Investigate which terms remain stable and which change during playback
  or after an audio-route/buffer change. Larger buffers can absorb network
  arrival variation; they do not alone remove relative clock drift, output-path
  differences or room effects, nor improve fidelity without limit.
- Microphones observe a mixture of speakers, direct sound, reflections and
  noise. Repeated beats, narrow frequency features and identical audio from
  several speakers may yield ambiguous matches. Candidate aids include
  identifiable probes, an initial speaker-by-speaker measurement, known
  geometry, multiple microphones or user-assisted calibration.
- Microphone capture has its own clock, timestamp and input delay. An observed
  lag includes the speaker output path, acoustic travel and recording path;
  it cannot automatically be attributed entirely to the speaker's output delay.
- Choose what is being aligned: electrical emission, arrival at a particular
  seat, or a compromise across a listening area. Alignment at one microphone
  does not imply alignment everywhere. Test whether position/room changes can
  be distinguished from device drift.
- Determine how much signal is needed, when measurements are trustworthy,
  whether probes/music features remain identifiable after DSP, and how quickly
  a remote analysis result becomes stale. Explore gradual corrections that
  avoid audible jumps, rather than presuming repeated offset jumps are harmless.
- The user is optimistic that this closes much of the gap with professional
  AV systems using commodity hardware. Preserve that ambition while measuring
  actual acoustic alignment, drift and dropouts; chat connectivity is separate
  evidence from sustained synchronised audio.

No feasibility claim is made for the complete feedback loop. Revisit these
ideas as the two-phone playback increment produces useful evidence.

## Original audio research proposal — reference, not current gates

The milestones below preserve the original research ideas and provisional
targets. They do not impose a Linux/wired-LAN prerequisite, fixed test order,
two-hour qualification run or interoperability programme on current development.
Choose a small audio increment using the implemented native stack when that
work begins. Measurements remain necessary to claim synchronization or latency;
they are not a prerequisite for implementing an initial stream or DSP worker.

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
src/Apps/                platform app sources
builds/              generated apps and compiler intermediates (Git-ignored)
docs/PLAN.md
LICENSE
docs/decisions/       architecture decisions
docs/protocol/        experimental specifications and schemas
src/control/             Erlang/OTP session services
audio/               native audio transport, timing, and DSP integration
tools/               measurement and fault-injection utilities
tests/interop/       protocol vectors and independent-client tests
examples/            reproducible hardware and session configurations
```

`src/control/` now contains the initial chat application and `docs/` records its
decisions and progress. Add the remaining directories when there is code to put
in them.

## Resuming work

Start with the implementation approach and next step at the top of this file,
then `docs/PROGRESS.md` for completed work and known limitations. Continue toward
two-phone synchronised playback, using binary-stream/remote-DSP work and native
apps as needed; do not restart
completed proofs or treat the historical
audio milestones as prerequisites. Update the plan as implementation reveals
what is useful next.
