#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/node_config.sh" ]; then
    source "$SCRIPT_DIR/node_config.sh"
fi

REPO_URL="${DCBENCH_REPO_URL:-https://github.com/Ashuuu2606/dc-bench.git}"
INSTALL_CMD="${DCBENCH_INSTALL_CMD:-sudo bash scripts/setup_node.sh}"
BUILD_DIR="${DCBENCH_BUILD_DIR:-build}"
SSH_OPTS_STR="${DCBENCH_SSH_OPTS:--o StrictHostKeyChecking=no}"
read -r -a SSH_OPTS <<< "$SSH_OPTS_STR"
NODES_CSV="${DCBENCH_NODES:-}"

NODES=()
if [ -n "$NODES_CSV" ]; then
    IFS=',' read -r -a NODES <<< "$NODES_CSV"
fi

usage() {
    cat <<EOF
Usage:
  $(basename "$0") --nodes NODE0,NODE1,... [options]
  $(basename "$0") <git-repo-url> <node0> <node1> ...

Options:
  --repo-url URL            Git repo to clone/pull (default: $REPO_URL)
  --nodes N0,N1,...         Comma-separated node SSH targets
  --node NODE               Add one node target (repeatable)
  --install-cmd CMD         Per-node setup command in repo root (default: $INSTALL_CMD)
  --build-dir DIR           Build directory name (default: $BUILD_DIR)
  --ssh-opts "..."          SSH options string (default: -o StrictHostKeyChecking=no)
  -h, --help                Show help

Environment:
    DCBENCH_REPO_URL, DCBENCH_INSTALL_CMD, DCBENCH_BUILD_DIR,
    DCBENCH_NODES, DCBENCH_SSH_OPTS
EOF
}

if [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; then
    REPO_URL="$1"
    shift
    NODES=("$@")
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --nodes)
            IFS=',' read -r -a NODES <<< "$2"
            shift 2
            ;;
        --node)
            NODES+=("$2")
            shift 2
            ;;
        --install-cmd)
            INSTALL_CMD="$2"
            shift 2
            ;;
        --build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        --ssh-opts)
            SSH_OPTS_STR="$2"
            read -r -a SSH_OPTS <<< "$SSH_OPTS_STR"
            shift 2
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

if [ "${#NODES[@]}" -lt 2 ]; then
    echo "Need at least 2 nodes (1 server + 1 client)."
    usage
    exit 1
fi

remote_ssh() {
    local host="$1"
    local cmd="$2"
    ssh "${SSH_OPTS[@]}" "$host" "$cmd"
}

SERVER="${NODES[0]}"
CLIENTS=("${NODES[@]:1}")

echo "=== Deploying to ${#NODES[@]} nodes ==="
echo "  Server:  $SERVER"
echo "  Clients: ${CLIENTS[*]}"
echo ""

for NODE in "${NODES[@]}"; do
    echo "--- Setting up $NODE ---"
    remote_ssh "$NODE" "bash -s" <<REMOTE
set -e
cd /tmp
if [ ! -d dc-bench ]; then
    git clone $REPO_URL dc-bench
else
    cd dc-bench && git pull && cd /tmp
fi

cd /tmp/dc-bench
$INSTALL_CMD

mkdir -p $BUILD_DIR && cd $BUILD_DIR
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
