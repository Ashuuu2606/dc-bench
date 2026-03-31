#!/usr/bin/env bash

# Source this file before running CloudLab helper scripts:
#   source cloudlab/node_config.sh

# Name your CloudLab nodes once here.
export DCBENCH_NODE_SERVER="Ashutosh@hp034.utah.cloudlab.us"

# Comma-separated client list.
export DCBENCH_NODE_CLIENTS="Ashutosh@hp037.utah.cloudlab.us,\
Ashutosh@hp004.utah.cloudlab.us,\
Ashutosh@hp024.utah.cloudlab.us,\
Ashutosh@hp008.utah.cloudlab.us"

export DCBENCH_SERVER="$DCBENCH_NODE_SERVER"
export DCBENCH_CLIENTS="$DCBENCH_NODE_CLIENTS"
export DCBENCH_NODES="$DCBENCH_SERVER,$DCBENCH_CLIENTS"

# Data-plane server IP seen by clients.
export DCBENCH_SERVER_IP="10.10.1.1"
