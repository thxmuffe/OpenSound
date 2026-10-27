# Embedded runtime provenance

Parvi uses the prebuilt interpreted OTP 29.1.2 / ERTS 17.1.1 archives from
[GenericJam/mob release otp-d199a49a](https://github.com/GenericJam/mob/releases/tag/otp-d199a49a).
The release identifies OTP source commit `d199a49a` (OTP-29.1.2). The downloader
checks these GitHub-published SHA-256 digests before extraction:

| Artifact | SHA-256 |
| --- | --- |
| `otp-ios-device-d199a49a.tar.gz` | `437475e8abb721f3ffbbfe6f17ddb495e8bddd13503eaee87aea5e2c14e5dd1d` |
| `otp-ios-sim-d199a49a.tar.gz` | `a6066a1cce2391f78e1cbf45f89f758f78e42cf8f8fda7363660940f4a7b6755` |

Build/packaging reference:
[GenericJam/mob_dev](https://github.com/GenericJam/mob_dev) commit
`0f67685cf65ff7a3987d541c8842dfbc40047855`, including the iOS runtime cross-build
patches. Upstream documents limitations around subprocess/fork support on iOS.

The native startup argument layout and static driver/NIF ABI table were adapted
from [GenericJam/mob](https://github.com/GenericJam/mob), commit
`66fe71ca818c68b101875ba9cb4f4949a2f0bc9e` (`ios/mob_beam.m`,
`ios/driver_tab_ios.zig`). The errno compatibility helper follows mob_dev's
`generate_erl_errno_compat_stub`. The Mob sources are MIT licensed; their license
is preserved in `MOB-LICENSE` and copied into the application resources. Parvi
does not use Mob's UI, Elixir framework, remote code updates or deployment tooling.

Erlang/OTP is Apache-2.0 licensed; its source and third-party components retain
upstream copyrights and licenses. The runtime archive also includes static
OpenSSL 3.5.9 and ASN.1 components, linked through the OTP NIF table. These
artifacts are upstream-provided binaries, not a locally reproduced OTP build.
Before public distribution, reproduce/audit the build and assemble all upstream
component notices for the chosen shipping artifact. This is a local feasibility
prototype, not an App Store distribution or compatibility claim.
