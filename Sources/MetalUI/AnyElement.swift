import MetalUICore
import MetalUILayout

// Spec §4.6. A hand-written type erasure for `Element`, and the three things
// that do **not** work in its place. Each is recorded with the mechanism that
// makes it fail, not with a toolchain version — a mechanism can be re-checked,
// and two of the three are re-checked on every run by the guards named below.
//
// **1. `any Element` cannot drive the pipeline.** `requestLayout` on an
// `inout any Element` type-checks, but `prepaint` does not:
//
//     error: member 'prepaint' cannot be used on value of type 'any Element'
//     [#ExistentialMemberAccess]
//
// The mechanism is SE-0309's: a member is usable on an existential only when
// its associated types appear in **covariant** (result) position, where the
// compiler can erase them to their upper bound. `requestLayout` returns its
// `LayoutState` and nothing more, so it opens; `prepaint` and `paint` take
// theirs as parameters, and a parameter needs the *caller* to name the type,
// which is exactly what an existential has hidden.
//
// **§4.6 attributes this to `inout` specifically, and that is narrower than
// what is true.** Measured, on a protocol reduced to the shape and nothing
// else: a plain by-value associated-type parameter is rejected with the
// identical diagnostic. So dropping `inout` from `Element.prepaint` would not
// bring the existential back and would not make this file redundant — only
// removing the associated type from the parameter list would. Both halves are
// compiled on every run:
// `anAssociatedTypeInParameterPositionBlocksExistentialUseEvenWithoutInout` and
// `aCovariantAssociatedTypeCanBeUsedOnAnExistential`, alongside
// `prepaintCannotBeCalledOnAnExistentialElement` itself, in
// `ErasureCompileGuards.swift`.
//
// **2. The box must be a `struct`.** With a class box, two copies of one
// `AnyElement` — `Row { sep; sep }` — refer to a single box and therefore to a
// single `LayoutState`: the second `requestLayout` overwrites the first's, both
// copies then prepaint and paint against the second's state, and the first is
// laid out at the wrong bounds. There is no error and no diagnostic; the frame
// is simply wrong. Pinned by `twoCopiesOfOneElementDoNotShareLayoutState` in
// `PipelineTests.swift`, which reports `[2, 2]` instead of `[1, 2]` the moment
// `AnyElementBox` becomes a class.
//
// `ElementObject` is deliberately **not** constrained to `AnyObject`. That one
// word is all it would take to make the class box legal again, so its absence
// is load-bearing and is itself pinned, by
// `aStructCanConformToElementObject`.
//
// **3. gpui's move-only `Box<dyn ElementObject>` has no Swift equivalent.**
// `struct AnyElement: ~Copyable` compiles on its own, but `[AnyElement]` does
// not: `Array`'s `Element` parameter carries an implicit `Copyable`
// requirement, so a noncopyable type cannot be stored in one —
// `error: type 'AnyElement' does not conform to protocol 'Copyable'`. Rust's
// `Vec<Box<dyn ElementObject>>` needs no such conformance because move is the
// default there. The mechanism is the stdlib's generic requirement, not a
// missing feature of any particular compiler release; pinned by
// `aNoncopyableElementCannotBeStoredInAnArray`, which measures it on a bare struct
// so the guard survives any change to `AnyElement` itself.
//
// **Allocation.** §4.6's first mitigation is that result builders preserve
// concrete types: `Column { Label(…); Button(…) }` builds a statically-typed
// `Column<Pair<Label, Button>>` and boxes nothing. This file is for genuinely
// dynamic children only, and must not become the default path.

/// The type-erased face of `Element`: the three phases with every associated
/// type removed.
///
/// **Not `AnyObject`, on purpose** — see the note at the top of this file. A
/// conforming *value* type is what gives each `AnyElement` copy its own
/// `LayoutState`.
///
/// The phase states do not appear here at all. They are held by the conformer
/// between calls, which is what lets these signatures be existential-friendly
/// where `Element`'s are not.
@MainActor
public protocol ElementObject {
    /// The erased element's local identity (§4.3).
    var elementID: ElementID? { get }

