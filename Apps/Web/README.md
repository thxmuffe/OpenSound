# Parvi Reception desk

An Erlang/OTP service with an in-memory node-name directory and a minimal
website. Its public name is **Reception desk**; the implementation remains in
`Apps/Web/`. It uses OTP `inets` for HTTP. It introduces peers; it does not join their
cluster, check liveness, distribute cookies or relay traffic.

## Run

`bash Apps/Web/build.sh` compiles and stages the application under
`builds/Web/ReceptionDesk/`; the run scripts use that output. Erlang compiler
files stay under `builds/intermediates/Web/`. The staged `lib/parvi_broker/`
directory includes `ebin/` and `priv/`, including the website assets.

From the repository root:

```sh
bash Apps/Web/run.sh
```

On Windows, after [setting up the private OTP runtime](../Windows/README.md), run
`.\Apps\Web\run.ps1` from the repository root. It compiles and runs the same service.

Open [http://127.0.0.1:8765/](http://127.0.0.1:8765/). Stop the terminal process
with Ctrl+C, then `a` at the Erlang break prompt. Restarting clears the directory.
No database, cloud account or distribution ports are required.

## Use from the Mac app

Rebuild/relaunch Parvi, open **Connect**, and click **Register / Find nodes**.
The shared Erlang client registers its actual `node()` name and returns other
known names. Select one, then supply its cookie separately to connect. Register
both instances and refresh discovery after another joins.

The native client and node transport remain loopback-only. iPhone BEAM embedding
is still pending. Discovery does not remove these existing limitations.

## API

```sh
curl http://127.0.0.1:8765/api/nodes

curl http://127.0.0.1:8765/api/nodes \
  -H 'Content-Type: application/json' \
  -d '{"node_id":"mac@192.168.1.10"}'
```

GET returns `{"node_ids":[...]}`. POST adds the name and returns the entire list,
including the caller:

```json
{
  "node_ids": ["mac@192.168.1.10"],
  "registered_node_id": "mac@192.168.1.10"
}
```

Calls are serialized by a `gen_server`. Re-registering is idempotent. Names are
sorted, with limits of 256 names, 255 bytes per name, and 1024 bytes per request.
Incoming names stay binaries, never atoms. Names are unverified announcements,
not globally authenticated device identities. They stay until the registry or
broker restarts; there is no expiration, unregister operation or persistent store.
Clients filter out their own name and independently authenticate reachable peers.

Invalid input returns 400, unsupported content type 415, unsupported method 405,
and a full directory 503. No cookies belong in the registration API or QR code.

## QR and phones

The QR opens the join form at the page's origin. A query such as
`/?node_id=mac%40127.0.0.1` prefills the form; visiting a GET link does not register
a name. A browser cannot obtain the phone app's node identity automatically. A
future app link handler must register its own name through the API.

**A localhost QR points to the scanning device itself. It cannot reach the Mac
from an iPhone.** The default listener is Mac-only. For a future trusted-LAN test:

```sh
PARVI_BROKER_BIND=192.168.1.10 bash Apps/Web/run.sh
```

Replace the example with the Mac's actual private address and open that address
in the browser so its QR uses it. This exposes an unauthenticated HTTP directory
on that interface; use only a trusted test LAN. It does not change the current
Mac app's loopback-only node transport. No internet deployment or TLS is configured.
`PARVI_BROKER_PORT` optionally changes the port.

## Verification

```sh
cd Apps/Web
rebar3 eunit
cd ../..
bash Apps/macOS/build.sh
python3 Apps/Web/tools/smoke.py
```

The integration test starts a separate broker on a temporary port, checks HTTP
validation and deduplication, registers two actual Erlang app runtimes, uses
returned names for a separately authenticated handshake and two-way chat, then
checks that broker restart clears the list. It leaves port 8765's list alone.

## QR dependency

`priv/www/qrcode.js` is the locally vendored `qrcode-generator` 2.0.4, MIT licensed
by Kazuhiko Arase. License: `priv/QRCODE-LICENSE`.
[Upstream source](https://github.com/kazuhikoarase/qrcode-generator).
The npm archive was verified against:

```text
sha512-mZSiP6RnbHl4xL2Ap5HfkjLnmxfKcPWpWe/c+5XxCuetEenqmNFf1FH/ftXPCtFG5/TDobjsjz6sSNL0Sr8Z9g==
```

QR generation sends nothing to third-party services.
