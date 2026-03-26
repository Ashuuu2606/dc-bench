#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:?Usage: ./setup_all.sh <git-repo-url> <node0> <node1> ... }"
shift
NODES=("$@")

if [ ${#NODES[@]} -lt 2 ]; then
    echo "Need at least 2 nodes (1 server + 1 client)"
    exit 1
fi

SERVER="${NODES[0]}"
CLIENTS=("${NODES[@]:1}")

echo "=== Deploying to ${#NODES[@]} nodes ==="
echo "  Server:  $SERVER"
echo "  Clients: ${CLIENTS[*]}"
echo ""

for NODE in "${NODES[@]}"; do
    echo "--- Setting up $NODE ---"
    ssh -o StrictHostKeyChecking=no "$NODE" bash -s <<REMOTE
set -e
cd /tmp
if [ ! -d dc-bench ]; then
    git clone $REPO_URL dc-bench
else
    cd dc-bench && git pull && cd /tmp
fi

cd /tmp/dc-bench
sudo bash scripts/setup_node.sh

mkdir -p build && cd build
cmake ..
make -j\$(nproc)

echo "Build complete on \$(hostname)"
REMOTE
    echo "  $NODE done."
done

echo ""
echo "=== All nodes ready ==="
echo ""
echo "Server IP (on bench-lan): 10.10.1.1"
echo ""
echo "Quick test (run manually):"
echo "  Server:  ssh $SERVER '/tmp/dc-bench/build/tcp_bench server --port 9000'"
echo "  Client:  ssh ${CLIENTS[0]} '/tmp/dc-bench/build/tcp_bench client --host 10.10.1.1 --port 9000 --pool-size 1 --dist fixed --msg-size 1024 --requests 10000'"
