#!/bin/bash
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SOURCE/../.." && pwd)
mkdir -p "$ROOT/builds/WebApp"
cp -R "$SOURCE/public/." "$ROOT/builds/WebApp/"
cp "$SOURCE/QRCODE-LICENSE" "$ROOT/builds/WebApp/"
echo "Built $ROOT/builds/WebApp"
