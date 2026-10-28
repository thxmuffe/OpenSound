#!/bin/bash
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SOURCE/../.." && pwd)
APP="$ROOT/builds/Services/ReceptionDesk/lib/parvi_broker"
cd "$SOURCE"
rebar3 compile
mkdir -p "$APP"
cp -R "$ROOT/builds/intermediates/ReceptionDesk/default/lib/parvi_broker/ebin" "$APP/"
echo "Built $ROOT/builds/Services/ReceptionDesk"
