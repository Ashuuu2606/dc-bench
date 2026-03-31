#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/node_config.sh" ]; then
    source "$SCRIPT_DIR/node_config.sh"
fi
source "$SCRIPT_DIR/remote_config.sh"

dcbench_init_remote_config \
    "${DCBENCH_NODE_SERVER:-}" \
    "${DCBENCH_NODE_CLIENTS:-}" \
    "${DCBENCH_SERVER_IP:-10.10.1.1}" \
    "/tmp/dc-bench/build/tcp_bench" \
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
            "$BENCH client --host $SERVER_IP --port $PORT $client_extra --requests $nreq --warmup $warmup --cpu-monitor --output /tmp/res_${name}" \
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
        local p95
        local p99
        local p999
        local tput
        local cpu
        p50=$(grep "p50:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        p95=$(grep "p95:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        p99=$(grep "p99:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | head -1 | awk '{print $2}')
        p999=$(grep "p99.9:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        tput=$(grep "Throughput:" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        cpu=$(grep "CPU" "$LOCALDIR/$name/client_${i}.txt" 2>/dev/null | awk '{print $3}')
        echo "    c$i: p50=${p50} p95=${p95} p99=${p99} p999=${p999} tput=${tput} cpu=${cpu}"
    done
}

echo "=== RE-TEST WITH FIXED SIZE_AWARE THRESHOLD (>4096) ==="
dcbench_print_remote_config

run_experiment "exp03_fixed_bimodal1m_pool32_sa" "" \
    "--pool-size 32 --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp17_fixed_bimodal64k_pool32_sa" "" \
    "--pool-size 32 --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9" \
    20000 2000

run_experiment "exp18_fixed_bimodal64k_dctcp_pool32_sa" "--dctcp" \
    "--pool-size 32 --dctcp --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9" \
    20000 2000

run_experiment "exp05_fixed_bimodal1m_dctcp_pool32_sa" "--dctcp" \
    "--pool-size 32 --dctcp --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" \
    10000 1000

run_experiment "exp07_fixed_pareto_pool32_sa" "" \
    "--pool-size 32 --scheduling size_aware --dist pareto --pareto-shape 1.5 --pareto-scale 256" \
    20000 2000

echo ""
echo "=== ALL RE-TESTS COMPLETE ==="
