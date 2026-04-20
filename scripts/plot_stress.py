#!/usr/bin/env python3.11
"""Plots for the stress-test sweep: CDFs + percentile bars per protocol."""

import glob
import os
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


RESULTS_DIR = Path("results")
PLOTS_DIR = Path("results/plots")
PLOTS_DIR.mkdir(parents=True, exist_ok=True)

LOSS_TAGS = ["loss0", "loss0p1", "loss1p0", "loss5p0"]
LOSS_LABELS = ["0%", "0.1%", "1%", "5%"]
LOSS_COLORS = ["#2ca02c", "#1f77b4", "#ff7f0e", "#d62728"]

PROTOCOLS = [
    ("Homa (256KB large)", "homa_default_new", "loss{}"),
    ("TCP pooled-32 (4MB large)", "tcp_pooled_32_new", "loss{}"),
]


def load_samples(run_dir):
    samples = []
    for c in sorted(glob.glob(f"{run_dir}/client_*/latency.csv")):
        with open(c) as f:
            next(f)
            for line in f:
                parts = line.strip().split(",")
                if len(parts) >= 3:
                    try:
                        samples.append(float(parts[2]))
                    except ValueError:
                        pass
    return np.array(sorted(samples))


def pct(arr, p):
    return arr[min(int(len(arr) * p), len(arr) - 1)]


def cdf_plot(proto_label, base_name, out_path):
    fig, ax = plt.subplots(figsize=(7, 5))
    for tag, lbl, color in zip(LOSS_TAGS, LOSS_LABELS, LOSS_COLORS):
        run_dir = RESULTS_DIR / f"{base_name}_{tag.replace('loss', 'loss')}"
        # result dirs: loss0, loss0p0 for tcp
        candidates = [
            RESULTS_DIR / f"{base_name}_{tag}",
            RESULTS_DIR / f"{base_name}_{tag.replace('loss', 'loss')}p0" if tag == "loss0" else None,
            RESULTS_DIR / f"{base_name}_loss0p0" if tag == "loss0" else None,
        ]
        run_dir = next((c for c in candidates if c is not None and c.exists()), None)
        if run_dir is None:
            print(f"  missing: {base_name}_{tag}")
            continue
        s = load_samples(run_dir)
        if len(s) == 0:
            continue
        y = np.arange(1, len(s) + 1) / len(s)
        ax.plot(s / 1000.0, y, label=f"loss {lbl}", color=color, linewidth=1.8)
    ax.set_xscale("log")
    ax.set_xlabel("Latency (ms, log scale)")
    ax.set_ylabel("CDF")
    ax.set_title(f"{proto_label} — Latency CDF under packet loss")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    print(f"  wrote {out_path}")


def percentile_bars(out_path):
    percentiles = [0.5, 0.95, 0.99, 0.999]
    pct_labels = ["p50", "p95", "p99", "p99.9"]

    fig, axes = plt.subplots(1, 2, figsize=(14, 5), sharey=True)

    for ax, (proto_label, base_name, _) in zip(axes, PROTOCOLS):
        data = {lbl: [] for lbl in pct_labels}
        for tag in LOSS_TAGS:
            candidates = [
                RESULTS_DIR / f"{base_name}_{tag}",
                RESULTS_DIR / f"{base_name}_loss0p0" if tag == "loss0" else None,
            ]
            run_dir = next((c for c in candidates if c is not None and c.exists()), None)
            if run_dir is None:
                for lbl in pct_labels:
                    data[lbl].append(0)
                continue
            s = load_samples(run_dir)
            for p, lbl in zip(percentiles, pct_labels):
                data[lbl].append(pct(s, p) / 1000.0)

        x = np.arange(len(LOSS_TAGS))
        width = 0.2
        for i, lbl in enumerate(pct_labels):
            ax.bar(x + (i - 1.5) * width, data[lbl], width, label=lbl)
        ax.set_xticks(x)
        ax.set_xticklabels(LOSS_LABELS)
        ax.set_yscale("log")
        ax.set_xlabel("Packet loss")
        ax.set_title(proto_label)
        ax.grid(True, axis="y", alpha=0.3)
        ax.legend()
    axes[0].set_ylabel("Latency (ms, log scale)")
    fig.suptitle("Tail latency vs. packet loss", fontsize=13)
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    print(f"  wrote {out_path}")


def p99_overlay(out_path):
    fig, ax = plt.subplots(figsize=(8, 5))
    x = np.arange(len(LOSS_TAGS))
    width = 0.35
    for offset, (proto_label, base_name, _) in zip([-width / 2, width / 2], PROTOCOLS):
        vals = []
        for tag in LOSS_TAGS:
            candidates = [
                RESULTS_DIR / f"{base_name}_{tag}",
                RESULTS_DIR / f"{base_name}_loss0p0" if tag == "loss0" else None,
            ]
            run_dir = next((c for c in candidates if c is not None and c.exists()), None)
            if run_dir is None:
                vals.append(0)
                continue
            s = load_samples(run_dir)
            vals.append(pct(s, 0.99) / 1000.0)
        ax.bar(x + offset, vals, width, label=proto_label)
        for xi, v in zip(x + offset, vals):
            ax.text(xi, v * 1.05, f"{v:.0f}", ha="center", fontsize=8)
    ax.set_xticks(x)
    ax.set_xticklabels(LOSS_LABELS)
    ax.set_yscale("log")
    ax.set_xlabel("Packet loss")
    ax.set_ylabel("p99 latency (ms, log)")
    ax.set_title("p99 latency: TCP vs Homa across loss rates")
    ax.grid(True, axis="y", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    print(f"  wrote {out_path}")


def relative_degradation(out_path):
    fig, ax = plt.subplots(figsize=(8, 5))
    for (proto_label, base_name, _), marker in zip(PROTOCOLS, ["o", "s"]):
        baseline = None
        vals = []
        for tag in LOSS_TAGS:
            candidates = [
                RESULTS_DIR / f"{base_name}_{tag}",
                RESULTS_DIR / f"{base_name}_loss0p0" if tag == "loss0" else None,
            ]
            run_dir = next((c for c in candidates if c is not None and c.exists()), None)
            if run_dir is None:
                vals.append(None)
                continue
            s = load_samples(run_dir)
            p99 = pct(s, 0.99)
            if baseline is None:
                baseline = p99
            vals.append(p99 / baseline)
        ax.plot(LOSS_LABELS, vals, marker=marker, linewidth=2, label=proto_label, markersize=9)
    ax.set_xlabel("Packet loss")
    ax.set_ylabel("p99 latency / p99 at 0% loss")
    ax.set_yscale("log")
    ax.set_title("Relative p99 degradation under loss")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)
    print(f"  wrote {out_path}")


if __name__ == "__main__":
    print("Generating CDF plots...")
    cdf_plot(PROTOCOLS[0][0], PROTOCOLS[0][1], PLOTS_DIR / "homa_cdf.png")
    cdf_plot(PROTOCOLS[1][0], PROTOCOLS[1][1], PLOTS_DIR / "tcp_cdf.png")

    print("Generating percentile bars...")
    percentile_bars(PLOTS_DIR / "percentile_bars.png")

    print("Generating p99 overlay...")
    p99_overlay(PLOTS_DIR / "p99_overlay.png")

    print("Generating relative degradation...")
    relative_degradation(PLOTS_DIR / "relative_degradation.png")

    print("\nAll plots in:", PLOTS_DIR)
