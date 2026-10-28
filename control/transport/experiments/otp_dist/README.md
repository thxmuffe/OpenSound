# Native OTP distribution over WebRTC experiment

Step 1 of the trusted-cluster plan: two independent OTP **29.1.2 / ERTS 17.1.1**
VMs use a reliable, ordered binary WebRTC DataChannel as their native Erlang
distribution carrier. This is isolated experimental code, not app integration.

## Run

First build the existing pinned WebRTC dependencies using the instructions in
[the transport README](../../README.md). Then run from the repository root:

```sh
python3 control/transport/tools/otp-dist-smoke.py
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
  OTP, not decoded or reimplemented here. Length framing and 16 KiB chunks allow
  a native packet to span several SCTP messages.
- `parvi_dist_probe` and `otp-dist-smoke.py`: test orchestration. The parent
  passes only SDP/ICE introductions between app-owned stdin/stdout pipes. It
  stops forwarding those signals before the native handshake starts. Test
  command results contain assertions/metadata, not the native payload stream.

Only this carrier is selected with `-proto_dist parvi_webrtc`; EPMD startup is
disabled. Automatic transitive connections are disabled. The test provisions
ephemeral node names, a random cookie and an explicit allowed peer locally.
This local provisioning authenticates the experiment's endpoints; it does not
implement production invitation-based trust or certificate issuance/revocation.

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

Step 2 must establish trusted admission/removal and how cluster access relates
to independent, potentially overlapping swarms. Until then, keep this out of
normal app build paths and do not expose its local probe command interface as
a network service. Runtime packaging, transport recovery and distributed DSP
remain later steps in [the plan](../../../../docs/PLAN.md).

API references: [OTP alternative carriers](https://www.erlang.org/docs/29/apps/erts/alt_dist.html),
[OTP 29.1.2 controller BIFs](https://www.erlang.org/docs/29/apps/erts/erlang.html#dist_ctrl_get_data/1),
and the installed OTP 29.1.2 `kernel/include/dist_util.hrl`.
