#!/usr/bin/env bash
# Run the fan-in scaling study N times (trials) so results can be averaged.
#
# Usage:
#   bash cloudlab/run_fanin_trials.sh [--trials 3] [--fan-ins "4 8 12 16"] [--dry-run]
#
# Produces:
#   results/fanin_test1/fanin_{4,8,12,16}/...
#   results/fanin_test2/fanin_{4,8,12,16}/...
#   results/fanin_test3/fanin_{4,8,12,16}/...
# then (if scripts/fanin_report.py exists) writes:
#   results/fanin_test1.md, results/fanin_test2.md, results/fanin_test3.md
#   results/fanin_averaged.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TRIALS=3
FAN_INS="4 8 12 16"
DRY_RUN=0
START_TRIAL=1

while [ "$#" -gt 0 ]; do
    case "$1" in
        --trials)       TRIALS="$2"; shift 2 ;;
        --fan-ins)      FAN_INS="$2"; shift 2 ;;
        --start-trial)  START_TRIAL="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=1; shift ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--trials N] [--fan-ins \"4 8 12 16\"] [--start-trial K] [--dry-run]"
            exit 0 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

END_TRIAL=$((START_TRIAL + TRIALS - 1))

echo "=========================================================="
echo "  Fan-in study: trials ${START_TRIAL}..${END_TRIAL}"
echo "  Fan-in levels: ${FAN_INS}"
[ "$DRY_RUN" -eq 1 ] && echo "  DRY RUN"
echo "=========================================================="
echo ""

for T in $(seq "$START_TRIAL" "$END_TRIAL"); do
    ARGS=(--trial "$T" --fan-ins "$FAN_INS")
    [ "$DRY_RUN" -eq 1 ] && ARGS+=(--dry-run)

    echo ""
    echo "##########  TRIAL ${T} / ${END_TRIAL}  ##########"
    echo ""
    bash "$SCRIPT_DIR/run_fanin.sh" "${ARGS[@]}"
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "Dry run done. No markdown reports generated."
    exit 0
fi

REPORT_SCRIPT="$REPO_ROOT/scripts/fanin_report.py"
if [ -x "$REPORT_SCRIPT" ] || [ -f "$REPORT_SCRIPT" ]; then
    echo ""
    echo "=========================================================="
    echo "  Generating per-trial + averaged markdown reports"
    echo "=========================================================="
    TRIAL_ARGS=()
    for T in $(seq "$START_TRIAL" "$END_TRIAL"); do
        TRIAL_ARGS+=(--trial "$T")
    done
    python3 "$REPORT_SCRIPT" \
        "${TRIAL_ARGS[@]}" \
        --fan-ins $FAN_INS \
        --results-dir "$REPO_ROOT/results"
else
    echo ""
    echo "scripts/fanin_report.py not found; skipping markdown generation."
fi

echo ""
echo "=== All trials + report done ==="
