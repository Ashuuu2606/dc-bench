#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/node_config.sh" ]; then
    source "$SCRIPT_DIR/node_config.sh"
fi

REMOTE_ROOT="${DCBENCH_REMOTE_ROOT:-\$HOME/tmp}"
REPO_DIR="${DCBENCH_REPO_DIR:-$REMOTE_ROOT/dc-bench}"
BRANCH="${DCBENCH_BRANCH:-}"
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
  --remote-root DIR         Remote workspace root (default: $REMOTE_ROOT)
  --repo-dir DIR            Remote repository directory (default: $REPO_DIR)
  --branch NAME             Branch to checkout and pull (default: current branch)
  --ssh-opts "..."          SSH options string (default: -o StrictHostKeyChecking=no)
  -h, --help                Show help

Environment:
  DCBENCH_NODES, DCBENCH_REMOTE_ROOT, DCBENCH_REPO_DIR,
  DCBENCH_BRANCH, DCBENCH_SSH_OPTS
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
        --remote-root)
            REMOTE_ROOT="$2"
            REPO_DIR="${DCBENCH_REPO_DIR:-$REMOTE_ROOT/dc-bench}"
            shift 2
            ;;
        --repo-dir)
            REPO_DIR="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
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

echo "=== Running git pull on ${#NODES[@]} nodes ==="
echo "  Nodes: ${NODES[*]}"
echo "  Repo dir: $REPO_DIR"
if [ -n "$BRANCH" ]; then
    echo "  Branch: $BRANCH"
else
    echo "  Branch: current checkout on each node"
fi

overall_rc=0
for NODE in "${NODES[@]}"; do
    echo "--- Updating $NODE ---"
    if remote_ssh "$NODE" "bash -s" <<REMOTE
set -e
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "ERROR: $REPO_DIR is missing or not a git repository."
    exit 1
fi
cd "$REPO_DIR"

git fetch --all --prune
if [ -n "$BRANCH" ]; then
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        git checkout "$BRANCH"
    else
        git checkout -b "$BRANCH" "origin/$BRANCH"
    fi
    git pull --ff-only origin "$BRANCH"
else
    git pull --ff-only
fi

echo "Updated \\$(hostname): \\$(git rev-parse --abbrev-ref HEAD) @ \\$(git rev-parse --short HEAD)"
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
    echo "One or more nodes failed during git pull."
    exit "$overall_rc"
fi

echo ""
echo "=== git pull complete on all nodes ==="
