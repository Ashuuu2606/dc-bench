#!/usr/bin/env python3
"""
Generate PNG plots for the TCP-vs-Homa project report.

Inputs:
  - Hard-coded midterm-report table data (Sections 4.2 - 4.5).
  - Per-trial fan-in results produced by scripts/fanin_report.py
    (reads latency.csv under results/fanin_test{1,2,3}/fanin_*/<proto>/client_*).

Outputs:
  plots/fig01_h1_extreme_bimodal.png            Table 4.2.1
  plots/fig02_h1_moderate_bimodal.png           Table 4.2.2
  plots/fig03_h1_pareto.png                     Table 4.2.3
  plots/fig04_h1_openloop_bimodal.png           Table 4.2.4
  plots/fig05_h2_dctcp_vs_tcp.png               Table 4.3
  plots/fig06_h3_pool_scaling.png               Table 4.4.1
  plots/fig07_h3_nodelay_sensitivity.png        Table 4.4.2
  plots/fig08_c6525_aggregate.png               Table 4.5.2
  plots/fig09_fanin_p99_latency.png             new fan-in study
  plots/fig10_fanin_percentile_stack.png        new fan-in study
  plots/fig11_fanin_gap_ratio.png               new fan-in study
  plots/fig12_fanin_fairness.png                new fan-in study
  plots/fig13_fanin_p99_errorbars.png           new fan-in study

Usage:
    /tmp/dcbench_venv/bin/python scripts/make_plots.py
"""
from __future__ import annotations

import csv
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Make matplotlib headless + writable cache
os.environ.setdefault("MPLCONFIGDIR", "/tmp/mpl_cache")
os.makedirs(os.environ["MPLCONFIGDIR"], exist_ok=True)

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

REPO = Path(__file__).resolve().parent.parent
PLOT_DIR = REPO / "plots"
PLOT_DIR.mkdir(exist_ok=True)

# --- Style ---------------------------------------------------------------
plt.rcParams.update({
    "figure.dpi":     130,
    "savefig.dpi":    150,
    "figure.figsize": (8.5, 5.0),
    "axes.grid":      True,
    "grid.alpha":     0.3,
    "grid.linestyle": "--",
    "axes.spines.top":   False,
    "axes.spines.right": False,
    "font.size":         11,
    "axes.titlesize":    12,
    "axes.labelsize":    11,
    "legend.fontsize":   9,
    "xtick.labelsize":   10,
    "ytick.labelsize":   10,
})

COLOR = {
    "homa":  "#1b9e77",
    "tcp1":  "#d95f02",
    "pool":  "#7570b3",
    "dctcp": "#e7298a",
    "other": "#666666",
}

PERCENTILES = ["P50", "P95", "P99", "P99.9"]
PCT_COLORS  = ["#4dac26", "#b8e186", "#f1a340", "#d7191c"]


def save(fig, name: str, note: Optional[str] = None) -> None:
    # Footer `note` intentionally dropped - captions are added in the final report.
    fig.tight_layout()
    out = PLOT_DIR / name
    fig.savefig(out, bbox_inches="tight")
    plt.close(fig)
    print(f"  wrote {out.relative_to(REPO)}")


def grouped_bar_log(ax, configs, values_by_pct, title, ylabel="Latency (us)"):
    """configs is list[str]; values_by_pct is list[list[float]] (one list per pct)."""
    n_cfg = len(configs)
    n_pct = len(PERCENTILES)
    x = np.arange(n_cfg)
    width = 0.8 / n_pct
    for i, (pct, vals) in enumerate(zip(PERCENTILES, values_by_pct)):
        ax.bar(x + (i - (n_pct - 1) / 2) * width, vals, width,
               label=pct, color=PCT_COLORS[i], edgecolor="black", linewidth=0.4)
    ax.set_yscale("log")
    ax.set_xticks(x)
    ax.set_xticklabels(configs, rotation=15, ha="right")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.legend(title="Percentile", ncol=len(PERCENTILES), frameon=False,
              loc="upper left", bbox_to_anchor=(0.0, 1.0))


# =========================================================================
# MIDTERM REPORT PLOTS
# =========================================================================

