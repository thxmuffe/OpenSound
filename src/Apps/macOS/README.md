# Parvi for macOS

Native SwiftUI host for a BEAM node. The current source integrates native OTP
distribution over WebRTC, invitation-based whole-VM trust and introductions
through the single global Render Reception Desk. Audio remains future work.

## Build and launch

Requirements: Apple Silicon Mac, macOS SDK/Swift command-line tools, Erlang/OTP
29.1.2, rebar3 and Elixir 1.19. The build uses the existing pinned Elixir cache
under `builds/intermediates/tools/elixir` when Mix is not on PATH. Building the
upstream transport dependencies also needs Rust, pkg-config and OpenSSL, as
explained in [the transport guide](../../control/transport/README.md).

```sh
bash src/Apps/macOS/build.sh
open builds/macOS/Parvi.app
# Optional second instance:
open -n builds/macOS/Parvi.app
```

The build bundles ERTS, OTP resources (including the compiler needed by Elixir),
the pinned transport libraries and Elixir support modules. `package-native.py`
copies runtime resources without build-cache symlinks, relocates native library
links and signs the Mach-O libraries. Dependency licenses are copied into the
bundle. The enclosing app is ad hoc signed for local development.

## Current native path

Start two rebuilt Mac instances. In the first, choose **New swarm**; its existing
chat view represents the single **Native cluster**. Once the desk connects, copy
its invitation into **Add swarm** in the second instance. Admission and OTP
connection happen asynchronously: the submission notice does not confirm a
connection. Wait for the other Mac to appear before sending chat.

The default desk is `wss://parvi-reception-desk.onrender.com/relay/v1`, from
`src/control/src/parvi.app.src`. The desk carries SDP/ICE introductions. Admission
proofs, cookies and native OTP packets use the encrypted WebRTC DataChannel.
Swift submits commands and displays snapshots; networking stays in BEAM.

This increment supports **one native cluster per app session**, displayed through
the existing swarm UI. Additional independent swarms and switching clusters are
not implemented in this path. Restart the app to create/join another cluster or
retry a failed join. Desk switching is not implemented in the native bridge.
Native `parvi://cluster/v2` invitations grant whole-VM trust. iPhone source now
has matching native packaging/startup; its new app has not been built or run.
Previously installed iPhone apps and current Windows builds use the earlier,
incompatible relay invitations.

Chat reuses `parvi_chat` and its `pg` scope, with local transient history of up
to 200 messages and best-effort sends. No history download or replay is added.
The shared UI receives OTP-observed chat processes and local native connections;
no custom gossip, node-health polling or topology worker runs in this profile.

**Remove both of us** uses cluster-wide revocation, including issued and entry
invitations. It is not scoped to one logical swarm. Incomplete remote removal
is reported as unconfirmed. **Voluntary leave is not implemented**; the action
reports that limitation. Quitting disconnects the VM but does not revoke its
membership at surviving nodes. Suspension, reconnect, connection mesh and
admission-authority recovery remain future increments.

## Implementation and validation

The Mac host selects `runtime_profile=native_cluster`, `native_desk=true`, and
`-proto_dist parvi_webrtc`, with EPMD and automatic transitive connections disabled.
`parvi_sup` supervises the shared `pg` scope, chat worker and desk connector.
The connector owns its relay client, trust worker and channel lifecycle.
A chat/scope restart restarts the connector too and discards its session trust;
transparent recovery has not been implemented.

The carrier, trust and connector modules now live in `src/control/src/`. Probe drivers
remain under `src/control/transport/experiments/otp_dist`. The earlier relay runtime
remains available to iPhone, Windows and legacy helpers; the existing Mac smoke
helpers exercise that older path and do not validate this new Mac integration.

Validation for this increment is recorded in [progress](../../../docs/PROGRESS.md).
Compilation, dependency packaging and Swift type-checking do not prove a working
Mac-to-Mac connection. No new tests or Render service changes are part of this
increment. The app bundle is generated under `builds/macOS/Parvi.app`; a previously
built or installed app retains its older behavior until rebuilt.
