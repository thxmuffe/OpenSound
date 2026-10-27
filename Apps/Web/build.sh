#!/bin/bash
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SOURCE/../.." && pwd)
APP="$ROOT/builds/Web/ReceptionDesk/lib/parvi_broker"
cd "$SOURCE"
rebar3 compile
mkdir -p "$APP"
cp -R "$ROOT/builds/intermediates/Web/default/lib/parvi_broker/ebin" "$APP/"
# Dereference rebar's priv symlink: the output must not depend on source paths.
cp -RL "$SOURCE/priv" "$APP/"
echo "Built $ROOT/builds/Web/ReceptionDesk"
