import MetalUICore
import MetalUILayout

// Paths, shadows and transforms, lane 2 — render effects (rulings `GX-G`,
// `GX-H`, `GX-I`, `GX-P`). Spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §4.2
// and §6; SwiftUI's side is `docs/probes/swiftui-paths-shadows-transforms.swift`,
// arms T1–T16, H1–H7, X1–X5 and N1–N9.

/// One render effect, as a legacy element's `Decoration` records it (in
/// written order) and as a proposal layer's case is read: what it does to the
/// element's laid-out rectangle, never to its layout.
enum RenderEffectSpec: Hashable, Sendable {
    case rotation(Angle, anchor: UnitPoint)
    case scale(x: Double, y: Double, anchor: UnitPoint)
    case offset(x: Pixels, y: Pixels)

    /// The effect's map in points over `rect` — the element's rectangle in the
    /// space its primitives are emitted in (already moved by the scroll
    /// translation, `GX-P` item 4): `T(A) · L · T(−A)` with `A` the anchor of
    /// `rect`, or a plain translation.
    func affine(in rect: Bounds<Pixels>) -> Affine2D {
        func anchorPoint(_ u: UnitPoint) -> (Double, Double) {
            (Double(rect.origin.x.value) + u.x * Double(rect.size.width.value),
             Double(rect.origin.y.value) + u.y * Double(rect.size.height.value))
        }
        switch self {
        case let .rotation(angle, anchor):
            let (ax, ay) = anchorPoint(anchor)
            return .rotation(radians: angle.radians, about: ax, ay)
        case let .scale(x, y, anchor):
            let (ax, ay) = anchorPoint(anchor)
            return .scale(x: x, y: y, about: ax, ay)
        case let .offset(x, y):
            return .translation(x: Double(x.value), y: Double(y.value))
        }
    }

    /// The animatable numbers, in a fixed order per kind (`GX-H`): the angle
    /// (radians) and its anchor; both factors and their anchor; both offsets.
    var numbers: [Double] {
        switch self {
        case let .rotation(angle, anchor): [angle.radians, anchor.x, anchor.y]
        case let .scale(x, y, anchor): [x, y, anchor.x, anchor.y]
        case let .offset(x, y): [Double(x.value), Double(y.value)]
        }
    }

    /// A small tag per kind, so a change of kind snaps (`LR-AS`).
    var kindTag: Int {
        switch self {
        case .rotation: 0
        case .scale: 1
        case .offset: 2
        }
    }

    /// This effect's kind with `numbers` read back in `numbers`' order.
    func with(_ numbers: ArraySlice<Double>) -> RenderEffectSpec {
        let n = Array(numbers)
        switch self {
        case .rotation:
            return .rotation(Angle(radians: n[0]), anchor: UnitPoint(x: n[1], y: n[2]))
        case .scale:
            return .scale(x: n[0], y: n[1], anchor: UnitPoint(x: n[2], y: n[3]))
        case .offset:
            return .offset(x: Pixels(Float(n[0])), y: Pixels(Float(n[1])))
        }
    }
}

// MARK: - The proposal vocabulary (one `LayoutModifier` layer each, `GX-H`)

extension ProposalElementGroup {
    /// Rotates this view's rendering by `angle` about `anchor` of its own
    /// rectangle — SwiftUI's `rotationEffect(_:anchor:)`. Positive angles turn
    /// clockwise (T1, T2). **Render only**: the layout is unchanged (the layer
    /// answers its content's size, T1), hit testing follows the drawn shape
    /// (H1, H6, H7) and the accessibility frame is the rotated rectangle's
    /// bounding box (X2; divergence 107 for angles off a right angle). One
    /// layer, one identity level (`MC-C`). The angle and the anchor animate.
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center)
        -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.rotationEffect(angle, anchor: anchor))
    }

    /// Scales this view's rendering by `s` on both axes about `anchor` —
    /// SwiftUI's `scaleEffect(_:anchor:)`. Render only (T3); a negative factor
    /// flips (T5), zero draws nothing (T5b). Text is resampled, not
    /// re-rasterized (divergence 106).
    public func scaleEffect(_ s: Double, anchor: UnitPoint = .center)
        -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.scaleEffect(x: s, y: s, anchor: anchor))
    }

    /// Scales this view's rendering by `s.width` horizontally and `s.height`
    /// vertically — the size form of `scaleEffect(x:y:anchor:)` (T4b).
    public func scaleEffect(_ s: SizeD, anchor: UnitPoint = .center)
        -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.scaleEffect(x: s.width, y: s.height, anchor: anchor))
    }

    /// Scales this view's rendering by `x` horizontally and `y` vertically
    /// about `anchor` (T4).
    public func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center)
        -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.scaleEffect(x: x, y: y, anchor: anchor))
    }

    /// Moves this view's rendering by `(x, y)` — SwiftUI's `offset(x:y:)`.
    /// Siblings do not move (T6b); hit testing moves with it (H4).
    public func offset(x: Pixels = Pixels(0), y: Pixels = Pixels(0))
        -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.offset(x: x, y: y))
    }

    /// Moves this view's rendering by `offset` — the size form of
    /// `offset(x:y:)` (T6c).
    public func offset(_ offset: Size<Pixels>) -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.offset(x: offset.width, y: offset.height))
    }
}

