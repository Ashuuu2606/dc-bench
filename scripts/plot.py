#!/usr/bin/env python3

import argparse
import csv
import os
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path


COLORS = ["#2196F3", "#FF5722", "#4CAF50", "#9C27B0", "#FF9800", "#607D8B"]


def load_latency_csv(path):
    latencies = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            latencies.append(float(row["latency_us"]))
    return np.array(latencies)


def load_experiment(result_dir):
    all_samples = []
    for entry in sorted(Path(result_dir).iterdir()):
        csv_path = entry / "latency.csv" if entry.is_dir() else None
        if csv_path and csv_path.exists():
            all_samples.append(load_latency_csv(csv_path))

    if not all_samples:
        for csv_path in sorted(Path(result_dir).glob("*.csv")):
            all_samples.append(load_latency_csv(csv_path))

    if all_samples:
        return np.concatenate(all_samples)
    return np.array([])


def plot_cdf(datasets, labels, output_path, title="Latency CDF"):
    fig, ax = plt.subplots(figsize=(10, 6))

    for i, (data, label) in enumerate(zip(datasets, labels)):
        if len(data) == 0:
            continue
        sorted_data = np.sort(data)
        cdf = np.arange(1, len(sorted_data) + 1) / len(sorted_data)
        ax.plot(sorted_data, cdf, label=label, color=COLORS[i % len(COLORS)],
                linewidth=2)

    ax.set_xlabel("Latency (us)", fontsize=12)
    ax.set_ylabel("CDF", fontsize=12)
    ax.set_title(title, fontsize=14)
    ax.legend(fontsize=11)
    ax.grid(True, alpha=0.3)
    ax.set_ylim(0, 1.02)

    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved CDF plot: {output_path}")


def plot_cdf_tail(datasets, labels, output_path, title="Tail Latency CDF"):
    fig, ax = plt.subplots(figsize=(10, 6))

    for i, (data, label) in enumerate(zip(datasets, labels)):
        if len(data) == 0:
            continue
        sorted_data = np.sort(data)
        cdf = np.arange(1, len(sorted_data) + 1) / len(sorted_data)
        mask = cdf >= 0.9
        ax.plot(sorted_data[mask], cdf[mask], label=label,
                color=COLORS[i % len(COLORS)], linewidth=2)

    ax.set_xlabel("Latency (us)", fontsize=12)
    ax.set_ylabel("CDF", fontsize=12)
    ax.set_title(title, fontsize=14)
    ax.legend(fontsize=11)
    ax.grid(True, alpha=0.3)
    ax.set_ylim(0.9, 1.001)

    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved tail CDF: {output_path}")


def plot_bar_percentiles(datasets, labels, output_path,
                         title="Latency Percentiles"):
    percentiles = [50, 95, 99, 99.9]
    pct_labels = ["P50", "P95", "P99", "P99.9"]

    fig, ax = plt.subplots(figsize=(10, 6))
    x = np.arange(len(percentiles))
    width = 0.8 / max(len(datasets), 1)

    for i, (data, label) in enumerate(zip(datasets, labels)):
        if len(data) == 0:
            continue
        values = [np.percentile(data, p) for p in percentiles]
        offset = (i - len(datasets) / 2 + 0.5) * width
        bars = ax.bar(x + offset, values, width, label=label,
                       color=COLORS[i % len(COLORS)], alpha=0.85)
        for bar, val in zip(bars, values):
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(),
                    f"{val:.0f}", ha="center", va="bottom", fontsize=8)

    ax.set_xlabel("Percentile", fontsize=12)
    ax.set_ylabel("Latency (us)", fontsize=12)
    ax.set_title(title, fontsize=14)
    ax.set_xticks(x)
    ax.set_xticklabels(pct_labels)
    ax.legend(fontsize=11)
    ax.grid(True, alpha=0.3, axis="y")

    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved bar chart: {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Plot benchmark results")
    parser.add_argument("dirs", nargs="+", help="Result directories")
    parser.add_argument("--labels", nargs="*", help="Labels for legend")
    parser.add_argument("--output-dir", default="./plots", help="Output directory")
    parser.add_argument("--title", default="TCP vs Homa Latency", help="Plot title")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    datasets = []
    labels = []
    for i, d in enumerate(args.dirs):
        label = args.labels[i] if args.labels and i < len(args.labels) else os.path.basename(d)
        data = load_experiment(d)
        if len(data) > 0:
            datasets.append(data)
            labels.append(label)
        else:
            print(f"Warning: no data in {d}", file=sys.stderr)

    if not datasets:
        print("No data to plot.", file=sys.stderr)
        sys.exit(1)

    plot_cdf(datasets, labels,
             os.path.join(args.output_dir, "cdf.png"),
             title=f"{args.title} - CDF")

    plot_cdf_tail(datasets, labels,
                  os.path.join(args.output_dir, "cdf_tail.png"),
                  title=f"{args.title} - Tail CDF (P90+)")

    plot_bar_percentiles(datasets, labels,
                         os.path.join(args.output_dir, "percentiles.png"),
                         title=f"{args.title} - Percentiles")


if __name__ == "__main__":
    main()
