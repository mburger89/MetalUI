import Testing
import MetalUITestSupport

// Spec §4.6 records three things that do **not** work, and which is why
// `AnyElement` is hand-written rather than `any Element`. None of them can be
// observed by a runtime test: each is a property of what the type checker
// accepts, so a regression makes the offending code *compile* and every test in
// the repo stays green. So they are compiled here, against the built module, by
// the same machinery `PhaseSeparationTests` uses (ruling EP-1).
//
// **Every negative is paired with a positive, and asserts against
// `TypecheckResult.messages`, never `output`.** `swiftc` echoes the offending
// source line beneath each diagnostic, so `output.contains("prepaint")` is
// satisfied by a fixture rejected for a typo — measured on this branch, where
// three phase-separation negatives passed against a `MetalUI` that declared no
// pass type at all.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — erasure guard skipped"

// MARK: - Fact 1: `any Element` cannot drive the pipeline

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func requestLayoutCanBeCalledOnAnExistentialElement() throws {
    // The load-bearing half of the pair. Without it, the negative below passes
    // just as well when `Element` has no phases at all, or when the existential
    // is unusable for some reason that has nothing to do with `inout`.
    let result = try typecheck("""
        @MainActor func probe(element: inout any Element, pass: inout LayoutPass) {
            _ = element.requestLayout(nil, pass: &pass)
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "requestLayout is fine on an existential — only the inout-state phases are not:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func prepaintCannotBeCalledOnAnExistentialElement() throws {
    // **The reason `AnyElement` exists.** An existential can be opened for a
    // member whose associated types occur only in parameter or return position;
    // `LayoutState` is `inout`, which is invariant, so the caller would have to
    // *name* the associated type to supply the argument and there is no name
    // for it.
    //
    // The guard is worth keeping past the day it was measured, because the
    // trigger is a signature shape, not a compiler release: adding any further
    // `inout` associated-type parameter to `Element` removes that phase from
    // every existential too, and adding one that is *not* `inout` would make
    // this test go green and the erasure look redundant when it is not.
    let result = try typecheck("""
        @MainActor func probe(element: inout any Element, bounds: Bounds<Pixels>,
                              layoutPass: inout LayoutPass, pass: inout PrepaintPass) {
            var layout = element.requestLayout(nil, pass: &layoutPass).1
            _ = element.prepaint(nil, bounds: bounds, layout: &layout, pass: &pass)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "`any Element` can drive prepaint after all — §4.6's whole reason for a hand-written erasure")
    #expect(result.messages.contains("prepaint"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
    #expect(result.messages.contains("any Element"),
            "rejected, but not because the existential could not be opened:\n\(result.output)")
}

// MARK: - Fact 2's foundation: `ElementObject` is not `AnyObject`

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aStructCanConformToElementObject() throws {
    // `twoCopiesOfOneElementDoNotShareLayoutState` pins that the *shipped* box
    // is a value type. This pins the thing that makes a value type possible at
    // all: adding `: AnyObject` to `ElementObject` is a one-word change that
    // silently permits the class box back, and nothing else in the suite would
    // notice until someone wrote one.
    let result = try typecheck("""
        @MainActor struct ValueBox: ElementObject {
            var elementID: ElementID? { nil }
            mutating func requestLayout(_ id: GlobalElementID?,
                                        pass: inout LayoutPass) -> LayoutNodeID {
                pass.requestNode(style: Style(), children: [])
            }
            mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                                   pass: inout PrepaintPass) {}
            mutating func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                                pass: inout PaintPass) {}
        }
        _ = ValueBox.self
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "ElementObject rejects value types — the struct box §4.6 requires is then unwritable:\n\(result.output)")
}

// MARK: - Fact 3: gpui's move-only box has no Swift equivalent

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aNoncopyableElementCannotBeStoredInAnArray() throws {
    // §4.6: `struct AnyElement: ~Copyable` plus `[AnyElement]` is rejected, so
    // gpui's move-only `Box<dyn ElementObject>` cannot be transliterated. The
    // mechanism is `Array`'s implicit `where Element: Copyable`, not a missing
    // compiler feature — which is why the fixture declares its own noncopyable
    // struct rather than importing `AnyElement`: the property under test is
    // about `Array`, and stays measurable however `AnyElement` changes.
    let result = try typecheck("""
        @MainActor struct MoveOnlyElement: ~Copyable { var box: any ElementObject }
        @MainActor func container(children: [MoveOnlyElement]) { _ = children }
        _ = container
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "a noncopyable element can live in an Array after all; §4.6's rejection of a move-only box is stale")
    #expect(result.messages.contains("Copyable"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aCopyableElementCanBeStoredInAnArray() throws {
    // The pair. Identical fixture minus `~Copyable`: without it the negative
    // above would also pass against a fixture that failed to import, or in
    // which `ElementObject` did not exist.
    let result = try typecheck("""
        @MainActor struct CopyableElement { var box: any ElementObject }
        @MainActor func container(children: [CopyableElement]) { _ = children }
        _ = container
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "the copyable half must compile, or the negative above proves nothing:\n\(result.output)")
}
