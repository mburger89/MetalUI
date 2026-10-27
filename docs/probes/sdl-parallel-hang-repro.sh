#!/bin/zsh
# Probe WG-H (item WG, rulings WG-H, WG-L, TL-G; record 150's 18-minute parallel hang of the whole Backends/SDL suite).
# Run after `swift build --build-tests` in Backends/SDL:
#   zsh docs/probes/sdl-parallel-hang-repro.sh baseline            # one unfiltered --no-parallel run: the healthy wall time
#   zsh docs/probes/sdl-parallel-hang-repro.sh parallel <n> <secs> # n whole-suite PARALLEL runs, METALUI_TEST_DEADLINE_SECONDS=<secs>
# Each run prints: run number, load averages before, wall seconds, exit status, the Swift Testing summary line, and
# `GUARD` lines if the deadline guard fired (exit 71; its `sample` of the helper is in the run's log, path printed).
# Logs go to ${WG_LOG_DIR:-/tmp/wg-parallel-hang}. A firing is read from its sample, never assumed to be the record-150 hang
# (a deadline below a loaded Mac's wall time fires on slowness: WG-L). No firing is not evidence of absence.
# Recorded 2026-10-26 (macOS 27, debug, METALUI_REQUIRE_GPU=1, a shared Mac under other workflows' builds, load average 10-26 rising to 110):
#  baseline, one unfiltered --no-parallel run: wall 16 s (Swift Testing 14.4 s, 331 tests), load[10.1 18.1 13.9]; deadline = 16 x 3 = 48 s (WG-L).
#  before the fix, 8 parallel runs at 48 s: 4 passed in 11-12 s, 3 HUNG (parallel-3, -6, -7: wall 53-54 s, guard exit 71, sample read) and
#  1 failed `sdlAFileDroppedOnTheAppIsAnOpenURL` (2 issues, SDLAppShellTests.swift:170/176, a separate parallel flake, not diagnosed).
#  All three samples are the same deadlock: the main thread, running a main-actor GPU test (aStorageBufferRoundTripsUploadedBytes,
#  aFragmentStageSamplesAMipLevel..., aPipelineThatWritesNoColour...), waits in SDLGPUDevice.make for makeLock (SDLGPUDevice.swift:110); the lock's
#  holder is a detached thread of SDLGPUDeviceInfoTests (anEngineDeviceMadeOffTheMainThread..., videoInitOffTheMainThreadIsMeasured) inside
#  onMainThreadIfCocoa -> DispatchQueue.main.sync (line 114): a lock-order inversion between makeLock and the main queue.
#  after the fix (video init outside makeLock, WG-H addendum), 12 parallel runs at 48 s: 12 passed, wall 12-14 s (load up to 110); one
#  --no-parallel run 332 tests passed, 17.1 s at load 114. Regression test aMainThreadMakeDuringAnOffThreadMakesHopDoesNotDeadlock: red before
#  (guard exit 71, sample at make's lock), green after, red again with the init moved back under the lock.
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
