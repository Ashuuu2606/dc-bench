#!/usr/bin/env bash
###############################################################################
# QUICKSTART: Run this ONCE on EACH CloudLab node after experiment is ready.
#
# Usage (from your Mac terminal):
#   ssh YourUser@node-0.tcp-homa-run1.gt-8803-dns.utah.cloudlab.us
#   curl -sL https://raw.githubusercontent.com/Ashuuu2606/dc-bench/main/cloudlab/QUICKSTART.sh | sudo bash
#
# Or if the repo is private, clone manually first:
#   git clone https://github.com/Ashuuu2606/dc-bench.git /tmp/dc-bench
#   sudo bash /tmp/dc-bench/cloudlab/QUICKSTART.sh
###############################################################################
set -euo pipefail

REPO="${DCBENCH_REPO_URL:-https://github.com/Ashuuu2606/dc-bench.git}"
DIR="${DCBENCH_DIR:-/tmp/dc-bench}"
SKIP_PACKAGES="${DCBENCH_SKIP_PACKAGES:-0}"
SKIP_TUNING="${DCBENCH_SKIP_TUNING:-0}"
SKIP_BUILD="${DCBENCH_SKIP_BUILD:-0}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --repo URL           Git repo URL (default: $REPO)
  --dir PATH           Checkout directory (default: $DIR)
  --skip-packages      Skip apt/pip installs
  --skip-tuning        Skip kernel/CPU/NIC tuning
  --skip-build         Skip cmake/make build
  -h, --help           Show help

Environment:
  DCBENCH_REPO_URL, DCBENCH_DIR,
  DCBENCH_SKIP_PACKAGES=1, DCBENCH_SKIP_TUNING=1, DCBENCH_SKIP_BUILD=1
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)
            REPO="$2"
            shift 2
            ;;
        --dir)
            DIR="$2"
            shift 2
            ;;
        --skip-packages)
            SKIP_PACKAGES=1
            shift
            ;;
        --skip-tuning)
            SKIP_TUNING=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

echo "============================================"
echo "  dc-bench CloudLab Node Setup"
echo "  $(hostname) | $(date)"
echo "============================================"

# 1. Clone or update repo
if [ ! -d "$DIR" ]; then
    echo "[1/5] Cloning repo..."
    git clone "$REPO" "$DIR"
else
    echo "[1/5] Updating repo..."
    cd "$DIR" && git pull
fi

# 2. Install dependencies
if [ "$SKIP_PACKAGES" = "1" ]; then
    echo "[2/5] Skipping package install (--skip-packages)"
else
    echo "[2/5] Installing packages..."
    apt-get update -qq
    apt-get install -y -qq build-essential cmake git linux-headers-$(uname -r) \
        python3 python3-pip htop iperf3 ethtool net-tools
    pip3 install numpy matplotlib pandas 2>/dev/null || true
fi

# 3. Kernel tuning
if [ "$SKIP_TUNING" = "1" ]; then
    echo "[3/5] Skipping kernel/CPU/NIC tuning (--skip-tuning)"
else
    echo "[3/5] Tuning kernel..."
    sysctl -w net.core.rmem_max=16777216
    sysctl -w net.core.wmem_max=16777216
    sysctl -w net.core.rmem_default=1048576
    sysctl -w net.core.wmem_default=1048576
    sysctl -w net.ipv4.tcp_rmem="4096 1048576 16777216"
    sysctl -w net.ipv4.tcp_wmem="4096 1048576 16777216"
    sysctl -w net.core.netdev_max_backlog=30000
    sysctl -w net.core.somaxconn=4096
    modprobe tcp_dctcp 2>/dev/null || true
    sysctl -w net.ipv4.tcp_ecn=1
    sysctl -w net.ipv4.tcp_ecn_fallback=1

    # CPU performance mode
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$gov" 2>/dev/null || true
    done
    # Disable turbo on AMD (c6525-25g has AMD EPYC)
    if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
        echo 0 > /sys/devices/system/cpu/cpufreq/boost
    fi

    # NIC tuning
    IFACE=$(ip -o link show | awk -F: '/ens|enp/{print $2; exit}' | tr -d ' ')
    if [ -n "$IFACE" ]; then
        echo "[4/5] Tuning NIC ($IFACE)..."
        ethtool -K "$IFACE" tso off gso off gro off 2>/dev/null || true
        ethtool -C "$IFACE" adaptive-rx off rx-usecs 0 2>/dev/null || true
    fi
fi

# 4. Build
if [ "$SKIP_BUILD" = "1" ]; then
    echo "[5/5] Skipping build (--skip-build)"
else
    echo "[5/5] Building..."
    cd "$DIR"
    rm -rf build && mkdir build && cd build
    cmake ..
    make -j$(nproc)
fi

echo ""
echo "============================================"
echo "  DONE on $(hostname)"
echo "  Binary: $DIR/build/tcp_bench"
echo "============================================"
echo ""
echo "DCTCP available: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control)"
echo ""

# Show the experiment LAN IP
ip -4 addr show | grep "10.10.1" || echo "(experiment LAN IP not found - check 'ip addr')"
