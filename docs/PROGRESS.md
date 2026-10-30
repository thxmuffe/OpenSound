# Progress

## 2026-10-30 — Compare and try reusable Windows audio bindings

Reviewed Comet/erl_com, cffi, Erlaudio/PortAudio and miniaudio against the user's
small-parts, Erlang-first, low-latency/configurability preferences. PortAudio is
the preferred reusable device-I/O library, but the existing Erlaudio binding
was rejected after an isolated x64 Windows/OTP trial. Both libraries compiled;
the NIF loaded and enumerated WASAPI loopback devices, then the first stream-open
trial crashed the isolated VM with an access violation. A second stream-open
attempt also failed to return. Source review found independent term-width,
binary ownership and string-buffer defects; the precise crash cause is not
debugger-confirmed. Direct native PortAudio capture of 480 silent stereo frames
at 48 kHz succeeded, distinguishing basic library operation from binding failure.

No dependency integrated, no upstream source patched, no running Parvi process
replaced, no device settings changed and no iOS/Mac app sources edited. Generated
trial artifacts remain ignored under `builds/intermediates/Windows/`. The working
WASAPI-to-Erlang adapter remains in use; latency and sustained capture through
PortAudio were not measured. See [decision 0004](decisions/0004-windows-audio-library-trial.md)
for exact pins, comparisons, source references and validation limits.

## 2026-10-30 — Move sample handling and metering into Erlang

Replaced the native meter with a thin WASAPI port bridge. It passes raw Windows
format/source information, PCM, capture flags, device positions and local QPC
timestamps. Erlang requests read batches, owns the read/report timers, decodes
sample formats/silence and computes peak/RMS. The shared pure Erlang
`parvi_audio_meter` supports float32 and PCM16/24/32. The C++ source is reduced
from 126 to 82 lines with no meter calculations, sample conversion, polling
timer or background thread. OTP's built-in packet framing carries local binary
IPC; no network audio protocol has been selected. No driver or dependency added.

Recorded the user's enduring preference in AGENTS.md and updated the earlier
native-engine proposal: implement processing in Erlang first, with native code
limited to necessary bindings; offload later for measured performance needs.
WASAPI is a native COM interface; no built-in OTP binding or existing Erlang
WASAPI binding was found in this review. iOS and Mac sources were not edited.

Validation: native `/W4 /WX` and Erlang warnings-as-errors compilation pass.
Direct checks of all four sample formats produce the expected -6.0206 dBFS for
half-scale samples. End-to-end capture using the bundled OTP receives real
48 kHz stereo PCM, computes about -35 dBFS for a quiet external diagnostic tone,
counts 79,872 frames and stops cleanly. The sandbox initially rejected native
port startup with `einval`; the authorized native run passed. These are focused
manual checks; no automated test files were added and no test suite was run.
This replaces the earlier helper-to-Erlang JSON meter protocol; Stop input
before replacing the helper and worker together. No service deployment.
Staged the matching bridge/BEAM files with input stopped; the live app then
started capture through the updated worker and displayed 48 kHz stereo sample
counts without a full app restart. Stopped input again after verification.

## 2026-10-30 — First Windows audio input meter

Implemented a user-mode WASAPI loopback helper and an OTP-owned native port,
with Start/Stop input, endpoint name, peak gauge, peak/RMS dBFS, sample format
and captured-frame count in the Windows UI. This reads actual default-output
PCM; only meter summaries cross to BEAM. Audio is neither saved nor transmitted.
No player or decoder was added. Capture is node-local and independent of chat.
No new dependency, virtual driver, machine audio-setting change, iOS app change
or Mac app change. The build script now builds/packages the native helper.

Validation: C++ `/W4 /WX` and Erlang warnings-as-errors compilation pass. Direct
capture opens the Projector/AMD default output at 48 kHz stereo; a brief quiet
external diagnostic tone measures about -37 dBFS and yields 44,160 captured
frames. The live Windows UI opens capture and reports those frames. The direct
helper exits with code 0 after stdin closes. Input was stopped after checking.
No automated tests were added, no test suite or full app build was run, and no
service was deployed. The existing Windows app was launched with staged beams.

The user's selectable Parvi default-device goal remains incomplete. Next is
choosing/reusing the virtual-device adapter, then exposing PCM blocks for
processing/transmission. Device-change recovery is manual stop/start, and
protected/exclusive output may not be captured. No FFT/spectrum yet.

## 2026-10-30 — Correct the player/signal-processing boundary

The user rejected adding preloaded-song playback to Parvi. Songs, decoding and
player controls belong to an upstream player; Parvi owns signal input/output,
processing and transmission. Corrected the immediate plan accordingly: select
audio-port adapters/contract and a media transport, connect an external source
to one iPhone output, then two synchronised outputs. A virtual driver, an audio
plugin or an app using native audio I/O are integration options rather than
definitions of the core. No adapter/protocol selection has been implemented.
Documentation only; no code, build, tests or deployment.

## 2026-10-30 — Reconcile plan with demonstrated relay chat and next audio slice

Recorded the user's 2026-10-29 Windows–iPhone success over separate school and
mobile-data networks. Supplied screenshots show the shared two-member swarm
and the phone's message on Windows; this is relay chat evidence, not proof of
native OTP-over-WebRTC, two-way message delivery or audio timing. The user also
confirmed the status correction worked. Earlier dated entries retain their
validation limits at the time they were written.

Corrected the stale separate-network status in the current plan. Made the next
audio slice explicit: one iPhone plays a preloaded song, then two phones schedule
the same song, measure acoustic alignment/drift and correct it. Confirm the
actual iPhone runtime profile while making the increment usable. Continuous
streaming, distributed DSP and microphone-based automatic calibration remain
follow-ons. No cleanup or Windows native dependency port blocks this product
target. Documentation only; no builds, tests or deployments performed.

## 2026-10-30 — Preserve audio and in-playback calibration ideas

Recorded the discussion in the master plan: two-iPhone synchronised music as
the next product target; a later 10–100-speaker commodity-device system;
buffering, spatial/upmixed playback and the Dolby compatibility distinction;
known-song features or inserted acoustic probes; scheduled short distributed
microphone captures; analysis on available nodes; and ongoing timing/drift,
room-response and listening-position correction. Included speculative ideas,
user input/heuristics, clock/output/input-delay distinctions and unresolved
measurement ambiguities without claiming feasibility. The user prefers moving
forward without a cleanup phase. Existing distributed-DSP work remains a
possible supporting increment, rather than replacing the stated product goal.

Documentation only. No implementation, build, tests or deployment performed.

## 2026-10-29 — Clear obsolete desk-disconnection error after reconnect

