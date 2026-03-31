#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/node_config.sh" ]; then
    source "$SCRIPT_DIR/node_config.sh"
fi

BENCH="${DCBENCH_BENCH:-/tmp/dc-bench/build/tcp_bench}"
SERVER_IP="${DCBENCH_SERVER_IP:-10.10.1.1}"
PORT="${DCBENCH_PORT:-9000}"
RESULTS="${DCBENCH_RESULTS:-/tmp/experiment_results}"
CLIENTS_CSV="${DCBENCH_CLIENTS:-10.10.1.2,10.10.1.3,10.10.1.4,10.10.1.5}"
SSH_OPTS_STR="${DCBENCH_SSH_OPTS:--o StrictHostKeyChecking=no}"
read -r -a SSH_OPTS <<< "$SSH_OPTS_STR"
IFS=',' read -r -a CLIENTS <<< "$CLIENTS_CSV"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --bench PATH              Benchmark binary path (default: $BENCH)
  --server-ip IP            Server IP (default: $SERVER_IP)
  --port PORT               Port (default: $PORT)
  --results DIR             Results directory (default: $RESULTS)
  --clients IP1,IP2,...     Comma-separated client SSH targets
  --ssh-opts "..."          SSH options string (default: -o StrictHostKeyChecking=no)
  -h, --help                Show help

Environment:
  DCBENCH_BENCH, DCBENCH_SERVER_IP, DCBENCH_PORT,
  DCBENCH_RESULTS, DCBENCH_CLIENTS, DCBENCH_SSH_OPTS
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --bench)
            BENCH="$2"
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
        --results)
            RESULTS="$2"
            shift 2
            ;;
        --clients)
            IFS=',' read -r -a CLIENTS <<< "$2"
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

if [ "${#CLIENTS[@]}" -eq 0 ]; then
    echo "At least one client is required."
    exit 1
fi

remote_ssh() {
    local host="$1"
    local cmd="$2"
    ssh "${SSH_OPTS[@]}" "$host" "$cmd"
}

remote_scp_from() {
    local host="$1"
    local remote_path="$2"
    local local_path="$3"
    scp "${SSH_OPTS[@]}" "$host:$remote_path" "$local_path"
}

mkdir -p "$RESULTS"

run_experiment() {
    local NAME="$1"
    local SERVER_FLAGS="$2"
    local CLIENT_FLAGS="$3"
    local REQUESTS="$4"
    local WARMUP="$5"

    echo ""
    echo "================================================================"
    echo "  EXPERIMENT: $NAME"
    echo "  Server flags: $SERVER_FLAGS"
    echo "  Client flags: $CLIENT_FLAGS"
    echo "================================================================"

    pkill -f tcp_bench 2>/dev/null || true
    sleep 1

    $BENCH server --port $PORT $SERVER_FLAGS &
    local SERVER_PID=$!
    sleep 1

    local PIDS=()
    for i in "${!CLIENTS[@]}"; do
        local CIP="${CLIENTS[$i]}"
        local OUTDIR="$RESULTS/$NAME/client_$i"
        remote_ssh "$CIP" \
            "$BENCH client --host $SERVER_IP --port $PORT \
            $CLIENT_FLAGS \
            --requests $REQUESTS --warmup $WARMUP --cpu-monitor \
            --output $OUTDIR" > "$RESULTS/$NAME/client_${i}_stdout.txt" 2>&1 &
        PIDS+=($!)
    done

    for pid in "${PIDS[@]}"; do
        wait "$pid" || true
    done

    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true

    echo "--- Results for $NAME ---"
    for i in "${!CLIENTS[@]}"; do
        echo ""
        echo "  Client $i (${CLIENTS[$i]}):"
        cat "$RESULTS/$NAME/client_${i}_stdout.txt" 2>/dev/null | grep -A20 "=== TCP"
    done

    for i in "${!CLIENTS[@]}"; do
        local CIP="${CLIENTS[$i]}"
        local OUTDIR="$RESULTS/$NAME/client_$i"
        mkdir -p "$RESULTS/$NAME/client_$i"
        remote_scp_from "$CIP" "$OUTDIR/latency.csv" \
            "$RESULTS/$NAME/client_$i/latency.csv" 2>/dev/null || true
    done
}

