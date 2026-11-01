import Testing
import MetalUITestSupport

// G1 lane 1 — typecheck guards for `@GestureState` and `updating` (rulings `GS-A`, `GS-B`). Whole-file Swift 6 against a
// PLAIN `import MetalUI` (`typecheckFile`, ruling SA-P). **A guard skips silently when `.build/<triple>/debug/Modules` is
// absent** (CLAUDE.md, "Guards"); grep the log for `GS GUARD`. Each guard is mutated red once (record §135).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func separate(_ name: String, positive: String, negative: String) throws {
    let p = try typecheckFile(positive, importing: "MetalUI")
    print("GS GUARD \(name) positive: succeeded=\(p.succeeded)\n\(p.messages)")
    let n = try typecheckFile(negative, importing: "MetalUI")
    print("GS GUARD \(name) negative: succeeded=\(n.succeeded)\n\(n.messages)")
    try #require(p.succeeded != n.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(p.output)\n\(n.output)")
    #expect(p.succeeded, "\(p.output)")
    #expect(!n.succeeded, "\(n.output)")
}

/// **GS.1 — the eight `GestureState` spellings compile for an outside module** (`GS-B`). The negative arm passes a
/// reset closure of the wrong shape. Mutation: remove `init(resetTransaction:)`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theEightGestureStateSpellingsCompileForAnOutsideModule() throws {
    try separate("GS.1", positive: """
        @MainActor public struct Spellings: Component {
            @GestureState var a = 0
            @GestureState(wrappedValue: 0, resetTransaction: Transaction(animation: .easeOut(duration: 0.2))) var b: Int
            @GestureState(wrappedValue: 0, reset: { _, t in t.animation = .linear(duration: 0.1) }) var c: Int
            @GestureState(initialValue: 0) var d: Int
            @GestureState(initialValue: 0, resetTransaction: Transaction()) var e: Int
            @GestureState(initialValue: 0, reset: { _, _ in }) var f: Int
            @GestureState var g: Int?
            @GestureState(resetTransaction: Transaction()) var h: Int?
            @GestureState(reset: { _, _ in }) var i: Int?
            public var content: some ElementGroup {
                Box().gesture(DragGesture().updating($a) { v, st, t in st = Int(v.translation.width.value); t.animation = nil })
            }
        }
        """, negative: """
        @MainActor public struct Bad: Component {
            @GestureState(wrappedValue: 0, reset: { (v: Int) in }) var c: Int
            public var content: some ElementGroup { Box() }
        }
        """)
}

/// **GS.2 — `updating` chains with `onChanged`/`onEnded`, returning the receiver's own type, on the four recognizers**
/// (`GS-B`). The negative arm passes a body of the wrong shape (composed gestures take `updating` since `GE-E`). Mutation: remove `LongPressGesture.updating`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func updatingChainsOnTheConcreteGestures() throws {
    try separate("GS.2", positive: """
        @MainActor public struct Chains: Component {
            @GestureState var n = 0
            @GestureState var b = false
            @GestureState var m = 1.0
            public var content: some ElementGroup {
                Box().gesture(DragGesture().updating($n) { _, st, _ in st += 1 }.onChanged { _ in }.onEnded { _ in })
                Box().gesture(LongPressGesture().updating($b) { v, st, _ in st = v }.onEnded { _ in })
                Box().gesture(MagnifyGesture().updating($m) { v, st, _ in st = v.magnification }.onCancelled { })
                Box().gesture(RotateGesture().updating($m) { _, st, _ in st = 0 })
                Box().gesture(TapGesture().updating($n) { _, _, _ in }.onEnded { })
                Box().gesture(SpatialTapGesture().updating($n) { _, _, _ in }.onEnded { _ in })
                Box().gesture(DragGesture().onChanged { _ in }.updating($n) { _, st, _ in st += 1 }.onEnded { _ in })
            }
        }
        """, negative: """
        @MainActor public struct Bad: Component {
            @GestureState var n = 0
            public var content: some ElementGroup {
                Box().gesture(DragGesture().updating($n) { _, _ in })
            }
        }
        """)
}

/// **GS.3 — `wrappedValue` is get-only** (`GS-B`): reading compiles, assigning does not. Mutation: give
/// `wrappedValue` a `nonmutating set`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aGestureStateWrappedValueHasNoSetter() throws {
    try separate("GS.3", positive: """
        @MainActor public struct Reads: Component {
            @GestureState var n = 0
            public var content: some ElementGroup {
                Box().gesture(DragGesture().updating($n) { _, st, _ in st += 1 }.onChanged { _ in _ = n + 1 })
            }
        }
        """, negative: """
        @MainActor public struct Writes: Component {
            @GestureState var n = 0
            public var content: some ElementGroup {
                Box().gesture(DragGesture().updating($n) { _, st, _ in st += 1 }.onChanged { _ in n = 1 })
            }
        }
        """)
}

/// **GS.4 — the box and the finished hook are unreachable from an outside module** (`GS-A`, `GS-C`): a plain importer
/// can name `GestureState` and not `GestureStateBox`. Mutation: make `GestureStateBox` public.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theGestureStateBoxIsNotReachable() throws {
    try separate("GS.4", positive: """
        @MainActor public func spelled() { let _: GestureState<Int> = GestureState(wrappedValue: 0) }
        """, negative: """
        @MainActor public func bad() { let _: GestureStateBox<Int>? = nil }
        """)
}

/// **GS.5 — `updating` is `@MainActor`, so its body and `GestureState`'s `reset:` are too** (`GS-S`, divergence 646). The
/// positive arm calls it from `@MainActor` code; the negative arm from a `nonisolated` function. **Limit:** a closure
/// literal in `@MainActor` code is inferred main-actor and a `@MainActor` function reference converts to a nonisolated
/// closure type without error, so mutating only the `body:`/`reset:` parameter type reddens nothing (measured, record §135);
/// the pin is the method's isolation. Mutation (red): drop `@MainActor` from `DragGesture.updating` (body replaced by `_ = state; _ = body`).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theUpdatingBodyAndTheResetClosureAreMainActor() throws {
    try separate("GS.5", positive: """
        @MainActor func body(_ v: DragGesture.Value, _ s: inout Int, _ t: inout Transaction) { s = 1 }
        @MainActor func reset(_ v: Int, _ t: inout Transaction) { t.animation = nil }
        @MainActor public struct Spelled: Component {
            @GestureState(wrappedValue: 0, reset: reset) var a: Int
            public var content: some ElementGroup {
                Box().gesture(DragGesture().updating($a, body: body))
            }
        }
        """, negative: """
        nonisolated func offMain(_ g: GestureState<Int>) -> DragGesture {
            DragGesture().updating(g) { _, s, _ in s = 1 }
        }
        """)
}
