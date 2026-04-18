#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/node_config.sh" ]; then
    source "$SCRIPT_DIR/node_config.sh"
fi

SERVER="${DCBENCH_SERVER:-}"
CLIENTS_CSV="${DCBENCH_CLIENTS:-}"
CLIENTS=()

if [ -n "$CLIENTS_CSV" ]; then
    IFS=',' read -r -a CLIENTS <<< "$CLIENTS_CSV"
fi

SERVER_IP="${DCBENCH_SERVER_IP:-10.10.1.1}"
PORT="${DCBENCH_PORT:-9000}"
REMOTE_ROOT="${DCBENCH_REMOTE_ROOT:-\$HOME/tmp}"
BENCH="${DCBENCH_BENCH:-$REMOTE_ROOT/dc-bench/build/tcp_bench}"
RESULTS_BASE="${DCBENCH_RESULTS_BASE:-$REMOTE_ROOT/dc-bench/exp_results}"
SSH_OPTS_STR="${DCBENCH_SSH_OPTS:--o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2}"
read -r -a SSH_OPTS <<< "$SSH_OPTS_STR"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") --server USER@HOST --clients H1,H2,... [options]
  $(basename "$0") <server> <client1> [client2] ...

Options:
  --server USER@HOST          Server SSH target
  --clients H1,H2,...         Comma-separated client SSH targets
  --client HOST               Add one client SSH target (repeatable)
  --server-ip IP              Server data-plane IP (default: $SERVER_IP)
  --port PORT                 Server port (default: $PORT)
    --remote-root DIR           Remote workspace root (default: $REMOTE_ROOT)
  --bench PATH                tcp_bench path (default: $BENCH)
  --results-base DIR          Remote base results dir (default: $RESULTS_BASE)
    --ssh-opts "..."            SSH options string (default: -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)
  -h, --help                  Show help

Environment:
  DCBENCH_SERVER, DCBENCH_CLIENTS, DCBENCH_SERVER_IP, DCBENCH_PORT,
    DCBENCH_REMOTE_ROOT, DCBENCH_BENCH, DCBENCH_RESULTS_BASE, DCBENCH_SSH_OPTS
EOF
}

if [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; then
    SERVER="$1"
    shift
    CLIENTS=("$@")
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        --server)
            SERVER="$2"
            shift 2
            ;;
        --clients)
            CLIENTS=()
            IFS=',' read -r -a CLIENTS <<< "$2"
            shift 2
            ;;
        --client)
            CLIENTS+=("$2")
            shift 2
            ;;
        --server-ip)
            SERVER_IP="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --remote-root)
            REMOTE_ROOT="$2"
            shift 2
            ;;
        --bench)
            BENCH="$2"
            shift 2
            ;;
        --results-base)
            RESULTS_BASE="$2"
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

if [ -z "$SERVER" ] || [ "${#CLIENTS[@]}" -eq 0 ]; then
    usage
    exit 1
fi

remote_ssh() {
    local host="$1"
    local cmd="$2"
    ssh "${SSH_OPTS[@]}" "$host" "$cmd"
}

