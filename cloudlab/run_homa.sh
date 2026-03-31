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
    "/tmp/dc-bench/build/homa_bench" \
    "$SCRIPT_DIR/../results" \
    "9500"

if ! dcbench_parse_remote_args "$(basename "$0")" "$@"; then
    rc=$?
    [ "$rc" -eq 2 ] && exit 0
    exit "$rc"
fi

run_homa() {
    local name="$1"
    local client_extra="$2"
    local nreq="$3"
    local warmup="$4"

    echo ""
    echo "================================================================"
    echo "  $name"
    echo "================================================================"

    dcbench_ssh "$SERVER" "pkill -f homa_bench 2>/dev/null; true"
    sleep 1
    dcbench_ssh "$SERVER" "nohup $BENCH server --port $PORT --threads 4 > /dev/null 2>&1 &"
    sleep 2

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
    dcbench_ssh "$SERVER" "pkill -f homa_bench 2>/dev/null; true"

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

echo "=== HOMA EXPERIMENTS ==="
dcbench_print_remote_config

run_homa "homa_fixed1k" \
    "--concurrency 1 --dist fixed --msg-size 1024" 10000 1000

run_homa "homa_bimodal64k" \
    "--concurrency 8 --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9" 10000 1000

run_homa "homa_bimodal1m" \
    "--concurrency 8 --dist bimodal --bimodal-small 256 --bimodal-large 1048576 --bimodal-ratio 0.9" 5000 500

run_homa "homa_pareto" \
    "--concurrency 8 --dist pareto --pareto-shape 1.5 --pareto-scale 256" 10000 1000

run_homa "homa_uniform256" \
    "--concurrency 8 --dist fixed --msg-size 256" 20000 2000

echo ""
echo "=== HOMA EXPERIMENTS COMPLETE ==="