def plot_h1_extreme_bimodal():
    """Table 4.2.1 - extreme bimodal 256B/1MB, 4 senders, xl170."""
    configs = ["Homa\n(conc=8)", "TCP\nsingle", "TCP pool=32\nround-robin", "TCP pool=32\nsize-aware"]
    p50  = [191,  99,  2610, 2730]
    p95  = [234, 1240, 18650, 14778]
    p99  = [265, 1751, 31944, 28755]
    p999 = [354, 2221, 70360, 49032]

    fig, ax = plt.subplots()
    grouped_bar_log(ax, configs, [p50, p95, p99, p999],
        title="H1 - Extreme bimodal (256 B / 1 MB), 4-to-1 incast, xl170")
    save(fig, "fig01_h1_extreme_bimodal.png")


def plot_h1_moderate_bimodal():
    """Table 4.2.2."""
    configs = ["Homa\n(conc=8)", "TCP\nsingle", "TCP pool=32\nround-robin", "TCP pool=32\nsize-aware"]
    p50  = [105,  79, 232, 236]
    p95  = [740, 187, 549, 525]
    p99  = [1201, 255, 742, 694]
    p999 = [1626, 335, 1211, 966]

    fig, ax = plt.subplots()
    grouped_bar_log(ax, configs, [p50, p95, p99, p999],
        title="H1 - Moderate bimodal (256 B / 64 KB), 4-to-1 incast, xl170")
    save(fig, "fig02_h1_moderate_bimodal.png")


def plot_h1_pareto():
    """Table 4.2.3."""
    configs = ["Homa\n(conc=8)", "TCP\nsingle", "TCP pool=32\nround-robin", "TCP pool=32\nsize-aware"]
    p50  = [163,  62, 139, 145]
    p95  = [257, 128, 277, 317]
    p99  = [318, 128, 381, 558]
    p999 = [531, 230, 850, 1625]

    fig, ax = plt.subplots()
    grouped_bar_log(ax, configs, [p50, p95, p99, p999],
        title="H1 - Pareto heavy-tail (shape=1.5, scale=256 B), xl170")
    save(fig, "fig03_h1_pareto.png")


def plot_h1_openloop():
    """Table 4.2.4."""
    labels = ["TCP single\n5K rps", "TCP pool=32 SA\n5K rps",
              "TCP single\n10K rps", "TCP pool=32 SA\n10K rps"]
    p50  = [ 96,  96,  80,  92]
    p95  = [214, 220, 185, 220]
    p99  = [286, 284, 252, 287]
    p999 = [398, 366, 368, 376]

    fig, ax = plt.subplots()
    x = np.arange(len(labels))
    width = 0.2
    for i, (p, vals, c) in enumerate(zip(PERCENTILES, [p50, p95, p99, p999], PCT_COLORS)):
        ax.bar(x + (i - 1.5) * width, vals, width, label=p, color=c,
               edgecolor="black", linewidth=0.4)
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel("Latency (us)")
    ax.set_title("Open-loop bimodal 256 B / 64 KB, Poisson arrivals, xl170")
    ax.legend(ncol=4, title="Percentile", frameon=False)
    save(fig, "fig04_h1_openloop_bimodal.png")


def plot_h2_dctcp_vs_tcp():
    """Table 4.3 - DCTCP vs TCP percentage delta in P99."""
    scenarios = [
        "Bimodal 1MB\nsingle",
        "Bimodal 64KB\nsingle",
        "Pareto\nsingle",
        "Pareto\npool=32",
    ]
    dctcp = [1720, 259,  137,  506]
    tcp   = [1751, 255,  128,  558]
    delta_pct = [(d - t) / t * 100.0 for d, t in zip(dctcp, tcp)]

    fig, ax = plt.subplots()
    colors = ["#1a9641" if v < 0 else "#d7191c" for v in delta_pct]
    bars = ax.bar(scenarios, delta_pct, color=colors, edgecolor="black", linewidth=0.5)
    ax.axhline(0, color="black", lw=0.8)
    # Put labels just inside the bar (against the zero line) to avoid title/axis collision.
    for b, v in zip(bars, delta_pct):
        ax.text(b.get_x() + b.get_width() / 2,
                0.35 if v > 0 else -0.35,
                f"{v:+.1f}%", ha="center",
                va="bottom" if v > 0 else "top",
                fontsize=11, fontweight="bold", color="black")

    ax.set_ylabel("P99 latency delta vs standard TCP (%)")
    ax.set_ylim(-13, 11)
    ax.set_title("H2 - DCTCP P99 latency vs standard TCP (negative = DCTCP wins)")
    from matplotlib.patches import Patch
    ax.legend(handles=[Patch(color="#1a9641", label="DCTCP wins"),
                       Patch(color="#d7191c", label="DCTCP hurts")],
              loc="upper right", frameon=False)
    save(fig, "fig05_h2_dctcp_vs_tcp.png")


