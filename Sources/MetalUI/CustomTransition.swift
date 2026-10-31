import MetalUICore

// Round 3 item R3-2 — the `Transition` protocol (ruling family `MG-`). SwiftUI's side is
// `docs/probes/swiftui-matched-geometry.swift`, arms TP1–TP4.

/// Where a custom ``Transition`` is in its life: SwiftUI's `TransitionPhase`.
public enum TransitionPhase: Sendable, Hashable {
    /// About to be inserted: the state an insertion starts from.
    case willAppear
    /// In the hierarchy: the state at rest.
    case identity
    /// Removed: the state a removal ends at.
    case didDisappear

    /// `true` for ``identity``.
    public var isIdentity: Bool { self == .identity }

    /// `-1` for ``willAppear``, `0` for ``identity``, `1` for ``didDisappear``.
    public var value: Double {
        switch self {
        case .willAppear: -1
        case .identity: 0
        case .didDisappear: 1
        }
    }
}

/// The content a ``Transition`` modifies: a record of the effects `body(content:phase:)` applies, which
/// MetalUI animates between the phases' values. It is MetalUI's stand-in for SwiftUI's opaque
/// `PlaceholderContentView<Self>` — a custom transition returns this value, not a view, because a transition
/// is a paint effect here (`MG-F`, divergence 898). Only these effects exist: `opacity`, `scaleEffect` and
/// `offset`, composed in call order (opacities multiply, scales multiply, offsets add).
public struct TransitionContent: Sendable {
    var alpha: Double = 1
    var scale: Double = 1
    var anchor: UnitPoint = .center
    var dx: Double = 0
    var dy: Double = 0

    init() {}

    /// This content at `opacity` (multiplied into any already applied).
    public func opacity(_ opacity: Double) -> TransitionContent {
        var copy = self
        copy.alpha *= opacity
        return copy
    }

    /// This content scaled uniformly by `scale` about `anchor` of its own rectangle (scales multiply; the
    /// latest non-unit scale's anchor applies).
    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> TransitionContent {
        var copy = self
        copy.scale *= scale
        if scale != 1 { copy.anchor = anchor }
        return copy
    }

    /// This content displaced by `(x, y)` (offsets add).
    public func offset(x: Pixels = Pixels(0), y: Pixels = Pixels(0)) -> TransitionContent {
        var copy = self
        copy.dx += Double(x.value)
        copy.dy += Double(y.value)
        return copy
    }

    /// The atoms that take the content from `identity`'s state to this one at full activeness.
    func atoms(relativeTo identity: TransitionContent) -> [TransitionAtom] {
        var atoms: [TransitionAtom] = []
        let alpha = identity.alpha > 0 ? self.alpha / identity.alpha : self.alpha
        if alpha != 1 { atoms.append(.alpha(alpha)) }
        let scale = identity.scale != 0 ? self.scale / identity.scale : self.scale
        if scale != 1 { atoms.append(.scale(scale, anchor: anchor)) }
        let x = dx - identity.dx, y = dy - identity.dy
        if x != 0 || y != 0 { atoms.append(.translate(sizeX: 0, sizeY: 0, x: x, y: y)) }
        return atoms
    }
}

/// A transition the app defines: SwiftUI's `Transition` (iOS 17 style), used with `.transition(_:)` or wrapped in
/// an ``AnyTransition``.
///
/// ```swift
/// struct Pop: Transition {
///     func body(content: TransitionContent, phase: TransitionPhase) -> TransitionContent {
///         content.scaleEffect(phase.isIdentity ? 1 : 0.5).opacity(phase.isIdentity ? 1 : 0)
///     }
/// }
/// ```
///
/// An insertion animates from the `.willAppear` state to the `.identity` one; a removal from `.identity` to
/// `.didDisappear` (probe TP1, TP2: `willAppear` and `didDisappear` are the states, the phases' values the
/// animation runs between). It applies where ``AnyTransition`` does, on the animation of the conditional it is
/// written inside, and Reduce Motion turns it into an opacity fade.
///
/// **Not SwiftUI:** `body` returns ``TransitionContent`` (opacity, scale and offset only), not a view
/// (divergence 898); the protocol is `Sendable`; `properties` (`TransitionProperties`) does not exist.
public protocol Transition: Sendable {
    /// The content in `phase`.
    func body(content: TransitionContent, phase: TransitionPhase) -> TransitionContent
}

extension AnyTransition {
    /// Wraps a custom ``Transition``: SwiftUI's `AnyTransition(_:)` over a `Transition`.
    public init<T: Transition>(_ transition: T) {
        self.init(.custom(CustomTransition { phase in transition.body(content: TransitionContent(), phase: phase) }))
    }
}

/// A custom transition resolved per phase.
struct CustomTransition: Sendable {
    let resolve: @Sendable (TransitionPhase) -> TransitionContent

    init(_ resolve: @escaping @Sendable (TransitionPhase) -> TransitionContent) { self.resolve = resolve }

    func atoms(insertion: Bool) -> [TransitionAtom] {
        resolve(insertion ? .willAppear : .didDisappear).atoms(relativeTo: resolve(.identity))
    }
}

extension ElementGroup {
    /// ``transition(_:)-(AnyTransition)`` with a custom ``Transition`` (SwiftUI's `transition(_:)` over a
    /// `Transition`).
    public func transition<T: Transition>(_ transition: T) -> TransitionGroup<Self> {
        TransitionGroup(content: self, transition: AnyTransition(transition))
    }
}
