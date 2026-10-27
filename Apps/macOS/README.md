# Parvi for macOS

Native SwiftUI interface for one Erlang node participating in multiple independent
swarms. Each swarm has its own membership, invitations, chat history and graph.
Audio remains future work.

## Build and launch

Requirements: Apple Silicon Mac, macOS SDK/Swift command-line tools, Erlang/OTP
29.1.2 and rebar3 3.27.3. Built on macOS 27.0.1 with Swift 6.4; deployment target
macOS 14. Earlier releases and Intel builds remain unverified.

```sh
bash Apps/macOS/build.sh
open builds/macOS/Parvi.app
# Optional second instance:
open -n builds/macOS/Parvi.app
```

The app bundles ERTS, OTP resources, and the OpenSSL library used by OTP crypto.
Erlang and Homebrew are build dependencies. Copies of OTP/OpenSSL licenses are
included, and modified native libraries are signed before the enclosing bundle.
This local build is ad hoc signed, not notarized for public distribution.

## Swarms

Each runtime starts with a fresh node identity and a new swarm of one. The swarm
list shows every current membership. **New swarm** creates another independent
swarm; pasting an invitation and clicking **Add swarm** joins another without
leaving existing memberships. Re-adding a current swarm selects it.

Select a swarm to see its read-only invitation string and **Copy** button.
That invitation belongs to the selected swarm, rather than to the whole node.
The two tabs show that swarm's **Chat** and **Graph**. Wide windows keep the swarm
list beside the selected swarm; narrow windows navigate between list and detail.
The shared iPhone layout supports horizontal page swipes between Chat and Graph.
There is no placeholder Settings tab.

Chat drafts are separate for each swarm. A reply for one swarm cannot clear a
draft in another. Rejected sends retain their text; successful sends clear only
the submitted draft. Send with the arrow, Return or Command–Return. Each local
swarm history retains up to 200 messages in arrival order. New participants do
not download earlier history. There is no durable storage or delivery guarantee.

The graph contains only that swarm's members and observed links between them.
It is not an audio-routing graph. Node health checks the shared swarm worker;
green means responsive, yellow not responding, red disconnected and grey checking.
A disconnected member is not proof of a dead VM. The list alternative and node
details expose the same state. Dragging adjusts the local display only.

**Leave swarm** ends just this membership. Selecting another device in the Graph
and choosing **Remove both of us** asks for confirmation, then ends both memberships
in this swarm and revokes their admission invitations. Other memberships and
existing members admitted through those invitations remain intact. An active
issuer automatically gets a new link when its old invitation is revoked.
A returning participant needs a fresh valid invitation. Invitations issued by a
member who leaves/removes itself also stop admitting new nodes. Remaining members
can invite others even after the original creator has left.

## Current transport and membership limits

This is a **trusted, same-computer prototype**. The new format is
`parvi://swarm/v1?node=...&cookie=...&swarm=...&token=...`. Links contain private
Erlang distribution credentials and a swarm-specific admission token. They work
only with the new swarm-aware interface; the older Windows UI still uses the
legacy single chat group and connection-string format.

Admission checks the issuing member's current local state. Membership changes
are propagated to connected participants. Temporary session-removal and revoked
invitation records prevent reuse during this runtime; there is no permanent
person/device blacklist. Voluntary leave does not revoke the invitation used to
admit that member. Membership records may retain disconnected peers for diagnosis.

This is not a hardened security boundary: Erlang distribution still grants broad
runtime trust, and a modified trusted peer can bypass application-level checks.
Partition reconciliation, reliable revocation during network splits, simultaneous
removal arbitration, configured invitation expiry, internet relays, LAN access,
large-swarm scaling and persistent reconnection remain future protocol work.
The prototype exchanges local peer credentials to establish distribution links;
it does not define the eventual internet topology. Do not expose it publicly.

Quitting stops the node and all its memberships. Closing a window follows normal
Mac app behavior. EPMD may remain running. SwiftUI hot reload is not implemented.

## Validation

```sh
(cd control && rebar3 eunit)
bash Apps/macOS/build.sh
python3 Apps/macOS/tools/smoke.py
python3 Apps/macOS/tools/swarm-smoke.py
bash Apps/macOS/test.sh
```

The three-node integration test uses bundled runtimes and verifies overlapping
swarms, isolated chat, member-only sending, scoped mutual removal, invitation
revocation/replacement, fresh re-admission, and operation after the creator leaves.
The legacy two-node bridge test also remains available. Integration tests need
permission to open localhost sockets. Swift model tests cover per-swarm drafts,
scoped graphs/invitations, delayed acknowledgements and failure handling.

The app bundle is written to `builds/macOS/Parvi.app`. Swift modules, test
products, OTP release staging and compiler caches are under `builds/intermediates/`.
The test helper selects full Xcode for its command and places SwiftPM output there
as well; it does not change the system's selected developer tools.

SwiftUI and its model live in `Apps/Shared/ParviKit`. `MacErlangRuntime` owns BEAM and
private JSON pipes. `parvi_swarms` owns memberships and histories; `parvi_network`
observes runtime health and topology. The old `parvi_chat` API remains for Windows
and existing tests. Rebuild iOS resources after changing Erlang sources; crypto
resources are now included for its statically linked crypto NIF.
