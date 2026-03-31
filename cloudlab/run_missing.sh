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

run_mem_measurement() {
    local name="$1"
    local pool="$2"
    echo ""
    echo "=== Memory: pool=$pool ==="
    dcbench_ssh "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"
    sleep 1
    dcbench_ssh "$SERVER" "nohup $BENCH server --port $PORT > /dev/null 2>&1 &"
    sleep 1

    local mem_before
    mem_before=$(dcbench_ssh "$SERVER" "grep 'Mem\|Tcp\|Sock' /proc/net/sockstat /proc/meminfo 2>/dev/null")

    local pids=()
    for i in "${!CLIENTS[@]}"; do
        dcbench_ssh "${CLIENTS[$i]}" \
            "$BENCH client --host $SERVER_IP --port $PORT --pool-size $pool --dist fixed --msg-size 1024 --requests 100000 --warmup 1000 --output /tmp/res_mem" \
            > /dev/null 2>&1 &
        pids+=($!)
    done

    sleep 3
    local mem_during
    local conn_count
    mem_during=$(dcbench_ssh "$SERVER" "grep 'Mem\|Tcp\|Sock' /proc/net/sockstat /proc/meminfo 2>/dev/null")
    conn_count=$(dcbench_ssh "$SERVER" "cat /proc/net/tcp | wc -l" 2>/dev/null)

    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
    dcbench_ssh "$SERVER" "pkill -f tcp_bench 2>/dev/null; true"

    mkdir -p "$LOCALDIR/mem_pool${pool}"
    echo "BEFORE:" > "$LOCALDIR/mem_pool${pool}/sockstat.txt"
    echo "$mem_before" >> "$LOCALDIR/mem_pool${pool}/sockstat.txt"
    echo "" >> "$LOCALDIR/mem_pool${pool}/sockstat.txt"
    echo "DURING (${#CLIENTS[@]} clients x pool=$pool = $((${#CLIENTS[@]} * pool)) connections):" >> "$LOCALDIR/mem_pool${pool}/sockstat.txt"
    echo "$mem_during" >> "$LOCALDIR/mem_pool${pool}/sockstat.txt"
    echo "TCP connections: $conn_count" >> "$LOCALDIR/mem_pool${pool}/sockstat.txt"
    echo "  Connections: $conn_count, pool=$pool"
    cat "$LOCALDIR/mem_pool${pool}/sockstat.txt"
}

echo "=========================================="
echo "  MISSING EXPERIMENTS"
echo "  $(date)"
echo "=========================================="
dcbench_print_remote_config

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
