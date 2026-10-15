#!/bin/zsh
# Re-takes record 105's timed figures (BL-A). Usage:
#   zsh docs/probes/perf-baselines.sh [release|debug] [--quick] [scenario]
# scenario: all (default), tree, demo, list, drag, bracket (C14b's node drag, three arms; the layout-only shapes run with every call),
#   bracketgraft (C14b-2 lane 2: the same with the graft off and on, METALUI_RETAINED_GRAFT=0/1),
#   bracketab (C14b-2: the node drag with prepaint replay off and on alternating in one process, METALUI_RETAINED_PREPAINT=0/1).
# Builds the public-API harness docs/probes/perf-harness against this checkout
# (through a symlink named MetalUI so the package identity resolves) in a scratch
# directory (kept between runs for the build cache; METALUI_PERF_SCRATCH overrides), runs it, and prints the machine line plus TSV measurements. Wall
# clock figures are dated measurements, never test pins; counts are the pins.
set -eu
config=${1:-release}; [[ $# -gt 0 ]] && shift
root=${0:A:h:h:h}
scratch=${METALUI_PERF_SCRATCH:-/tmp/metalui-perf-${root:t}}
mkdir -p "$scratch"
ln -sfn "$root" "$scratch/MetalUI"
rm -rf "$scratch/perf-harness/Sources" "$scratch/perf-harness/Package.swift"
mkdir -p "$scratch/perf-harness"
cp -R "$root/docs/probes/perf-harness/Sources" "$root/docs/probes/perf-harness/Package.swift" "$scratch/perf-harness/"
# C14b: the bracket window fixture is a test-target file (no Testing import); the harness compiles a copy.
cp "$root/Tests/MetalUITestingTests/BracketFixture.swift" "$scratch/perf-harness/Sources/PerfBaselines/BracketFixture.swift"
echo "date\t$(date -u +%FT%TZ)"
echo "commit\t$(git -C "$root" rev-parse --short HEAD)"
echo "machine\t$(sysctl -n hw.model) / $(sysctl -n machdep.cpu.brand_string) / macOS $(sw_vers -productVersion) / $(swift --version 2>&1 | head -1)"
echo "config\t$config"
# Layout-kernel-only harness: the checkout's MetalUICore/MetalUILayout sources
# linked into a package of its own, so `package` API is readable.
mkdir -p "$scratch/perf-layout/Sources"
rm -rf "$scratch/perf-layout/Sources/LayoutOnly" "$scratch/perf-layout/Package.swift"
cp -R "$root/docs/probes/perf-layout/Sources/LayoutOnly" "$scratch/perf-layout/Sources/"
cp "$root/docs/probes/perf-layout/Package.swift" "$scratch/perf-layout/"
ln -sfn "$root/Sources/MetalUICore" "$scratch/perf-layout/Sources/MetalUICore"
ln -sfn "$root/Sources/MetalUILayout" "$scratch/perf-layout/Sources/MetalUILayout"
cd "$scratch/perf-layout"
swift build -c "$config" >&2
"$(swift build -c "$config" --show-bin-path)/LayoutOnly" "$@"
cd "$scratch/perf-harness"
swift build -c "$config" >&2
# Median of 3 whole-process runs is the reader's job: run this three times.
"$(swift build -c "$config" --show-bin-path)/PerfBaselines" "$@"
