#!/usr/bin/env bash

SERVER="Ashutosh@hp034.utah.cloudlab.us"
CLIENT1="Ashutosh@hp037.utah.cloudlab.us"
CLIENT2="Ashutosh@hp004.utah.cloudlab.us"
CLIENT3="Ashutosh@hp024.utah.cloudlab.us"
CLIENT4="Ashutosh@hp008.utah.cloudlab.us"
CLIENTS=("$CLIENT1" "$CLIENT2" "$CLIENT3" "$CLIENT4")
SERVER_IP="10.10.1.1"
BENCH="/tmp/dc-bench/build/tcp_bench"
LOCALDIR="/Users/ashutoshbharadwaj/Desktop/dns/dc-bench/results"
SSH="ssh -o StrictHostKeyChecking=no"

run_experiment() {
    local NAME="$1"; local SERVER_EXTRA="$2"; local CLIENT_EXTRA="$3"
    local NREQ="$4"; local WARMUP="$5"

    echo ""
    echo "================================================================"
    echo "  $NAME"
    echo "================================================================"

    $SSH "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"
    sleep 1
    $SSH "$SERVER" "nohup $BENCH server --port 9000 $SERVER_EXTRA > /dev/null 2>&1 &"
    sleep 1

    mkdir -p "$LOCALDIR/$NAME"
    local PIDS=()
    for i in "${!CLIENTS[@]}"; do
        $SSH "${CLIENTS[$i]}" \
            "$BENCH client --host $SERVER_IP --port 9000 $CLIENT_EXTRA --requests $NREQ --warmup $WARMUP --cpu-monitor --output /tmp/res_${NAME}" \
            > "$LOCALDIR/$NAME/client_${i}.txt" 2>&1 &
        PIDS+=($!)
    done
    for pid in "${PIDS[@]}"; do wait "$pid" || true; done
    $SSH "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"

    echo "  Results:"
    for i in "${!CLIENTS[@]}"; do
        local p50=$(grep "p50:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        local p95=$(grep "p95:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        local p99=$(grep "p99:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | head -1 | awk '{print $2}')
        local p999=$(grep "p99.9:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        local tput=$(grep "Throughput:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        local cpu=$(grep "CPU" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | awk '{print $3}')
        echo "    c$i: p50=${p50} p95=${p95} p99=${p99} p999=${p999} tput=${tput} cpu=${cpu}"
    done
}

echo "=== RE-TEST WITH FIXED SIZE_AWARE THRESHOLD (>4096) ==="

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
