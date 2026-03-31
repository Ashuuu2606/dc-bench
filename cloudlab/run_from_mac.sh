#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[DEPRECATED] run_from_mac.sh was renamed to run_remote_experiments.sh"
echo "             This wrapper remains for backward compatibility."
exec "$SCRIPT_DIR/run_remote_experiments.sh" "$@"
