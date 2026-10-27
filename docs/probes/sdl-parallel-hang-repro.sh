#!/bin/zsh
# Probe WG-H (item WG, rulings WG-H, WG-L, TL-G; record 150's 18-minute parallel hang of the whole Backends/SDL suite).
# Run after `swift build --build-tests` in Backends/SDL:
#   zsh docs/probes/sdl-parallel-hang-repro.sh baseline            # one unfiltered --no-parallel run: the healthy wall time
#   zsh docs/probes/sdl-parallel-hang-repro.sh parallel <n> <secs> # n whole-suite PARALLEL runs, METALUI_TEST_DEADLINE_SECONDS=<secs>
# Each run prints: run number, load averages before, wall seconds, exit status, the Swift Testing summary line, and
# `GUARD` lines if the deadline guard fired (exit 71; its `sample` of the helper is in the run's log, path printed).
# Logs go to ${WG_LOG_DIR:-/tmp/wg-parallel-hang}. A firing is read from its sample, never assumed to be the record-150 hang
# (a deadline below a loaded Mac's wall time fires on slowness: WG-L). No firing is not evidence of absence.
set -u
ROOT=${0:A:h:h:h}
MODE=${1:-baseline}
cd "$ROOT/Backends/SDL" || exit 2
LOG=${WG_LOG_DIR:-/tmp/wg-parallel-hang}; mkdir -p "$LOG"
FLAGS=("${(@f)$(python3 scripts/fetch-accesskit.py --print-flags)}")
run_one() { # $1 label, $2 parallel flag, $3 deadline
  local out="$LOG/$1.log" load t0=$SECONDS
  load=$(sysctl -n vm.loadavg | tr -d '{}')
  METALUI_REQUIRE_GPU=1 METALUI_TEST_DEADLINE_SECONDS=$3 swift test --skip-build $2 "${FLAGS[@]}" >"$out" 2>&1
  local rc=$?
  echo "run $1 load[$load] wall $(( SECONDS - t0 )) s exit $rc :: $(grep -E 'Test run with|Executed .* tests' "$out" | tail -1)"
  grep -n "METALUI_TEST_DEADLINE_SECONDS\|sample" "$out" | head -3 | sed 's/^/  GUARD /'
  echo "  log $out"
}
case $MODE in
  baseline) run_one baseline --no-parallel 0 ;;
  parallel) for i in {1..${2:-6}}; do run_one "parallel-$i" --parallel ${3:-600}; done ;;
  *) echo "usage: $0 baseline | parallel <n> <secs>"; exit 2 ;;
esac
