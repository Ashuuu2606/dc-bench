#!/usr/bin/env python3
"""Run experiments under tc netem packet loss on the server interface."""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def ssh(host, user, cmd, check=False):
    return subprocess.run(
        ["ssh", "-o", "StrictHostKeyChecking=no", f"{user}@{host}", cmd],
        capture_output=True, text=True, check=check,
    )


def detect_bench_iface(host, user):
    r = ssh(host, user, "ip -4 -o addr show | awk '/inet 10\\./{print $2; exit}'")
    iface = r.stdout.strip()
    if not iface:
        raise RuntimeError(f"no 10.x.x.x interface found on {host}")
    return iface


def apply_netem(host, user, iface, loss_pct):
    ssh(host, user, f"sudo tc qdisc del dev {iface} root 2>/dev/null; true")
    if loss_pct > 0:
        r = ssh(host, user, f"sudo tc qdisc add dev {iface} root netem loss {loss_pct}%")
        if r.returncode != 0:
            raise RuntimeError(f"tc netem add failed: {r.stderr.strip()}")
        print(f"  applied netem loss {loss_pct}% on {iface}")


def clear_netem(host, user, iface):
    ssh(host, user, f"sudo tc qdisc del dev {iface} root 2>/dev/null; true")


def main():
    ap = argparse.ArgumentParser(description="tc netem stress sweep")
    ap.add_argument("configs", nargs="+", help="experiment config JSONs")
    ap.add_argument("--loss", nargs="+", type=float, default=[0, 0.1, 1.0, 5.0],
                    help="loss rates in percent (default: 0 0.1 1 5)")
    ap.add_argument("--iface", default=None, help="server interface (default: auto-detect 10.x.x.x iface)")
    args = ap.parse_args()

    for config_path in args.configs:
        with open(config_path) as f:
            cfg = json.load(f)
        server = cfg["server"]
        base_output = cfg.get("output_dir", f"./results/{cfg['name']}")
        iface = args.iface or detect_bench_iface(server["hostname"], server["user"])
        print(f"  bench iface on {server['hostname']}: {iface}")

        for loss in args.loss:
            print(f"\n=== {cfg['name']}  loss={loss}% ===")
            try:
                apply_netem(server["hostname"], server["user"], iface, loss)
                rc = subprocess.run(
                    ["python3", "scripts/orchestrate.py", config_path]
                ).returncode
                if rc != 0:
                    print(f"  experiment failed (exit={rc})")
                    continue
                tag = f"loss{str(loss).replace('.', 'p')}"
                dest = f"{base_output}_{tag}"
                if Path(base_output).exists():
                    if Path(dest).exists():
                        shutil.rmtree(dest)
                    shutil.move(base_output, dest)
                    print(f"  results -> {dest}")
            finally:
                clear_netem(server["hostname"], server["user"], iface)


if __name__ == "__main__":
    main()
