# Native OTP distribution over WebRTC experiment

Steps 1 and 2 of the trusted-cluster plan: independent OTP **29.1.2 / ERTS 17.1.1**
VMs use a reliable, ordered binary WebRTC DataChannel as their native Erlang
distribution carrier. This is isolated experimental code, not app integration.

## Run

First build the existing pinned WebRTC dependencies using the instructions in
[the transport README](../../README.md). Then run from the repository root:

```sh
python3 control/transport/tools/otp-dist-smoke.py
python3 control/transport/tools/otp-trust-smoke.py
```

The script compiles only these experimental modules with warnings as errors,
under `builds/intermediates/OTPWebRTCProbe`. It checks the installed OTP version.
It uses the same local Elixir library paths and Mac OpenSSL 3 search path as the
existing direct-transport experiment. Per-VM logs are in that build directory.
It does not launch, install or modify any Parvi app or Reception Desk.

## Responsibilities

- `parvi_webrtc_dist`: OTP carrier callbacks and bindings for pre-established
  channels. Reuses `dist_util` for cookie handshakes, negotiated distribution
  flags, connection supervision and ticks. A logical listener accepts channels;
  it opens no TCP distribution listener and does not register with EPMD.
- `parvi_dist_channel`: the process registered with ERTS as distribution
  controller. It passes opaque packets between `dist_ctrl_get_data/1`,
  `dist_ctrl_put_data/2` and the third-party `ex_webrtc`/`ex_sctp` libraries.
  Native terms, PIDs, atom caches, remote spawn, RPC and monitors are handled by
  OTP, not decoded or reimplemented here. Typed length framing separates admission
  control envelopes from native packets; 16 KiB chunks allow a native packet to
  span several SCTP messages. Native frames are rejected before their bodies
  arrive unless the connection has been authorized.
- `parvi_dist_probe` and `otp-dist-smoke.py`: test orchestration. The parent
  passes only SDP/ICE introductions between app-owned stdin/stdout pipes. It
  stops forwarding those signals before the native handshake starts. Test
  command results contain assertions/metadata, not the native payload stream.

Only this carrier is selected with `-proto_dist parvi_webrtc`; EPMD startup is
disabled. Automatic transitive connections are disabled. The step-1 test
explicitly configures a local fixture admission policy and provisions its cookie.
The carrier's default is now `parvi_cluster_trust`: missing policy, missing trust
manager, unknown controller or mismatched peer name denies native distribution.
The step-2 test does not provision shared cookies through its parent process.

## Invitation admission and cluster removal

Each VM's `parvi_cluster_trust` worker generates an in-memory Ed25519 key pair.
There is no account, permanent device identity, certificate issuer service or
shared cluster cookie. The new experimental invitation is explicitly a grant of
whole-VM cluster trust:

```text
parvi://cluster/v1?v=1&cluster=ID&issuer=PUBLIC_KEY&node=NAME&invite=ID&secret=SECRET&expires=TIME
```

The actual URI uses standard percent encoding. It contains an expiring bearer
capability and the inviter's public-key pin, never an Erlang cookie. Invitations
default to 72 hours in the probe; the authority accepts TTLs up to seven days.
Both endpoint parsing and the authority's stored expiry are checked. Changing
the URL expiry does not extend the capability.

Admission takes place over the established encrypted DataChannel, before OTP:

1. The inviter signs a fresh challenge using OTP `crypto` Ed25519. It includes a
   binding to the actual local/remote DTLS certificate fingerprints, obtained
   through the existing SDP library. The recipient verifies the pinned key.
2. The joiner signs its ephemeral public key, native node name, invitation
   capability, fresh nonce and the challenge/binding. The inviter verifies key
   possession and asks the admission actor to validate the live invitation.
3. The inviter returns a signed, nonce-bound grant and fresh pairwise OTP cookie
   inside DTLS. Both endpoints install the connection grant. The carrier checks
   it before setup, incoming acceptance, node-up and activation; the inbound OTP
   handshake permits exactly the authenticated native node name.

The Python introducer forwards only SDP/ICE and user invitations. Proofs and
cookies do not go through it. Reconnect as an existing member still requires a
fresh signed, channel-bound exchange and current membership validation. Restored
old cookies or OTP allow-list entries alone cannot enable a new connection.
OTP's cookie list is not a revocation mechanism; the explicit carrier gate is.

`parvi_cluster_authority` is a serialized OTP actor inside the cluster, not a
public Reception Desk or a permanently assigned machine. Any active node can
request invitations. The authority stores hashes of live capabilities and the
current membership snapshot. On removal of its own host, it transfers the policy
and retained capability records to a survivor, which completes publication.

