# Parvi for iPhone

The app embeds an interpreted OTP 29.1.2 / ERTS 17.1.1 VM inside the iOS
process, reusing the shared Erlang runtime and SwiftUI interface. The current
source adds native OTP distribution over WebRTC, with the same trust and Render
desk connector as Mac. No execution is forwarded to a Mac.

**Current status:** device native dependencies cross-compile and the embedded
host links. Shared iOS Swift compilation/type-checking and resource preparation
pass. This native app has not been fully built, installed or run on a phone.
The previously installed relay build and its physical Mac–iPhone chat proof are
historical; they do not validate the new native transport.

## Prepare and build

Requirements: Xcode/iOS SDK, Python 3.11+, OTP 29.1.2, rebar3, Elixir 1.19,
CMake, make and Rust 1.90+. Compile the pinned upstream dependencies in
`src/control/transport` with Mix first, as described in its
[guide](../../control/transport/README.md). That supplies portable BEAM files and
Unifex-generated C sources; no Mac native binary is copied to the phone.
The scripts use the existing Rust/Elixir caches under `builds/intermediates/tools`.

From the repository root:

```sh
python3 src/Apps/iOS/prepare-runtime.py --target device
```

Preparation downloads/checks the pinned Mob OTP archive, compiles the shared
Erlang sources and cross-builds the static transport dependencies. The first
native preparation also downloads OpenSSL 3.5.9, SRTP 2.7.0 and Rust crates.
OpenSSL's source checksum is checked against its published SHA-256. The separate
iOS Cargo manifest/lock uses upstream Rustler 0.37.0 for static NIF entry points,
with the unmodified ExSCTP implementation and sctp-proto 0.3.0. The desktop's
Rustler dependency remains unchanged.

All generated resources, archives, objects and toolchain caches stay under
`builds/`. Device and simulator outputs are separate. For a simulator preparation,
use `--target sim`; its new native path has not been compiled in this increment.

Open `src/Apps/iOS/Parvi.xcodeproj`, select **Parvi** and your connected iPhone, then
Run with the existing Personal Team signing configuration. Developer Mode and
Apple's developer-profile trust are still required. Keep the app in the foreground
and allow the local-network permission for direct peer connections.

For an unsigned full compilation when wanted:

```sh
bash src/Apps/iOS/build.sh device
# Or: bash src/Apps/iOS/build.sh sim
```

Full app builds and installation are separate from runtime preparation. The app
build script does not deploy to a device. Re-run preparation after changing
Erlang/native source; a preparation stamp makes Xcode recopy runtime resources.
Swift-only edits compile normally in Xcode.

## Native invitation and chat path

Use a rebuilt native Mac and native iPhone. Create a cluster using **New swarm**
on one node, wait for **Reception desk connected**, then copy its invitation to
**Add swarm** on the other. A submitted invitation is not a completed connection;
wait until both nodes appear before sending. The existing swarm view represents
one **Native cluster** per app session.

The shared default desk is `wss://parvi-reception-desk.onrender.com/relay/v1`.
It introduces peers; native messages and admission proofs use the encrypted
WebRTC DataChannel. Native invitations grant whole-VM trust. **Remove both of
us** revokes cluster-wide access, rather than one logical swarm. These links are
incompatible with the older relay invitations used by current Windows and
previously installed Apple apps.

One native cluster per session is implemented. Voluntary leave, switching,
automatic reconnect, a connection mesh, authority recovery and background
operation remain incomplete. Force-quit and reopen to retry a failed join or
start a different cluster. Quitting disconnects but does not revoke the remote
membership. History is local, transient and best effort; no replay is added.

## Embedded host

`parvi_beam.c` registers static DTLS, SRTP, SCTP and CRC NIF entry points alongside
OTP's static NIFs. C NIF globals are namespaced at compilation to preserve the
isolation that separate shared objects provide on Mac. Rustler's runtime symbol
lookup is supported by exporting the OTP NIF API from the linked executable.

`parvi_ios` adds resource code paths, starts a fresh named node with the WebRTC
carrier, then starts the shared native profile and desk connector. EPMD and
automatic transitive connections are disabled. DNS uses OTP's in-process
`net:getaddrinfo` adapter for the desk and configured STUN/TURN hostnames; iOS
cannot spawn the desktop `inet_gethost` helper. TLS verification uses public
build-host trust anchors exported to `cacerts.pem`.

The loopback socket is only the UI/BEAM bridge inside the same phone. Networking,
admission and chat remain in BEAM. The VM starts once per process and iOS may
suspend the entire process in the background.

Normal startup writes a `status=running` receipt to Documents/
`parvi_runtime_proof.json`; this is not a passing connection or supervision test.
The earlier destructive runtime probe is opt-in with `PARVI_RUNTIME_PROBE=1` in
Xcode's launch environment. `parvi_connection_status.json` records actual snapshot
status, native node/peer names and OS PID, without invitation secrets or chat.
Startup failures can leave `parvi_erl_crash.dump` for diagnosis.

## Earlier relay path

The earlier runtime is retained explicitly, without the new static dependencies:

```sh
python3 src/Apps/iOS/prepare-runtime.py --target device --transport relay
bash src/Apps/iOS/build.sh device relay
```

For a direct Xcode build of that prepared path, set the `PARVI_TRANSPORT` build
setting to `relay`. It uses separate resources under `Resources-relay-device`.
The default build setting is `native`. Relay mode retains the earlier multi-swarm
behavior; it cannot join a native cluster.

See [provenance](THIRD_PARTY.md), [plan](../../../docs/PLAN.md) and
[progress](../../../docs/PROGRESS.md) for versions and validation limits.