The live Render health endpoint returns HTTP 200, and a temporary client using
the bundled Windows runtime authenticated over public WSS. Reading the existing
Windows UI confirmed that its sidebar said connected while its action-error
label still said disconnected. The model retained the earlier failed-action
error across successful snapshots. It now clears that specific error when a
snapshot confirms relay connectivity; unrelated errors remain visible. Failed
send drafts remain available for manual retry; no message was sent on the user's
behalf. The initial disconnection's cause was not captured and is unconfirmed.

The model compiles with warnings as errors and is staged for the existing
automatic reloader. A direct callback check confirms a connected snapshot clears
the old error. The existing live window still showed the old error after staging;
loading the expanded backend watcher in that instance is not confirmed. No tests
were added. No service deployment or restart was performed.

## 2026-10-29 — Unconditional backend reload in the Windows watcher

Extended the existing 750 ms watcher with 13 executable lines using OTP's
`code:module_status/1`, `code:purge/1` and `code:load_file/1`. It reloads all
changed, loaded project modules in the app's `ebin/`; the UI retains its existing
window rebuild path. Backend, model and host receive no compatibility/state
checks or environment-specific treatment. No additional worker or dependency.
Existing process state is retained; incompatible changes and old-code purges
may crash/terminate processes. Failed loads are logged and retried.

The host compiles with warnings as errors and is staged in the Windows bundle.
No tests were added or run and the live app was not restarted. One restart of
an app using the old UI-only watcher is needed to install the expanded watcher.
Native libraries, runtime and launch settings remain outside BEAM code reload.

## 2026-10-29 — Correct local node status during desk disconnection

The legacy relay snapshot incorrectly marked the local node down whenever it
had neither a desk connection nor direct peers. The runtime producing the
snapshot is itself evidence that the local node is running. It now reports
Running with `local_process` detail independently of desk connectivity; the
sidebar continues to report desk reconnection. Remote status and graph edges
are unchanged. The shared worker compiles with warnings as errors and is staged
in the Windows app's `ebin` for the next restart. No tests were added or run,
and the running app was not restarted or reloaded.

## 2026-10-29 — Windows native source alignment; dependency build incomplete

Reviewed the accepted OTP architecture, incremental implementation policy and
recent Mac/iPhone integration. Windows now has explicit launch profiles. Native
startup selects the shared WebRTC distribution carrier and native desk/runtime,
disables EPMD and automatic/transitive distribution connections, and loads
transport applications from `native_lib/`. The existing bridge already routes
native commands to the shared runtime; no second membership/chat layer was added.

The Windows UI recognizes native snapshots, uses the actual OTP node identity,
shows asynchronous submission notices and whole-VM trust, and confirms
cluster-wide mutual removal. It disables voluntary leave and hides unsupported
desk switching. Additional create/join actions are disabled while a native
cluster is selected. Existing swarm labels, graph implementation, UI/model
ownership and the legacy multi-swarm path remain in place.

`build.ps1 -Transport Native -NativeLibRoot ...` can accept a self-contained
Windows dependency bundle, checking application/NIF loading before packaging.
No such complete bundle is available here. The default remains `Legacy`, with
an explicit profile file consumed by both launchers; failed native packaging
does not silently select another transport.

Validation: all shared and Windows Erlang sources compile with warnings as
errors. The Win32 launcher compiles with `/W4 /WX`; PowerShell scripts parse.
A Windows OTP VM boots the native carrier without EPMD using a transient cookie;
this does not exercise WebRTC or admission. The complete legacy Windows app was
rebuilt at `builds/Windows/Parvi/Parvi.exe`, without running test suites or UI.
No tests were added. No app launch, peer connection, Render service change or
Mac/iPhone build was performed.

Dependency investigation fetched the pinned transport packages. With the
Visual Studio environment, upstream CRC compiles; the Mix build then fails
because Cargo is not installed. Source inspection also confirms POSIX socket/
time headers in DTLS and POSIX shared memory/mapping in Shmex/Unifex. A Rust
installation alone is not a demonstrated solution. Dependency sources were not
edited, and no native bundle or cross-platform interoperability is claimed.
Next Windows work is a supported Windows NIF build/port, followed by native app
packaging and a focused invitation/chat check through the global Render desk.

## 2026-10-29 — Native iPhone packaging and startup in source

Added target static builds for upstream DTLS, SCTP, SRTP and CRC NIFs, using
OpenSSL 3.5.9 and SRTP 2.7.0. The iOS-only Cargo manifest/lock builds the
unmodified ExSCTP implementation with Rustler 0.37.0's static entry points;
the desktop dependency is unchanged. C NIF globals receive compiler namespaces
to preserve isolation at static link time. Dependency sources are not modified.
CMake and the missing Rust simulator target were installed as build tooling.

The iOS host now registers those NIFs, starts a fresh named node using the shared
WebRTC carrier/native profile, and stages portable BEAM dependencies plus OTP
compiler resources. Runtime preparation defaults to native; an explicit relay
build retains the earlier path in separate resources. Xcode's expanded device
settings select the expected archives, C/Swift flags and resource directory.
The executable exports the OTP NIF API for Rustler's runtime lookup.

The existing in-process DNS adapter also seeds configured STUN/TURN hostnames;
desk resolution no longer clears unrelated cached hostnames. The phone declares
its local-network usage. Networking and trust stay in BEAM. Normal iOS startup
now records `status=running` rather than automatically killing/restarting the
chat worker; the earlier feasibility probe is opt-in via `PARVI_RUNTIME_PROBE=1`.

Validation: shared Erlang compilation passes with warnings as errors. Device
static archives compile, and the C host links against the embedded OTP runtime
and transport, including an executable link with 176 exported NIF API symbols.
The shared iOS Swift module compiles and the native iPhone host type-checks.
Device runtime resources and public TLS roots are prepared. The initial sandbox
blocked certificate export and Swift package cache access; authorized execution
completed those steps. No automated tests were added or run.

No full app build, installation, on-device execution, Render connection or desk
interruption was performed. Simulator native compilation remains unverified.
Previously installed Mac/iPhone apps retain their earlier behavior; compile/link
success does not establish a native Mac–iPhone connection. The one-cluster,
leave/reconnect, mesh and authority-recovery limitations remain as documented.
Next implementation is the small binary-stream/remote-DSP increment; build/use
the new native apps when that work needs connection evidence.

## 2026-10-29 — Native Mac integration in source

Moved the reusable WebRTC carrier, distribution controller, admission authority,
trust worker and desk connector from the experiment into `control/src/`.
Probe drivers stay isolated; their existing compile helper follows the move.
The Mac host now selects the native profile/carrier without EPMD or automatic
transitive connections. Its supervisor starts shared `pg`/chat and the connector;
legacy swarm routing, discovery and topology workers do not run in that profile.

