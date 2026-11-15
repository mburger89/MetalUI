#!/bin/zsh
# Capture one app window by id for the website (site/img). No input is sent.
# USAGE: site-capture.sh <out.png> <binary> [args...]
# PRECONDITION: docs/probes/appkit-screen-lock-state.swift prints no
# CGSSessionScreenIsLocked line (see docs/probes/window-capture/capture.sh).
set -e
OUT=$1; shift
HERE=${0:A:h}; REPO=${HERE:h}
W=${SITE_CAPTURE_TMP:-${TMPDIR:-/tmp}/site-capture}; mkdir -p $W
[ -x $W/winid ] || xcrun swiftc -O $REPO/docs/probes/window-capture/winid.swift -o $W/winid
"$@" >/dev/null 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null || true' EXIT
line=""
for i in {1..80}; do
  line=$($W/winid $pid | awk '$6=="true"' | head -1); [ -n "$line" ] && break
  perl -e 'select(undef,undef,undef,0.25)'
done
[ -n "$line" ] || { echo "no window for pid $pid" >&2; exit 1; }
sleep 4
screencapture -x -o -l ${line%% *} $OUT
echo "captured $OUT from window [$line]"
