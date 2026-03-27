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

mkdir -p "$LOCALDIR"

run_experiment() {
    local NAME="$1"
    local SERVER_EXTRA="$2"
    local CLIENT_EXTRA="$3"
    local NREQ="$4"
    local WARMUP="$5"

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

    for pid in "${PIDS[@]}"; do
        wait "$pid" || true
    done

    $SSH "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"

    echo "  Results:"
    for i in "${!CLIENTS[@]}"; do
        local p50=$(grep "p50:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        local p99=$(grep "p99:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | head -1 | awk '{print $2}')
        local p999=$(grep "p99.9:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        local tput=$(grep "Throughput:" "$LOCALDIR/$NAME/client_${i}.txt" 2>/dev/null | awk '{print $2}')
        echo "    client_$i: p50=${p50}us  p99=${p99}us  p99.9=${p999}us  ${tput} rps"
    done
}

echo "Starting all experiments at $(date)"

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
