#!/bin/sh
# The X11 window icon read back from outside the process (ruling WI-E). Run by IconCheck
# (Backends/SDL) once its window is up, under Xvfb: reads the window's _NET_WM_ICON with xprop
# and walks the property's width, height, width*height pixels records. $1 is the sizes the
# property must hold, in order, e.g. "16x16 32x32 256x256". xprop's own icon pretty-printer
# prints nothing for an icon over about 250 pixels (ruling WI-A), so the values are read
# with an explicit 32c format.
set -u
expected="$1"
raw=$(xprop -name IconCheck -len 4000000 -f _NET_WM_ICON 32c _NET_WM_ICON 2>&1) || { echo "xprop failed: $raw" | head -c 300; exit 1; }
found=$(printf '%s' "$raw" | sed -n 's/^_NET_WM_ICON(CARDINAL) = //p' | awk -F', *' '{
  i = 1; out = ""
  while (i + 1 <= NF) { w = $i + 0; h = $(i + 1) + 0; out = out (out == "" ? "" : " ") w "x" h; i += 2 + w * h }
  if (i != NF + 1) out = out " (truncated: " NF " values)"
  print out }')
echo "_NET_WM_ICON sizes: [${found}] expected: [${expected}]"
[ "$found" = "$expected" ]
