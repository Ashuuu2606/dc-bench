#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/node_config.sh" ]; then
    source "$SCRIPT_DIR/node_config.sh"
fi

HOMA_BRANCH="${DCBENCH_HOMA_BRANCH:-linux_5.4.80}"
REMOTE_ROOT="${DCBENCH_REMOTE_ROOT:-\$HOME/tmp}"
HOMA_DIR="${DCBENCH_HOMA_DIR:-$REMOTE_ROOT/HomaModule}"
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

Options:
  --nodes N0,N1,...         Comma-separated node SSH targets
  --node NODE               Add one node target (repeatable)
  --homa-branch NAME        HomaModule branch (default: $HOMA_BRANCH)
  --homa-dir DIR            HomaModule directory on remote nodes (default: $HOMA_DIR)
  --remote-root DIR         Remote workspace root (default: $REMOTE_ROOT)
  --ssh-opts "..."          SSH options string (default: -o StrictHostKeyChecking=no)
  -h, --help                Show help

Environment:
  DCBENCH_NODES, DCBENCH_HOMA_BRANCH, DCBENCH_HOMA_DIR,
  DCBENCH_REMOTE_ROOT, DCBENCH_SSH_OPTS
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --nodes)
            IFS=',' read -r -a NODES <<< "$2"
            shift 2
            ;;
        --node)
            NODES+=("$2")
            shift 2
            ;;
        --homa-branch)
            HOMA_BRANCH="$2"
            shift 2
            ;;
        --homa-dir)
            HOMA_DIR="$2"
            shift 2
            ;;
        --remote-root)
            REMOTE_ROOT="$2"
            HOMA_DIR="${DCBENCH_HOMA_DIR:-$REMOTE_ROOT/HomaModule}"
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

if [ "${#NODES[@]}" -eq 0 ]; then
    echo "No nodes specified. Provide --nodes/--node or set DCBENCH_NODES."
    usage
    exit 1
fi

remote_ssh() {
    local host="$1"
    local cmd="$2"
    ssh "${SSH_OPTS[@]}" "$host" "$cmd"
}

echo "=== Building HomaModule on ${#NODES[@]} nodes ==="
echo "  Nodes: ${NODES[*]}"
echo "  Homa branch: $HOMA_BRANCH"
echo "  Homa dir: $HOMA_DIR"

overall_rc=0
for NODE in "${NODES[@]}"; do
    echo "--- Building Homa on $NODE ---"
    if remote_ssh "$NODE" "bash -s" <<REMOTE
set -e
mkdir -p "$REMOTE_ROOT"
if [ ! -d "$REMOTE_ROOT/dc-bench/.git" ]; then
    echo "ERROR: $REMOTE_ROOT/dc-bench is missing or not a git repository. Run cloudlab/setup_all.sh first."
    exit 1
fi
cd "$REMOTE_ROOT/dc-bench"
sudo bash scripts/build_homa.sh "$HOMA_DIR" "$HOMA_BRANCH"
REMOTE
    then
        echo "  $NODE done."
    else
        echo "  $NODE failed."
        overall_rc=1
    fi
done

if [ "$overall_rc" -ne 0 ]; then
    echo ""
    echo "One or more nodes failed to build HomaModule."
    exit "$overall_rc"
fi

echo ""
echo "=== HomaModule build complete on all nodes ==="
