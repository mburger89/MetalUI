#!/bin/zsh
# C14-e (b), CF-F: the bracket window's cold frames at a commit, timed in release (and optionally under xctrace Time Profiler).
#   zsh docs/probes/warm-settle/cold-profile.sh <commit> [rounds] [--trace]
# Archives <commit> (git archive, so any commit builds without touching a worktree) into a scratch directory named for it, copies in
# this harness and BracketFixture.swift from the same commit, builds release and prints TSV. Run it for the base and the head
# alternately, three times each: a dated measurement, never a pin. --trace records a Time Profiler trace of the whole run beside the
# binary (open it in Instruments, or `xctrace export`; see cold-profile.md for the aggregation).
set -eu
commit=$1; rounds=${2:-12}; trace=${3:-}
root=${0:A:h:h:h:h}
tag=$(git -C "$root" rev-parse --short "$commit")
scratch=${METALUI_COLD_SCRATCH:-/tmp/metalui-cold-$tag}
if [[ ! -d "$scratch/MetalUI" ]]; then
  mkdir -p "$scratch/MetalUI"
  git -C "$root" archive "$commit" | tar -x -C "$scratch/MetalUI"
fi
rm -rf "$scratch/cold-harness"; mkdir -p "$scratch"
cp -R "$root/docs/probes/warm-settle/cold-harness" "$scratch/cold-harness"
git -C "$root" show "$commit:Tests/MetalUITestingTests/BracketFixture.swift" > "$scratch/cold-harness/Sources/ColdFrames/BracketFixture.swift"
echo "date\t$(date -u +%FT%TZ)"
echo "commit\t$tag"
echo "machine\t$(sysctl -n hw.model) / $(sysctl -n machdep.cpu.brand_string) / macOS $(sw_vers -productVersion) / $(swift --version 2>&1 | head -1)"
cd "$scratch/cold-harness"
swift build -c release >&2
bin="$(swift build -c release --show-bin-path)/ColdFrames"
if [[ "$trace" == "--trace" ]]; then
  rm -rf "$scratch/cold.trace"
  xctrace record --template 'Time Profiler' --output "$scratch/cold.trace" --launch -- "$bin" "$rounds" >&2
  echo "trace\t$scratch/cold.trace"
else
  "$bin" "$rounds"
fi
