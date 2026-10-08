#!/bin/zsh
# macOS arm of probe.c: SDL3 from Homebrew, AccessKit from Backends/SDL's
# fetch (python3 Backends/SDL/scripts/fetch-accesskit.py). Shows a 320x200
# window briefly in arms V, H and S. Run from the repository root.
set -e
here=${0:A:h}
ak=Backends/SDL/.accesskit
out=${TMPDIR:-/tmp}/accesskit-window-show; mkdir -p $out
clang $here/probe.c -o $out/probe -I/opt/homebrew/include -I$ak/accesskit-c-0.23.0/include \
  -L/opt/homebrew/lib -L$ak/lib -lSDL3 -laccesskit -lobjc -lc++ \
  -framework AppKit -framework Foundation -framework CoreFoundation
for arm in V H S N; do
  set +e; $out/probe $arm > $out/$arm.out 2> $out/$arm.err; code=$?; set -e
  print "arm $arm: exit $code"; print "  stdout: $(cat $out/$arm.out)"
  [[ -s $out/$arm.err ]] && print "  stderr: $(head -3 $out/$arm.err | tr '\n' '|')"
done
