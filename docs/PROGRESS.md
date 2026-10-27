# Progress

## 2026-10-27 — Investigated native topology graph reuse

Inspected the installed OTP Reltool sources and ran an isolated native Windows
probe of its force graph. Embedding, live graph updates, four status colours and
shutdown cleanup pass. Identified private-API, fixed-controls, callback, event
handling and continuous-redraw constraints. No production UI was changed.
See [investigation](NODE_GRAPH_INVESTIGATION.md) and
`windows/test/parvi_graph_probe.erl` for the result and reproducible probe.

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
expected. See `windows/reload-smoke.py`.

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

Added `windows/`: native wxErlang chat UI, Win32 C launcher, private pinned OTP
29.1.2 runtime setup, PowerShell build/diagnostic scripts, and a loopback smoke
test. Reuses the existing `parvi` workers and shared request/snapshot contract.
The shared bridge accepts Windows app node names alongside Mac names while
preserving the loopback restriction. Added `broker/run.ps1` for the unchanged
Reception desk service. No audio or mobile/LAN transport was added.

Validation on Windows x64: warnings-as-errors Erlang compilation; all four core
EUnit tests pass; the native app launches and sends through the wx composer;
the connection dialog renders. The integration test passes with two real Windows
nodes, directory discovery, cookie-authenticated connection, bidirectional UTF-8
chat, oversized-message rejection, and peer departure. The sandbox blocked OTP's
native DNS helper, so the passing integration run used normal desktop permissions.

Build and run: [Windows guide](../windows/README.md). The package is unsigned and
retains the full OTP libraries; installer, size reduction, and cross-device
transport remain future work.

## 2026-10-26 — Embedded iOS BEAM runtime test build

Replaced the unavailable iOS adapter with a real in-process OTP host using the
pinned Mob iOS runtime artifacts for OTP 29.1.2 / ERTS 17.1.1. SHA-256 checks
match the upstream release digests. Native startup and static-driver glue are
small platform-specific files; the UI, chat state, JSON contract and supervision
remain shared. Runtime provenance is in `ios/THIRD_PARTY.md`.

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

Added `broker/`: supervised in-memory directory, OTP HTTP server on
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
UI; the page renders its local QR code. See [broker guide and API](../broker/README.md)
for usage, limits, QR behavior and the integration-test command.

## 2026-10-26 — Shared native code and iPhone project

Extracted the existing Mac UI and model into the local `shared/ParviKit` Swift
package. Mac retains a small app entry point and its Erlang process adapter.
Created `ios/Parvi.xcodeproj` using that same package, with an explicit unavailable
embedded-runtime adapter. There is no fake iPhone chat or remote-execution proxy.
Extracted the transport-independent Erlang JSON entry point `parvi_bridge:request/1`.

Full Xcode 27.1 and the iOS 27.1 SDK are now available. The unsigned arm64 iPhone
project builds with Xcode. The Mac app rebuilds using the shared sources, and
EUnit passes (4 tests), including the native JSON entry point. The bundled Mac
runtime's messaging smoke test also passes, and sending through the extracted
shared SwiftUI view was verified in the native Mac window.

Next: pin and integrate an actual in-process iOS BEAM runtime, then prove shared
Erlang worker execution on a signed physical device. Building the UI shell does
not satisfy that gate. See [iPhone project](../ios/README.md),
[shared package](../shared/ParviKit/README.md) and
[decision 0002](decisions/0002-shared-native-app-code.md).

## 2026-10-26 — Native Mac application

Added a SwiftUI application in `macos/` with chat bubbles, composition, runtime
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
[Mac build and usage](../macos/README.md).

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