// MARK: - The legacy vocabulary (`Decoration.renderEffects`, `GX-H`)

extension StyledElement {
    /// Rotates this element's rendering by `angle` about `anchor` — SwiftUI's
    /// `rotationEffect(_:anchor:)`, returning `Self` (no identity level, no id
    /// moves). Effects keep their written order among themselves, and always
    /// wrap the whole element — its background and border too, wherever they
    /// were written (divergence 108). Animates on the window's animation store.
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> Self {
        appendingRenderEffect(.rotation(angle, anchor: anchor))
    }

    /// Scales this element's rendering by `s` about `anchor`; see
    /// `rotationEffect(_:anchor:)` for the legacy rules.
    public func scaleEffect(_ s: Double, anchor: UnitPoint = .center) -> Self {
        appendingRenderEffect(.scale(x: s, y: s, anchor: anchor))
    }

    /// Scales this element's rendering by `s.width` × `s.height` about `anchor`.
    public func scaleEffect(_ s: SizeD, anchor: UnitPoint = .center) -> Self {
        appendingRenderEffect(.scale(x: s.width, y: s.height, anchor: anchor))
    }

    /// Scales this element's rendering by `x` × `y` about `anchor`.
    public func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> Self {
        appendingRenderEffect(.scale(x: x, y: y, anchor: anchor))
    }

    /// Moves this element's rendering by `(x, y)`; siblings stay put.
    public func offset(x: Pixels = Pixels(0), y: Pixels = Pixels(0)) -> Self {
        appendingRenderEffect(.offset(x: x, y: y))
    }

    /// Moves this element's rendering by `offset`.
    public func offset(_ offset: Size<Pixels>) -> Self {
        appendingRenderEffect(.offset(x: offset.width, y: offset.height))
    }

    func appendingRenderEffect(_ effect: RenderEffectSpec) -> Self {
        var copy = self
        copy.decoration.renderEffects.append(effect)
        return copy
    }
}

// MARK: - The pass helpers

extension PrepaintPass {
    /// Runs `body` — the content's registration — inside `effect` over
    /// `bounds` (`GX-I`): hitboxes store the inverse composed map and the
    /// outer clip, accessibility records the transformed bounding box.
    func withRenderEffect<R>(_ effect: RenderEffectSpec, bounds: Bounds<Pixels>, _ body: () -> R) -> R {
        frame.prepaintWithRenderEffect(effect, bounds: bounds, body)
    }

    /// `body` inside each of `effects` in written order (the last written is
    /// the outermost) — a legacy element's `Decoration.renderEffects`.
    func withRenderEffects<R>(_ effects: [RenderEffectSpec], bounds: Bounds<Pixels>, _ body: () -> R) -> R {
        guard let outermost = effects.last else { return body() }
        return withRenderEffect(outermost, bounds: bounds) {
            withRenderEffects(Array(effects.dropLast()), bounds: bounds, body)
        }
    }

    /// Runs `register` — a proposal wrapper's own `registerHandlers` — then
    /// `content`, letting an effect opened inside `content` at the same
    /// rectangle transform what `register` registered (`GX-P` item 1).
    func sharingRegistrationsWithEffects<R>(at bounds: Bounds<Pixels>, register: () -> Void,
                                            content: () -> R) -> R {
        frame.sharingRegistrationsWithEffects(at: bounds, register: register, content: content)
    }
}

extension PaintPass {
    /// Runs `body` — the content's paint — inside `effect` over `bounds`
    /// (`GX-G`): every primitive emitted is mapped, flattened on the CPU for a
    /// translation plus a uniform positive scale, a transform record otherwise.
    /// A degenerate map (a zero scale) paints nothing.
    func withRenderEffect(_ effect: RenderEffectSpec, bounds: Bounds<Pixels>, _ body: () -> Void) {
        frame.paintWithRenderEffect(effect, bounds: bounds, body)
    }

    /// `body` inside each of `effects` in written order (the last written is
    /// the outermost).
    func withRenderEffects(_ effects: [RenderEffectSpec], bounds: Bounds<Pixels>, _ body: () -> Void) {
        guard let outermost = effects.last else { return body() }
        withRenderEffect(outermost, bounds: bounds) {
            withRenderEffects(Array(effects.dropLast()), bounds: bounds, body)
        }
    }
}

// MARK: - Frame (skeleton — red commit)

extension Frame {
    func prepaintWithRenderEffect<R>(_ effect: RenderEffectSpec, bounds: Bounds<Pixels>, _ body: () -> R) -> R {
        body()
    }

    func paintWithRenderEffect(_ effect: RenderEffectSpec, bounds: Bounds<Pixels>, _ body: () -> Void) {
        body()
    }

    func sharingRegistrationsWithEffects<R>(at bounds: Bounds<Pixels>, register: () -> Void,
                                            content: () -> R) -> R {
        register()
        return content()
    }
}

/// The animation-store key of a legacy element's render-effect track (ruling
/// `GX-H`): a store key, never a `StateTable` slot, so the reserved names stay
/// seven (`theSevenRetentionSlotsAreMutuallyDistinct`).
@MainActor
func legacyEffectsAnimationKey(for id: GlobalElementID) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim-effects"))
}
