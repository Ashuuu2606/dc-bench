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

REPO="https://github.com/Ashuuu2606/dc-bench.git"
DIR="/tmp/dc-bench"

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
echo "[2/5] Installing packages..."
apt-get update -qq
apt-get install -y -qq build-essential cmake git linux-headers-$(uname -r) \
    python3 python3-pip htop iperf3 ethtool net-tools
pip3 install numpy matplotlib pandas 2>/dev/null || true

# 3. Kernel tuning
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

# 4. Build
echo "[5/5] Building..."
cd "$DIR"
rm -rf build && mkdir build && cd build
cmake ..
make -j$(nproc)

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
