/// The input callbacks an element has asked to receive — `StyledElement`'s
/// fourth stored requirement, alongside `style`, `decoration` and `elementID`.
///
/// **A type of its own rather than a field on either of the other two, and both
/// exclusions are mechanical.** `Style` lives in `MetalUILayout`, which may
/// import only `MetalUICore` (CLAUDE.md's build constraint), and it is compared
/// field-by-field on whole-value equality by
/// `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` — a closure field
/// makes `Style` unequatable and takes that test with it. `Decoration` is paint
/// data: `Box.paint` reads it and nothing else does, while a handler is read in
/// `prepaint` by the frame and afterwards by the window.
///
/// **Empty is the default and it means "not a hit target".** A `Handlers` with
/// no callback set registers no hitbox at all — see
/// `PrepaintPass.registerHandlers(_:at:id:)` — which is what keeps an ordinary
/// `Box` transparent to the pointer and, more sharply, keeps every box inside a
/// `ScrollView` from swallowing that scroller's wheel.
///
/// **Bubble-only, and today that means "the topmost opaque handler wins".**
/// Design spec §3.5 cuts the capture phase, because an opaque hitbox already
/// swallows, which is the case framework spec §8.2 names capture for. What is
/// also absent — and is worth knowing before writing a nested pair — is
/// *chaining*: a click resolves to one hitbox and stops, so an `onClick` on a
/// container whose child also has one never sees a click that landed on the
/// child. There is no ancestry on a `Hitbox` to walk, exactly as there is no
/// scroll chaining in `Window.applyScroll` and for the same reason. Adding it
/// means putting a parent link on the registration, not changing dispatch.
public struct Handlers {
    /// Run when this element is clicked: pressed and released on **this same
    /// element**, with the pointer free to leave and return in between.
    ///
    /// `@MainActor` because everything that could reach it is: `Window`'s input
    /// path, the `StateTable` a handler will almost always write, and
    /// `StyledElement` itself. Typing it here rather than relying on the
    /// closure's context means a handler that captures a non-`Sendable` value
    /// is a compile error at the call site rather than a data race later.
    ///
    /// **One handler, and a second `onClick(_:)` REPLACES the first rather than
    /// adding to it.** `.onClick { a }.onClick { b }` runs only `b`, and still
    /// registers one hitbox. That is what every other modifier on
    /// `StyledElement` does — each writes one field — and it is written down
    /// because the name sounds additive in a way `background(_:)` does not, so
    /// "attach a second handler" is a plausible misreading with no diagnostic
    /// behind it.
    public var onClick: (@MainActor () -> Void)?

    public init() {}

    /// Whether this element asked for anything at all. The registration gate:
    /// an element with an empty set contributes no hitbox.
    var isEmpty: Bool { onClick == nil }
}
