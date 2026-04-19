#!/usr/bin/env python3
"""
Generate per-trial and averaged markdown reports for the fan-in scaling study.

Expected layout (produced by cloudlab/run_fanin.sh --trial N):

  results/fanin_test{TRIAL}/fanin_{FANIN}/homa_fi{FANIN}/client_*/latency.csv
  results/fanin_test{TRIAL}/fanin_{FANIN}/tcp_single_fi{FANIN}/client_*/latency.csv
  results/fanin_test{TRIAL}/fanin_{FANIN}/tcp_dctcp_fi{FANIN}/client_*/latency.csv

Outputs (to results/):
  fanin_test{TRIAL}.md        # per-trial raw tables (one per trial)
  fanin_averaged.md           # mean of latency + fairness across trials

Usage:
  python3 scripts/fanin_report.py \
      --trial 1 --trial 2 --trial 3 \
      --fan-ins 4 8 12 16 \
      --results-dir results
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np

CONFIGS = [
    # (label,     subdir_template,          pool_size_for_fairness)
    ("Homa",         "homa_fi{fi}",       1),
    ("TCP single",   "tcp_single_fi{fi}", 1),
    ("TCP DCTCP-32", "tcp_dctcp_fi{fi}",  32),
]


def load_latency_csv(path: Path) -> np.ndarray:
    lat = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            lat.append(int(row["latency_ns"]))
    return np.asarray(lat, dtype=np.float64)


def per_client_samples(exp_dir: Path) -> Dict[str, np.ndarray]:
    out: Dict[str, np.ndarray] = {}
    if not exp_dir.exists():
        return out
    for entry in sorted(exp_dir.iterdir()):
        if not entry.is_dir():
            continue
        csv_path = entry / "latency.csv"
        if csv_path.exists():
            samples = load_latency_csv(csv_path)
            if len(samples) > 0:
                out[entry.name] = samples
    return out


def latency_stats(samples_ns: np.ndarray) -> Dict[str, float]:
    us = samples_ns / 1000.0
    return {
        "count": int(len(us)),
        "mean_us": float(np.mean(us)),
        "p50_us": float(np.percentile(us, 50)),
        "p95_us": float(np.percentile(us, 95)),
        "p99_us": float(np.percentile(us, 99)),
        "p999_us": float(np.percentile(us, 99.9)),
    }


def fairness_stats(clients: Dict[str, np.ndarray],
                   pool_size: int) -> Dict[str, float]:
    if not clients:
        return {"jain": float("nan"), "cv": float("nan"), "min_max": float("nan")}
    tputs = []
    for samples in clients.values():
        mean_ns = float(np.mean(samples))
        if mean_ns <= 0:
            continue
        tputs.append(pool_size * 1e9 / mean_ns)
    if not tputs:
        return {"jain": float("nan"), "cv": float("nan"), "min_max": float("nan")}
    arr = np.asarray(tputs, dtype=np.float64)
    n = len(arr)
    denom = n * float(np.sum(arr * arr))
    jain = float(arr.sum() ** 2 / denom) if denom > 0 else float("nan")
    mean_t = float(np.mean(arr))
    cv = float(np.std(arr) / mean_t) if mean_t > 0 else float("nan")
    min_max = float(arr.min() / arr.max()) if arr.max() > 0 else float("nan")
    return {"jain": jain, "cv": cv, "min_max": min_max}


# --------------------------------------------------------------------------

def collect_one_trial(results_dir: Path,
                      trial: int,
                      fan_ins: List[int]) -> Dict[Tuple[str, int], dict]:
    """
    Returns dict keyed by (config_label, fan_in) with:
        {"latency": {...}, "fairness": {...}} or None if data missing.
    """
    out: Dict[Tuple[str, int], dict] = {}
    trial_root = results_dir / f"fanin_test{trial}"
    for fi in fan_ins:
        fi_dir = trial_root / f"fanin_{fi}"
        for label, subdir_tmpl, pool in CONFIGS:
            exp_dir = fi_dir / subdir_tmpl.format(fi=fi)
            clients = per_client_samples(exp_dir)
            if not clients:
                out[(label, fi)] = None  # type: ignore[assignment]
                continue
            merged = np.concatenate(list(clients.values()))
            out[(label, fi)] = {
                "latency": latency_stats(merged),
                "fairness": fairness_stats(clients, pool),
                "n_clients": len(clients),
                "path": str(exp_dir),
            }
    return out


# --------------------------------------------------------------------------

def fmt_latency_row(label: str, fi: int, stats: Optional[dict]) -> str:
    if stats is None:
        return (f"| {label:<13} | {fi:^6} | {'n/a':^8} | {'n/a':^8} | "
                f"{'n/a':^8} | {'n/a':^10} | {'n/a':^9} |")
    lat = stats["latency"]
    return (f"| {label:<13} | {fi:^6} | "
            f"{lat['p50_us']:>8.1f} | {lat['p95_us']:>8.1f} | "
            f"{lat['p99_us']:>8.1f} | {lat['p999_us']:>10.1f} | "
            f"{lat['mean_us']:>9.1f} |")


def fmt_fairness_row(label: str, fi: int, stats: Optional[dict]) -> str:
    if stats is None:
        return f"| {label:<13} | {fi:^6} | {'n/a':^6} | {'n/a':^5} | {'n/a':^7} |"
    f = stats["fairness"]
    return (f"| {label:<13} | {fi:^6} | "
            f"{f['jain']:>6.4f} | {f['cv']:>5.3f} | {f['min_max']:>7.3f} |")


def build_markdown(title: str,
                   table: Dict[Tuple[str, int], dict],
                   fan_ins: List[int]) -> str:
    lines: List[str] = []
    lines.append(f"# {title}\n")
    lines.append("**Workload:** Bimodal (256B small / 1MB large, bimodal_ratio=0.9), closed-loop  ")
    lines.append("**Configs:** Homa (concurrency=8), TCP single-stream (pool=1), TCP DCTCP (pool=32, size-aware)  ")
    lines.append(f"**Fan-in levels:** {', '.join(str(x) for x in fan_ins)} senders -> 1 receiver\n")

    lines.append("---\n")
    lines.append("## 1. Latency\n")
    lines.append("| Config        | Fan-in | P50 (us) | P95 (us) | P99 (us) | P99.9 (us) | Mean (us) |")
    lines.append("|---------------|--------|----------|----------|----------|------------|-----------|")
    for label, _, _ in CONFIGS:
        for fi in fan_ins:
            lines.append(fmt_latency_row(label, fi, table.get((label, fi))))
    lines.append("")

    lines.append("## 2. Fairness (Jain's Fairness Index)\n")
    lines.append("| Config        | Fan-in |  Jain  |  CV   | Min/Max |")
    lines.append("|---------------|--------|--------|-------|---------|")
    for label, _, _ in CONFIGS:
        for fi in fan_ins:
            lines.append(fmt_fairness_row(label, fi, table.get((label, fi))))
    lines.append("")

    # Gap table
    lines.append("## 3. Homa vs TCP/DCTCP P99 gap\n")
    lines.append("| Fan-in | Homa P99 | TCP1 P99 | DCTCP P99 | TCP1 / Homa | DCTCP / Homa |")
    lines.append("|--------|----------|----------|-----------|-------------|--------------|")
    for fi in fan_ins:
        h = table.get(("Homa", fi))
        t = table.get(("TCP single", fi))
        d = table.get(("TCP DCTCP-32", fi))
        if h and t and d:
            h99 = h["latency"]["p99_us"]
            t99 = t["latency"]["p99_us"]
            d99 = d["latency"]["p99_us"]
            lines.append(
                f"| {fi:^6} | {h99:>8.1f} | {t99:>8.1f} | {d99:>9.1f} | "
                f"{(t99 / h99):>11.2f} | {(d99 / h99):>12.2f} |"
            )
        else:
            lines.append(f"| {fi:^6} | n/a      | n/a      | n/a       | n/a         | n/a          |")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------

def average_trials(all_trials: List[Dict[Tuple[str, int], dict]]
                   ) -> Dict[Tuple[str, int], dict]:
    keys = set()
    for t in all_trials:
        keys.update(t.keys())

    averaged: Dict[Tuple[str, int], dict] = {}
    for key in keys:
        rows = [t.get(key) for t in all_trials if t.get(key) is not None]
        if not rows:
            averaged[key] = None  # type: ignore[assignment]
            continue

        def mean_field(section: str, field: str) -> float:
            vals = [r[section][field] for r in rows
                    if r and section in r and field in r[section]
                    and r[section][field] == r[section][field]]
            return float(np.mean(vals)) if vals else float("nan")

        averaged[key] = {
            "latency": {
                "p50_us":  mean_field("latency", "p50_us"),
                "p95_us":  mean_field("latency", "p95_us"),
                "p99_us":  mean_field("latency", "p99_us"),
                "p999_us": mean_field("latency", "p999_us"),
                "mean_us": mean_field("latency", "mean_us"),
                "count":   int(mean_field("latency", "count") or 0),
            },
            "fairness": {
                "jain":    mean_field("fairness", "jain"),
                "cv":      mean_field("fairness", "cv"),
                "min_max": mean_field("fairness", "min_max"),
            },
            "n_clients": rows[0].get("n_clients", 0),
            "n_trials":  len(rows),
        }
    return averaged


# --------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--trial", type=int, action="append", required=True,
                        help="Trial number (repeat flag for each trial, e.g. --trial 1 --trial 2)")
    parser.add_argument("--fan-ins", type=int, nargs="+", default=[4, 8, 12, 16],
                        help="Fan-in levels (default: 4 8 12 16)")
    parser.add_argument("--results-dir", type=Path, default=Path("results"),
                        help="Root results dir (default: results)")
    args = parser.parse_args()

    trials = sorted(set(args.trial))
    fan_ins = list(args.fan_ins)
    results_dir: Path = args.results_dir.resolve()

    print(f"Results dir: {results_dir}")
    print(f"Trials:      {trials}")
    print(f"Fan-ins:     {fan_ins}")

    all_tables: List[Dict[Tuple[str, int], dict]] = []
    for t in trials:
        print(f"\n--- Collecting trial {t} ---")
        table = collect_one_trial(results_dir, t, fan_ins)
        missing = [k for k, v in table.items() if v is None]
        if missing:
            print(f"  WARNING trial {t}: missing data for {len(missing)} (cfg, fan-in) pairs:")
            for k in missing[:6]:
                print(f"    - {k[0]} fan-in={k[1]}")
            if len(missing) > 6:
                print(f"    ... ({len(missing) - 6} more)")
        all_tables.append(table)

        md = build_markdown(
            title=f"Fan-in Scaling Study - Trial {t} (raw)",
            table=table,
            fan_ins=fan_ins,
        )
        out_path = results_dir / f"fanin_test{t}.md"
        out_path.write_text(md)
        print(f"  wrote {out_path}")

    print("\n--- Averaging across trials ---")
    avg_table = average_trials(all_tables)
    md = build_markdown(
        title=f"Fan-in Scaling Study - Averaged across {len(trials)} trials ({trials})",
        table=avg_table,
        fan_ins=fan_ins,
    )
    out_path = results_dir / "fanin_averaged.md"
    out_path.write_text(md)
    print(f"  wrote {out_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
