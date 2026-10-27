# Parvi for Windows — wxErlang exercise

Native Windows controls, using the same `control/` Erlang/OTP application as the
Mac/iOS prototypes. The UI runs in the local BEAM process through wxErlang;
the small C launcher starts the private runtime without a console. There is no
browser, remote backend substitute, or separate chat implementation.

The layout follows the shared SwiftUI app: device sidebar, Swarm chat heading,
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
The build directory is ignored by Git. Close the app before rebuilding.

For terminal diagnostics, run `.\windows\run.ps1`. Each launch creates an
independent named Erlang node with a fresh session cookie. The cookie included in
the connection string is generated inside BEAM, separate from the launch-time cookie.

## Connect two instances

Launch `Parvi.exe` twice. Open **Connect** in each instance. In the first, select
**This instance's connection string** and copy with Ctrl+A, Ctrl+C (or the native
context menu). Paste into **Other instance's connection string** in the second
instance with Ctrl+V, then click **Connect**. The first field is read-only; the
second is editable. Wait for both device
lists to show two participants, then send messages in either direction. Enter
or **Send** submits a message; invalid messages leave the draft intact.

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
```

The smoke test starts its own directory on a temporary loopback port and two real
Windows BEAM nodes. It checks directory registration, peer selection, cookie
authentication, two-way UTF-8 chat, oversized input, and peer departure. It does
not alter the normal desk on port 8765. Core EUnit tests cover worker and `pg`
restart recovery. A GUI send and the connection dialog were checked separately.

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
