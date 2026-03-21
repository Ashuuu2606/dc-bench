#!/usr/bin/env bash
set -euo pipefail

SERVER="${1:?Usage: ./run_all_experiments.sh <server> <client1> [client2] ...}"
shift
CLIENTS=("$@")

SERVER_IP="10.10.1.1"
PORT=9000
BENCH="/tmp/dc-bench/build/tcp_bench"
RESULTS_BASE="/tmp/dc-bench/exp_results"

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

    ssh "$SERVER" "mkdir -p $RESULTS_BASE/$NAME"
    ssh "$SERVER" "pkill -f tcp_bench || true"
    sleep 1

    local SERVER_CMD="$BENCH server --port $PORT"
    if [ "$DCTCP_FLAG" = "yes" ]; then
        SERVER_CMD="$SERVER_CMD --dctcp"
    fi
    ssh "$SERVER" "nohup $SERVER_CMD > $RESULTS_BASE/$NAME/server.log 2>&1 &"
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
        ssh "$CLIENT" "$CLIENT_CMD" &
        CLIENT_PIDS+=($!)
    done

    echo "  Waiting for ${#CLIENT_PIDS[@]} clients..."
    for pid in "${CLIENT_PIDS[@]}"; do
        wait "$pid" || true
    done

    ssh "$SERVER" "pkill -f tcp_bench || true"
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
