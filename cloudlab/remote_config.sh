#!/usr/bin/env bash

# Common argument/env parsing helpers for CloudLab remote runner scripts.

dcbench_init_remote_config() {
    local default_server="$1"
    local default_clients_csv="$2"
    local default_server_ip="$3"
    local default_bench="$4"
    local default_localdir="$5"
    local default_port="$6"

    SERVER="${DCBENCH_SERVER:-$default_server}"
    CLIENTS_CSV="${DCBENCH_CLIENTS:-$default_clients_csv}"
    SERVER_IP="${DCBENCH_SERVER_IP:-$default_server_ip}"
    BENCH="${DCBENCH_BENCH:-$default_bench}"
    LOCALDIR="${DCBENCH_LOCALDIR:-$default_localdir}"
    PORT="${DCBENCH_PORT:-$default_port}"

    # Use a single string and split once to support multi-word SSH options.
    SSH_OPTS_STR="${DCBENCH_SSH_OPTS:--o StrictHostKeyChecking=no}"
    read -r -a SSH_OPTS <<< "$SSH_OPTS_STR"

    CLIENTS=()
    if [ -n "$CLIENTS_CSV" ]; then
        IFS=',' read -r -a CLIENTS <<< "$CLIENTS_CSV"
    fi
}

dcbench_print_remote_usage() {
    local script_name="$1"
    cat <<EOF
Usage: $script_name [options]

Options:
  --server USER@HOST           Server SSH target
  --clients H1,H2,H3           Comma-separated client SSH targets
  --client HOST                Add one client SSH target (repeatable)
  --server-ip IP               Server data-plane IP seen by clients
  --bench PATH                 Benchmark binary path on remote hosts
  --localdir PATH              Local results directory
  --port PORT                  Server/client port
  --ssh-opts "..."             SSH options string (default: -o StrictHostKeyChecking=no)
  -h, --help                   Show help

Environment equivalents:
  DCBENCH_SERVER, DCBENCH_CLIENTS, DCBENCH_SERVER_IP,
  DCBENCH_BENCH, DCBENCH_LOCALDIR, DCBENCH_PORT, DCBENCH_SSH_OPTS
EOF
}

dcbench_parse_remote_args() {
    local script_name="$1"
    shift

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --server)
                [ "$#" -ge 2 ] || { echo "Missing value for --server"; return 1; }
                SERVER="$2"
                shift 2
                ;;
            --clients)
                [ "$#" -ge 2 ] || { echo "Missing value for --clients"; return 1; }
                CLIENTS=()
                IFS=',' read -r -a CLIENTS <<< "$2"
                shift 2
                ;;
            --client)
                [ "$#" -ge 2 ] || { echo "Missing value for --client"; return 1; }
                CLIENTS+=("$2")
                shift 2
                ;;
            --server-ip)
                [ "$#" -ge 2 ] || { echo "Missing value for --server-ip"; return 1; }
                SERVER_IP="$2"
                shift 2
                ;;
            --bench)
                [ "$#" -ge 2 ] || { echo "Missing value for --bench"; return 1; }
                BENCH="$2"
                shift 2
                ;;
            --localdir)
                [ "$#" -ge 2 ] || { echo "Missing value for --localdir"; return 1; }
                LOCALDIR="$2"
                shift 2
                ;;
            --port)
                [ "$#" -ge 2 ] || { echo "Missing value for --port"; return 1; }
                PORT="$2"
                shift 2
                ;;
            --ssh-opts)
                [ "$#" -ge 2 ] || { echo "Missing value for --ssh-opts"; return 1; }
                SSH_OPTS_STR="$2"
                read -r -a SSH_OPTS <<< "$SSH_OPTS_STR"
                shift 2
                ;;
            -h|--help)
                dcbench_print_remote_usage "$script_name"
                return 2
                ;;
            *)
                echo "Unknown argument: $1"
                dcbench_print_remote_usage "$script_name"
                return 1
                ;;
        esac
    done

    if [ -z "$SERVER" ]; then
        echo "SERVER is required. Provide --server or DCBENCH_SERVER."
        return 1
    fi

    if [ "${#CLIENTS[@]}" -eq 0 ]; then
        echo "At least one client is required. Provide --clients/--client or DCBENCH_CLIENTS."
        return 1
    fi

    mkdir -p "$LOCALDIR"
}

dcbench_print_remote_config() {
    echo "  Server:    $SERVER"
    echo "  Clients:   ${CLIENTS[*]}"
    echo "  Server IP: $SERVER_IP"
    echo "  Bench:     $BENCH"
    echo "  Port:      $PORT"
    echo "  Local dir: $LOCALDIR"
}

dcbench_ssh() {
    local host="$1"
    local cmd="$2"
    ssh "${SSH_OPTS[@]}" "$host" "$cmd"
}

dcbench_scp_from() {
    local host="$1"
    local remote_path="$2"
    local local_path="$3"
    scp "${SSH_OPTS[@]}" "$host:$remote_path" "$local_path"
}
