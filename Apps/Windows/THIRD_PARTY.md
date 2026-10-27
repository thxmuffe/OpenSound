# Windows graph-view provenance

`src/parvi_fgraph_win.erl` is adapted from Erlang/OTP **29.1.2**, Reltool **1.1**:

https://github.com/erlang/otp/blob/OTP-29.1.2/lib/reltool/src/reltool_fgraph_win.erl

Copyright Ericsson AB 2009–2025. Licensed under **Apache-2.0**. The original
copyright and license header are retained in the adapted source. The project's
root `LICENSE` contains the Apache-2.0 license text.

Parvi adaptations: module name, light background, bidirectional connection
arrows, bounded initial layout for a small viewport, centered labels, node-click
notifications, hidden-tab pause/resume, and ignoring irrelevant move events.
The original editing controls are hidden by the adapter. Force calculations
remain in the unmodified `reltool_fgraph` module from the bundled OTP runtime.
Compilation uses that same pinned runtime's `reltool_fgraph.hrl` header.

The native graph component is an internal OTP implementation, not a public
stable API. Keep the runtime version pinned when building or changing it.
