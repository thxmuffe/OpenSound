# ReceptionDesk

An Erlang/OTP service, separate from the browser app in
[`Apps/WebApp`](../../Apps/WebApp/README.md). Its current implementation is a
supervised, in-memory node-name directory and an HTTP API using OTP `inets`.
The internal OTP application/module names remain `parvi_broker` for compatibility.

The Reception Desk is the future home for internet rendezvous, permission-checked
mailboxes and relay mechanisms. Those features are not implemented yet. The
current API is an unauthenticated local prototype, not ready for public deployment.

## Build and run

From the repository root:

```sh
bash Services/ReceptionDesk/build.sh
bash Services/ReceptionDesk/run.sh
```

The service listens on `http://127.0.0.1:8765`. Its root returns service metadata;
it does not serve the WebApp. Products go to `builds/Services/ReceptionDesk/`,
and compiler output goes to `builds/intermediates/ReceptionDesk/`.

On Windows, after [preparing OTP](../../Apps/Windows/README.md):

```powershell
.\Services\ReceptionDesk\run.ps1
```

`PARVI_BROKER_BIND` and `PARVI_BROKER_PORT` retain their existing configuration
names. The default bind is loopback. Restarting clears all directory records.

## Current API

- `GET /`: service name and API path.
- `GET /api/nodes`: `{"node_ids":[...]}`.
- `POST /api/nodes` with `Content-Type: application/json` and
  `{"node_id":"mac@127.0.0.1"}` registers a name and returns `node_ids` plus
  `registered_node_id`.

Names are unverified announcements, not stable device identities. Registrations
are idempotent and serialized by a gen_server. Limits: 256 names, 255 bytes per
name and 1024 bytes per request. Incoming names remain binaries, never atoms.
Errors: 400 invalid input, 415 unsupported content type, 405 unsupported method,
503 full directory. No Erlang cookies belong in this API.

There is no expiry, unregister, persistence, liveness check, mailbox, WebSocket,
NAT traversal, TLS configuration or relay yet. Native apps still have their
existing transport restrictions; discovery does not establish a connection.
The native Mac invitation UI no longer exposes this legacy directory flow.

## Verification

```sh
rebar3 eunit
python3 Services/ReceptionDesk/tools/smoke.py
```

The integration check builds the service and WebApp, tests their separate HTTP
origins and API forwarding, validates directory behavior, then uses the existing
Mac bundle to check two real local Erlang runtimes, discovery and chat. Build
that bundle first with `bash Apps/macOS/build.sh` if it is absent.

Render deployment will be a separate step after the internet protocol is ready.