echo "============================================================"
echo "  TCP vs Homa Benchmark Suite"
echo "  Server: $SERVER_IP (node-0)"
echo "  Clients: ${CLIENTS[*]}"
echo "  Bench: $BENCH"
echo "  Results: $RESULTS"
echo "  Time: $(date)"
echo "============================================================"

echo ""
echo "###############################################################"
echo "#  HYPOTHESIS 1: HoL Blocking (Bimodal Workload)              #"
echo "###############################################################"

run_experiment "exp1_hol_single" \
    "" \
    "--pool-size 1 --scheduling round_robin --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp2_hol_pool32_rr" \
    "" \
    "--pool-size 32 --scheduling round_robin --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp3_hol_pool32_sa" \
    "" \
    "--pool-size 32 --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

echo ""
echo "###############################################################"
echo "#  HYPOTHESIS 2: Congestion Control (DCTCP + ECN)             #"
echo "###############################################################"

run_experiment "exp4_dctcp_single" \
    "--dctcp" \
    "--pool-size 1 --dctcp --scheduling round_robin --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp5_dctcp_pool32_sa" \
    "--dctcp" \
    "--pool-size 32 --dctcp --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

echo ""
echo "###############################################################"
echo "#  HEAVY-TAIL WORKLOAD (Pareto Distribution)                  #"
echo "###############################################################"

run_experiment "exp6_pareto_single" \
    "" \
    "--pool-size 1 --scheduling round_robin --dist pareto --pareto-shape 1.5 --pareto-scale 256" \
    20000 2000

run_experiment "exp7_pareto_pool32_sa" \
    "" \
    "--pool-size 32 --scheduling size_aware --dist pareto --pareto-shape 1.5 --pareto-scale 256" \
    20000 2000

run_experiment "exp8_pareto_dctcp_pool32" \
    "--dctcp" \
    "--pool-size 32 --dctcp --scheduling size_aware --dist pareto --pareto-shape 1.5 --pareto-scale 256" \
    20000 2000

echo ""
echo "###############################################################"
echo "#  HYPOTHESIS 3: Config Overhead (Fixed 1KB, vary pool size)  #"
echo "###############################################################"

run_experiment "exp9_overhead_pool1" \
    "" \
    "--pool-size 1 --scheduling round_robin --dist fixed --msg-size 1024" \
    50000 5000

run_experiment "exp10_overhead_pool16" \
    "" \
    "--pool-size 16 --scheduling round_robin --dist fixed --msg-size 1024" \
    50000 5000

run_experiment "exp11_overhead_pool32" \
    "" \
    "--pool-size 32 --scheduling round_robin --dist fixed --msg-size 1024" \
    50000 5000

run_experiment "exp12_overhead_pool64" \
    "" \
    "--pool-size 64 --scheduling round_robin --dist fixed --msg-size 1024" \
    50000 5000

echo ""
echo "============================================================"
echo "  ALL EXPERIMENTS COMPLETE"
echo "  Results in: $RESULTS"
echo "  Time: $(date)"
echo "============================================================"

echo ""
echo "=== SUMMARY ==="
for exp_dir in "$RESULTS"/exp*; do
    exp_name=$(basename "$exp_dir")
    echo ""
    echo "--- $exp_name ---"
    for f in "$exp_dir"/client_*_stdout.txt; do
        client=$(basename "$f" | sed 's/_stdout.txt//')
        p50=$(grep "p50:" "$f" 2>/dev/null | awk '{print $2, $3}')
        p99=$(grep "p99:" "$f" 2>/dev/null | head -1 | awk '{print $2, $3}')
        throughput=$(grep "Throughput:" "$f" 2>/dev/null | awk '{print $2, $3}')
        cpu=$(grep "CPU" "$f" 2>/dev/null | awk '{print $3}')
        echo "  $client: p50=$p50  p99=$p99  tput=$throughput  cpu=$cpu"
    done
done
