#!/bin/zsh
# Swift probe: a `for` loop in a result builder over a helper returning an
# opaque type (MetalCreator gap M4-b (1); ruling KF-M in
# docs/superpowers/2026-10-08-key-focus-decisions.md).
#
# HOW TO RUN:   zsh docs/probes/swift-builder-for-opaque.sh
#
# Each arm is a self-contained file typechecked with `xcrun swiftc -typecheck
# -swift-version 6`; the probe prints `ok` or the first error line. No MetalUI
# import: the builders are twelve-line stand-ins with MetalUI's shapes
# (`buildPartialBlock`, a generic `buildArray` returning `ArrayGroup<X>`).
#
# POSITIVE CONTROLS: A2 (the same loop over a concrete-returning helper) and A3
# (the same opaque values appended to an array by hand) compile, so neither the
# loop nor "an array of an opaque type" is refused — only the builder's
# synthesized array is. A1 is the failing spelling.
#
# RECORDED 2026-10-08 by the key-focus (C9) designer, macOS 27.0.1 (26A434),
# Apple Swift 6.4 (swiftlang-6.4.0.33.1). Run twice, byte-identical:
#   A1 builder for-loop over an opaque helper: error: underlying type for opaque result type 'some G' could not be inferred from return expression
#   A2 builder for-loop over a concrete helper (control): ok
#   A3 hand-written loop appending the opaque values (control): ok
#   A4 non-generic buildArray([any G]): error: underlying type for opaque result type 'some G' could not be inferred from return expression
#   A5 buildExpression wrapping in W<X>: error: underlying type for opaque result type 'some G' could not be inferred from return expression
#   A6 buildExpression erasing to AnyG: ok
#   A7 SwiftUI VStack { for }: error: closure containing control flow statement cannot be used with result builder 'ViewBuilder'
#   A8 SwiftUI ForEach over an opaque helper: ok
#
# RESULT. The builder transform (SE-0289 as implemented since Swift 5.8)
# declares the loop's accumulator with the BODY BLOCK's type; when that type
# mentions an opaque result type the synthesized declaration reads as a new
# `some G` whose underlying type nothing determines (Swift forums, "Improved
# Result Builder Implementation in Swift 5.8", post 16). It is decided before
# `buildArray` is consulted (A4: a non-generic `buildArray` taking `[any G]`
# fails identically) and a wrapper that still names the opaque type fails (A5);
# only erasing EVERY expression (A6) compiles, which no typed builder can do
# for the `for` case alone. SwiftUI's `ViewBuilder` has no `buildArray` at all
# (A7); its spelling is `ForEach` (A8).

set -u
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

common='protocol G {}
struct T: G {}
struct Pair<A: G, B: G>: G {}
struct ArrayGroup<X: G>: G { var x: [X] }
func label() -> some G { T() }
struct L: G {}
func concrete() -> L { L() }
'
builder='@resultBuilder enum B {
    static func buildPartialBlock<X: G>(first: X) -> X { first }
    static func buildPartialBlock<A: G, C: G>(accumulated: A, next: C) -> Pair<A, C> { Pair() }
    static func buildArray<X: G>(_ xs: [X]) -> ArrayGroup<X> { ArrayGroup(x: xs) }
}
func box<C: G>(@B _ c: () -> C) -> C { c() }
'

arm() {
    local label=$1 source=$2
    print -r -- "$source" > "$dir/arm.swift"
    local out
    out=$(xcrun swiftc -typecheck -swift-version 6 "$dir/arm.swift" 2>&1)
    if [[ $? -eq 0 ]]; then
        print -r -- "  $label: ok"
    else
        print -r -- "  $label: $(print -r -- "$out" | grep -m1 -o 'error: .*')"
    fi
}

arm "A1 builder for-loop over an opaque helper" "$common$builder
func use(_ xs: [Int]) { _ = box { for _ in xs { label() } } }"

arm "A2 builder for-loop over a concrete helper (control)" "$common$builder
func use(_ xs: [Int]) { _ = box { for _ in xs { concrete() } } }"

arm "A3 hand-written loop appending the opaque values (control)" "$common
func use(_ xs: [Int]) { var a = [label()]; a.removeAll(); for _ in xs { a.append(label()) }; _ = ArrayGroup(x: a) }"

arm "A4 non-generic buildArray([any G])" "$common
struct AnyArray: G { var x: [any G] }
@resultBuilder enum B {
    static func buildBlock<X: G>(_ x: X) -> X { x }
    static func buildArray(_ xs: [any G]) -> AnyArray { AnyArray(x: xs) }
}
func box<C: G>(@B _ c: () -> C) -> C { c() }
func use(_ xs: [Int]) { _ = box { for _ in xs { label() } } }"

arm "A5 buildExpression wrapping in W<X>" "$common
struct W<X: G>: G { var x: X }
@resultBuilder enum B {
    static func buildExpression<X: G>(_ x: X) -> W<X> { W(x: x) }
    static func buildBlock<X: G>(_ x: X) -> X { x }
    static func buildArray<X: G>(_ xs: [X]) -> ArrayGroup<X> { ArrayGroup(x: xs) }
}
func box<C: G>(@B _ c: () -> C) -> C { c() }
func use(_ xs: [Int]) { _ = box { for _ in xs { label() } } }"

arm "A6 buildExpression erasing to AnyG" "$common
struct AnyG: G { var x: any G }
@resultBuilder enum B {
    static func buildExpression<X: G>(_ x: X) -> AnyG { AnyG(x: x) }
    static func buildBlock<X: G>(_ x: X) -> X { x }
    static func buildArray<X: G>(_ xs: [X]) -> ArrayGroup<X> { ArrayGroup(x: xs) }
}
func box<C: G>(@B _ c: () -> C) -> C { c() }
func use(_ xs: [Int]) { _ = box { for _ in xs { label() } } }"

arm "A7 SwiftUI VStack { for }" "import SwiftUI
func label(_ s: String) -> some View { Text(s) }
func use(_ xs: [String]) -> some View { VStack { for x in xs { label(x) } } }"

arm "A8 SwiftUI ForEach over an opaque helper" "import SwiftUI
func label(_ s: String) -> some View { Text(s) }
func use(_ xs: [String]) -> some View { VStack { ForEach(xs, id: \\.self) { label(\$0) } } }"
