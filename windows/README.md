# Parvi for Windows — wxErlang exercise

Native Windows controls, using the same `control/` Erlang/OTP application as the
Mac/iOS prototypes. The UI runs in the local BEAM process through wxErlang;
the small C launcher starts the private runtime without a console. There is no
browser, remote backend substitute, or separate chat implementation.

The layout follows the shared SwiftUI app: node sidebar, Swarm chat heading,
conversation, composer, and a connection dialog with Reception desk discovery.
History stays in the existing bounded, transient chat worker (200 messages).

## Build and launch

Requires Windows x64, PowerShell, and Visual Studio's **Desktop development with
C++** workload. From the repository root:

```powershell
.\windows\setup.ps1
.\windows\build.ps1 -Test
.\windows\_build\Parvi\Parvi.exe
```

Setup downloads the official OTP 29.1.2 Windows ZIP and checks its pinned SHA-256.
It extracts under `windows/_build/otp`; it does not install Erlang, edit PATH,
or change machine settings. `PARVI_OTP_ROOT` can point to another extracted
Windows OTP 29.1.2 distribution with wx support.

The resulting `_build/Parvi/` folder contains `Parvi.exe`, `ebin/`, and `runtime/`.
Keep these together. This first exercise retains the full runtime libraries;
package-size reduction and a signed installer are later work. Windows may need
the Microsoft Visual C++ runtime required by the official OTP distribution.
The build directory is ignored by Git. UI builds can run while the app is open;
close the app when changing the native C launcher itself.

For terminal diagnostics, run `.\windows\run.ps1`. Each launch creates an
independent named Erlang node with a fresh session cookie. The cookie included in
the connection string is generated inside BEAM, separate from the launch-time cookie.

## Connect two instances

Launch `Parvi.exe` twice. Open **Connect** in each instance. In the first, select
**This instance's connection string** and copy with Ctrl+A, Ctrl+C (or the native
context menu). Paste into **Other instance's connection string** in the second
instance with Ctrl+V, then click **Connect**. The first field is read-only; the
second is editable. Wait for both node
lists to show two nodes, then send messages in either direction. Enter
or **Send** submits a message; invalid messages leave the draft intact.

Click a node in the **Nodes** sidebar to copy its connection string. For a remote
node, Parvi requests that node's own string over the existing trusted Erlang
connection. Both nodes must include the shared connection-string operation.
Discovery-only names do not contain credentials and cannot be copied
as complete connection strings.

## Node status lights

