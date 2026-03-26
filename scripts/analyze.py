#!/usr/bin/env python3

import argparse
import csv
import os
import sys
import json
import numpy as np
from pathlib import Path


def load_latency_csv(path):
    latencies_ns = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            latencies_ns.append(int(row["latency_ns"]))
    return np.array(latencies_ns)


def compute_stats(samples_ns):
    if len(samples_ns) == 0:
        return {}

    samples_us = samples_ns / 1000.0

    return {
        "count": len(samples_us),
        "min_us": float(np.min(samples_us)),
        "mean_us": float(np.mean(samples_us)),
        "p50_us": float(np.percentile(samples_us, 50)),
        "p95_us": float(np.percentile(samples_us, 95)),
        "p99_us": float(np.percentile(samples_us, 99)),
        "p999_us": float(np.percentile(samples_us, 99.9)),
        "max_us": float(np.max(samples_us)),
        "std_us": float(np.std(samples_us)),
    }


def analyze_experiment(result_dir):
    all_samples = []
    client_stats = {}

    for entry in sorted(Path(result_dir).iterdir()):
        csv_path = entry / "latency.csv" if entry.is_dir() else None
        if csv_path and csv_path.exists():
            samples = load_latency_csv(csv_path)
            all_samples.append(samples)
            client_stats[entry.name] = compute_stats(samples)

    if not all_samples:
        csv_files = list(Path(result_dir).glob("*.csv"))
        for csv_path in csv_files:
            samples = load_latency_csv(csv_path)
            all_samples.append(samples)
            client_stats[csv_path.stem] = compute_stats(samples)

    if not all_samples:
        print(f"No latency data found in {result_dir}", file=sys.stderr)
        return None

    merged = np.concatenate(all_samples)
    aggregate = compute_stats(merged)

    return {
        "aggregate": aggregate,
        "per_client": client_stats,
    }


def compare_experiments(dirs, labels=None):
    results = {}
    for i, d in enumerate(dirs):
        label = labels[i] if labels and i < len(labels) else os.path.basename(d)
        analysis = analyze_experiment(d)
        if analysis:
            results[label] = analysis["aggregate"]

    if not results:
        return

    header = f"{'Config':<25} {'P50':>10} {'P95':>10} {'P99':>10} {'P99.9':>10} {'Mean':>10} {'Count':>10}"
    print(header)
    print("-" * len(header))

    for label, stats in results.items():
        print(f"{label:<25} "
              f"{stats['p50_us']:>9.1f} "
              f"{stats['p95_us']:>9.1f} "
              f"{stats['p99_us']:>9.1f} "
              f"{stats['p999_us']:>9.1f} "
              f"{stats['mean_us']:>9.1f} "
              f"{stats['count']:>10d}")

    return results


def main():
    parser = argparse.ArgumentParser(description="Analyze benchmark results")
    parser.add_argument("dirs", nargs="+", help="Result directories to analyze")
    parser.add_argument("--labels", nargs="*", help="Labels for each directory")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--output", help="Save analysis to file")
    args = parser.parse_args()

    if len(args.dirs) == 1:
        result = analyze_experiment(args.dirs[0])
        if result:
            if args.json:
                output = json.dumps(result, indent=2)
            else:
                stats = result["aggregate"]
                output = (
                    f"Aggregate ({stats['count']} samples):\n"
                    f"  min:    {stats['min_us']:.1f} us\n"
                    f"  mean:   {stats['mean_us']:.1f} us\n"
                    f"  p50:    {stats['p50_us']:.1f} us\n"
                    f"  p95:    {stats['p95_us']:.1f} us\n"
                    f"  p99:    {stats['p99_us']:.1f} us\n"
                    f"  p99.9:  {stats['p999_us']:.1f} us\n"
                    f"  max:    {stats['max_us']:.1f} us\n"
                )

            print(output)
            if args.output:
                with open(args.output, "w") as f:
                    f.write(output)
    else:
        results = compare_experiments(args.dirs, args.labels)
        if results and args.output:
            with open(args.output, "w") as f:
                json.dump(results, f, indent=2)


if __name__ == "__main__":
    main()
