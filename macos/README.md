# Parvi for macOS

Native SwiftUI chat window backed by a real, bundled Erlang/OTP runtime. This is
the first local Mac app, before iPhone embedding or LAN onboarding.

## Build and launch

Requirements: Apple Silicon Mac, matching macOS SDK/Swift command-line tools,
Erlang/OTP 29.1.2 and rebar3 3.27.3. Built and tested on macOS 27.0.1 with Swift
6.4 command-line tools. Earlier macOS releases and Intel builds are unverified.

From the repository root:

```sh
bash macos/build.sh
open macos/build/Parvi.app
```

Or double-click `macos/build/Parvi.app` in Finder. The app contains its own ERTS,
kernel, stdlib and Parvi code: Erlang/Homebrew are needed to build, not to launch
the resulting bundle. No full Xcode project or paid signing account is required
for this local Mac build. The script applies an ad hoc signature; the bundle is
not notarized or prepared for public distribution.

The sidebar shows whether Erlang is running and which chat peers are visible.
Type in the message box and click the arrow or press Command–Return. The UI
shows the latest 200 messages. History belongs to the Erlang worker and is lost
when it restarts or the app quits. Quitting the app stops its runtime. Closing
the window alone follows normal Mac app behavior; use Parvi → Quit Parvi to end
the session.

## Connect two app instances

Launch a second process:

```sh
open -n macos/build/Parvi.app
```

In the second instance, click **Connect**, then **Copy node** and **Copy cookie**.
Paste those values into the first instance's Connect form and click **Connect**.
Copy/paste one field at a time since the clipboard holds one value. After group
membership converges, each sidebar lists the other instance. Messages then flow
both ways. Each launch generates a new cookie and node identity; reconnect after
relaunching. Cookies grant trusted Erlang access: share them only with your own
test instance.

This build binds distribution to loopback and accepts only other native Parvi
node names on this Mac. It does not yet connect to another computer, an iPhone,
or a browser. No broker, QR enrollment, persistent identity or public networking
is implemented. EPMD, Erlang's local name service, may remain running after quit.
If EPMD was already running, its existing interface configuration is unchanged.

## Validation

```sh
cd control
rebar3 eunit
cd ..
python3 macos/tools/smoke.py
```

The smoke test launches the **bundled** runtime twice, tests the line-delimited
JSON bridge used by SwiftUI, UTF-8, rejected empty messages, two-way group chat
and peer departure. Its sockets require local network permission in sandboxed
development environments.

## Implementation

SwiftUI owns presentation; `ChatModel` receives runtime snapshots through
`ChatRuntime`. The UI and model now live in the shared
`ParviKit` package; `MacErlangRuntime` owns the subprocess and its private
stdin/stdout pipes. `parvi_bridge` adapts requests to the OTP actor API. Chat
state and peer membership remain in Erlang. The iPhone project reuses ParviKit
but still needs an embedded runtime; the Mac launcher does not establish iOS
embedding feasibility.

The bundle copies the repository Apache-2.0 license. OTP components retain their
own licensing and bundled notices. No third-party UI packages are used.
