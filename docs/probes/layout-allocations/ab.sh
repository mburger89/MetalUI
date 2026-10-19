#!/bin/zsh
# usage: ab.sh A B rounds secs scenario...   -> prints "scenario variant median_ms" lines
A=$1; B=$2; rounds=$3; secs=$4; shift 4
for s in "$@"; do
  for r in $(seq 1 $rounds); do
    for v in $A $B; do
      l=$(uptime | sed 's/.*averages: //')
      m=$(./Prof.$v $s $secs 2>&1 | grep -o "median_ms=[0-9.]*" | head -1)
      echo "$s $v $r $m load=$l"
    done
  done
done