def plot_h3_pool_scaling():
    """Table 4.4.1 - pool size vs P99 vs throughput."""
    pools = [1, 16, 32, 64]
    p50   = [59, 133, 171, 229]
    p99   = [116, 274, 549, 936]
    p999  = [208, 377, 1183, 4107]
    tput  = [14661, 95299, 103099, 116553]

    fig, ax1 = plt.subplots()
    x = np.arange(len(pools))
    w = 0.25
    ax1.bar(x - w, p50,  w, label="P50",   color=PCT_COLORS[0], edgecolor="black", linewidth=0.4)
    ax1.bar(x,     p99,  w, label="P99",   color=PCT_COLORS[2], edgecolor="black", linewidth=0.4)
    ax1.bar(x + w, p999, w, label="P99.9", color=PCT_COLORS[3], edgecolor="black", linewidth=0.4)
    ax1.set_yscale("log")
    ax1.set_xticks(x)
    ax1.set_xticklabels([f"pool={p}" for p in pools])
    ax1.set_ylabel("Latency (us, log)")
    ax1.legend(loc="upper left", frameon=False, title="Latency")

    ax2 = ax1.twinx()
    ax2.plot(x, tput, "o-", color="black", lw=2, ms=7, label="Throughput (rps)")
    ax2.set_ylabel("Throughput (rps)")
    ax2.grid(False)
    ax2.legend(loc="upper right", frameon=False)

    ax1.set_title("H3 - Pool-size scaling, fixed 1 KB messages, xl170")
    save(fig, "fig06_h3_pool_scaling.png")


def plot_h3_nodelay():
    """Table 4.4.2 - NODELAY sensitivity."""
    settings = ["NODELAY = ON\n(correct)", "NODELAY = OFF\n(Nagle + delayed ACK)"]
    p50  = [ 52,   76]
    p99  = [111,  278]
    p999 = [152, 44218]
    tput = [16806, 1868]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.5),
                                   gridspec_kw={"width_ratios": [1.3, 1]})

    x = np.arange(len(settings))
    w = 0.25
    ax1.bar(x - w, p50,  w, label="P50",   color=PCT_COLORS[0], edgecolor="black", linewidth=0.4)
    ax1.bar(x,     p99,  w, label="P99",   color=PCT_COLORS[2], edgecolor="black", linewidth=0.4)
    ax1.bar(x + w, p999, w, label="P99.9", color=PCT_COLORS[3], edgecolor="black", linewidth=0.4)
    ax1.set_yscale("log")
    ax1.set_xticks(x)
    ax1.set_xticklabels(settings)
    ax1.set_ylabel("Latency (us, log)")
    ax1.legend(ncol=3, frameon=False, loc="upper left")
    ax1.set_title("TCP_NODELAY sensitivity (256 B, pool=1)")

    ax2.bar(settings, tput, color=[COLOR["homa"], COLOR["dctcp"]],
            edgecolor="black", linewidth=0.4)
    ax2.set_ylabel("Throughput (rps)")
    ax2.set_title("Throughput")
    for i, v in enumerate(tput):
        ax2.text(i, v + 500, f"{v:,}", ha="center", fontsize=10, fontweight="bold")

    save(fig, "fig07_h3_nodelay_sensitivity.png")


