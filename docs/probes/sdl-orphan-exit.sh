#!/bin/zsh
# Probe TL-3 (item HG, rulings TL-E, TL-J, record 154): an orphaned MetalUISDLTests helper exits.
# Run after `swift build --build-tests` in Backends/SDL (it passes the flags of scripts/fetch-accesskit.py):
#   zsh docs/probes/sdl-orphan-exit.sh
# Starts `swift test --skip-build` (the whole suite, 10-16 s) as a background job, waits for its
# swiftpm-testing-helper child, kills `swift test` (not the helper) with SIGKILL after 2 s (the helper
# re-parents to PID 1) and asserts the helper is gone within 3 s.
# Prints `ok orphan exited after <n> s`, `FAIL helper <pid> survived 3 s` or `inconclusive: ...`.
# Separating arm: the pre-guard measurement of record 154 section 2 (helper re-parented, slept on).
# Recorded output: see record 154.
set -u
ROOT=${0:A:h:h:h}
cd "$ROOT/Backends/SDL" || exit 2
FLAGS=("${(@f)$(python3 scripts/fetch-accesskit.py --print-flags)}")
METALUI_REQUIRE_GPU=1 swift test --skip-build --no-parallel "${FLAGS[@]}" >/dev/null 2>&1 &
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