The native Nodes list uses RabbitMQ Management v3.13.7's existing
[green/yellow/red/grey status palette](https://github.com/rabbitmq/rabbitmq-server/blob/v3.13.7/deps/rabbitmq_management/priv/www/css/main.css).
Every light also has a text label:

| Light | Label | Observation |
| --- | --- | --- |
| Green | Running | The node's Parvi chat worker answered its status call. |
| Yellow | Not responding | Distribution may still be connected, but the worker timed out or is unavailable. |
| Red | Disconnected | OTP reported `nodedown`; this does not prove the remote VM stopped. |
| Grey | Checking | A connection is known but its first worker check has not completed. |

`net_kernel:monitor_nodes/2` supplies connection events and disconnect reasons.
A supervised status worker checks connected chat workers every two seconds with
a 1.5-second timeout, separately from the UI. It does not declare a remote node
dead or shorten OTP's distribution heartbeat timeout. Network failure detection
can therefore take longer than a worker responsiveness check.

Disconnected nodes remain visible for the session and their status survives UI
reload. Reconnection returns them to Checking/Running. Clicking a disconnected
row reports that its connection string cannot currently be fetched. The worker
is installed under the running Windows supervisor during UI reload, so this UI
update does not require restarting existing apps.

## Automatic UI reload during development

Restart existing instances once to activate the reload host. After that, compiling
`windows/src/parvi_windows.erl` into the app's `ebin/` directory automatically
rebuilds each running window, normally within about a second. Use
`.\windows\build.ps1` while the app is running; the script skips rebuilding an
unchanged native launcher. There is no need to reconnect or recopy connection
strings for a UI edit.

The Windows supervisor owns a model process, a reload watcher, a disposable wx
window, and a node-status worker. The model stores current drafts, window geometry,
and connection-dialog fields as edits happen. It also dispatches requests so an
in-flight send survives destruction of the window. Chat history stays exclusively
in the existing chat worker; windows read fresh snapshots instead of restoring
old chat data. The Erlang node, cookie, and peer connections remain alive. The
window may briefly flicker when recreated.

Incomplete compiler output is ignored. There is **no rollback** and no saved old
UI binary. If new UI code fails to initialize, the window remains unavailable
until a corrected build arrives; the model and backend continue running. A window
that crashes during normal operation is restarted by its OTP supervisor using
the current code. Repeated crashes escalate through normal supervisor restart
limits. Closing the current window normally still ends the app.

This watches the Windows UI module only. Changes to the host, shared backend,
native libraries, or runtime still require a deliberate upgrade or restart.
For an explicit rebuild from an Erlang debugging connection, call
`parvi_windows_host:reload/0`.

The versioned format is `parvi://connect/v1?node=...&cookie=...`, with URI-encoded
values. The string contains private credentials; it is not encryption or a public
web link. It expires when the originating app closes.
The shared parser rejects invalid, duplicate, missing, and oversized fields;
the existing bridge still enforces loopback-only peer names. The Mac app's legacy
two-field request remains supported internally.

Optional discovery:

```powershell
.\broker\run.ps1
```

Open `http://127.0.0.1:8765/` for the existing Reception desk website. Register
both apps with **Register / Find nodes** and refresh to see known names. Ask
the desired instance for its connection string. Discovery does not authenticate or
connect nodes and never carries chat traffic. Restarting the desk clears names.
The PowerShell launcher supports the same `PARVI_BROKER_BIND` and
`PARVI_BROKER_PORT` environment variables as the existing shell script.

## Checks

```powershell
.\windows\build.ps1 -Test
# Run broker/run.ps1 once to compile it, then stop it if desired.
python .\windows\smoke.py
python .\windows\reload-smoke.py
```

The smoke test starts its own directory on a temporary loopback port and two real
Windows BEAM nodes. It checks directory registration, peer selection, cookie
authentication, two-way UTF-8 chat, oversized input, and peer departure. It does
not alter the normal desk on port 8765. Core EUnit tests cover worker and `pg`
restart recovery. A GUI send and the connection dialog were checked separately.

The native-window reload test uses an isolated copy of the app modules. It checks
repeated automatic reloads, retained model data, unchanged node/cookie/chat workers,
continued messaging while UI code is broken, corrected-build recovery, supervised
window-crash recovery, and sends that survive window replacement.

## Current scope

Connections remain loopback-only, matching the Mac prototype's existing policy.
The shared bridge now accepts both `parvi_mac_<digits>` and
`parvi_windows_<digits>` local names. It rejects LAN hosts. This does not prove
Windows–Mac or Windows–iPhone networking. The iOS prototype remains foreground,
local-only, with its physical-device runtime test still pending in the progress
log. There is no audio engine in this milestone.

Polling the shared snapshot every 600 ms provides chat/member updates without
blocking the wx event loop. This is a UI refresh interval, not an audio-latency
claim. Worker restarts are recovered by the existing OTP supervisor; the next
snapshot shows the worker's new session history. Closing the app ends its node.
OTP's local EPMD helper can remain running after all app instances close.

## Runtime provenance

Official archive:
https://github.com/erlang/otp/releases/download/OTP-29.1.2/otp_win64_29.1.2.zip

SHA-256 recorded from the downloaded archive:
`4efe9772a84c6c1ef75377e9326815584958776c905f2bf687b62509e2d809c0`.

Erlang/OTP is Apache-2.0 licensed; wxWidgets uses the wxWindows Library Licence
(LGPL with an exception). Keep upstream notices when preparing a distributable
package. This local build is unsigned. See the upstream
[OTP source and license](https://github.com/erlang/otp/tree/OTP-29.1.2) and
[wxWidgets license](https://www.wxwidgets.org/about/licence/).
