#!/usr/bin/env bash

# Source this file before running CloudLab helper scripts:
#   source cloudlab/node_config.sh

# Reusable SSH naming pieces.
export DCBENCH_NODE_USER="varunm"
export DCBENCH_NODE_DOMAIN="utah.cloudlab.us"

# Only edit host short names below.
# Stress-test allocation: 9 hp-class nodes (shared machine, varunm user).
# Server = hp069. Clients = hp077..hp073.
export DCBENCH_NODE_SERVER_HOST="hp069"
export DCBENCH_NODE_CLIENT_HOSTS="hp077,hp066,hp046,hp079,hp074,hp078,hp055,hp073"

# Build full SSH targets from USER + HOST + DOMAIN.
export DCBENCH_NODE_SERVER="$DCBENCH_NODE_USER@$DCBENCH_NODE_SERVER_HOST.$DCBENCH_NODE_DOMAIN"

# Comma-separated client list.
IFS=',' read -r -a _dcbench_client_hosts <<< "$DCBENCH_NODE_CLIENT_HOSTS"
_dcbench_client_targets=()
for _dcbench_host in "${_dcbench_client_hosts[@]}"; do
	_dcbench_client_targets+=("$DCBENCH_NODE_USER@$_dcbench_host.$DCBENCH_NODE_DOMAIN")
done
export DCBENCH_NODE_CLIENTS="$(IFS=','; echo "${_dcbench_client_targets[*]}")"

export DCBENCH_SERVER="$DCBENCH_NODE_SERVER"
export DCBENCH_CLIENTS="$DCBENCH_NODE_CLIENTS"
export DCBENCH_NODES="$DCBENCH_SERVER,$DCBENCH_CLIENTS"

# Data-plane server IP seen by clients.
# dirigent-xl170 bench-LAN is 10.0.1.0/24 on ens1f1 (server = node-0 = .1).
export DCBENCH_SERVER_IP="10.0.1.1"
