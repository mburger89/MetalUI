#!/bin/zsh
# Real release-window captures of MetalUIDemo, compared commit to commit.
# Added 2026-09-17 to settle the captures owed by MC-J (tasks 3/9/12), record
# §16 (tasks 4/5), CN- (task 6) and LR- (task 7 stage 1). Results are in
# record §03's "Release-window captures, 2026-09-17" section.
#
# PRECONDITION: run docs/probes/appkit-screen-lock-state.swift first. Capture
# only when it prints no CGSSessionScreenIsLocked/ScreenLockedTime line (the
# keys are ABSENT when unlocked, not 0) and `displayAsleep main: 0`. The
# backstop: `./nonblack` on a full `screencapture -x` must read above 0.
#
# METHOD. Differs from MC-J's `screencapture -x -R<rect>` on purpose: this
# captures the window by id (`-l`) with no shadow (`-o`), so desktop corners
# and neighbouring windows never enter the image and a window's on-screen
# position (which varies by a few points between launches) does not matter.
# No input is sent and the pointer is not moved. Each window is captured twice,
# 1.5 s apart, after a 3 s settle; the pair must read 0 before a comparison
# between commits means anything.
#
# USAGE: capture.sh <workdir> <commit>...   (in commit order)
set -e
W=$1; shift; HERE=${0:A:h}; REPO=$(git -C $HERE rev-parse --show-toplevel)
mkdir -p $W; cd $W
for f in winid pixdiff nonblack; do [ -x $f ] || xcrun swiftc -O $HERE/$f.swift -o $f; done
for c in "$@"; do
  [ -x src-$c/.build/release/MetalUIDemo ] && continue
  mkdir -p src-$c && git -C $REPO archive $c | tar -x -C src-$c
  (cd src-$c && swift build -c release --product MetalUIDemo > ../build-$c.log 2>&1)
done
sleepf() { perl -e "select(undef,undef,undef,$1)"; }
cap() {
  if [ "$2" = preview ]; then METALUI_NATIVE_LAYOUT_PREVIEW=1 ./src-$1/.build/release/MetalUIDemo >/dev/null 2>&1 &
  else ./src-$1/.build/release/MetalUIDemo >/dev/null 2>&1 & fi
  local pid=$! line=""
  for i in {1..40}; do line=$(./winid $pid | awk '$6=="true"' | head -1); [ -n "$line" ] && break; sleepf 0.25; done
  sleepf 3.0; local id=${line%% *}
  screencapture -x -o -l $id $1-$2-a.png; sleepf 1.5; screencapture -x -o -l $id $1-$2-b.png
  echo "$1 $2 window=[$line] a-vs-b: $(./pixdiff $1-$2-a.png $1-$2-b.png)"
  kill $pid; wait $pid 2>/dev/null || true
}
for c in "$@"; do for m in default preview; do cap $c $m; done; done
prev=""; for c in "$@"; do
  [ -n "$prev" ] && for m in default preview; do echo "$prev -> $c $m: $(./pixdiff $prev-$m-a.png $c-$m-a.png)"; done
  prev=$c
done
last=${@[-1]}; echo "control, default vs preview at $last: $(./pixdiff $last-default-a.png $last-preview-a.png)"