Added a native JSON adapter for create/invite/join/chat and cluster-wide mutual
removal through the existing UI. Invitations are cached rather than issued on
every UI poll. Join submission is explicitly pending; it does not claim
connection success. Removal's confirmation text reflects full-cluster scope;
the graph's rendering/interaction and Windows sources are unchanged. Native
operation failures are surfaced in status snapshots.

The Mac build now compiles the pinned Mix dependencies, packages Elixir support
and OTP compiler resources, dereferences build-cache links and relocates/signs
native dependencies. A packaging check exposed SRTP path/header-size issues;
short sibling library paths resolve those without rebuilding upstream NIFs.
The shared JSON additions are optional for existing iPhone/Windows snapshots.

Validation: shared Erlang compilation passes with warnings as errors; shared
Swift module compilation and Mac-host type-checking pass. Dependency packaging
and native signing complete in `/private/tmp/opensound-native-packaging`.
No automated tests were added or run. No full app rebuild, launch, connection
test, iPhone deployment or Render service change was performed. These checks
do not establish a working connection through the new Mac app path.

Limits: one native cluster per app session, represented by the existing swarm
view. Additional independent swarms, desk/cluster switching, voluntary leave,
connection mesh and automatic reconnect are not implemented. Failed joins need
a restart. Quitting disconnects but does not revoke remote membership. Existing
authority/publication recovery limits remain. Current iPhone/Windows builds and
previously installed Mac apps retain their earlier transport and cannot use
native cluster invitations. Next implementation is iPhone native packaging;
use/check the updated Mac path when needed, without a separate testing phase.

## 2026-10-29 — Plan revised around incremental implementation

Removed the requirement to complete internet/recovery checks and broad failure
handling before native app integration. Next is a small Mac integration of the
existing carrier, trust worker, desk connector and shared OTP chat runtime, then
iPhone packaging. Connection checks support that work when needed; TURN and
broader recovery remain follow-ups rather than prerequisites. Keep asking before
adding automated tests or hardening.

Removed the stale competing next-steps list, corrected the desk deployment
status, and marked the original audio research milestones as reference rather
than current development gates. Render CLI login and access to the single
global desk are confirmed. This was a documentation revision; no app code,
connection test, deployment or service interruption was performed.

## 2026-10-29 — Use the global Render desk for development

Clarified step 3b: development and connection checks use the single global
Reception Desk at `wss://parvi-reception-desk.onrender.com/relay/v1`.
No separate local/test desk is needed. The user confirmed that this is one
shared development, testing and production environment and authorized changes
regardless of risks, including hosted-desk interruption for the outage check.
This update changes the plan only; no connection check or service change was
performed. Step 3a remains compiled only, and step 3b remains pending.

## 2026-10-29 — Step 3a Reception Desk introductions, compiled only

Started step 3 with a small isolated connector. The user requested implementation,
compilation and documentation only; no tests were added or run for this slice
and no live desk was contacted.

`parvi_relay:start_link/1` can send mailbox envelopes to an explicit Erlang owner
without the legacy swarm decoder. Existing defaults remain for current apps.
`parvi_cluster_desk` uses it to introduce an inviter/joiner pair, exchange SDP/ICE,
and hand admission/native setup to the existing trust worker and OTP carrier.
Experimental v2 links wrap native v1 invitations with desk/mailbox addresses.
Cookies and native packets stay on the WebRTC DataChannel.

The carrier accepts the third-party library's ICE-server configuration for
STUN/TURN; no TURN service was provisioned. Shared core and all experimental
Erlang modules compile with warnings as errors. No app, Windows, graph, test or
public-service changes. Internet connectivity and recovery remain unverified.

