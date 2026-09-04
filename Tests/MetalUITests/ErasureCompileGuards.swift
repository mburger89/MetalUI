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
    // is unusable for some reason that has nothing to do with where an
    // associated type sits in a signature.
    //
    // `requestLayout` is the phase that opens, and the reason is exactly the
    // rule the third guard below pins: its only associated type is in its
    // **return**, where the compiler can erase it. Nothing about it is
    // `inout`-free — `pass` is `inout` too — so this pair is not a statement
    // about `inout` at all.
    let result = try typecheck("""
        @MainActor func probe(element: inout any Element, pass: inout LayoutPass) {
            let id = GlobalElementID.child(of: nil, at: 0, name: nil)
            _ = element.requestLayout(id, pass: &pass)
        }
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "requestLayout returns its associated type and takes none, so it must open:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func prepaintCannotBeCalledOnAnExistentialElement() throws {
    // **The reason `AnyElement` exists.** A member is usable on an existential
    // only when its associated types appear in **covariant** (result) position,
    // where the compiler can erase them to their upper bound — SE-0309.
    // `prepaint` takes `LayoutState` as a *parameter*, and a parameter needs the
    // caller to name the type, which is precisely what the existential hid.
    //
    // **Not because it is `inout`.** That is §4.6's wording, it is narrower than
    // the truth, and the sibling guard below measures the difference: a plain
    // by-value associated-type parameter is rejected identically. So dropping
    // `inout` from `Element.prepaint` would leave this test red and `AnyElement`
    // just as necessary — the only change that would turn this green is removing
    // the associated type from the parameter list entirely, at which point the
    // erasure really would be redundant and this file should go.
    //
    // The guard is worth keeping past the day it was measured because the
    // trigger is a signature shape, not a compiler release: any new phase that
    // passes an associated type in loses that phase from every existential too.
    let result = try typecheck("""
        @MainActor func probe(element: inout any Element, bounds: Bounds<Pixels>,
                              layoutPass: inout LayoutPass, pass: inout PrepaintPass) {
            let id = GlobalElementID.child(of: nil, at: 0, name: nil)
            var layout = element.requestLayout(id, pass: &layoutPass).1
            _ = element.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "`any Element` can drive prepaint after all — §4.6's whole reason for a hand-written erasure")
    #expect(result.messages.contains("prepaint"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
    // **The discriminator, and it is not optional.** Measured: renaming
    // `Element.prepaint` away yields `value of type 'any Element' has no member
    // 'prepaint'`, which contains both "prepaint" and "any Element" — so the two
    // obvious substring checks are both satisfied by a `prepaint` that does not
    // exist, and the test would claim the existential could not be opened when
    // there was nothing to open it for. The diagnostic *group* is the stable
    // name for the property, where the surrounding prose is not.
    #expect(result.messages.contains("#ExistentialMemberAccess"),
            "rejected, but not because the existential could not be opened:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anAssociatedTypeInParameterPositionBlocksExistentialUseEvenWithoutInout() throws {
    // **§4.6's stated mechanism is narrower than the real one, and this pins the
    // real one.** The spec says `LayoutState` and `PrepaintState` "appear in
    // `inout` (invariant) position and cannot be opened", which reads as though
    // dropping `inout` would restore the existential. It would not: measured
    // here on a protocol reduced to nothing but the shape, a **by-value**
    // associated-type parameter is rejected with the identical diagnostic.
    //
    // The rule is SE-0309's: a member is usable on an existential only when its
    // associated types appear in **covariant** (result) position, because only
    // there can the compiler erase them to their upper bound. Every parameter
    // position — `inout` or not — needs the caller to name the type, and there
    // is no name for it.
    //
    // Which matters for what a future signature change costs. Removing `inout`
    // from `Element.prepaint` — a plausible "simplification", since §4.1 threads
    // it that way only so an element can mutate in place — would not make
    // `AnyElement` redundant, and this guard says so without anyone having to
    // try it.
    let result = try typecheck("""
        protocol Phased {
            associatedtype S
            func make() -> S
            func byValue(_ s: S)
        }
        @MainActor func probe(p: any Phased) {
            let s = p.make()
            p.byValue(s)
        }
        _ = probe
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "a by-value associated-type parameter opens after all; §4.6's mechanism needs restating")
    #expect(result.messages.contains("#ExistentialMemberAccess"),
            "rejected, but not because the existential could not be opened:\n\(result.output)")
}

@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aCovariantAssociatedTypeCanBeUsedOnAnExistential() throws {
    // The pair, and the half that makes the rule a *rule* rather than "nothing
    // with an associated type ever works on an existential". `make() -> S` is
    // fine: the result is erased to `Any`. This is also why `requestLayout` —
    // whose only associated type is in its return — type-checks on an
    // `any Element` while the two later phases do not.
    let result = try typecheck("""
        protocol Phased {
            associatedtype S
            func make() -> S
        }
        @MainActor func probe(p: any Phased) {
            _ = p.make()
        }
        _ = probe
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "a covariant associated type must be usable, or the negative above proves nothing:\n\(result.output)")
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
            mutating func requestLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> LayoutNodeID {
                pass.requestNode(style: Style(), children: [])
            }
            mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                   pass: inout PrepaintPass) {}
            mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
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
    // The pair, and it carries more weight here than a pair usually does.
    // Measured: `Array`'s Copyable diagnostic is emitted even when the
    // fixture's *other* types are broken, so the negative above stays green
    // against a `MetalUI` in which `ElementObject` does not exist at all. This
    // test — identical fixture minus `~Copyable` — is the only thing that
    // catches that, because it is the half that has to succeed.
    let result = try typecheck("""
        @MainActor struct CopyableElement { var box: any ElementObject }
        @MainActor func container(children: [CopyableElement]) { _ = children }
        _ = container
        """, importing: "MetalUI")
    #expect(result.succeeded,
            "the copyable half must compile, or the negative above proves nothing:\n\(result.output)")
}

// MARK: - Fact 4 (Task 3): `.background()` is not offered on a `Component`

/// Spec §5's limit, as a compile guard rather than only as
/// `decorationBackedModifiersAreNotOfferedOnAComponent`'s type-name check.
/// `Decoration` is per-element state a `StyledElement`'s own `prepaint`
/// registers; `LayoutTree.setStyle` reaches only a node's `Style`, so
/// `background`/`onClick`/`focusable`/`keyContext` cannot distribute the way
/// `padding`/`width`/`height` do, and are deliberately not declared in the
/// `Component` extension at all. A regression that adds one makes this
/// *compile*, which no runtime test could see.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func backgroundCannotBeCalledOnAComponent() throws {
    let result = try typecheck("""
        struct Leafless: Component {
            var elementID: ElementID? { nil }
            var content: some ElementGroup { EmptyGroup() }
        }
        @MainActor func probe() {
            _ = Leafless().background(.accent)
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded,
            "`.background()` type-checks on a Component — it must stay Decoration-backed and undistributable:\n\(result.output)")
    #expect(result.messages.contains("background"),
            "rejected, but not for the reason this test is about:\n\(result.output)")
}
