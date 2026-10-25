#!/bin/zsh
# Probe TL-3 (item HG, rulings TL-E, TL-J, record 154): an orphaned MetalUISDLTests helper exits.
# Run after `swift build --build-tests` in Backends/SDL (it passes the flags of scripts/fetch-accesskit.py):
#   zsh docs/probes/sdl-orphan-exit.sh
# Starts `swift test --skip-build --filter theProbeHoldBlocksTheHelper` with METALUI_TL_HOLD=1 (test TL7 blocks the
# helper 120 s on a semaphore, like a hung GPU wait), waits for the swiftpm-testing-helper child, kills `swift test`
# (not the helper) with SIGKILL after 2 s (the helper re-parents to PID 1) and asserts the helper is gone within 3 s.
# Prints `ok orphan exited after <n> s`, `FAIL helper <pid> survived 3 s` or `inconclusive: ...`.
# Recorded 2026-10-24 (macOS 27, debug): with the guard `ok orphan exited after 0 s` (twice); separating arm, the
# guard's C file replaced by its red-phase stub (no constructor): `FAIL helper 39097 survived 3 s`.
set -u
ROOT=${0:A:h:h:h}
cd "$ROOT/Backends/SDL" || exit 2
FLAGS=("${(@f)$(python3 scripts/fetch-accesskit.py --print-flags)}")
METALUI_TL_HOLD=1 METALUI_REQUIRE_GPU=1 swift test --skip-build --no-parallel --filter theProbeHoldBlocksTheHelper "${FLAGS[@]}" >/dev/null 2>&1 &
RUNNER=$!
HELPER_PID=""
for i in {1..300}; do
  HELPER_PID=$(pgrep -P $RUNNER -f swiftpm-testing-helper | head -1)
  [ -n "$HELPER_PID" ] && break
  kill -0 $RUNNER 2>/dev/null || break
  sleep 0.1
done
[ -n "$HELPER_PID" ] || { echo "inconclusive: no helper found"; exit 3; }
sleep 2
# swift test starts a helper per phase (listing, then the run): take the one alive now.
HELPER_PID=$(pgrep -P $RUNNER -f swiftpm-testing-helper | tail -1)
[ -n "$HELPER_PID" ] || { echo "inconclusive: no helper alive after 2 s"; exit 3; }
kill -0 $HELPER_PID 2>/dev/null || { echo "inconclusive: helper already finished"; exit 3; }
kill -9 $RUNNER
START=$SECONDS
while kill -0 $HELPER_PID 2>/dev/null; do
  if (( SECONDS - START >= 3 )); then echo "FAIL helper $HELPER_PID survived 3 s"; kill -9 $HELPER_PID; exit 1; fi
  sleep 0.05
done
echo "ok orphan exited after $(( SECONDS - START )) s"
