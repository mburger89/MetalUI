#!/bin/zsh
# Probe TL-3 (item HG, rulings TL-E, TL-J, record 154): an orphaned MetalUISDLTests helper exits.
# Run from anywhere after `swift build --build-tests` in Backends/SDL (flags of scripts/fetch-accesskit.py):
#   zsh docs/probes/sdl-orphan-exit.sh
# A stand-in runner (a zsh we own) starts the real swiftpm-testing-helper on the guard suite, the script
# kills the runner with SIGKILL (the helper re-parents to PID 1, as when `swift test` is killed) and
# asserts the helper is gone within 3 s. Prints `ok orphan exited` or `FAIL helper ... survived`.
# Separating arm: the pre-guard measurement of record 154 section 2 (helper re-parented, slept on, SIGTERM
# ignored). The guard suite is short, so the helper may finish by itself before the kill: the script
# only claims the watcher when the helper was still alive at the kill (it prints `inconclusive` otherwise).
# Recorded output: see record 154.
set -u
ROOT=${0:A:h:h:h}
cd "$ROOT/Backends/SDL" || exit 2
HELPER=$(xcrun --find swiftpm-testing-helper 2>/dev/null)
BUNDLE=$(find .build -type d -name 'MetalUISDLTests.xctest' 2>/dev/null | head -1)
[ -n "$HELPER" ] && [ -n "$BUNDLE" ] || { echo "need swiftpm-testing-helper and a built test bundle"; exit 2; }
# The hold test: a runner shell that starts the helper on a test that blocks. The blocking test is
# TL2's exit-test child arm running with SIGTERM disabled is not available, so use the suite filter
# `aDeadlineExpiresOnceAfterItsMilliseconds`-free: any test of the suite keeps the helper alive
# at least a second (TL4 polls 5 x 1 ms, TL2 waits). TL2 is the longest when the guard is absent.
zsh -c "'$HELPER' --test-bundle-path '$BUNDLE/Contents/MacOS/MetalUISDLTests' --testing-library swift-testing --filter SDLTestProcessGuardTests >/dev/null 2>&1 & echo \$! > /tmp/muitg-helper.pid; wait" &
RUNNER=$!
until [ -s /tmp/muitg-helper.pid ]; do :; done
HELPER_PID=$(cat /tmp/muitg-helper.pid); rm -f /tmp/muitg-helper.pid
kill -0 $HELPER_PID 2>/dev/null || { echo "inconclusive: helper already finished"; exit 3; }
kill -9 $RUNNER
START=$(python3 -c 'import time;print(time.time())')
while kill -0 $HELPER_PID 2>/dev/null; do
  NOW=$(python3 -c 'import time;print(time.time())')
  if [ $(python3 -c "print(int(($NOW-$START)>3))") = 1 ]; then echo "FAIL helper $HELPER_PID survived 3 s"; kill -9 $HELPER_PID; exit 1; fi
done
echo "ok orphan exited"
