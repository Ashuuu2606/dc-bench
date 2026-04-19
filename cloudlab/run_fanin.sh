#!/usr/bin/env bash
# Fan-in scaling study: generates JSON configs and runs them through
# scripts/orchestrate.py, then analyzes with scripts/analyze.py.
#
# Usage: bash cloudlab/run_fanin.sh [--trial N] [--fan-ins "4 8 12 16"] [--dry-run]
#
# With --trial N, output goes to:
#   results/fanin_test${N}/fanin_${FANIN}/{homa_fi${FANIN},tcp_single_fi${FANIN},tcp_dctcp_fi${FANIN}}
# Default trial = 1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/node_config.sh"

FANIN_LEVELS=(4 8 12 16)
TRIAL=1
DRY_RUN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --trial)    TRIAL="$2"; shift 2 ;;
        --fan-ins)  read -r -a FANIN_LEVELS <<< "$2"; shift 2 ;;
        --dry-run)  DRY_RUN=1; shift ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--trial N] [--fan-ins \"4 8 12 16\"] [--dry-run]"
            exit 0 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

IFS=',' read -r -a ALL_CLIENT_HOSTS <<< "$DCBENCH_NODE_CLIENT_HOSTS"
SERVER_HOST="$DCBENCH_NODE_SERVER_HOST.$DCBENCH_NODE_DOMAIN"
USER="$DCBENCH_NODE_USER"

TRIAL_ROOT="$REPO_ROOT/results/fanin_test${TRIAL}"

make_config() {
    local out_file="$1"
    local name="$2"
    local protocol="$3"
    local out_dir="$4"
    shift 4
    local client_hosts=("$@")

    python3 - "$out_file" "$name" "$protocol" "$SERVER_HOST" "$USER" \
              "$out_dir" "${client_hosts[@]}" <<'PYEOF'
import json, sys

out_file   = sys.argv[1]
name       = sys.argv[2]
protocol   = sys.argv[3]
server_host= sys.argv[4]
user       = sys.argv[5]
out_dir    = sys.argv[6]
clients    = sys.argv[7:]

base_params = dict(
    dist="bimodal",
    bimodal_small=256,
    bimodal_large=1048576,
    bimodal_ratio=0.9,
    requests=100000,
    warmup=5000,
    cpu_monitor=True,
)

if protocol == "tcp_single":
    params = {**base_params, "port": 9000, "pool_size": 1}
    protocol_key = "tcp"
elif protocol == "tcp_dctcp":
    params = {**base_params, "port": 9000,
              "pool_size": 32, "scheduling": "size_aware", "dctcp": True}
    protocol_key = "tcp"
elif protocol == "homa":
    params = {**base_params, "port": 9500, "threads": 4, "concurrency": 8}
    protocol_key = "homa"
else:
    raise ValueError(f"Unknown protocol variant: {protocol}")

config = {
    "name": name,
    "protocol": protocol_key,
    "server": {"hostname": server_host, "user": user},
    "clients": [{"hostname": h, "user": user} for h in clients],
    "binary_dir": "./build",
    "output_dir": out_dir,
    "params": params,
}
with open(out_file, "w") as f:
    json.dump(config, f, indent=2)
print(f"  wrote {out_file}")
PYEOF
}

run_experiment() {
    local config_file="$1"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] python scripts/orchestrate.py $config_file"
    else
        python3 "$REPO_ROOT/scripts/orchestrate.py" "$config_file"
    fi
}

analyze() {
    local fanin="$1"
    local results_dir="$TRIAL_ROOT/fanin_${fanin}"
    echo ""
    echo "--- Analysis (trial=${TRIAL}): fan-in=$fanin ---"
    python3 "$REPO_ROOT/scripts/analyze.py" \
        "$results_dir/homa_fi${fanin}" \
        "$results_dir/tcp_single_fi${fanin}" \
        "$results_dir/tcp_dctcp_fi${fanin}" \
        --labels "homa-${fanin}" "tcp1-${fanin}" "dctcp32-${fanin}"

    echo ""
    python3 "$REPO_ROOT/scripts/fairness.py" \
        "$results_dir/homa_fi${fanin}" \
        "$results_dir/tcp_single_fi${fanin}" \
        "$results_dir/tcp_dctcp_fi${fanin}" \
        --labels "homa-${fanin}" "tcp1-${fanin}" "dctcp32-${fanin}" \
        --pool-size 32
}

# ---------------------------------------------------------------------------

echo "=== Fan-in scaling study (trial=${TRIAL}) ==="
echo "  Server:    $SERVER_HOST"
echo "  Clients (${#ALL_CLIENT_HOSTS[@]}): ${ALL_CLIENT_HOSTS[*]}"
echo "  Fan-in levels: ${FANIN_LEVELS[*]}"
echo "  Output root:   $TRIAL_ROOT"
[ "$DRY_RUN" -eq 1 ] && echo "  DRY RUN"
echo ""

mkdir -p "$TRIAL_ROOT"

TMPDIR_CONFIGS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_CONFIGS"' EXIT

for FANIN in "${FANIN_LEVELS[@]}"; do
    if [ "$FANIN" -gt "${#ALL_CLIENT_HOSTS[@]}" ]; then
        echo "SKIP fan-in=$FANIN: only ${#ALL_CLIENT_HOSTS[@]} clients available"
        continue
    fi

    SLICE=("${ALL_CLIENT_HOSTS[@]:0:$FANIN}")
    CLIENT_FQDNS=("${SLICE[@]/%/.$DCBENCH_NODE_DOMAIN}")
    OUTBASE="$TRIAL_ROOT/fanin_${FANIN}"

    echo "====== Trial=${TRIAL}  Fan-in=${FANIN} ======"
    echo "  Clients: ${CLIENT_FQDNS[*]}"

    for VARIANT in tcp_single tcp_dctcp homa; do
        case "$VARIANT" in
            tcp_single) EXP_NAME="tcp_single_fi${FANIN}" ;;
            tcp_dctcp)  EXP_NAME="tcp_dctcp_fi${FANIN}" ;;
            homa)       EXP_NAME="homa_fi${FANIN}" ;;
        esac

        CFG="$TMPDIR_CONFIGS/${EXP_NAME}.json"
        make_config "$CFG" "$EXP_NAME" "$VARIANT" \
            "$OUTBASE/$EXP_NAME" "${CLIENT_FQDNS[@]}"
        run_experiment "$CFG"
    done

    [ "$DRY_RUN" -eq 0 ] && analyze "$FANIN"
    echo ""
done

echo "=== Fan-in study trial=${TRIAL} complete ==="
echo "  Data under: $TRIAL_ROOT"
