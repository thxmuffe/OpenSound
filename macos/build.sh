#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/macos/build/Parvi.app"
cd "$ROOT/control"
rebar3 release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/macos/Parvi/Info.plist" "$APP/Contents/Info.plist"
# ditto preserves the runtime layout, including versioned OTP directories.
ditto "$ROOT/control/_build/default/rel/parvi" "$APP/Contents/Resources/runtime"
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
SHARED="$ROOT/macos/build/shared"
mkdir -p "$SHARED"
# Build the same sources exposed by the local ParviKit Swift package in Xcode.
swiftc -swift-version 5 -O -parse-as-library -emit-library -static -emit-module \
  -module-name ParviKit -emit-module-path "$SHARED/ParviKit.swiftmodule" \
  -module-cache-path "$ROOT/macos/build/ModuleCache" \
  "$ROOT"/shared/ParviKit/Sources/ParviKit/*.swift -o "$SHARED/libParviKit.a"
swiftc -swift-version 5 -O -parse-as-library -framework SwiftUI -framework AppKit \
  -module-cache-path "$ROOT/macos/build/ModuleCache" \
  -I "$SHARED" -L "$SHARED" -lParviKit \
  "$ROOT"/macos/Parvi/*.swift -o "$APP/Contents/MacOS/Parvi"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
