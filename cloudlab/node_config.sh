#!/usr/bin/env bash

# Source this file before running CloudLab helper scripts:
#   source cloudlab/node_config.sh

# Reusable SSH naming pieces.
export DCBENCH_NODE_USER="himanish"
export DCBENCH_NODE_DOMAIN="utah.cloudlab.us"

# Only edit host short names below.
export DCBENCH_NODE_SERVER_HOST="hp078"
export DCBENCH_NODE_CLIENT_HOSTS="hp073,hp074,hp060,hp171,hp188,hp052,hp172,hp077,hp054,hp046,hp069,hp079"

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
export DCBENCH_SERVER_IP="10.10.1.1"