def plot_c6525_aggregate():
    """Table 4.5.2."""
    configs = [
        "homa_default",
        "homa_default_new",
        "tcp_single",
        "tcp_single_new",
        "tcp_pooled_32",
        "tcp_pooled_32_new",
        "tcp_dctcp_pooled_32",
        "tcp_dctcp_pooled_32_new",
    ]
    p50   = [168.1, 100.8, 63.2, 10521.8, 1234.3, 80268.1, 1321.5, 66544.7]
    p95   = [172.6, 168.2, 2127.9, 13407.7, 13297.2, 764666.7, 15597.2, 793481.5]
    p99   = [177.5, 177.4, 2900.3, 15810.0, 44552.9, 1047017.3, 52000.6, 1103647.4]
    p999  = [202.7, 190.1, 4621.4, 19746.4, 119737.4, 1623987.2, 113081.9, 1900414.9]

    fig, ax = plt.subplots(figsize=(11, 5))
    x = np.arange(len(configs))
    w = 0.2
    for i, (p, vals, c) in enumerate(zip(PERCENTILES, [p50, p95, p99, p999], PCT_COLORS)):
        ax.bar(x + (i - 1.5) * w, vals, w, label=p, color=c,
               edgecolor="black", linewidth=0.3)
    ax.set_yscale("log")
    ax.set_xticks(x)
    ax.set_xticklabels(configs, rotation=25, ha="right")
    ax.set_ylabel("Latency (us, log)")
    ax.set_title("c6525 aggregate summary (Table 4.5.2)")
    ax.legend(ncol=4, title="Percentile", frameon=False, loc="upper left")
    save(fig, "fig08_c6525_aggregate.png")


# =========================================================================
# NEW FAN-IN STUDY PLOTS
# =========================================================================

def load_latency_ns(path: Path) -> np.ndarray:
    lat = []
    with open(path) as f:
        rd = csv.DictReader(f)
        for row in rd:
            lat.append(int(row["latency_ns"]))
    return np.asarray(lat, dtype=np.float64)


def collect_per_trial(fan_ins: List[int], trials: List[int]
                      ) -> Dict[Tuple[str, int, int], dict]:
    """
    Returns {(proto_label, fi, trial): {p50, p95, p99, p999, mean, clients: {name: tputs}}}
    """
    protos = [
        ("Homa",         "homa_fi{fi}",       1),
        ("TCP single",   "tcp_single_fi{fi}", 1),
        ("TCP DCTCP-32", "tcp_dctcp_fi{fi}",  32),
    ]
    out: Dict[Tuple[str, int, int], dict] = {}
    for t in trials:
        root = REPO / "results" / f"fanin_test{t}"
        if not root.exists():
            continue
        for fi in fan_ins:
            fi_dir = root / f"fanin_{fi}"
            for label, tmpl, pool in protos:
                exp_dir = fi_dir / tmpl.format(fi=fi)
                if not exp_dir.exists():
                    continue
                merged = []
                clients: Dict[str, np.ndarray] = {}
                for client in sorted(exp_dir.iterdir()):
                    if client.is_dir():
                        csv_path = client / "latency.csv"
                        if csv_path.exists():
                            samples = load_latency_ns(csv_path)
                            if len(samples):
                                clients[client.name] = samples
                                merged.append(samples)
                if not merged:
                    continue
                all_us = np.concatenate(merged) / 1000.0
                # Throughputs per client for fairness
                tputs = np.array([pool * 1e9 / float(np.mean(s))
                                  for s in clients.values()])
                jain = (tputs.sum() ** 2) / (len(tputs) * np.sum(tputs ** 2))
                cv = float(np.std(tputs) / np.mean(tputs)) if tputs.mean() > 0 else float("nan")
                min_max = float(tputs.min() / tputs.max()) if tputs.max() > 0 else float("nan")
                out[(label, fi, t)] = {
                    "p50":  float(np.percentile(all_us, 50)),
                    "p95":  float(np.percentile(all_us, 95)),
                    "p99":  float(np.percentile(all_us, 99)),
                    "p999": float(np.percentile(all_us, 99.9)),
                    "mean": float(np.mean(all_us)),
                    "jain": float(jain),
                    "cv":   cv,
                    "min_max": min_max,
                    "n_clients": len(clients),
                }
    return out


def average_across_trials(per_trial: Dict[Tuple[str, int, int], dict],
                          trials: List[int],
                          fan_ins: List[int]
                          ) -> Dict[Tuple[str, int], dict]:
    """Return {(proto, fi): {metric: (mean, min, max, std)}}"""
    protos = ["Homa", "TCP single", "TCP DCTCP-32"]
    fields = ["p50", "p95", "p99", "p999", "mean", "jain", "cv", "min_max"]
    agg: Dict[Tuple[str, int], dict] = {}
    for proto in protos:
        for fi in fan_ins:
            rows = [per_trial[(proto, fi, t)]
                    for t in trials if (proto, fi, t) in per_trial]
            if not rows:
                continue
            entry: Dict[str, Tuple[float, float, float, float]] = {}
            for f in fields:
                vals = np.array([r[f] for r in rows])
                entry[f] = (float(vals.mean()), float(vals.min()),
                            float(vals.max()), float(vals.std()))
            agg[(proto, fi)] = entry
    return agg


