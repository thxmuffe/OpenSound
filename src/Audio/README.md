# Audio runtime and platform adapters

`src/` contains Erlang audio processing and device workers. `native/Windows/`
contains the thin WASAPI loopback executable; it transfers raw PCM and Windows
format/timing metadata to Erlang through an OTP port. There is no installed
virtual driver or cross-node audio transport yet.

The shared `src/control/rebar.config` includes this component's Erlang sources
in the existing `parvi` application. Windows builds compile the same sources
and package the native helper beside `Parvi.exe`. No separate audio OTP
application or service is introduced by this directory move.

The [Windows app guide](../Apps/Windows/README.md) documents capture controls
and the local bridge protocol. See the [binding decision](../../docs/decisions/0004-windows-audio-library-trial.md)
for the PortAudio trial and the reason the direct WASAPI adapter remains.
Apple and Android adapters have not been implemented here.
