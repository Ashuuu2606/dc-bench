# dc-bench: TCP vs Homa Datacenter Benchmark

Empirical comparison of TCP (with connection pooling, DCTCP, priority scheduling) vs Homa under latency-sensitive datacenter incast workloads.

## Repository Structure

```
dc-bench/
├── include/dcbench/       # C++ headers
│   ├── message.h          # Wire protocol (22-byte packed header)
│   ├── timing.h           # Nanosecond-precision clock utilities
│   ├── statistics.h       # Latency histogram with percentile computation
│   ├── workload.h         # Workload generators (fixed/uniform/bimodal/pareto)
│   ├── connection_pool.h  # TCP connection pool with socket option control
│   ├── priority_scheduler.h # Connection selection (round-robin/size-aware/random)
│   ├── tcp_server.h       # Thread-per-connection TCP echo server
│   ├── tcp_client.h       # TCP benchmark client (open-loop + closed-loop)
│   ├── homa_api.h         # HomaModule kernel socket wrapper
│   ├── homa_server.h      # Homa echo server
│   ├── homa_client.h      # Homa benchmark client
│   └── cpu_monitor.h      # /proc/stat CPU utilization tracker
├── src/                   # C++ implementations + main drivers
├── scripts/               # Python/shell automation
│   ├── orchestrate.py     # SSH-based multi-node experiment runner
│   ├── sweep.py           # Parameter sweep automation
│   ├── analyze.py         # Result parsing and statistics
│   ├── plot.py            # CDF, tail latency, and bar chart generation
│   ├── setup_node.sh      # CloudLab node kernel/NIC configuration
│   └── build_homa.sh      # HomaModule build and install
└── configs/               # Experiment presets (JSON)
```

## Building

### TCP benchmark (no kernel module required)

```bash
mkdir build && cd build
cmake ..
make -j$(nproc)
```

### With Homa support (requires HomaModule on the target machine)

```bash
# First, build and load HomaModule
sudo bash scripts/build_homa.sh

# Then build with Homa enabled
mkdir build && cd build
cmake -DBUILD_HOMA=ON -DHOMA_INCLUDE_DIR=/tmp/HomaModule ..
make -j$(nproc)
```

## Usage

### TCP Server

```bash
./tcp_bench server --port 9000 --dctcp
```

### TCP Client

```bash
# Single-stream baseline (what Homa papers benchmark against)
./tcp_bench client --host 10.0.0.1 --pool-size 1 --dist bimodal --requests 100000

# Connection-pooled with size-aware scheduling
./tcp_bench client --host 10.0.0.1 --pool-size 32 --scheduling size_aware \
    --dist bimodal --bimodal-small 256 --bimodal-large 1048576

# DCTCP with open-loop arrivals
./tcp_bench client --host 10.0.0.1 --pool-size 32 --dctcp \
    --arrival open --rps 50000 --dist pareto
```

### Homa Server/Client

```bash
./homa_bench server --port 9500 --threads 4
./homa_bench client --host 10.0.0.1 --port 9500 --concurrency 8 \
    --dist bimodal --requests 100000
```

### Automated Experiments

```bash
# Run a single experiment config
python3 scripts/orchestrate.py configs/tcp_pooled.json --deploy

# Parameter sweep
python3 scripts/sweep.py configs/tcp_pooled.json sweep_pool_size.json

# Analyze and compare
python3 scripts/analyze.py results/tcp_single results/tcp_pooled_32 results/homa_default \
    --labels "TCP-1" "TCP-32" "Homa"

# Generate plots
python3 scripts/plot.py results/tcp_single results/tcp_pooled_32 results/homa_default \
    --labels "TCP (single)" "TCP (pool=32)" "Homa" --output-dir plots/
```

## Experiment Configurations

| Config | Protocol | Pool Size | DCTCP | Scheduling |
|--------|----------|-----------|-------|------------|
| `tcp_single` | TCP | 1 | No | round_robin |
| `tcp_pooled` | TCP | 32 | No | size_aware |
| `tcp_dctcp_pooled` | TCP | 32 | Yes | size_aware |
| `homa_default` | Homa | N/A | N/A | N/A |

## Workload Distributions

- **fixed**: Constant message size
- **uniform**: Uniform random between `--uniform-min` and `--uniform-max`
- **bimodal**: 90% small (256B) + 10% large (1MB) to induce HoL blocking
- **pareto**: Heavy-tailed (shape=1.5, scale=256B) for realistic DC traffic

## CloudLab Setup

Target: **c6525-25g** nodes (AMD EPYC, 25GbE ConnectX-5)

1. Allocate nodes via CloudLab experiment
2. SSH into each node and run setup:
   ```bash
   sudo bash scripts/setup_node.sh
   ```
3. Build on one node and scp binaries, or build on each node
4. For Homa experiments, also run:
   ```bash
   sudo bash scripts/build_homa.sh
   ```
5. Edit hostnames in config JSONs to match your CloudLab allocation
6. Run experiments from your local machine:
   ```bash
   python3 scripts/orchestrate.py configs/tcp_pooled.json --deploy
   ```

### CloudLab Shell Helpers

The scripts under `cloudlab/` now support CLI flags and environment variable
overrides (for server, clients, bench path, IPs, ports, SSH options, and output
directories) so you do not need to edit script files per allocation.

Examples:

```bash
# Source reusable node names once per shell session.
source cloudlab/node_config.sh

# Then run any helper script without retyping host lists.
bash cloudlab/run_remote_experiments.sh
bash cloudlab/run_missing.sh
bash cloudlab/setup_all.sh

# Renamed from cloudlab/run_from_mac.sh (works from Linux/macOS)
bash cloudlab/run_remote_experiments.sh \
    --server user@node0.utah.cloudlab.us \
    --clients user@node1.utah.cloudlab.us,user@node2.utah.cloudlab.us \
    --server-ip 10.10.1.1 \
    --localdir ./results

# Alternative via environment variables
DCBENCH_SERVER=user@node0.utah.cloudlab.us \
DCBENCH_CLIENTS=user@node1.utah.cloudlab.us,user@node2.utah.cloudlab.us \
DCBENCH_SERVER_IP=10.10.1.1 \
bash cloudlab/run_missing.sh
```

## Key Metrics

- **P50 / P95 / P99 / P99.9 latency** (microseconds)
- **Throughput** (requests/second)
- **Goodput** (Mbps)
- **CPU utilization** (percentage)
