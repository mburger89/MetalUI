#!/bin/zsh
# XP-G21 / WR-A: release build of the demo under the Mac asserts toolchain (the stand-in for Windows CI's 6.4.0+Asserts).
# Run from the checkout root: zsh docs/probes/windows-release-crash/repro.sh [scratch]
# Recorded output, 2026-10-21, 68975774 (macOS, swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a):
#   unmodified                      : FAIL  "SIL verification failed: return with stack allocs that haven't been deallocated"
#                                     in `specialized PaintPass.withRenderEffects(...)` (closure-specialised, suffix Tf1nnncn_n)
#   C  @_optimize(none) on it only  : FAIL  same message, same function
#   A  index helper, both optnone   : FAIL  "inconsistent stack states entering basic block" in `closure #1 in paintDecoration`
#      (the entry guard `isEmpty` inlined into the caller)
#   after the lane (commit WR-B): the env-gated AssertsCompilerTests (all four release arms) red at 68975774, green after
#   B  candidate-b.patch            : PASS  "Build complete! (73.63 sec)" -- entry @_optimize(none), index helper optimised
scratch=${1:-${TMPDIR:-/tmp}/wr-asserts}
tc=~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a.xctoolchain
TOOLCHAINS=$(plutil -extract CFBundleIdentifier raw $tc/Info.plist) \
  swift build -c release --product MetalUIDemo --scratch-path "$scratch" 2>&1 | grep -E "SIL verification|Build complete|error: Build failed"
