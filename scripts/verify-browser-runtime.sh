#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec env -u PYTHONPATH -u PYTHONHOME python3 -I \
  "$SCRIPT_DIR/browser_runtime_integrity.py" verify "$@"
