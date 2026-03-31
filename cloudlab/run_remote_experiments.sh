#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/node_config.sh" ]; then
    source "$SCRIPT_DIR/node_config.sh"
fi
source "$SCRIPT_DIR/remote_config.sh"

REMOTE_ROOT="${DCBENCH_REMOTE_ROOT:-\$HOME/tmp}"

dcbench_init_remote_config \
    "${DCBENCH_NODE_SERVER:-}" \
    "${DCBENCH_NODE_CLIENTS:-}" \
    "${DCBENCH_SERVER_IP:-10.10.1.1}" \
    "$REMOTE_ROOT/dc-bench/build/tcp_bench" \
    "$SCRIPT_DIR/../results" \
    "9000"

if ! dcbench_parse_remote_args "$(basename "$0")" "$@"; then
    rc=$?
    [ "$rc" -eq 2 ] && exit 0
    exit "$rc"
fi

run_experiment() {
    local name="$1"
    local server_extra="$2"
    local client_extra="$3"
    local nreq="$4"
    local warmup="$5"

    echo ""
    echo "================================================================"
    echo "  $name"
    echo "================================================================"

    dcbench_ssh "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"
    sleep 1

    dcbench_ssh "$SERVER" "nohup $BENCH server --port $PORT $server_extra > /dev/null 2>&1 &"
    sleep 1

    mkdir -p "$LOCALDIR/$name"
    local pids=()
    for i in "${!CLIENTS[@]}"; do
        dcbench_ssh "${CLIENTS[$i]}" \
            "$BENCH client --host $SERVER_IP --port $PORT $client_extra --requests $nreq --warmup $warmup --cpu-monitor --output $REMOTE_ROOT/res_${name}" \
            > "$LOCALDIR/$name/client_${i}.txt" 2>&1 &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    dcbench_ssh "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"

    echo "  Results:"
    for i in "${!CLIENTS[@]}"; do
        local p50
        local p99
        local p999
        local tput
        p50=$(grep "p50:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        p99=$(grep "p99:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | head -1 | awk '{print $2}')
        p999=$(grep "p99.9:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        tput=$(grep "Throughput:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        echo "    client_$i: p50=${p50}us  p99=${p99}us  p99.9=${p999}us  ${tput} rps"
    done
}

echo "Starting all experiments at $(date)"
dcbench_print_remote_config

run_experiment "exp01_bimodal_single" \
    "" \
    "--pool-size 1 --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp02_bimodal_pool32_rr" \
    "" \
    "--pool-size 32 --scheduling round_robin --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp03_bimodal_pool32_sa" \
    "" \
    "--pool-size 32 --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp04_bimodal_dctcp_single" \
    "--dctcp" \
    "--pool-size 1 --dctcp --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp05_bimodal_dctcp_pool32_sa" \
    "--dctcp" \
    "--pool-size 32 --dctcp --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp06_pareto_single" \
    "" \
    "--pool-size 1 --dist pareto --pareto-shape 1.5 --pareto-scale 256" \
    20000 2000

run_experiment "exp07_pareto_pool32_sa" \
    "" \
    "--pool-size 32 --scheduling size_aware --dist pareto --pareto-shape 1.5 --pareto-scale 256" \
    20000 2000

run_experiment "exp08_pareto_dctcp_pool32_sa" \
    "--dctcp" \
    "--pool-size 32 --dctcp --scheduling size_aware --dist pareto --pareto-shape 1.5 --pareto-scale 256" \
    20000 2000

run_experiment "exp09_fixed1k_pool1" \
    "" \
    "--pool-size 1 --dist fixed --msg-size 1024" \
    50000 5000

run_experiment "exp10_fixed1k_pool16" \
    "" \
    "--pool-size 16 --dist fixed --msg-size 1024" \
    50000 5000

run_experiment "exp11_fixed1k_pool32" \
    "" \
    "--pool-size 32 --dist fixed --msg-size 1024" \
    50000 5000

run_experiment "exp12_fixed1k_pool64" \
    "" \
    "--pool-size 64 --dist fixed --msg-size 1024" \
    50000 5000

echo ""
echo "ALL EXPERIMENTS COMPLETE at $(date)"
echo "Results in: $LOCALDIR"
