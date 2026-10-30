#!/bin/bash
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SOURCE/../../.." && pwd)
TARGET=${1:-device}
TRANSPORT=${2:-native}
case "$TRANSPORT" in native|relay) ;; *) echo 'Transport must be native or relay' >&2; exit 2 ;; esac
case "$TARGET" in
  device) SDK=iphoneos; DESTINATION='generic/platform=iOS' ;;
  sim) SDK=iphonesimulator; DESTINATION='generic/platform=iOS Simulator' ;;
  *) echo 'Usage: bash src/Apps/iOS/build.sh [device|sim] [native|relay]' >&2; exit 2 ;;
esac
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
python3 "$SOURCE/prepare-runtime.py" --target "$TARGET" --transport "$TRANSPORT"
# An unsigned verification build; installation/signing remain explicit Xcode steps.
xcrun xcodebuild -project "$SOURCE/Parvi.xcodeproj" -scheme Parvi \
  -configuration Debug -sdk "$SDK" -destination "$DESTINATION" \
  -derivedDataPath "$ROOT/builds/intermediates/iOS/Xcode-$TARGET" \
  CONFIGURATION_BUILD_DIR="$ROOT/builds/iOS/Debug-$SDK" \
  PARVI_TRANSPORT="$TRANSPORT" \
  CODE_SIGNING_ALLOWED=NO build
