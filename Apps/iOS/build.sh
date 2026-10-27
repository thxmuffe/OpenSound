#!/bin/bash
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SOURCE/../.." && pwd)
TARGET=${1:-device}
case "$TARGET" in
  device) SDK=iphoneos; DESTINATION='generic/platform=iOS' ;;
  sim) SDK=iphonesimulator; DESTINATION='generic/platform=iOS Simulator' ;;
  *) echo 'Usage: bash Apps/iOS/build.sh [device|sim]' >&2; exit 2 ;;
esac
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
python3 "$SOURCE/prepare-runtime.py" --target "$TARGET"
# An unsigned verification build; installation/signing remain explicit Xcode steps.
xcrun xcodebuild -project "$SOURCE/Parvi.xcodeproj" -scheme Parvi \
  -configuration Debug -sdk "$SDK" -destination "$DESTINATION" \
  -derivedDataPath "$ROOT/builds/intermediates/iOS/Xcode-$TARGET" \
  CODE_SIGNING_ALLOWED=NO build
