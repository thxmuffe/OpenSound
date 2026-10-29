# Parvi chat: first prototype step

A small Erlang/OTP application; no audio or iPhone runtime is implemented yet.
Tested on Apple Silicon macOS with OTP 29.1.2 and rebar3 3.27.3. No third-party
Erlang dependencies. Use those tool versions to reproduce this baseline; other
OTP versions have not been validated.

## Build and test

Compiler output is under `builds/intermediates/control/` at the repository root.
The local `rebar.config` selects this location automatically. Root-level
`rebar3 eunit` checks both this application and `Services/ReceptionDesk/`, with its own shared
workspace cache under `builds/intermediates/erlang/`.

```sh
brew install erlang rebar3
cd control
rebar3 compile
rebar3 eunit
escript tools/smoke.escript
```

Run from the repository root before `cd control`. The smoke test launches real
BEAM processes on loopback, uses an ephemeral cookie, and stops its peer processes
on completion. It does not need a phone or an EPMD daemon. It checks two-way
delivery, worker restart, node departure, rejoin, and delivery after rejoin.
Socket access must be allowed by the environment. The test harness uses an
internal OTP EPMD registration query; this detail may need updating with OTP.

## Try it in two terminals

From `control/`, start terminal A:

```sh
ERL_EPMD_ADDRESS=127.0.0.1 rebar3 shell --name parvi_a@127.0.0.1 --setcookie local_parvi_demo
```

From `control/`, start terminal B:

```sh
ERL_EPMD_ADDRESS=127.0.0.1 rebar3 shell --name parvi_b@127.0.0.1 --setcookie local_parvi_demo
```

In terminal A:

```erlang
parvi:connect('parvi_b@127.0.0.1').
parvi:status().
parvi:send(<<"Hello from A!">>).
```

Group membership converges asynchronously. Wait until `parvi:status()` lists
both nodes in `chat_nodes` before sending. In terminal B:

```erlang
parvi:history().
parvi:send(<<"Hello back from B!">>).
```

Back in A, `parvi:history().` shows the reply. To observe UI events, use
`parvi:subscribe().`, send from B, then `flush().` in A; events have the form
`{parvi_message, MessageMap}`. Stop each shell with `q().`.

The shell is the initial interface; automatic chat rendering is deferred.
`rebar3 shell` without name/cookie also works for a single local session.

## Process structure and semantics

```text
parvi_app -> parvi_sup (rest_for_one)
                +-- parvi_pg (OTP pg scope)
                +-- parvi_chat (gen_server)
                +-- parvi_discovery (local HTTP directory client)
```

`parvi` is the UI boundary: send, history, status, subscribe/unsubscribe and manual
connect/disconnect. The worker publishes directly to members of one versioned
`pg` chat group. Messages do not pass through the optional discovery directory.
Starting more named nodes with the same
application and cookie allows additional participants; three-device operation
has not been tested. `connected_nodes` reports Erlang connections, while
`chat_nodes` reports devices whose chat workers have joined the group. These
are runtime node identities, not persistent device identities.

Messages are maps containing `version`, `id`, `sender`, `text`, `sent_at_ms`.
Text must be a valid UTF-8 binary, 1–4096 bytes. Each worker retains its latest
200 messages in arrival order. The timestamp is diagnostic wall-clock time,
not a synchronized timeline. This Erlang term format is an internal experiment,
not the future public audio/control protocol.

Delivery is best effort to currently visible members. A successful send confirms
local acceptance, not remote receipt. There are no acknowledgements, offline
delivery, replay, deduplication, durable history, or cross-sender ordering.
The history limit does not bound the process mailbox under overload.

OTP restarts a failed worker; its history is lost. Local UI subscriptions live
in `pg`, so they survive a chat-worker restart and disappear when the observer
process exits. If `pg` fails, the supervisor restarts chat too so it rejoins;
observers must resubscribe after that scope restart. Disconnected nodes disappear after
Erlang/`pg` detects them. Reconnection is manual; prior history is not merged.

## Native cluster foundation (opt-in)

`parvi:start(native_cluster)` starts only the existing `parvi_pg` and
`parvi_chat` workers under the standard supervisor. It must be called before
the application starts. The default `parvi:start()` keeps the current apps'
compatibility workers. The selected profile is application configuration and
persists across application stops; unset `runtime_profile` to return to the
default before restarting.

The native profile uses OTP process groups and remote `gen_server` casts for
chat. It does not start swarm gossip, application relay/direct routing,
discovery or topology polling. OTP connection/process liveness is separate from
the invitation policy's permission to reconnect. Group membership converges
asynchronously; there is no additional application membership registry.

The isolated [WebRTC distribution experiment](transport/experiments/otp_dist/README.md)
now runs this same core and verifies chat, observers, supervision and revocation
across independent VMs. The profile does not itself introduce peers, establish
WebRTC channels or build a connection mesh. Those remain carrier/admission and
step-3 recovery work. The Mac source now enables `native_desk=true` alongside
this profile: `parvi_sup` then also supervises `parvi_cluster_desk`, which owns
the trust worker, relay client and WebRTC channels. The native JSON bridge
adapts this single cluster to the existing chat UI. iPhone and Windows retain
their earlier runtime profile. See [Mac usage](../Apps/macOS/README.md) for the
integration's current limitations. UI/source naming cleanup remains deferred.

## Network scope

The supplied shell config binds distribution to loopback. The demo cookie is
only for this local demonstration. `ERL_EPMD_ADDRESS` affects a newly started
EPMD daemon; it cannot change an already running daemon's interfaces. EPMD may
remain running after the shells exit.

Before a future LAN test, explicitly configure a private LAN interface, matching
reachable node names and a fresh shared secret. Use only trusted devices on an
isolated private network. Standard Erlang distribution grants cluster-wide trust
and this prototype does not add TLS, enrollment, authorization or abuse limits.
Do not expose its ports to the internet. The public device interface remains a
separate future design.

See [the iOS investigation](../docs/decisions/0001-chat-first-and-ios-feasibility.md)
and [progress log](../docs/PROGRESS.md) for the next hardware gate.


## Reception Desk transport

`parvi_relay` now provides an outbound Gun WebSocket adapter with authenticated
binary node identities, scoped mailboxes, verified WSS and reconnect. The shared
OTP settings in `src/parvi.app.src` provide `default_reception_desk_url`, bundled
with every native app. Override with `PARVI_RECEPTION_DESK_URL` at startup (an
empty value selects local-only transport), or issue bridge `configure_desk` with `url`
to explicitly start a fresh session. Swarm v2 invitations route through that desk;
local v1 invitations remain the separate developer transport.

`parvi_swarm_wire` defines the validated JSON schema. `parvi_swarms` owns admission,
membership, bounded histories and revocation for either transport. Its relay
admission path is asynchronous. `parvi_network` reports relay connection presence
without inventing direct distribution edges. The desk never receives Erlang
cookies or executable terms. See [protocol](../docs/RELAY_PROTOCOL.md) and
[launch/deployment guide](../Services/ReceptionDesk/README.md).