def plot_fanin_p99(avg):
    fan_ins = sorted({fi for (_, fi) in avg})
    fig, ax = plt.subplots()
    styles = [("Homa", COLOR["homa"], "o-"),
              ("TCP single", COLOR["tcp1"], "s-"),
              ("TCP DCTCP-32", COLOR["dctcp"], "^-")]
    for proto, color, style in styles:
        ys = [avg[(proto, fi)]["p99"][0] for fi in fan_ins]
        ax.plot(fan_ins, ys, style, color=color, lw=2, ms=8, label=proto)
        for fi, y in zip(fan_ins, ys):
            ax.annotate(f"{y:,.0f}", (fi, y),
                        textcoords="offset points", xytext=(0, 7),
                        ha="center", fontsize=8, color=color)
    ax.set_yscale("log")
    ax.set_xlabel("Fan-in (number of senders)")
    ax.set_ylabel("P99 latency (us, log)")
    ax.set_xticks(fan_ins)
    ax.set_title("Fan-in scaling - P99 latency vs number of senders (avg of 3 trials)")
    ax.legend(frameon=False, loc="upper left")
    save(fig, "fig09_fanin_p99_latency.png")


def plot_fanin_percentile_stack(avg):
    fan_ins = sorted({fi for (_, fi) in avg})
    fig, axes = plt.subplots(1, 3, figsize=(13.5, 4.5), sharey=False)
    protos = [("Homa", COLOR["homa"]),
              ("TCP single", COLOR["tcp1"]),
              ("TCP DCTCP-32", COLOR["dctcp"])]
    for ax, (proto, color) in zip(axes, protos):
        for p, key, c in zip(PERCENTILES, ["p50", "p95", "p99", "p999"], PCT_COLORS):
            ys = [avg[(proto, fi)][key][0] for fi in fan_ins]
            ax.plot(fan_ins, ys, "o-", color=c, lw=2, ms=6, label=p)
        ax.set_yscale("log")
        ax.set_xticks(fan_ins)
        ax.set_xlabel("Fan-in")
        ax.set_title(proto)
        ax.grid(alpha=0.3, linestyle="--")
    axes[0].set_ylabel("Latency (us, log)")
    axes[-1].legend(title="Percentile", frameon=False,
                    loc="center left", bbox_to_anchor=(1.02, 0.5))
    fig.suptitle("Fan-in scaling - full latency percentile stack per protocol",
                 y=1.02, fontsize=12)
    save(fig, "fig10_fanin_percentile_stack.png")


def plot_fanin_gap_ratio(avg):
    fan_ins = sorted({fi for (_, fi) in avg})
    tcp_ratio   = [avg[("TCP single", fi)]["p99"][0]   / avg[("Homa", fi)]["p99"][0]
                   for fi in fan_ins]
    dctcp_ratio = [avg[("TCP DCTCP-32", fi)]["p99"][0] / avg[("Homa", fi)]["p99"][0]
                   for fi in fan_ins]

    fig, ax = plt.subplots()
    ax.plot(fan_ins, tcp_ratio,   "s-", color=COLOR["tcp1"],  lw=2, ms=8,
            label="TCP single / Homa")
    ax.plot(fan_ins, dctcp_ratio, "^-", color=COLOR["dctcp"], lw=2, ms=8,
            label="TCP DCTCP-32 / Homa")
    for fi, y in zip(fan_ins, tcp_ratio):
        ax.annotate(f"{y:.1f}x", (fi, y), xytext=(0, 7),
                    textcoords="offset points", ha="center",
                    fontsize=9, color=COLOR["tcp1"])
    for fi, y in zip(fan_ins, dctcp_ratio):
        ax.annotate(f"{y:.0f}x", (fi, y), xytext=(0, 7),
                    textcoords="offset points", ha="center",
                    fontsize=9, color=COLOR["dctcp"])
    ax.set_yscale("log")
    ax.set_xlabel("Fan-in (number of senders)")
    ax.set_ylabel("P99 ratio vs Homa (log)")
    ax.set_xticks(fan_ins)
    ax.set_title("Fan-in scaling - P99 ratio vs Homa")
    ax.legend(frameon=False, loc="upper left")
    ax.axhline(1.0, color="black", lw=0.6, linestyle="--", alpha=0.5)
    save(fig, "fig11_fanin_gap_ratio.png")


