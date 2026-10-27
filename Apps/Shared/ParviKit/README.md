# ParviKit

A local Swift package under `Apps/Shared/`, used by the macOS app and iPhone project.
This is shared application code; the Erlang layer remains in `control/`. It contains the
shared native chat UI, observable UI model, JSON snapshot types and `ChatRuntime`
interface. It has no third-party Swift dependencies and owns no chat history or
membership rules: those remain in the shared Erlang application under `control/`.

```text
macOS app -- MacErlangRuntime -- bundled BEAM subprocess
           \                 /
            ParviKit + shared Erlang application
           /                 \
iPhone app -- IOSErlangRuntime -- embedded BEAM (physical test pending)
```

Both adapters return actual Erlang snapshots to the same model. The iOS adapter
now starts interpreted BEAM in-process and uses a device-local socket to the
same shared OTP application. Startup, supervisor recovery and UI messaging have
been verified in the simulator; the signed physical-device test remains pending.

Xcode consumes the package directly through a relative local package reference.
The command-line Mac build compiles the same package sources as a static module.
Each platform compiles its own native library; compiled macOS binaries cannot
be reused as iOS libraries. Erlang sources are also shared, but their bytecode
must be compatible with the runtime shipped on each platform.

UI layout adapts to the device: a sidebar on Mac and a compact screen on iPhone.
Runtime hosting, permissions, audio hardware and lifecycle behavior remain
platform boundaries. No speculative audio interfaces are introduced yet.