    /// Runs the erased element's `requestLayout` and **stores** the
    /// `LayoutState` it returned.
    mutating func requestLayout(_ id: GlobalElementID?, pass: inout LayoutPass) -> LayoutNodeID

    /// Runs `prepaint` against the stored `LayoutState` and stores the
    /// `PrepaintState` it returned.
    mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                           pass: inout PrepaintPass)

    /// Runs `paint` against both stored states.
    mutating func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>, pass: inout PaintPass)
}

/// Holds one concrete element together with the state its phases hand forward.
///
/// **A `struct`, and the whole erasure depends on it.** See fact 2 at the top
/// of this file: a class here makes two copies of one `AnyElement` share a
/// single `LayoutState`, silently.
///
/// The states are `Optional` because the box cannot express "layout has run" in
/// the type system the way the pass structs express "this phase may paint". The
/// erasure trades that guarantee away: calling `prepaint` before `requestLayout`
/// is a trap here, where on a concrete `Element` it would not compile — the
/// caller could not have produced the `inout LayoutState` argument. Callers
/// inside `MetalUI` drive the phases in order; nothing outside can drive them
/// at all, because it cannot obtain a pass.
@MainActor
public struct AnyElementBox<E: Element>: ElementObject {
    var element: E
    var layoutState: E.LayoutState?
    var prepaintState: E.PrepaintState?

    public init(_ element: E) { self.element = element }

    public var elementID: ElementID? { element.elementID }

    public mutating func requestLayout(_ id: GlobalElementID?,
                                       pass: inout LayoutPass) -> LayoutNodeID {
        let (node, state) = element.requestLayout(id, pass: &pass)
        layoutState = state
        return node
    }

    public mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                                  pass: inout PrepaintPass) {
        guard var layout = layoutState else {
            preconditionFailure("AnyElement.prepaint before requestLayout: no LayoutState to pass")
        }
        // Written back because `Element.prepaint` takes its layout state
        // `inout` — §4.1 threads it that way so an element can mutate it in
        // place rather than copy it, and dropping the write-back would discard
        // that mutation before `paint` ever sees it.
        prepaintState = element.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
        layoutState = layout
    }

    public mutating func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                               pass: inout PaintPass) {
        guard var layout = layoutState else {
            preconditionFailure("AnyElement.paint before requestLayout: no LayoutState to pass")
        }
        guard var prepaint = prepaintState else {
            preconditionFailure("AnyElement.paint before prepaint: no PrepaintState to pass")
        }
        element.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
        layoutState = layout
        prepaintState = prepaint
    }
}

/// A heterogeneous `Element` for containers whose children are not known
/// statically (spec §4.6).
///
/// ```swift
/// let children = items.map { AnyElement(Row(item: $0)) }
/// ```
///
/// **Copying an `AnyElement` copies its element and its phase state**, because
/// `AnyElementBox` is a struct: two copies of one value are two independent
/// elements, which is what `Row { sep; sep }` requires. See fact 2 at the top
/// of this file for what a class box does instead.
///
/// The phases are `mutating`, so a container holding `[AnyElement]` must mutate
/// its children **in place** — `for i in children.indices { children[i].prepaint(…) }`.
/// `for child in children` does not compile, and that is the type system doing
/// the work rather than a convention this comment asks you to keep: the loop
/// variable is a `let`, so `error: cannot use mutating member on immutable
/// value` rejects the version that would have walked copies and dropped each
/// child's stored state. Measured, not assumed.
@MainActor
public struct AnyElement {
    var box: any ElementObject

    public init<E: Element>(_ element: E) {
        box = AnyElementBox(element)
    }

    /// The erased element's local identity (§4.3).
    public var elementID: ElementID? { box.elementID }

    public mutating func requestLayout(_ id: GlobalElementID?,
                                       pass: inout LayoutPass) -> LayoutNodeID {
        box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                                  pass: inout PrepaintPass) {
        box.prepaint(id, bounds: bounds, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, pass: &pass)
    }
}