run_tcp_experiment() {
    local NAME="$1"
    local POOL="$2"
    local SCHED="$3"
    local DCTCP_FLAG="$4"
    local DIST="$5"

    echo ""
    echo "========================================"
    echo "  Experiment: $NAME"
    echo "========================================"

    remote_ssh "$SERVER" "mkdir -p $RESULTS_BASE/$NAME"
    remote_ssh "$SERVER" "pkill -u \$(id -u) -f tcp_bench || true"
    sleep 1

    local SERVER_CMD="$BENCH server --port $PORT"
    if [ "$DCTCP_FLAG" = "yes" ]; then
        SERVER_CMD="$SERVER_CMD --dctcp"
    fi
    remote_ssh "$SERVER" "nohup $SERVER_CMD > $RESULTS_BASE/$NAME/server.log 2>&1 &"
    sleep 2

    local CLIENT_PIDS=()
    for i in "${!CLIENTS[@]}"; do
        local CLIENT="${CLIENTS[$i]}"
        local CLIENT_CMD="$BENCH client --host $SERVER_IP --port $PORT"
        CLIENT_CMD="$CLIENT_CMD --pool-size $POOL --scheduling $SCHED"
        CLIENT_CMD="$CLIENT_CMD --dist $DIST"

        if [ "$DIST" = "bimodal" ]; then
            CLIENT_CMD="$CLIENT_CMD --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9"
        fi

        if [ "$DCTCP_FLAG" = "yes" ]; then
            CLIENT_CMD="$CLIENT_CMD --dctcp"
        fi

        CLIENT_CMD="$CLIENT_CMD --requests 100000 --warmup 5000 --cpu-monitor"
        CLIENT_CMD="$CLIENT_CMD --output $RESULTS_BASE/$NAME/client_$i"

        echo "  Starting client $i on $CLIENT..."
        remote_ssh "$CLIENT" "mkdir -p $RESULTS_BASE/$NAME && $CLIENT_CMD" &
        CLIENT_PIDS+=($!)
    done

    echo "  Waiting for ${#CLIENT_PIDS[@]} clients..."
    local client_failed=0
    for pid in "${CLIENT_PIDS[@]}"; do
        if ! wait "$pid"; then
            client_failed=1
        fi
    done

    remote_ssh "$SERVER" "pkill -u \$(id -u) -f tcp_bench || true"
    if [ "$client_failed" -ne 0 ]; then
        echo "  ERROR: one or more clients failed in $NAME"
        return 1
    fi
    echo "  $NAME complete."
}

echo "=== Running full experiment suite ==="
echo "  Server:  $SERVER ($SERVER_IP)"
echo "  Clients: ${CLIENTS[*]}"

# ---- Experiment 1: TCP single-stream (Homa paper baseline) ----
run_tcp_experiment "tcp_single_bimodal" 1 "round_robin" "no" "bimodal"

# ---- Experiment 2: TCP pooled (realistic datacenter) ----
run_tcp_experiment "tcp_pool32_bimodal" 32 "round_robin" "no" "bimodal"

# ---- Experiment 3: TCP pooled + size-aware scheduling ----
run_tcp_experiment "tcp_pool32_sizeaware_bimodal" 32 "size_aware" "no" "bimodal"

# ---- Experiment 4: DCTCP + pooled + size-aware ----
run_tcp_experiment "tcp_dctcp_pool32_sizeaware_bimodal" 32 "size_aware" "yes" "bimodal"

# ---- Experiment 5: Pareto (heavy-tail) variants ----
run_tcp_experiment "tcp_single_pareto" 1 "round_robin" "no" "pareto"
run_tcp_experiment "tcp_pool32_sizeaware_pareto" 32 "size_aware" "no" "pareto"
run_tcp_experiment "tcp_dctcp_pool32_sizeaware_pareto" 32 "size_aware" "yes" "pareto"

# ---- Experiment 6: Fixed small messages (overhead test) ----
run_tcp_experiment "tcp_single_fixed" 1 "round_robin" "no" "fixed"
run_tcp_experiment "tcp_pool32_fixed" 32 "round_robin" "no" "fixed"

echo ""
echo "=== All TCP experiments complete ==="
echo ""
echo "Collect results:"
echo "  mkdir -p local_results"
echo "  scp -r $SERVER:$RESULTS_BASE/* local_results/"
echo ""
echo "Analyze:"
echo "  python3 scripts/analyze.py local_results/tcp_single_bimodal local_results/tcp_pool32_sizeaware_bimodal local_results/tcp_dctcp_pool32_sizeaware_bimodal --labels 'TCP-1' 'TCP-32-SA' 'DCTCP-32-SA'"
echo ""
echo "Plot:"
echo "  python3 scripts/plot.py local_results/tcp_single_bimodal local_results/tcp_pool32_sizeaware_bimodal local_results/tcp_dctcp_pool32_sizeaware_bimodal --labels 'TCP-1' 'TCP-32-SA' 'DCTCP-32-SA'"
