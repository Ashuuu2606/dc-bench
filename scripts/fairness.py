#!/usr/bin/env python3
"""
Compute Jain's Fairness Index across concurrent senders.

Reads per-client latency.csv files from experiment result directories,
estimates per-sender throughput, and computes:
  - Jain's Fairness Index: J = (Σxi)² / (n·Σxi²)  ∈ [1/n, 1.0]
  - Coefficient of Variation (CV): std/mean of throughputs
  - Min/Max throughput ratio

Throughput model (closed-loop):
  throughput_i = pool_size * count_i / sum(latencies_ns_i)
  (pool_size parallel threads each run requests sequentially;
   wall_time ≈ sum_latencies / pool_size → tput = pool_size / mean_latency)

Usage:
  python scripts/fairness.py results/homa_default results/tcp_single \\
      --labels homa tcp-1 --pool-size 1
"""

import argparse
import csv
import json
import sys
import os
import numpy as np
from pathlib import Path


def load_latency_csv(path):
    latencies_ns = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            latencies_ns.append(int(row["latency_ns"]))
    return np.array(latencies_ns, dtype=np.float64)


def client_throughput_rps(samples_ns, pool_size):
    """Estimate throughput in rps for one sender process."""
    if len(samples_ns) == 0:
        return 0.0
    # wall_time_s ≈ mean_latency_s × n_requests (single thread);
    # pool_size threads run in parallel → total tput scales linearly.
    mean_ns = np.mean(samples_ns)
    return pool_size * 1e9 / mean_ns


def jain_index(values):
    """Jain's Fairness Index. Returns 1.0 for perfect equality."""
    arr = np.asarray(values, dtype=np.float64)
    n = len(arr)
    if n == 0 or np.sum(arr ** 2) == 0:
        return float("nan")
    return float(arr.sum() ** 2 / (n * np.sum(arr ** 2)))


def analyze_fairness(result_dir, pool_size):
    """Return per-client stats and aggregate fairness metrics for one experiment."""
    clients = {}
    for entry in sorted(Path(result_dir).iterdir()):
        if not entry.is_dir():
            continue
        csv_path = entry / "latency.csv"
        if not csv_path.exists():
            continue
        samples = load_latency_csv(csv_path)
        if len(samples) == 0:
            continue
        tput = client_throughput_rps(samples, pool_size)
        clients[entry.name] = {
            "count": len(samples),
            "mean_us": float(np.mean(samples) / 1000.0),
            "throughput_rps": tput,
        }

    if not clients:
        return None

    tputs = [c["throughput_rps"] for c in clients.values()]
    mean_tput = float(np.mean(tputs))
    std_tput = float(np.std(tputs))
    return {
        "per_client": clients,
        "n_senders": len(clients),
        "jain_index": jain_index(tputs),
        "cv": std_tput / mean_tput if mean_tput > 0 else float("nan"),
        "min_max_ratio": min(tputs) / max(tputs) if max(tputs) > 0 else float("nan"),
        "mean_throughput_rps": mean_tput,
    }


def print_experiment(label, data):
    print(f"\n=== {label} ===")
    header = f"  {'Sender':<12} {'Count':>8}  {'Mean(us)':>10}  {'Tput(rps)':>12}"
    print(header)
    print("  " + "-" * (len(header) - 2))
    for name, c in data["per_client"].items():
        print(f"  {name:<12} {c['count']:>8}  {c['mean_us']:>10.1f}  {c['throughput_rps']:>12,.1f}")
    print(
        f"\n  Jain Index: {data['jain_index']:.4f}   "
        f"CV: {data['cv']:.3f}   "
        f"Min/Max ratio: {data['min_max_ratio']:.3f}   "
        f"Senders: {data['n_senders']}"
    )


def print_summary_table(results):
    print("\n" + "=" * 72)
    print("Summary across experiments")
    print("=" * 72)
    header = f"{'Config':<28} {'Senders':>7}  {'Jain':>6}  {'CV':>6}  {'MinMax':>6}  {'MeanTput':>10}"
    print(header)
    print("-" * len(header))
    for label, data in results.items():
        print(
            f"{label:<28} "
            f"{data['n_senders']:>7}  "
            f"{data['jain_index']:>6.4f}  "
            f"{data['cv']:>6.3f}  "
            f"{data['min_max_ratio']:>6.3f}  "
            f"{data['mean_throughput_rps']:>10,.1f}"
        )


def main():
    parser = argparse.ArgumentParser(
        description="Compute Jain Fairness Index across concurrent senders"
    )
    parser.add_argument("dirs", nargs="+", help="Result directories to analyze")
    parser.add_argument("--labels", nargs="*", help="Labels for each directory")
    parser.add_argument(
        "--pool-size",
        type=int,
        default=1,
        metavar="N",
        help="Connection pool size (threads per sender). Default: 1. "
             "Note: Jain index is pool-size-invariant when uniform across senders.",
    )
    parser.add_argument("--json", action="store_true", dest="as_json", help="Output as JSON")
    args = parser.parse_args()

    results = {}
    for i, d in enumerate(args.dirs):
        label = (args.labels[i] if args.labels and i < len(args.labels)
                 else os.path.basename(d.rstrip("/")))
        data = analyze_fairness(d, args.pool_size)
        if data is None:
            print(f"WARNING: no latency data found in {d}", file=sys.stderr)
            continue
        results[label] = data

    if not results:
        print("No data found.", file=sys.stderr)
        sys.exit(1)

    if args.as_json:
        print(json.dumps(results, indent=2))
        return

    for label, data in results.items():
        print_experiment(label, data)

    if len(results) > 1:
        print_summary_table(results)


if __name__ == "__main__":
    main()
