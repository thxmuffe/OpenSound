# Parvi for Windows — wxErlang

The native Windows app follows the [shared app structure](../../docs/APP_STRUCTURE.md)
used by macOS and iOS. The sidebar lists swarms and provides **New swarm** and
**Add swarm**. Selecting a swarm opens its invitation, **Graph** and **Chat** tabs.
Nodes can belong to many swarms or none; swarms own their chat histories.

## Build and launch

Requires Windows x64, PowerShell, and Visual Studio's **Desktop development with
C++** workload. From the repository root:

```powershell
.\Apps\Windows\setup.ps1
.\Apps\Windows\build.ps1 -Test
.\builds\Windows\Parvi\Parvi.exe
```

Setup verifies and extracts the official OTP 29.1.2 archive into
`builds/intermediates/Windows/otp`. To reuse an older ignored runtime cache, set
`PARVI_OTP_ROOT` to that extracted directory before building. No global Erlang
installation or PATH change is required. Keep `Parvi.exe`, `ebin/`, and `runtime/`
together. The current build is unsigned and retains the full runtime libraries.
Use `.\Apps\Windows\run.ps1` for terminal diagnostics.

After upgrading from the old node-sidebar UI, launch the executable at the new
path above. Backend/model changes require restarting older sessions once.

## Join through a Reception desk

Start the [Reception Desk](../../Services/ReceptionDesk/README.md) with
`.\Services\ReceptionDesk\run.ps1`. Restart the Windows app after upgrading this
backend. In each app enter `ws://127.0.0.1:8765/relay/v1` in **Reception desk URL**
and choose **Use desk (new session)**. This discards the current transient
memberships and creates a fresh relay session. Copy a selected swarm invitation
to the other app's Add swarm field. The desk continues forwarding chat and
membership messages over the open connections.

For internet use, deploy the supplied Render service and enter its public
`wss://.../relay/v1` URL on every device. No port forwarding or direct Erlang
connection is needed. Public deployment and an updated physical-iPhone build
still need verification. Relay mode displays connection observations, and does
not draw fictional direct peer links. See the [protocol](../../docs/RELAY_PROTOCOL.md).
The full browser client is not required.

## Join and select swarms (local development mode)

Launch two instances. In the first, select a swarm and copy **Invitation to this
swarm** using Ctrl+A, Ctrl+C or the native context menu. In the second, paste into
**Add a swarm** and click **Add swarm**. Only one admission is needed. Both nodes
can then chat in that swarm. Their other memberships remain independent.

**New swarm** creates and selects another swarm. Clicking a sidebar row makes it
current without changing any memberships. **Leave swarm** ends only that
membership. Leaving every swarm keeps the node running and shows the empty-state
instructions. The prototype starts with one fresh swarm for convenience.

The Chat composer and history belong to the selected swarm. Drafts survive
selection changes and window rebuilds; acknowledgments clear only the matching
submitted draft. Histories remain in `parvi_swarms`, bounded to 200 messages per
swarm for this session. New members do not receive earlier history.

Invitations use `parvi://swarm/v1?node=...&cookie=...&swarm=...&token=...`.
These legacy local invitations include private Erlang credentials and work only
between trusted Parvi nodes on the same computer. Relay mode instead generates
v2 invitations containing desk/node/mailbox credentials without Erlang cookies. The shared core handles admission, leave and mutual
removal. These strings are different from the legacy node connection strings.
The Reception Desk directory remains a separate service; joining a swarm uses
its member invitation directly.

## Graph and node details

Graph shows only the selected swarm's members and observed distribution links
between them. It uses the attributed native OTP Reltool force graph with the
bundled layout engine; see [third-party notices](THIRD_PARTY.md). Drag nodes to
arrange them. The hidden graph pauses while Chat is selected.

Click a graph vertex or member-list row to see the node identity. For another
member, **Remove both of us** asks for confirmation and invokes the same
swarm-scoped operation as the Apple apps. Other memberships stay intact.

Status lights retain RabbitMQ Management's existing palette, with text labels:
Running (green), Not responding (yellow), Disconnected (red), Checking (grey).
The shared `parvi_network` worker observes OTP connection events and probes the
swarm worker asynchronously. Disconnected does not prove that a VM stopped.
A member can remain in the roster while disconnected. Observations are sampled,
not a globally consistent topology or an audio routing graph.

## Automatic UI reload

Compiling `Apps/Windows/src/parvi_windows.erl` into the running app's `ebin/`
rebuilds its window automatically, normally within a second. Building skips an
unchanged native launcher, so UI-only builds work while the app is open.
Selection, drafts by swarm, selected tab, invitation input and geometry belong to
the supervised model; they survive disposal of the window. Pending actions also
belong to the model, so they complete while a window is being replaced.

There is no rollback. Incomplete BEAM output is ignored; valid code that fails to
start leaves the UI unavailable until a corrected build arrives. Ordinary window
crashes use normal OTP supervision. The backend, model, host, native libraries
and runtime need a deliberate upgrade or restart when their code changes.

## Checks

```powershell
.\Apps\Windows\build.ps1 -Test
python .\Apps\Windows\reload-smoke.py
```

EUnit covers the shared chat/swarm core and Windows model: graph membership
filtering, isolated histories/drafts, delayed acknowledgments, rejected invitations,
and a live node with no swarms. The isolated native-window test checks real peer
membership, scoped graphs, repeated reloads, model/worker continuity, failed-build
recovery without rollback, window-crash recovery and an in-flight swarm send.
It uses private module copies and temporary local nodes.

The legacy transport/directory smoke test remains available via
`python Apps/Windows/smoke.py` after compiling ReceptionDesk with its Windows
launcher (`run-legacy.ps1`). It tests the old bridge compatibility path, not the swarm UI.

## Current scope and runtime provenance

This is native wxErlang in the local BEAM with shared `control/` code. Windows-Mac and Windows-iPhone relay interoperability still requires rebuilt
Apple apps and physical-device testing. There is no audio
engine yet. UI snapshots refresh roughly every 600 ms; this is not an audio
latency claim. Quitting ends the node and all transient memberships.

The official Windows OTP archive is pinned to 29.1.2 with SHA-256
`4efe9772a84c6c1ef75377e9326815584958776c905f2bf687b62509e2d809c0`.
Erlang/OTP is Apache-2.0 licensed; wxWidgets uses the wxWindows Library Licence.
Keep the bundled notices with the runtime when distributing it.
