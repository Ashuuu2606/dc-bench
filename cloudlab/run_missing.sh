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

run_mem_measurement() {
    local NAME="$1"; local POOL="$2"
    echo ""
    echo "=== Memory: pool=$POOL ==="
    $SSH "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"
    sleep 1
    $SSH "$SERVER" "nohup $BENCH server --port 9000 > /dev/null 2>&1 &"
    sleep 1

    local MEM_BEFORE=$($SSH "$SERVER" "grep 'Mem\|Tcp\|Sock' /proc/net/sockstat /proc/meminfo 2>/dev/null")

    local PIDS=()
    for i in "${!CLIENTS[@]}"; do
        $SSH "${CLIENTS[$i]}" \
            "$BENCH client --host $SERVER_IP --port 9000 --pool-size $POOL --dist fixed --msg-size 1024 --requests 100000 --warmup 1000 --output /tmp/res_mem" \
            > /dev/null 2>&1 &
        PIDS+=($!)
    done

    sleep 3
    local MEM_DURING=$($SSH "$SERVER" "grep 'Mem\|Tcp\|Sock' /proc/net/sockstat /proc/meminfo 2>/dev/null")
    local CONN_COUNT=$($SSH "$SERVER" "cat /proc/net/tcp | wc -l" 2>/dev/null)

    for pid in "${PIDS[@]}"; do wait "$pid" || true; done
    $SSH "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"

    mkdir -p "$LOCALDIR/mem_pool${POOL}"
    echo "BEFORE:" > "$LOCALDIR/mem_pool${POOL}/sockstat.txt"
    echo "$MEM_BEFORE" >> "$LOCALDIR/mem_pool${POOL}/sockstat.txt"
    echo "" >> "$LOCALDIR/mem_pool${POOL}/sockstat.txt"
    echo "DURING (4 clients x pool=$POOL = $((4 * POOL)) connections):" >> "$LOCALDIR/mem_pool${POOL}/sockstat.txt"
    echo "$MEM_DURING" >> "$LOCALDIR/mem_pool${POOL}/sockstat.txt"
    echo "TCP connections: $CONN_COUNT" >> "$LOCALDIR/mem_pool${POOL}/sockstat.txt"
    echo "  Connections: $CONN_COUNT, pool=$POOL"
    cat "$LOCALDIR/mem_pool${POOL}/sockstat.txt"
}

echo "=========================================="
echo "  MISSING EXPERIMENTS"
echo "  $(date)"
echo "=========================================="

echo ""
echo "###############################################"
echo "#  UNIFORM SMALL MESSAGES (256B baseline)     #"
echo "###############################################"

run_experiment "exp13_uniform256_pool1" "" \
    "--pool-size 1 --dist fixed --msg-size 256" 50000 5000

run_experiment "exp14_uniform256_pool32_sa" "" \
    "--pool-size 32 --scheduling size_aware --dist fixed --msg-size 256" 50000 5000

echo ""
echo "###############################################"
echo "#  BIMODAL WITH 64KB LARGE (moderate HoL)     #"
echo "###############################################"

run_experiment "exp15_bimodal64k_single" "" \
    "--pool-size 1 --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9" 20000 2000

run_experiment "exp16_bimodal64k_pool32_rr" "" \
    "--pool-size 32 --scheduling round_robin --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9" 20000 2000

run_experiment "exp17_bimodal64k_pool32_sa" "" \
    "--pool-size 32 --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9" 20000 2000

run_experiment "exp18_bimodal64k_dctcp_pool32_sa" "--dctcp" \
    "--pool-size 32 --dctcp --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9" 20000 2000

echo ""
echo "###############################################"
echo "#  OPEN-LOOP EXPERIMENTS                      #"
echo "###############################################"

run_experiment "exp19_openloop_bimodal_single_5k" "" \
    "--pool-size 1 --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9 --arrival open --rps 5000" 20000 2000

run_experiment "exp20_openloop_bimodal_pool32_sa_5k" "" \
    "--pool-size 32 --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9 --arrival open --rps 5000" 20000 2000

run_experiment "exp21_openloop_bimodal_single_10k" "" \
    "--pool-size 1 --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9 --arrival open --rps 10000" 20000 2000

run_experiment "exp22_openloop_bimodal_pool32_sa_10k" "" \
    "--pool-size 32 --scheduling size_aware --dist bimodal --bimodal-small 256 --bimodal-large 65536 --bimodal-ratio 0.9 --arrival open --rps 10000" 20000 2000

echo ""
echo "###############################################"
echo "#  TCP_NODELAY ON vs OFF                      #"
echo "###############################################"

run_experiment "exp23_nodelay_on_pool1" "" \
    "--pool-size 1 --dist fixed --msg-size 256" 50000 5000

run_experiment "exp24_nodelay_off_pool1" "" \
    "--pool-size 1 --no-nodelay --dist fixed --msg-size 256" 50000 5000

echo ""
echo "###############################################"
echo "#  KERNEL MEMORY OVERHEAD                     #"
echo "###############################################"

run_mem_measurement "mem1" 1
run_mem_measurement "mem16" 16
run_mem_measurement "mem32" 32
run_mem_measurement "mem64" 64

echo ""
echo "ALL MISSING EXPERIMENTS COMPLETE at $(date)"
