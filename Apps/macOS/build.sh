#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APP="$ROOT/builds/macOS/Parvi.app"
cd "$ROOT/control"
rebar3 release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Apps/macOS/Parvi/Info.plist" "$APP/Contents/Info.plist"
# ditto preserves the runtime layout, including versioned OTP directories.
ditto "$ROOT/builds/intermediates/control/default/rel/parvi" "$APP/Contents/Resources/runtime"
# OTP crypto provides secure session/invitation randomness. Bundle its OpenSSL
# dependency so the app does not depend on the build machine's Homebrew install.
for crypto_nif in "$APP"/Contents/Resources/runtime/lib/crypto-*/priv/lib/crypto.so; do
  crypto_library=$(otool -L "$crypto_nif" | awk '$1 ~ /libcrypto.*[.]dylib$/ {print $1; exit}')
  if [[ "$crypto_library" = /* && "$crypto_library" != /usr/lib/* ]]; then
    crypto_destination="$(dirname "$crypto_nif")/$(basename "$crypto_library")"
    if [ -e "$crypto_destination" ]; then chmod u+w "$crypto_destination"; fi
    cp -L "$crypto_library" "$crypto_destination"
    chmod u+w "$crypto_destination" "$crypto_nif"
    install_name_tool -change "$crypto_library" "@loader_path/$(basename "$crypto_library")" "$crypto_nif"
    install_name_tool -id "@loader_path/$(basename "$crypto_library")" "$crypto_destination"
    codesign --force --sign - "$crypto_destination"
    codesign --force --sign - "$crypto_nif"
    crypto_license="$(dirname "$(dirname "$crypto_library")")/LICENSE.txt"
    test -f "$crypto_license"
    cp "$crypto_license" "$APP/Contents/Resources/OPENSSL-LICENSE.txt"
  fi
done
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
OTP_ROOT=$(erl -noshell -eval 'io:put_chars(code:root_dir()), halt().')
OTP_LICENSE=""
for candidate in "$OTP_ROOT/LICENSE.txt" "$OTP_ROOT/../../LICENSE.txt"; do
  if [ -f "$candidate" ]; then OTP_LICENSE="$candidate"; break; fi
done
if [ -z "$OTP_LICENSE" ]; then
  echo "Cannot locate the Erlang distribution license; refusing to package without it." >&2
  exit 1
fi
cp "$OTP_LICENSE" "$APP/Contents/Resources/ERLANG-LICENSE.txt"
SHARED="$ROOT/builds/intermediates/macOS/shared"
mkdir -p "$SHARED"
# Build the same sources exposed by the local ParviKit Swift package in Xcode.
swiftc -swift-version 5 -O -parse-as-library -emit-library -static -emit-module \
  -module-name ParviKit -emit-module-path "$SHARED/ParviKit.swiftmodule" \
  -module-cache-path "$ROOT/builds/intermediates/macOS/ModuleCache" \
  "$ROOT"/Apps/Shared/ParviKit/Sources/ParviKit/*.swift -o "$SHARED/libParviKit.a"
swiftc -swift-version 5 -O -parse-as-library -framework SwiftUI -framework AppKit \
  -module-cache-path "$ROOT/builds/intermediates/macOS/ModuleCache" \
  -I "$SHARED" -L "$SHARED" -lParviKit \
  "$ROOT"/Apps/macOS/Parvi/*.swift -o "$APP/Contents/MacOS/Parvi"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
