import MetalUICore
import MetalUILayout

/// What one writer does to the environment it inherits. Internal: the public
/// modifiers below are the only producers (ruling EV-U).
///
/// `.theme` is a case of its own, not a transform, because it is the one
/// write allowed to change `theme`: `Frame.scopedValues(applying:)` re-stamps
/// `theme` and `pixelLength` after every `.transform`, so a `\.self` write
/// cannot reset either.
enum EnvironmentWrite {
    case transform(@MainActor (inout EnvironmentValues) -> Void)
    case theme(Theme)
}

/// What an `EnvironmentScope` carries between phases: the values it computed in
/// layout, and its content's own layout.
public struct EnvironmentScopeLayout<ContentLayout> {
    var values: EnvironmentValues
    var content: ContentLayout
}

/// A writer: its content, run with one write applied to the environment it
/// inherits (rulings EV-A, EV-B, EV-V).
///
/// **Transparent to layout and to identity.** It contributes no layout node,
/// consumes no cursor index and mints no id: it forwards `parent` and `cursor`
/// to its content unchanged and returns the content's nodes unchanged —
/// `StyledComponent`'s shape (ruling CO-U). So `X()` and
/// `X().environment(\.k, v)` give `X` the same `GlobalElementID`, and a value
/// that changes between frames keeps the state below it, as probe D measured
/// in SwiftUI.
///
/// **The write runs once per frame, in layout.** `requestGroupLayout` computes
/// the scope's values from a copy of the current top and stores them;
/// `prepaintGroup` and `paintGroup` push those stored values and never run the
/// write again. So all three phases read identical values even when a
/// `transformEnvironment` closure reads a counter, a clock or a model
/// (ruling EV-V).
///
/// **Where it can and cannot go** (ruling EV-B). Over any `ElementGroup`: a
/// legacy element, proposal content, a `Component`, a builder group. Not as a
/// window root, `Deferred` content or a `List` row, each of which requires an
/// `Element` — write the scope outside instead. Over **legacy** content, not
/// directly before `.padding` or a handler modifier: `.theme(.dark).padding(4)`
/// and `.theme(.dark).onClick {}` do not compile; write
/// `.padding(4).theme(.dark)`. Over **proposal** content the proposal
/// `.padding(_:)` does compile after a scope; whether it sits inside or outside
/// the scope is not measured (ruling EV-X).
///
/// **`.frame(width:height:)` may follow a scope**, because it is declared on
/// `ElementGroup` and returns a `StyledElement`, so any `StyledElement`
/// modifier may follow *it*. **Such a modifier sits OUTSIDE the scope**, as in
/// SwiftUI (ruling EV-X, probe `swiftui-disabled-ancestor-and-order.swift` O2,
/// O3, O6): in `X().theme(.dark).frame(width: 20, height: 20).background(.surface)`
/// the frame layer paints with the enclosing theme, and only `X` paints dark.
/// Nothing implements this: the frame layer registers and paints in its own
/// phases, outside its content's push. Pinned by the after-`.theme` arm of
/// `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`.
public struct EnvironmentScope<Content: ElementGroup>: ElementGroup {
    var content: Content
    let write: EnvironmentWrite

    init(content: Content, write: EnvironmentWrite) {
        self.content = content
        self.write = write
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], EnvironmentScopeLayout<Content.GroupLayout>) {
        // The ONLY place the write runs (ruling EV-V). `parent` and `cursor`
        // are forwarded unchanged: a scope is not a level in the tree.
        let values = pass.frame.scopedValues(applying: write)
        let (nodes, layout) = pass.frame.withEnvironment(values) {
            content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        return (nodes, EnvironmentScopeLayout(values: values, content: layout))
    }

    public mutating func prepaintGroup(layout: inout EnvironmentScopeLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // The values layout stored, not the write run again (ruling EV-V).
        pass.frame.withEnvironment(layout.values) {
            content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
    }

    public mutating func paintGroup(layout: inout EnvironmentScopeLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        pass.frame.withEnvironment(layout.values) {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
    }
}

/// A scope over proposal content is proposal content.
///
/// **An obligation for the modifier-composition merge** (ruling EV-W): when
/// `ProposalElementGroup` gains `requestProposalGroupLayout`, this empty
/// conformance stops compiling, and its implementation must go through the
/// same resolve-once-then-push path as `requestGroupLayout` above. A bare
/// forward skips the layout-phase push; the layout slot of
/// `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase` is the test
/// that sees it.
extension EnvironmentScope: ProposalElementGroup where Content: ProposalElementGroup {}

extension ElementGroup {
    /// Sets one environment value for this content and everything below it.
    ///
    /// The nearest writer wins: `X().environment(\.k, 2).environment(\.k, 1)`
    /// reads 2 (ruling EV-A, probe A2). A plain write replaces whatever a
    /// transform above it computed (A8).
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                               _ value: V) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { $0[keyPath: keyPath] = value })
    }

    /// Transforms one environment value, starting from what this content
    /// inherits: a `+10` inside a `+100` reads 110 (ruling EV-A, probe A7).
    ///
    /// The closure runs **once per frame**, in layout (ruling EV-V).
    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                                        transform: @escaping @MainActor (inout V) -> Void)
        -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { transform(&$0[keyPath: keyPath]) })
    }

    /// Disables interaction with this content and everything below it when
    /// `disabled` is true.
    ///
    /// **An AND with what it inherits, not a plain write** (ruling EV-D, probe
    /// `swiftui-environment-scoping.swift` B): `.disabled(false)` inside a
    /// disabled ancestor stays disabled (B3, B6), while a raw
    /// `.environment(\.isEnabled, true)` written below one re-enables (B5).
    ///
    /// What "disabled" does is decided in one place, `Frame.registerHandlers`,
    /// which reads the resulting `isEnabled` (rulings EV-E, EV-F, EV-T): no
    /// hitbox, so a click reaches an enabled ancestor or what lies under the
    /// target; no focus, action handlers, raw `onKey` or `keyContext`; and the
    /// `.disabled` trait on a declared accessibility node. A modifier written
    /// AFTER the scope sits outside it: `X().disabled(true).frame(width: 40,
    /// height: 40).onClick {}` fires (ruling EV-X, probe O2).
    public func disabled(_ disabled: Bool) -> EnvironmentScope<Self> {
        transformEnvironment(\.isEnabled) { $0 = $0 && !disabled }
    }

    /// Sets `dynamicTypeSize`. Carried; changes no built-in text size, as in
    /// SwiftUI on macOS (ruling EV-I).
    public func dynamicTypeSize(_ size: DynamicTypeSize) -> EnvironmentScope<Self> {
        environment(\.dynamicTypeSize, size)
    }

    /// Resolves every token below against `theme` — the only public theme
    /// writer (ruling EV-G).
    ///
    /// Still **paint-only**: the scoped theme is read through `PaintPass.theme`
    /// and nowhere else. A `Deferred` declared inside the scope keeps it; a
    /// portal escapes clip, offset and layer, not scope.
    public func theme(_ theme: Theme) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .theme(theme))
    }
}
