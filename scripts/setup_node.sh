#!/usr/bin/env bash
set -euo pipefail

echo "=== CloudLab Node Setup ==="

echo "[1/7] Installing build dependencies..."
apt-get update -qq
apt-get install -y -qq build-essential cmake git linux-headers-$(uname -r) \
    python3 python3-pip htop iperf3 ethtool

echo "[2/7] Installing Python packages..."
pip3 install numpy matplotlib pandas

echo "[3/7] Disabling CPU frequency scaling..."
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "performance" > "$gov" 2>/dev/null || true
done

echo "[4/7] Disabling turbo boost..."
if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
    echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
fi
if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
    echo 0 > /sys/devices/system/cpu/cpufreq/boost
fi

echo "[5/7] Configuring kernel network parameters..."
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
sysctl -w net.core.rmem_default=1048576
sysctl -w net.core.wmem_default=1048576
sysctl -w net.ipv4.tcp_rmem="4096 1048576 16777216"
sysctl -w net.ipv4.tcp_wmem="4096 1048576 16777216"
sysctl -w net.core.netdev_max_backlog=30000
sysctl -w net.core.somaxconn=4096

echo "[6/7] Enabling DCTCP and ECN..."
modprobe tcp_dctcp 2>/dev/null || true
sysctl -w net.ipv4.tcp_ecn=1
sysctl -w net.ipv4.tcp_ecn_fallback=1

IFACE=$(ip -o link show | awk -F: '/ens|enp/{print $2; exit}' | tr -d ' ')
if [ -n "$IFACE" ]; then
    echo "[7/7] Configuring NIC ($IFACE)..."
    ethtool -K "$IFACE" tso off gso off gro off 2>/dev/null || true
    ethtool -C "$IFACE" adaptive-rx off rx-usecs 0 2>/dev/null || true
else
    echo "[7/7] No NIC found to configure, skipping."
fi

echo ""
echo "=== Node setup complete ==="
echo "TCP congestion controls available:"
cat /proc/sys/net/ipv4/tcp_available_congestion_control
echo "Current default: $(cat /proc/sys/net/ipv4/tcp_congestion_control)"
