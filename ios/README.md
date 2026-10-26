# Parvi iPhone project

Open `ios/Parvi.xcodeproj` in Xcode and choose the **Parvi** scheme. It uses the
local `shared/ParviKit` Swift package; no downloaded Swift dependencies are needed.

**Status: the native app shell and shared UI build for iOS arm64. Embedded
Erlang is not linked yet, so this is not a working iPhone chat app.** The UI
reports that state and disables sending/connecting. It does not simulate Erlang
or proxy execution to the Mac.

## What is shared

- `control/`: Erlang/OTP application, supervision, chat and membership logic.
- `parvi_bridge:request/1`: JSON requests/responses independent of terminal I/O.
- `shared/ParviKit`: message types, observable chat state, validation and SwiftUI
  chat screen used by both native apps.

Only runtime hosting and app lifecycle belong in the platform app. The Mac
adapter launches the bundled runtime as a process. `IOSErlangRuntime` is the
explicit unavailable adapter to replace with an in-process iOS BEAM integration.
Clipboard and adaptive colors/layout have small platform conditionals in ParviKit.
There is no duplicate iPhone chat implementation.

## Compile without a phone or signing

From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project ios/Parvi.xcodeproj -scheme Parvi \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

This verifies native iOS code and the shared package compile for a device. It
does not install the app, run it on a physical device, or establish runtime
feasibility. Minimum iOS target is 17.0; SDK used for validation is 27.1.

For eventual device installation, select your development team in Signing &
Capabilities, use your own bundle identifier if needed, and choose your connected
iPhone as the run destination. No team ID or credentials are committed. The
current unsigned output cannot be installed directly.

## Next gate: real BEAM inside the app

1. Pin and review an iOS full-OTP runtime candidate, its licenses and arm64 build.
   See [the feasibility investigation](../docs/decisions/0001-chat-first-and-ios-feasibility.md).
2. Add the runtime library and its OTP resources to the iOS target. Compile the
   shared Erlang modules with a compiler compatible with that embedded version.
   The current bridge uses OTP's `json` module (OTP 27+); older embedded runtimes
   need an explicit compatibility decision rather than silently dropping logic.
3. Replace `IOSErlangRuntime` with a native host that starts BEAM in-process,
   invokes `parvi_bridge:request/1`, and returns its JSON through `ChatRuntime`.
   The desktop subprocess launcher must not be copied into iOS.
4. Prove local Erlang worker execution and supervision on a physical iPhone.
   Then add foreground LAN transport and the required local-network permission.
   The current bridge's connection command is still restricted to Mac loopback
   node names and must be redesigned explicitly for phone networking.

No broker or QR flow is required to validate this runtime gate. Add onboarding
after device execution and a manual Mac–iPhone connection work.
