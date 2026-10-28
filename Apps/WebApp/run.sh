#!/bin/bash
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")" && pwd)
bash "$SOURCE/build.sh"
exec python3 "$SOURCE/serve.py"
