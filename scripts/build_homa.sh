#!/usr/bin/env bash
set -euo pipefail

HOMA_DIR="${1:-/tmp/HomaModule}"
BRANCH="${2:-master}"

echo "=== Building HomaModule ==="

if [ ! -d "$HOMA_DIR" ]; then
    echo "[1/4] Cloning HomaModule..."
    git clone https://github.com/PlatformLab/HomaModule.git "$HOMA_DIR"
else
    echo "[1/4] Updating existing HomaModule..."
    cd "$HOMA_DIR" && git pull
fi

cd "$HOMA_DIR"
git checkout "$BRANCH"

echo "[2/4] Building kernel module..."
make -j"$(nproc)"

echo "[3/4] Loading kernel module..."
rmmod homa 2>/dev/null || true
insmod homa.ko

echo "[4/4] Verifying..."
if lsmod | grep -q homa; then
    echo "HomaModule loaded successfully."
    echo "Homa protocol number: $(cat /proc/sys/net/homa/protocol 2>/dev/null || echo 'check /proc/sys/net/homa/')"
else
    echo "ERROR: HomaModule failed to load."
    exit 1
fi

echo ""
echo "=== HomaModule build complete ==="
echo "Include path for dc-bench: $HOMA_DIR"
echo "Build with: cmake -DBUILD_HOMA=ON -DHOMA_INCLUDE_DIR=$HOMA_DIR .."
