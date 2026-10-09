#!/bin/zsh
# Swift probe: does an app's `attributed.foregroundColor = .red` resolve to
# MetalUI's attribute scope when AppKit's scope is also visible — explicitly
# (`import AppKit`) or transitively (MetalUI imports AppKit; member lookups
# leak through imports without the `MemberImportVisibility` feature)?
# AppKit's dynamic-member subscript is `@_disfavoredOverload`
# (AppKit.swiftinterface), yet a second GENERIC subscript ties with it on
# `.red` (both `NSColor.red` and `MColor.red` exist). Evidence for RT-D.
#
# HOW TO RUN: zsh docs/probes/swift-attribute-scope-ambiguity/run.sh
#
# RECORDED 2026-10-08 (macOS 27.0, Xcode beta toolchain):
#
#   generic UsePlain: error: ambiguous use of 'red'
#   generic UseAppKit: error: ambiguous use of 'red'
#   per-key UsePlain: ok Optional(Scope.MColor(r: 1.0))
#   per-key UseAppKit: ok Optional(Scope.MColor(r: 1.0))
#
# Separating arm: the only difference between the two builds is the one
# non-generic subscript (`-D PER_KEY`). SwiftUI itself compiles
# `attributed.foregroundColor = .red` beside `import AppKit` (checked by hand
# the same day: SwiftUI's subscript is generic, but SwiftUI's own Color is the
# only other candidate it competes with).
cd "${0:A:h}"
T=$(mktemp -d)
for variant in generic per-key; do
  flags=(); [[ $variant == per-key ]] && flags=(-D PER_KEY)
  xcrun swiftc $flags -emit-module -emit-library -module-name Scope Scope.swift -o $T/libScope.dylib -emit-module-path $T/Scope.swiftmodule 2>&1 | grep error
  for use in UsePlain UseAppKit; do
    out=$(xcrun swiftc -I $T -L $T -lScope $use.swift -o $T/$use 2>&1 | grep -m1 -o "error: .*")
    if [[ -n $out ]]; then echo "$variant $use: $out"; else echo "$variant $use: $(DYLD_LIBRARY_PATH=$T $T/$use)"; fi
  done
done
rm -rf $T