def plot_fanin_fairness(avg):
    fan_ins = sorted({fi for (_, fi) in avg})

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.5))

    styles = [("Homa", COLOR["homa"], "o-"),
              ("TCP single", COLOR["tcp1"], "s-"),
              ("TCP DCTCP-32", COLOR["dctcp"], "^-")]

    for proto, color, style in styles:
        jy = [avg[(proto, fi)]["jain"][0]    for fi in fan_ins]
        my = [avg[(proto, fi)]["min_max"][0] for fi in fan_ins]
        ax1.plot(fan_ins, jy, style, color=color, lw=2, ms=7, label=proto)
        ax2.plot(fan_ins, my, style, color=color, lw=2, ms=7, label=proto)

    ax1.set_xlabel("Fan-in")
    ax1.set_ylabel("Jain's fairness index")
    ax1.set_title("Jain's fairness (1.0 = perfectly fair)")
    ax1.set_xticks(fan_ins)
    ax1.set_ylim(0.9, 1.01)
    ax1.legend(frameon=False, loc="lower left")

    ax2.set_xlabel("Fan-in")
    ax2.set_ylabel("Min / Max throughput ratio")
    ax2.set_title("Min/Max ratio (higher = more even per-sender tput)")
    ax2.set_xticks(fan_ins)
    ax2.set_ylim(0, 1.0)
    ax2.legend(frameon=False, loc="upper right")

    fig.suptitle("Fan-in scaling - fairness across senders", y=1.02, fontsize=12)
    save(fig, "fig12_fanin_fairness.png")


def plot_fanin_errorbars(avg):
    fan_ins = sorted({fi for (_, fi) in avg})
    fig, ax = plt.subplots()
    styles = [("Homa", COLOR["homa"], "o"),
              ("TCP single", COLOR["tcp1"], "s"),
              ("TCP DCTCP-32", COLOR["dctcp"], "^")]
    for proto, color, marker in styles:
        means = np.array([avg[(proto, fi)]["p99"][0] for fi in fan_ins])
        lo    = np.array([avg[(proto, fi)]["p99"][1] for fi in fan_ins])
        hi    = np.array([avg[(proto, fi)]["p99"][2] for fi in fan_ins])
        yerr = np.vstack([means - lo, hi - means])
        ax.errorbar(fan_ins, means, yerr=yerr, fmt=marker + "-",
                    color=color, lw=2, ms=8, capsize=5, label=proto)
    ax.set_yscale("log")
    ax.set_xticks(fan_ins)
    ax.set_xlabel("Fan-in")
    ax.set_ylabel("P99 latency (us, log)")
    ax.set_title("Fan-in scaling - P99 latency with trial-to-trial range (min/max of 3 trials)")
    ax.legend(frameon=False, loc="upper left")
    save(fig, "fig13_fanin_p99_errorbars.png")


# =========================================================================

def main():
    print(f"Writing plots under {PLOT_DIR.relative_to(REPO)}/")

    # ---- midterm ------------------------------------------------------
    plot_h1_extreme_bimodal()
    plot_h1_moderate_bimodal()
    plot_h1_pareto()
    plot_h1_openloop()
    plot_h2_dctcp_vs_tcp()
    plot_h3_pool_scaling()
    plot_h3_nodelay()
    plot_c6525_aggregate()

    # ---- fan-in (needs per-trial raw CSVs) ---------------------------
    fan_ins = [4, 8, 12, 16]
    trials  = [1, 2, 3]

    # Check that at least one raw-CSV dir exists
    if any((REPO / "results" / f"fanin_test{t}").exists() for t in trials):
        per_trial = collect_per_trial(fan_ins, trials)
        if per_trial:
            avg = average_across_trials(per_trial, trials, fan_ins)
            plot_fanin_p99(avg)
            plot_fanin_percentile_stack(avg)
            plot_fanin_gap_ratio(avg)
            plot_fanin_fairness(avg)
            plot_fanin_errorbars(avg)
        else:
            print("  (no per-trial CSVs found; skipping fig09-fig13)")
    else:
        print("  (results/fanin_test* directories absent; skipping fig09-fig13)")

    print("\nDone. See plots/*.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