The user selected **cluster-wide remove both**. The caller and target lose native
access to all honest surviving nodes, including access associated with other
logical swarms in this cluster. Their issued invitations and the invitations
through which either entered are removed from the authority's live capability
set, which all admissions consult. Other capabilities remain valid. Membership credentials
are removed, the epoch advances, native routes/controllers are fenced and peer
cookies are invalidated. Connections between surviving members stay usable.
There is no permanent banned-device register; a fresh invitation can authorize
a new membership for a removed device.

One VM has one native trust domain. Multiple logical swarms may use that domain;
they are not VM-security boundaries. A populated domain cannot silently join an
unrelated domain. A solitary domain can be replaced by explicit invitation
acceptance. Independently isolated domains require separate VMs or a separately
designed explicit merge operation. Existing app invitation URLs and UI behavior
are unchanged until native app integration.
The isolated authority does not rewrite the existing apps' swarm metadata or
their legacy relay sessions; that integration remains step 4.

The step-2 smoke test verifies four VMs, invitations by different nodes, remote
execution, wrong/expired tokens, altered expiry, forged signatures, wrong node
names, replay across DTLS sessions, nonce replay, malformed claims, unapproved
native frames, cluster-wide removal, stale cookies, retained survivor traffic,
fresh-invitation re-entry, authority handover and trust-manager shutdown. It also
verifies that authority outage denies new admissions without stopping existing
native traffic. Replay/cookie-restoration hooks live only in the local probe;
authentication-envelope observation is explicitly enabled by that probe and is
off by default in the channel worker.

## Acceptance checks

The test checks the OS process IDs differ and that ERTS reports each WebRTC
controller process as the native distribution controller for the other node.
It exercises both directions:

- `erpc` and real remote PIDs from native `spawn`;
- remote computation and exact echo of a random 256 KiB binary with SHA-256;
- 100 messages received in order, normal remote process monitoring and an
  abnormal linked remote process exit;
- an idle period exceeding two test tick-time periods, with native tick packets
  keeping the connection alive without application traffic;
- silent receive loss injected beneath distribution: OTP's own tick timeout
  tears down the connection and delivers `DOWN`, linked `EXIT` and `nodedown`;
- rejection of a mismatched cookie even though WebRTC has connected successfully.

The test uses a four-second native tick time to keep failure checks short. That
is a test setting, not the chosen timeout policy for mobile or live playback.

## Boundaries and next work

This proves native distribution over WebRTC between two desktop VMs. It does
not prove remote-network NAT traversal, relay transport of distribution,
simultaneous connection arbitration, reconnect, mobile support or audio latency.
The same-process controller serializes input/output for simplicity. Packets are
limited to 8 MiB, and local WebRTC mailbox overload fails the connection closed;
these are prototype bounds, not a completed end-to-end backpressure solution.
The library's asynchronous sends do not acknowledge delivery to the remote VM.

Admission/removal is verified under the isolated test's connected-cluster
conditions. This is not a consensus protocol, a security audit or a claim of
instant revocation across partitions. Unexpected authority/host recovery,
reconciliation of partial policy publication, cancelled joins, membership leases
and reliable revocation receipts remain step-3 work. A removal whose reply is
lost as the caller is fenced can report `pending`; survivors' current policy is
the completion evidence. Offline removed devices can retain a stale local view,
but a surviving node rejects their old credentials. New admissions fail closed
when the authority is unavailable; existing native connections do not depend on
it for each message. The authority actor currently has no automatic crash recovery.

Native distribution deliberately grants full VM trust. An already compromised
admitted VM can read or alter its peers' state, including keys; removing it cannot
undo prior compromise. These checks protect against outsiders and stale
credentials while honest nodes enforce current policy. They do not sandbox
malicious code already admitted into the cluster.

Prototype bounds include 64 members, 256 active invitations, 32 local sessions,
256 admitted native names and 4,096 pair-cookie installations per VM lifetime.
The last two bound non-garbage-collected OTP atom allocation. Fresh runtime
sessions are required after those budgets are exhausted. Trust-manager death,
including normal termination, closes its monitored native controllers.

Keep this out of normal app build paths and do not expose its local probe command
interface as a network service. Runtime packaging, internet transport recovery
and distributed DSP remain later steps in [the plan](../../../../docs/PLAN.md).

API references: [OTP alternative carriers](https://www.erlang.org/docs/29/apps/erts/alt_dist.html),
[OTP 29.1.2 controller BIFs](https://www.erlang.org/docs/29/apps/erts/erlang.html#dist_ctrl_get_data/1),
and the installed OTP 29.1.2 `kernel/include/dist_util.hrl`.
