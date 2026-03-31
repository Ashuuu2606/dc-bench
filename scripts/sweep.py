#!/usr/bin/env python3

import argparse
import json
import subprocess
import os
import itertools
import copy
from pathlib import Path


def generate_sweep_configs(base_config, sweep_params):
    keys = list(sweep_params.keys())
    value_lists = [sweep_params[k] for k in keys]

    configs = []
    for combo in itertools.product(*value_lists):
        cfg = copy.deepcopy(base_config)
        name_parts = [base_config["name"]]
        for key, val in zip(keys, combo):
            cfg["params"][key] = val
            name_parts.append(f"{key}={val}")
        cfg["name"] = "_".join(str(p) for p in name_parts)
        cfg["output_dir"] = os.path.join(
            base_config.get("output_dir", "./results"), cfg["name"]
        )
        configs.append(cfg)

    return configs


def main():
    parser = argparse.ArgumentParser(description="Parameter sweep runner")
    parser.add_argument("base_config", help="Base experiment config JSON")
    parser.add_argument("sweep_config", help="Sweep parameters JSON")
    parser.add_argument("--deploy", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    with open(args.base_config) as f:
        base = json.load(f)
    with open(args.sweep_config) as f:
        sweep = json.load(f)

    configs = generate_sweep_configs(base, sweep)
    print(f"Generated {len(configs)} experiment configurations:")
    for cfg in configs:
        print(f"  {cfg['name']}")

    if args.dry_run:
        return

    home_tmp = os.path.join(os.path.expanduser("~"), "tmp")
    os.makedirs(home_tmp, exist_ok=True)

    for i, cfg in enumerate(configs):
        tmp_path = os.path.join(home_tmp, f"sweep_config_{i}.json")
        with open(tmp_path, "w") as f:
            json.dump(cfg, f, indent=2)

        print(f"\n{'='*60}")
        print(f"Running [{i+1}/{len(configs)}]: {cfg['name']}")
        print(f"{'='*60}")

        cmd = ["python3", "scripts/orchestrate.py", tmp_path]
        if args.deploy and i == 0:
            cmd.append("--deploy")

        subprocess.run(cmd, check=True)
        os.unlink(tmp_path)

    print(f"\nAll {len(configs)} experiments complete.")
    print("Analyze with: python3 scripts/analyze.py results/*")
    print("Plot with:    python3 scripts/plot.py results/*")


if __name__ == "__main__":
    main()