Next, when requested: connection proof (3b), then individual recovery behaviors
(3c). See [the plan](PLAN.md) and
[connector usage and limitations](../control/transport/experiments/otp_dist/README.md#reception-desk-introductions-step-3a-compiled-only).

## 2026-10-29 — OTP foundation alignment step 2a

Completed the interrupted foundation work before internet/recovery step 3.
Behavior and reuse take priority; `parvi`/`swarm` names and UI labels remain for
later cleanup. No Windows, graph, native UI or Reception Desk changes.

Added opt-in `parvi:start(native_cluster)`. Its supervisor starts only the
existing `parvi_pg` scope and shared chat `gen_server`. Custom swarm gossip,
application relay/direct routing, discovery and topology workers do not run in
that profile. Existing apps retain the compatibility startup path until native
integration. The profile does not establish channels or a connection mesh.

Replaced the chat worker's observer monitor map with OTP `pg` membership.
Observer exit cleanup is automatic, duplicate subscriptions remain idempotent,
and subscriptions survive chat-worker restart. A scope restart rebuilds chat
membership and requires explicit observer resubscription. History stays local,
bounded and transient; sends remain best effort. Admission permission stays
separate from OTP's live node/process membership.

Validation: shared-core compilation and all 16 EUnit tests pass. The extended
trust smoke passes using four independent BEAM VMs over real WebRTC: shared
chat, one observer event per test send, worker/scope restart recovery, native
group pruning after cluster-wide removal, fresh re-admission, authority
handover/outage and trust-manager shutdown. All previous admission rejection
checks still pass. The original carrier regression also passes binary RPC,
remote execution, ordered messages, links/monitors, idle ticks, silent loss and
bad-cookie rejection. Socket tests require local UDP access outside the sandbox.

Next: step 3 internet/recovery, including connection establishment/arbitration,
backpressure and admission-actor failure recovery, before native app integration.

## 2026-10-28 — Trusted native cluster admission step 2

The user chose cluster-wide mutual removal: the caller and target lose native
cluster access across their logical swarms. Implemented the isolated policy in
Erlang without changing the working apps, Windows, graphs, core relay or public
service. See [the experiment](../control/transport/experiments/otp_dist/README.md)
and [the updated plan](PLAN.md#trusted-native-otp-cluster-direction-accepted-2026-10-28).

`parvi_cluster_auth` uses OTP Ed25519, JSON/URI parsing and secure randomness.
Expiring capability invitations pin an ephemeral inviter key and contain no OTP
cookie. Challenge/proof/grant exchanges bind both device identities and the
native name to actual DTLS certificate fingerprints and fresh nonces. Pairwise
cookies travel inside DTLS; the local Python introducer never supplies them.
`parvi_cluster_trust` gates native setup, acceptance and activation and monitors
its controllers so even normal trust-manager shutdown closes native access.
Unapproved native frames are rejected at the header, before body buffering.

`parvi_cluster_authority` is a serialized, cluster-local OTP actor. Every active
node may invite. It retains current membership and live invitation hashes, not
permanent banned-device records. Mutual removal expires capabilities issued by
either removed node and the capabilities through which either entered, advances
the epoch and fences their native routes. Surviving links continue. The actor
and retained capability records move to a survivor when its host is removed.
Fresh invitations can readmit previously removed nodes. A populated VM trust
domain cannot silently merge with another; swarms within it share full VM trust.

The four-node step-2 smoke check passes: remote execution, invitations from
different nodes, wrong/expired capabilities and altered expiry, session/nonce
replay, forged signatures, node-name impersonation, malformed signed claims,
unauthorized native frames, cluster-wide revocation, deliberately restored old
cookies, fresh re-admission, retained survivor invitations after authority
handover, admission-actor outage and trust-manager termination. The original
step-1 check also passes native RPC/spawn/PIDs, binary echoes, ordered messages,
links/monitors, healthy ticks, silent-loss detection and bad-cookie rejection.
All experimental modules compile with warnings as errors.

This is not production deployment or a claim of Byzantine security. Native
members retain full VM access; removal cannot undo prior key theft or code
compromise. Authority crash/partition recovery, cancelled-join cleanup, partial
publication and reliable revocation receipts remain step-3 work. Admission fails
closed during authority outage while existing native connections continue.

Run: `python3 control/transport/tools/otp-trust-smoke.py` and
`python3 control/transport/tools/otp-dist-smoke.py`.

## 2026-10-28 — Native OTP distribution over WebRTC step 1 passed

Added an isolated carrier proof under
`control/transport/experiments/otp_dist`, outside normal compilation and app
packaging. The three Erlang modules supply carrier callbacks, a WebRTC process
distribution controller and a local probe harness. OTP `dist_util` handles the
native handshake, cookie verification, connection supervision and ticks;
`ex_webrtc`/`ex_sctp` handle WebRTC and binary delivery. No distribution protocol,
remote-PID encoding, RPC or monitor implementation was recreated.

The smoke runner compiles with warnings as errors and passes on OTP 29.1.2 /
ERTS 17.1.1. Two independent OS processes register their WebRTC controllers with
ERTS and exercise native RPC, remote spawn/PIDs, computation and exact 256 KiB
binary echoes in both directions, 100 messages in receive order, remote normal
exit monitoring and abnormal linked exits. Native ticks preserve an otherwise
idle connection for nine seconds with a four-second test tick time. Silent loss
then produces OTP `net_tick_timeout`, remote monitor/link `noconnection` and
node-down notifications on both nodes. A separate pair verifies that mismatched
cookies reject distribution after WebRTC has already connected.

The parent passes only local SDP/ICE introductions and stops forwarding signals
before the native handshake. There is no TCP distribution listener, EPMD,
Reception Desk or application message router carrying native traffic. Names and
cookies are temporary, and each node allows only its locally provisioned peer.
This is not production invitation authentication or revocation. The accepted
six-step direction and remaining admission, internet/recovery, mobile and DSP
work are recorded in [the plan](PLAN.md#trusted-native-otp-cluster-direction-accepted-2026-10-28).
End-to-end backpressure, reconnection and audio latency remain unverified.
Working apps, Windows, graph code and public services were not changed.

Run: `python3 control/transport/tools/otp-dist-smoke.py`.

## 2026-10-28 — Shared Apple snapshot reader and single decoding

Mac and iPhone now use Foundation asynchronous byte reading through one shared
LF-delimited snapshot reader. Hosts pass decoded `ChatSnapshot` values to the
model, removing the second JSON decode. Reader delivery stays on the main actor;
shutdown cancels reading, and the iPhone shuts down its local bridge socket
without halting the embedded VM. Windows and all graph sources are unchanged.

Foundation's `.lines` was tested and rejected: it treats Unicode paragraph
separators inside valid JSON strings as record boundaries. The shared reader
keeps LF-only framing, preserves split UTF-8 sequences, skips non-JSON log lines,
and discards incomplete records at EOF, matching the previous bridge behavior.

Twelve Swift tests pass, including real pipes and sockets, fragmented UTF-8,
Unicode separators, EOF, cancellation and idle socket shutdown. The Mac bundle
builds and passes strict signature verification; the unsigned iPhone device
build succeeds. The updated iPhone build has not been installed or tested on
the physical device.

## 2026-10-28 — Library reuse audit and automatic WebSocket pongs

Recorded a first codebase-wide reuse pass in [the plan](PLAN.md#code-reuse-audit-2026-10-28),
separating existing vendored libraries, removable legacy code, and actual
replacement candidates. Removed Parvi's extra WebSocket pong handler: Gun 2.7
already sends the reply and normally suppresses ping notifications.

Twelve Erlang tests pass. Three local nodes stayed connected through the relay
check's 50-second idle period. The first run then hit the helper's five-second
deadline for Phoenix graceful shutdown; the remaining relay regression passed
with deliberate crashes of the disposable test desk, covering reconnect,
admission, chat, overlapping swarms and mutual removal. No public service or
installed app was changed.

## 2026-10-28 — Direct connection worker moved to Erlang

Removed `control/transport/lib/peer.ex`. `parvi_peer_connection` is now an Erlang
`gen_server` calling the existing WebRTC library directly, retaining per-peer
process isolation, signalling, candidate handling and connection-state events.
`parvi_direct` starts and communicates with that worker using ordinary Erlang
calls. No custom Elixir transport modules remain; Mix still builds the upstream
Elixir dependencies and their support modules remain required at runtime. The
existing Phoenix Reception Desk was not rewritten or redeployed.

All twelve Erlang tests pass. The integration check again verifies direct chat
after shutting down a disposable local desk, independent swarms, retention of a
connection shared by two swarms, and interoperability with a relay-only node.
Native Mac/iPhone transport packaging remains unfinished; installed apps were
not changed by this refactor.

## 2026-10-28 — BEAM-owned direct transport experiment

Added an optional direct-transport worker and authenticated swarm signalling,
using third-party `ex_webrtc` and `ex_sctp` through a small Elixir adapter.
Networking stays in BEAM; the native views only display connection state.
The initial Swift WebRTC adapter experiment was removed following the user's
architecture clarification. No WebRTC protocol implementation was written here.

The isolated Mac experiment passes: two independent BEAM VMs establish a direct
data channel, continue bidirectional chat after their local desk is killed,
retain independent swarms and a shared connection, then interoperate with a
relay-only peer after desk recovery. The public Render service is unchanged.
The transport's native dependency packaging and physical iPhone test remain
unfinished; installed apps continue using the working relay. See
[the transport prototype](../control/transport/README.md).

## 2026-10-28 — Apple apps rebuilt for the public relay

Reviewed the Windows relay/default-configuration changes and rebuilt both Apple
apps against the shared OTP settings, Gun/Cowlib and v2 invitation protocol.
The default Render URL remains defined only in `control/src/parvi.app.src`;
neither Apple adapter nor the new Mac smoke check duplicates it.

Fixed iPhone trust-bundle export for OTP 29's certificate-record representation.
Physical testing then exposed the unsupported external `inet_gethost` helper.
iOS now resolves using its in-process `net:getaddrinfo` NIF and refreshes the VM's
host table before Gun connects. An optional resolver callback keeps this adapter
out of other platforms. The original hostname is retained for HTTP and TLS
verification; IPv6-only results select the IPv6 socket family.
The Xcode resource-copy phase now declares the bundled runtime directory as an
output and runs each build, so Erlang-only updates also trigger resource sealing.
Both final app bundles pass strict signature verification.

Shared UI now shows relay errors as well as connected status. A small iPhone
connection receipt records actual snapshot status and OS PID without invitation
credentials or chat content. Eight Swift model tests and twelve Erlang tests
pass. The packaged Mac runtime passes public WSS authentication, admission,
two-way chat and departure, and its legacy local smoke check still passes.

Installed and launched the signed iPhone build. Its OTP self-test passes and
the connection receipt reports authenticated WSS to the shared Render default,
with no error, matching live process 14698. The native Mac UI also shows the
default desk connected and a v2 invitation. The user joined the Mac swarm from
the phone and exchanged “Hi” and “it works” in both directions. Native Mac
inspection confirms both physical nodes in that swarm and both marked Running
in Graph. Operation across separate access networks remains a further test;
this exchange used the public Render relay regardless of local network layout.

## 2026-10-28 - Shared default Reception Desk configuration

The shared OTP settings in `control/src/parvi.app.src` now bundle the public
desk URL once for Windows, macOS and iOS. Fresh native sessions connect without
manual URL entry. `PARVI_RECEPTION_DESK_URL` overrides the default; an empty value
selects local-only development. Explicit OTP/UI configuration takes precedence.
Local test fixtures explicitly disable the public default to remain isolated.

Rebuilt Windows and passed all 14 core/model tests. Two unnamed BEAM clients,
started without any desk environment setting, passed the public WSS invitation,
bidirectional chat, idle and departure test. The three-client local relay test
also passed, including environment overrides and fresh-session configuration.
Apple apps inherit the default when rebuilt; no Apple build was performed here.
Existing sessions need restarting to use the new startup setting.

## 2026-10-28 - Remove leftover build directories

Moved the obsolete `broker/_build` and Windows build products/caches into
`builds/intermediates/legacy-layout-20261028`, preserving their contents.
The private OTP runtime now lives at `builds/intermediates/Windows/otp`, matching
the current build scripts; its startup was verified after relocation. Stopped
the approved legacy Erlang process using the old runtime. The current Windows
app stayed running. Removed the now-empty legacy source directories.

## 2026-10-28 - Reception Desk deployed to Render

Deployed commit `e5e002b80c3b7885b5f38d14153ff9219ff821e5` as one Docker
web service on Render's free plan in Frankfurt. Service
`srv-dbgvjfui0phs73ablggg` is live at https://parvi-reception-desk.onrender.com;
native apps use `wss://parvi-reception-desk.onrender.com/relay/v1`.
Automatic deploys are disabled. Credentials remain in the local Render CLI
configuration, and `SECRET_KEY_BASE` was generated by Render.

The Linux image built and booted on Render, and `/health` passed. Two disposable
Windows BEAM clients with Distributed Erlang disabled passed public WSS
certificate verification/authentication, invitation admission, bidirectional
chat, a 50-second idle check followed by delivery, and departure. The reusable
test is `Services/ReceptionDesk/tools/public-smoke.py`; its clients were stopped.
This verifies the public relay from this laptop, not separate physical networks.
Rebuilt Mac/iPhone apps and cross-device testing remain pending. Free-plan
inactivity can cause a cold start on the next connection.

## 2026-10-28 - Persistent Reception Desk relay

Implemented a minimal Phoenix/Cowboy service around supervised Erlang routing
workers, independent of the deferred browser app. Nodes authenticate ephemeral
Ed25519 identities, register per-swarm capability mailboxes and exchange explicit
versioned JSON over persistent outbound WebSockets. The service owns no swarm
memberships or histories. The shared Erlang core now has an asynchronous relay
admission/transport adapter, v2 invitations without Erlang cookies, reconnect,
presence observations and membership resynchronization after service restart.
Local developer distribution remains available separately.

Windows has desk configuration/status and bundles Gun/Cowlib transport code.
Apple UI and iOS packaging sources have equivalent configuration and TLS trust
resources; Mac/iPhone builds and device execution require Xcode and are not
verified on this Windows machine. Existing apps need restarting/rebuilding.
Deployment is prepared as one Render Docker service; nothing is published.
The old directory launchers remain explicit legacy-only test paths.

See [relay protocol](RELAY_PROTOCOL.md) and [desk guide](../Services/ReceptionDesk/README.md).

Validation on Windows: 14 core/model EUnit checks, 13 workspace/legacy checks,
and two Phoenix authorization tests pass. Three independent BEAM clients with
distribution disabled pass scoped admission/chat, invitation revocation, mutual
removal, creator-independent continuation, runtime desk configuration, a 50-second
idle check and desk restart/reconnect. WSS chat passes; untrusted certificates
and wrong hostnames are rejected. Native relay graph/send/window rebuild and the
existing local UI reload regression pass. The production release boots with
runtime configuration and distribution disabled. Docker image execution and
Render deployment remain unverified because the local engine is stopped; Apple
build/device verification remains pending. Temporary test processes were stopped.

## 2026-10-28 — Windows shares the swarm app structure

Replaced the Windows node sidebar and global chat with a swarm list, New/Add
swarm actions and selected-swarm Graph/Chat tabs. Invitations, scoped histories,
admission, leave and mutual removal reuse `parvi_swarms` through the shared bridge.
Graphs filter `parvi_network` observations by membership. Nodes keep running with
zero memberships. Drafts, selection, tabs, input and pending operations belong to
the supervised Windows model and survive disposable-window reloads.

The shared contract is now explicit in [APP_STRUCTURE.md](APP_STRUCTURE.md).
No change to the transport or previously identified backend membership issues.

Validation: Windows build with warnings as errors and all eleven core/model tests
pass. The native UI was checked for swarm creation/selection, tabs and sending a
message through the selected swarm's composer into its scoped history.
The isolated three-node reload test passes, including scoped membership/graph,
retained drafts/selection/tab, pending swarm sends, crash recovery, corrected
builds without rollback and two-node disconnect/reconnect. Its temporary cluster
uses one shared cookie; per-peer invitation authentication is not covered by that
reload test. The backend's existing concurrency and authentication limitations
remain outside this layout update.


## 2026-10-28 — Browser/server BEAM architecture selected

Recorded the accepted Phoenix/Cowboy + Popcorn 1.0/LocalLiveView direction in
[the current implementation plan](PLAN.md#current-implementation-plan--accepted-2026-10-28).
Shared swarm logic remains Erlang/OTP; the browser runs its own actors and uses
an explicit transport protocol. The plan records the new browser runtime's
limited operating history, compatibility checks and internet-first Mac–iPhone
connectivity scope. This entry records a decision; no stack migration or new
networking functionality has been implemented.

## 2026-10-28 — WebApp and ReceptionDesk separated

Moved the browser assets and QR license to `Apps/WebApp`, and the Erlang service,
API, launchers and directory tests to `Services/ReceptionDesk`. Build outputs are
`builds/WebApp` and `builds/Services/ReceptionDesk`; service compiler caches use
`builds/intermediates/ReceptionDesk`. Updated workspace and Windows references.
The service root identifies ReceptionDesk; browser assets have their own host.
A small local development host forwards the existing WebApp API requests to the
separate service, preserving the directory UI without adding a runtime dependency
from the service to the browser app.

No internet transport, mailbox, relay, browser node or Render deployment was added.
All ten Erlang tests and the integration smoke check pass, including separate
frontend assets, API forwarding, real local node discovery/chat and directory
restart. Native Windows execution was not tested on this Mac.

## 2026-10-28 — Invitation text-field behavior

Replaced the iPhone invitation text/scroll view with a regular editable SwiftUI
text field. Copy always copies its current text, without runtime/network guards.
The Add swarm invitation field also stays editable while networking is disabled
or an operation is pending. Joining still requires working network support;
editing a displayed invitation does not change swarm credentials.
The signed build and all seven shared model tests pass. Installed and launched
on the physical iPhone; its passing runtime receipt matches live process 9635.

## 2026-10-28 — iPhone interface and deployment

The iPhone now shares the Mac swarm list, swarm-specific invitation area,
Chat/Graph views, node details and membership actions. Native stack navigation,
swipeable tabs, larger touch controls, keyboard handling and a runtime information
sheet adapt that shared interface to the phone. Network invitation controls
remain disabled until the iOS transport is implemented; local swarms and chat
use the embedded BEAM.

Both simulator and device builds completed. All seven shared Swift model tests
pass. The device build was signed with the configured development team, its
signature verified, and the update installed on the connected iPhone 12 mini.
After unlocking, a launch crash exposed mismatched shared-package build
artifacts caused by the target-only product-directory override. A clean rebuild
with a global product directory fixed startup. The build helper now sets that
directory for both app and package; native Xcode builds use their default shared
product directory.

The corrected update is installed and running on the physical phone. Its new
Erlang receipt matches the live process (9447), reports OTP 29 / ERTS 17.1.1,
and passes message delivery and supervisor restart checks. Device Hub screen
sharing requires iOS 27, whereas this phone runs 26.6.1, so interactive visual
checks on the phone remain manual. Mac–iPhone networking is still disabled.

## 2026-10-27 — Shared app code belongs with the apps

Moved `ParviKit` to `Apps/Shared/ParviKit`. Updated Mac build/test scripts, the
iOS local-package reference and documentation. `control/` remains the top-level
Erlang layer; build outputs remain under `builds/`. The Mac build and seven
Swift model tests pass; the iPhone project is checked through an unsigned build.

## 2026-10-27 — Platform sources and generated builds separated

Moved app sources to `Apps/macOS`, `Apps/iOS`, `Apps/Windows` and `Apps/Web`.
Shared app code is in `Apps/Shared/`; shared Erlang code remains in `control/`. Existing local
artifacts were moved under the Git-ignored `builds/` directory; platform products
and compiler/runtime caches are separated into platform folders and
`builds/intermediates/`. Absolute-path Apple caches were regenerated in place of
reusing relocated precompiled modules.

Updated shell/PowerShell launchers, Python tests, Erlang build directories,
the Xcode local-package reference, runtime preparation and documentation links.
Added unsigned iOS and web build helpers, a shared Apple test helper, and a root
Erlang workspace configuration so supported commands also keep their output under
`builds/`. Plan/handover links follow their current locations under `docs/`.

Validation: ten Erlang tests and seven Swift model tests pass. The relocated
Mac bundle passes signature verification, two-node and three-node smoke tests,
and native launch. The web HTTP/discovery smoke test passes using staged assets.
The moved iOS project compiles unsigned into `builds/iOS/Debug-iphoneos/Parvi.app`.
Windows build/setup/test paths were updated and inspected; native Windows builds
cannot be executed on this Mac. Existing ignored Windows caches on other machines
can be reused through `PARVI_OTP_ROOT` or moved to the documented cache location.

## 2026-10-27 — Multiple swarms per node

Replaced the single-swarm Mac layout with a swarm list. Add swarm accepts an
invitation without replacing other memberships; New swarm creates an independent
group. The selected swarm owns its invitation/Copy action and Chat/Graph tabs.
Narrow windows navigate list/detail; iPhone uses swipeable pages. Drafts and
operation acknowledgements are scoped by swarm ID, and the graph filters the
shared observations to the selected membership.

Added the supervised `parvi_swarms` worker and `parvi_invitation` format. Each
swarm has a roster, bounded history, local admission token and temporary removal/
revocation state. Leave affects one membership. Remove both revokes the two
memberships and their admission invitations, leaving other memberships and other
admitted participants intact. Active invitation issuers rotate revoked links.
Remaining members can invite after the creator leaves. The legacy chat/Windows
interface is preserved separately; it does not yet expose the new swarm model.

Secure randomness uses OTP crypto. Mac packaging now includes its OpenSSL dylib,
rewrites the local load path, signs both native libraries and includes its license.
iOS preparation includes the crypto resources for its already-linked static NIF;
the on-device startup proof now also appears in the scoped swarm chat.

Nine Erlang tests and seven Swift model tests pass. The three-node bundled-runtime
test passes overlapping swarms, isolated messaging, mutual removal, invitation
revocation, fresh re-admission and creator-independent continuation. The iPhone
interface compiles unsigned. Native Mac layout is checked separately.

This remains loopback-only trusted Erlang distribution, not an internet security
boundary. Partition reconciliation, simultaneous-removal arbitration, calendar
expiry and large-swarm transport remain open. See the Mac guide for limitations.


## 2026-10-27 — Adaptive Mac invitation interface

Replaced the Mac Connect sheet and directory-based onboarding with a permanent
two-row invitation grid: selectable read-only local link plus Copy, and a paste
field plus Join swarm. The strings come from the shared BEAM formatter; this is
still a trusted same-computer connection preview, not the proposed revocable
invitation/membership protocol. Expiry controls, leave, mutual removal and LAN/
internet transport are not implemented. Each Mac runtime start now creates a new
session name and cookie, including restart within the same app process.

Shared SwiftUI now adapts between a desktop sidebar and compact Chat/Swarm
navigation. Swarm has a draggable native graph, node details and an accessible
list. A portable supervised `parvi_network` observer gathers bounded worker
health checks and peer adjacency reports without drawing invented mesh links.
Existing Windows status/graph workers remain unchanged. No SwiftUI hot reload
was added.

Bridge responses echo request IDs. The Apple model waits for acknowledgement,
retains rejected drafts/invitations and preserves newer draft edits. The old
separate node/cookie fields and Reception desk controls are removed from this UI.
The shared iPhone interface compiles with networking still disabled there.

Validation: seven Erlang tests and four Swift model tests pass. The rebuilt
bundled-runtime integration test passes invitation joins, correlated errors,
network status/edges, bidirectional UTF-8 chat and disconnect retention. Native
Mac checks cover wide/narrow layout, invalid invitations, chat composition and
network navigation. The unsigned physical-iPhone target compiles; this does not
establish on-device execution or inter-device networking.

## 2026-10-27 — Live native node-network graph

Added Chat/Network tabs and a lightly adapted, attributed OTP Reltool graph view.
The existing force-layout engine remains unchanged. Vertices use the established
status colours; drag moves them and click requests the existing connection-string
copy operation. Reltool's editor controls are hidden and hidden-tab layout pauses.
The graph and ticker are disposed with the old window during UI reload.

A separately supervised topology worker gathers real peer adjacency reports
without assuming a fully connected mesh. Reports are sampled and uncertain or
indirectly known nodes remain distinguishable. This is connectivity, not audio
routing. Source provenance is in `Apps/Windows/THIRD_PARTY.md`.

The live Windows instances successfully reloaded and kept their original nodes,
worker PIDs and chat history. An initial wrong notebook constructor made the UI
unavailable briefly; the corrected build recovered automatically without rollback.
Warnings-as-errors compilation and six core tests pass. The native integration
test covers repeated graph/window replacement and peer-link updates.

## 2026-10-27 — Investigated native topology graph reuse

Inspected the installed OTP Reltool sources and ran an isolated native Windows
probe of its force graph. Embedding, live graph updates, four status colours and
shutdown cleanup pass. Identified private-API, fixed-controls, callback, event
handling and continuous-redraw constraints. No production UI was changed.
See [investigation](NODE_GRAPH_INVESTIGATION.md) and
`Apps/Windows/test/parvi_graph_probe.erl` for the result and reproducible probe.

## 2026-10-27 — OTP node-status lights, applied through live UI reload

Replaced the plain sidebar list with native status icons and text, using the
RabbitMQ Management v3.13.7 palette. A supervised Windows status worker combines
OTP nodeup/nodedown notifications with bounded asynchronous chat-worker calls.
Green means responsive, yellow unresponsive, red disconnected, grey checking.
Disconnected peers stay listed; no state claims that an unreachable VM is dead.
Status rows survive UI replacement through the existing live model.

The worker is added dynamically after wx startup, allowing this feature to reach
already-running apps through the UI watcher without a backend restart. Verified
in the user's running app: both original nodes remain connected, the worker PID
and history are unchanged, and both status lights are green.

The isolated native integration test passes worker suspend/resume (yellow/green),
disconnect/reconnect (red/green), retention of red across reload, and the existing
supervision/reload checks. Source/style references are in the Windows guide.

## 2026-10-27 — Supervised disposable UI; no rollback

Replaced reload-time state capture and old-code rollback with a Windows OTP
supervisor, a small live UI-model process, and a disposable wx child. Drafts,
geometry, and connection fields are updated in the model as edits happen. Chat
history is read from its existing worker. Requests belong to the model so a send
can finish after its window disappears. The watcher retains only a build hash,
not an old UI binary. A failed new build leaves no window until corrected; normal
runtime window crashes are restarted by the supervisor using current code.

The isolated native-window test passes for repeated reload, persistent model and
backend identity, messaging while UI initialization fails, corrected-build
recovery, supervised crash recovery, and in-flight sends. Existing instances need
one restart because the host architecture changed. This supersedes the earlier
rollback implementation described below.

## 2026-10-27 — Automatic Windows UI reload

Added a stable `parvi_windows_host` that watches the compiled Windows UI module.
Each changed valid build replaces the wx process/window without restarting the
node or shared OTP application. Draft, geometry, maximized state, visible history,
error text, and connection-dialog fields are restored. Reload waits for active
requests; incomplete files are ignored and failed initialization rolls back to
the previous UI. Closing the active window still closes the app normally.

The build script now skips an unchanged C launcher, so UI builds can run while
Parvi.exe is open. Existing instances need one restart to activate the host.
Backend, host, and native-runtime changes remain separate upgrades.

Validation: warnings-as-errors compilation and an isolated native-wx integration
test pass. The test proves repeated automatic replacements, retained UI fields,
unchanged node/cookie/chat and pg workers, peer connectivity and message delivery
across reloads, invalid-file rejection, failed-build rollback, corrected-build
recovery, and normal shutdown. The deliberate broken-build crash report is
expected. See `Apps/Windows/reload-smoke.py`.

## 2026-10-27 — Click a node to copy its connection string

The Windows Nodes list now copies the selected node's connection string to the
clipboard. Remote strings are fetched asynchronously from the connected node,
with a timeout and validation, rather than guessing its cookie from the local
connection. Snapshot refreshes preserve list selection when membership is
unchanged. Both instances must be restarted after the update.

Warnings-as-errors compilation passes. The two-node integration test passes,
including retrieval of the initiating node's actual connection string through
its peer when their default cookies differ. The first test run hit a directory
discovery failure; a diagnostic rerun passed all checks.

## 2026-10-27 — Standard text fields for connection strings

Simplified the Windows dialog to a selectable read-only local connection string
and an editable peer connection string. Removed custom clipboard buttons and
handlers; copying and pasting use the operating system's text-field shortcuts
and context menus. Recompiled the Windows module with warnings treated as errors.

## 2026-10-27 — Single connection string on Windows

Replaced the Windows node/cookie copy buttons and inputs with **Copy connection
string**, one masked input, and **Paste connection string**. The versioned
`parvi://connect/v1?node=...&cookie=...` format is encoded and validated in shared
Erlang code. The existing loopback policy and Mac request format are preserved.
The Reception desk continues to list names without publishing credentials.

Validation: six core EUnit tests pass, including escaped-field round trips and
invalid/duplicate/oversized input. The real Windows two-node integration test
passes using the combined string for connection and bidirectional chat.

## 2026-10-27 — Windows wxErlang exercise

Added `Apps/Windows/`: native wxErlang chat UI, Win32 C launcher, private pinned OTP
29.1.2 runtime setup, PowerShell build/diagnostic scripts, and a loopback smoke
test. Reuses the existing `parvi` workers and shared request/snapshot contract.
The shared bridge accepts Windows app node names alongside Mac names while
preserving the loopback restriction. Added `Apps/Web/run.ps1` for the unchanged
Reception desk service. No audio or mobile/LAN transport was added.

Validation on Windows x64: warnings-as-errors Erlang compilation; all four core
EUnit tests pass; the native app launches and sends through the wx composer;
the connection dialog renders. The integration test passes with two real Windows
nodes, directory discovery, cookie-authenticated connection, bidirectional UTF-8
chat, oversized-message rejection, and peer departure. The sandbox blocked OTP's
native DNS helper, so the passing integration run used normal desktop permissions.

Build and run: [Windows guide](../Apps/Windows/README.md). The package is unsigned and
retains the full OTP libraries; installer, size reduction, and cross-device
transport remain future work.

## 2026-10-26 — Embedded iOS BEAM runtime test build

Replaced the unavailable iOS adapter with a real in-process OTP host using the
pinned Mob iOS runtime artifacts for OTP 29.1.2 / ERTS 17.1.1. SHA-256 checks
match the upstream release digests. Native startup and static-driver glue are
small platform-specific files; the UI, chat state, JSON contract and supervision
remain shared. Runtime provenance is in `Apps/iOS/THIRD_PARTY.md`.

Validation:

- Physical-device arm64 and arm64 simulator builds both succeed.
- The simulator actually boots BEAM and executes the shared `parvi_chat` worker.
- Erlang's startup self-test verifies messaging, kills the worker and confirms
  supervisor recovery. Its JSON receipt reports `status=passed`, OTP 29,
  ERTS 17.1.1, different worker PIDs (`<0.91.0>` → `<0.93.0>`), and the same
  OS process PID returned by the simulator app launcher.
- A message typed and sent through the simulator SwiftUI composer appears in
  history. Core EUnit checks pass (4 tests).

The physical iPhone 12 mini is paired over USB and reports iOS 26.6.1. Developer
Mode is enabled. Personal Team signing is configured and the user authorized
the macOS signing-key prompt. The development-signed build succeeds, its code
signature verifies, and `devicectl` successfully installed it on the phone.
iOS currently refuses launch pending the user's developer-profile trust step
under Settings → General → VPN & Device Management. Physical runtime execution
remains unverified until that step and a successful launch.

This build is foreground/local-only: it intentionally remains an unnamed node
without EPMD, peer joins or Reception desk access. It proves the embedded-runtime
path in the simulator, not the final Mac–iPhone messaging milestone. Next: the
signed physical-phone test, then private-LAN transport.

## 2026-10-26 — Reception desk (local discovery)

Added `Apps/Web/`: supervised in-memory directory, OTP HTTP server on
127.0.0.1:8765, JSON list/register API, join form and local QR generation. Duplicate
names are deduplicated and all names are forgotten on restart. The directory
stores names as binaries, caps resource usage and makes no liveness claims.
The website and native connection sheet call it **Reception desk**. It runs in
Erlang, but does not join the registered nodes' cluster or store chat messages.

Added a shared Erlang discovery client and a minimal **Register / Find nodes**
action in the native connection sheet. It registers the actual local node name
and returns known names for selection. Cookies remain separate. Mac transport
is still loopback-only; iPhone runtime integration remains pending.

Broker EUnit and control EUnit checks pass. Both Mac and unsigned iPhone UI
builds succeed. End-to-end testing passed for real app registration, returned
peer names, authenticated Erlang connection, two-way chat and broker reset.
Native registration and idempotent web registration were also verified in the
UI; the page renders its local QR code. See [broker guide and API](../Services/ReceptionDesk/README.md)
for usage, limits, QR behavior and the integration-test command.

## 2026-10-26 — Shared native code and iPhone project

Extracted the existing Mac UI and model into the local `Apps/Shared/ParviKit` Swift
package. Mac retains a small app entry point and its Erlang process adapter.
Created `Apps/iOS/Parvi.xcodeproj` using that same package, with an explicit unavailable
embedded-runtime adapter. There is no fake iPhone chat or remote-execution proxy.
Extracted the transport-independent Erlang JSON entry point `parvi_bridge:request/1`.

Full Xcode 27.1 and the iOS 27.1 SDK are now available. The unsigned arm64 iPhone
project builds with Xcode. The Mac app rebuilds using the shared sources, and
EUnit passes (4 tests), including the native JSON entry point. The bundled Mac
runtime's messaging smoke test also passes, and sending through the extracted
shared SwiftUI view was verified in the native Mac window.

Next: pin and integrate an actual in-process iOS BEAM runtime, then prove shared
Erlang worker execution on a signed physical device. Building the UI shell does
not satisfy that gate. See [iPhone project](../Apps/iOS/README.md),
[shared package](../Apps/Shared/ParviKit/README.md) and
[decision 0002](decisions/0002-shared-native-app-code.md).

## 2026-10-26 — Native Mac application

Added a SwiftUI application in `Apps/macOS/` with chat bubbles, composition, runtime
status, visible chat peers and a manual connection sheet. The `.app` bundles an
OTP release and starts Erlang as a child process. A private JSON pipe bridge
keeps chat and membership logic in Erlang. No terminal is needed to launch it.

The build uses the installed Swift command-line tools, with ad hoc signing for
local execution. Public distribution, notarization, iPhone embedding and LAN
onboarding remain future steps. Connections are intentionally loopback-only.

The bundled-runtime smoke test passed for startup, UTF-8, validation, two-way
chat and peer departure. The native app was launched and visually checked;
sending through the SwiftUI composer displayed the message in history. Existing
EUnit checks still pass (3 tests). The app's ad hoc signature verifies. See
[Mac build and usage](../Apps/macOS/README.md).

## 2026-10-26 — Mac chat baseline

Read all design documents and followed the newer Parvi handover's chat-first
scope. [Decision and iOS investigation](decisions/0001-chat-first-and-ios-feasibility.md)
record the runtime candidates, recommendation, environment and remaining gate.

Implemented `control/`: OTP application, supervisor, `pg` group membership,
chat worker, terminal/UI API, bounded in-memory history and loopback defaults.
Installed Erlang/OTP 29.1.2 and rebar3 3.27.3 through Homebrew. Homebrew also
installed runtime dependencies and upgraded libpng/pcre2 as part of installation.

Validation on this Mac:

- `rebar3 compile`: passed with warnings treated as errors.
- `rebar3 eunit`: 3 tests passed, covering messaging/UI events, input validation,
  history eviction, worker restart and `pg` restart recovery.
- `escript tools/smoke.escript`: passed using two real local BEAM nodes; checked
  two-way messaging, killed-worker recovery, node departure and rejoin delivery.

This proves a Mac actor/messaging baseline, not iPhone execution or audio sync.
Messages/history are transient and best effort; overload handling, discovery,
stable identities and production security remain outside this step.

Next required environment work: full Xcode, iOS SDK, Apple ID development signing,
and a connected physical iPhone. Then reproduce a pinned embedded full-BEAM
runtime and execute the Erlang chat worker on the phone before adding UI or audio.

Build and demo instructions: [control/README.md](../control/README.md).
