#!/usr/bin/env python3

import argparse
import json
import subprocess
import os
import time
import sys
from pathlib import Path
from dataclasses import dataclass, field


@dataclass
class NodeConfig:
    hostname: str
    user: str = "root"
    role: str = "sender"


@dataclass
class ExperimentConfig:
    name: str
    protocol: str
    server: NodeConfig
    clients: list
    binary_dir: str
    output_dir: str
    params: dict = field(default_factory=dict)


def ssh_cmd(node, cmd, check=True):
    full = ["ssh", "-o", "StrictHostKeyChecking=no",
            f"{node.user}@{node.hostname}", cmd]
    return subprocess.run(full, capture_output=True, text=True, check=check)


def scp_to(node, local_path, remote_path):
    full = ["scp", "-o", "StrictHostKeyChecking=no",
            local_path, f"{node.user}@{node.hostname}:{remote_path}"]
    return subprocess.run(full, capture_output=True, text=True, check=True)


def scp_from(node, remote_path, local_path):
    full = ["scp", "-o", "StrictHostKeyChecking=no",
            f"{node.user}@{node.hostname}:{remote_path}", local_path]
    return subprocess.run(full, capture_output=True, text=True, check=True)


def deploy_binaries(nodes, binary_dir):
    for node in nodes:
        print(f"  Deploying to {node.hostname}...")
        ssh_cmd(node, "mkdir -p /tmp/dc-bench")
        for binary in ["tcp_bench", "homa_bench"]:
            src = os.path.join(binary_dir, binary)
            if os.path.exists(src):
                scp_to(node, src, f"/tmp/dc-bench/{binary}")
                ssh_cmd(node, f"chmod +x /tmp/dc-bench/{binary}")


def build_tcp_args(params):
    args = []
    for key, val in params.items():
        flag = f"--{key.replace('_', '-')}"
        if isinstance(val, bool):
            if val:
                args.append(flag)
        else:
            args.extend([flag, str(val)])
    return " ".join(args)


def run_tcp_experiment(config):
    server = config.server
    params = config.params

    server_args = f"server --port {params.get('port', 9000)}"
    if params.get("dctcp", False):
        server_args += " --dctcp"

    print(f"  Starting server on {server.hostname}...")
    ssh_cmd(server, f"nohup /tmp/dc-bench/tcp_bench {server_args} "
            f"> /tmp/dc-bench/server.log 2>&1 &")
    time.sleep(2)

    client_procs = []
    for i, client_node in enumerate(config.clients):
        client_params = dict(params)
        client_params["host"] = server.hostname
        client_params["output"] = f"/tmp/dc-bench/results_{i}"
        client_args = f"client {build_tcp_args(client_params)}"

        print(f"  Starting client {i} on {client_node.hostname}...")
        proc = subprocess.Popen(
            ["ssh", "-o", "StrictHostKeyChecking=no",
             f"{client_node.user}@{client_node.hostname}",
             f"/tmp/dc-bench/tcp_bench {client_args}"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        client_procs.append((i, client_node, proc))

    for i, node, proc in client_procs:
        stdout, stderr = proc.communicate(timeout=600)
        print(f"  Client {i} finished (exit={proc.returncode})")
        if stdout:
            print(stdout)
        if stderr:
            print(f"  STDERR: {stderr}")

    print("  Stopping server...")
    ssh_cmd(server, "pkill -f tcp_bench", check=False)

    os.makedirs(config.output_dir, exist_ok=True)
    for i, client_node, _ in client_procs:
        local_dir = os.path.join(config.output_dir, f"client_{i}")
        os.makedirs(local_dir, exist_ok=True)
        scp_from(client_node, f"/tmp/dc-bench/results_{i}/latency.csv",
                 os.path.join(local_dir, "latency.csv"))

    scp_from(server, "/tmp/dc-bench/server.log",
             os.path.join(config.output_dir, "server.log"))


def run_homa_experiment(config):
    server = config.server
    params = config.params
    port = params.get("port", 9500)
    threads = params.get("threads", 4)

    print(f"  Starting Homa server on {server.hostname}...")
    ssh_cmd(server, f"nohup /tmp/dc-bench/homa_bench server "
            f"--port {port} --threads {threads} "
            f"> /tmp/dc-bench/server.log 2>&1 &")
    time.sleep(2)

    client_procs = []
    for i, client_node in enumerate(config.clients):
        client_params = dict(params)
        client_params["host"] = server.hostname
        client_params["output"] = f"/tmp/dc-bench/results_{i}"
        client_args = f"client {build_tcp_args(client_params)}"

        print(f"  Starting client {i} on {client_node.hostname}...")
        proc = subprocess.Popen(
            ["ssh", "-o", "StrictHostKeyChecking=no",
             f"{client_node.user}@{client_node.hostname}",
             f"/tmp/dc-bench/homa_bench {client_args}"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        client_procs.append((i, client_node, proc))

    for i, node, proc in client_procs:
        stdout, stderr = proc.communicate(timeout=600)
        print(f"  Client {i} finished (exit={proc.returncode})")
        if stdout:
            print(stdout)
        if stderr:
            print(f"  STDERR: {stderr}")

    print("  Stopping server...")
    ssh_cmd(server, "pkill -f homa_bench", check=False)

    os.makedirs(config.output_dir, exist_ok=True)
    for i, client_node, _ in client_procs:
        local_dir = os.path.join(config.output_dir, f"client_{i}")
        os.makedirs(local_dir, exist_ok=True)
        scp_from(client_node, f"/tmp/dc-bench/results_{i}/latency.csv",
                 os.path.join(local_dir, "latency.csv"))


def load_experiment(config_path):
    with open(config_path) as f:
        raw = json.load(f)

    server = NodeConfig(hostname=raw["server"]["hostname"],
                        user=raw["server"].get("user", "root"))
    clients = [NodeConfig(hostname=c["hostname"], user=c.get("user", "root"))
               for c in raw["clients"]]

    return ExperimentConfig(
        name=raw["name"],
        protocol=raw["protocol"],
        server=server,
        clients=clients,
        binary_dir=raw.get("binary_dir", "./build"),
        output_dir=raw.get("output_dir", f"./results/{raw['name']}"),
        params=raw.get("params", {})
    )


def main():
    parser = argparse.ArgumentParser(description="DC benchmark orchestrator")
    parser.add_argument("config", help="Experiment config JSON file")
    parser.add_argument("--deploy", action="store_true", help="Deploy binaries first")
    args = parser.parse_args()

    config = load_experiment(args.config)
    all_nodes = [config.server] + config.clients

    if args.deploy:
        print("Deploying binaries...")
        deploy_binaries(all_nodes, config.binary_dir)

    print(f"\nRunning experiment: {config.name}")
    print(f"  Protocol: {config.protocol}")
    print(f"  Server:   {config.server.hostname}")
    print(f"  Clients:  {len(config.clients)}")

    if config.protocol == "tcp":
        run_tcp_experiment(config)
    elif config.protocol == "homa":
        run_homa_experiment(config)
    else:
        print(f"Unknown protocol: {config.protocol}", file=sys.stderr)
        sys.exit(1)

    print(f"\nResults saved to {config.output_dir}")


if __name__ == "__main__":
    main()
