import MetalUICore
import MetalUILayout
import MetalUIPrimitives

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
    /// A shadow (`GX-J`): no map — a paint scope that shadows each leaf.
    case shadow(Color, radius: Pixels, x: Pixels, y: Pixels)
    /// A blur (`LK-K`): no map — a paint scope that blurs each leaf.
    case blur(radius: Pixels)

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
        case .shadow, .blur:
            return .identity
        }
    }

    /// The animatable numbers, in a fixed order per kind (`GX-H`): the angle
    /// (radians) and its anchor; both factors and their anchor; both offsets.
    var numbers: [Double] {
        switch self {
        case let .rotation(angle, anchor): [angle.radians, anchor.x, anchor.y]
        case let .scale(x, y, anchor): [x, y, anchor.x, anchor.y]
        case let .offset(x, y): [Double(x.value), Double(y.value)]
        case let .shadow(_, radius, x, y): [Double(radius.value), Double(x.value), Double(y.value)]
        case let .blur(radius): [Double(radius.value)]
        }
    }

    /// A small tag per kind, so a change of kind snaps (`LR-AS`).
    var kindTag: Int {
        switch self {
        case .rotation: 0
        case .scale: 1
        case .offset: 2
        case .shadow: 3
        case .blur: 4
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
        case let .shadow(token, _, _, _):
            return .shadow(token, radius: Pixels(Float(max(0, n[0]))), x: Pixels(Float(n[1])), y: Pixels(Float(n[2])))
        case .blur:
            return .blur(radius: Pixels(Float(max(0, n[0]))))
        }
    }

    /// Whether this is a shadow, which has no prepaint scope (a shadow never
    /// hits and publishes nothing, `GX-J`).
    var isShadow: Bool {
        if case .shadow = self { return true }
        return false
    }

    /// Whether this effect is a paint scope only — a shadow or a blur — which
    /// registers nothing and moves nothing (`GX-J`, `LK-K` item 4).
    var isPaintScopeOnly: Bool {
        switch self {
        case .shadow, .blur: true
        default: false
        }
    }
}

// MARK: - The proposal vocabulary (one `LayoutModifier` layer each, `GX-H`)

extension LayoutModifier {
    /// The render effect this layer applies, or `nil` for every other case.
    var renderEffect: RenderEffectSpec? {
        switch self {
        case let .rotationEffect(angle, anchor): .rotation(angle, anchor: anchor)
        case let .scaleEffect(x, y, anchor): .scale(x: x, y: y, anchor: anchor)
        case let .offset(x, y): .offset(x: x, y: y)
        default: nil
        }
    }
}

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
        // A shadow registers nothing and moves nothing (`GX-J`; H5, X6).
        // A blur likewise (`LK-K` item 4).
        guard !effect.isPaintScopeOnly else { return body() }
        return frame.prepaintWithRenderEffect(effect, bounds: bounds, body)
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
    /// the outermost). A shadow opens a shadow scope (`GX-J`), its colour on a
    /// store track under `id` when one is given (`legacyShadowColourKey`).
    func withRenderEffects(_ effects: [RenderEffectSpec], bounds: Bounds<Pixels>, id: GlobalElementID? = nil,
                           _ body: () -> Void) {
        guard let outermost = effects.last else { return body() }
        let inner = { withRenderEffects(Array(effects.dropLast()), bounds: bounds, id: id, body) }
        if case let .shadow(token, radius, x, y) = outermost {
            let color = id.map { storedAnimatedColor(token, at: legacyShadowColourKey(for: $0, index: effects.count - 1),
                                                     pass: self) } ?? resolve(token)
            withShadow(color: color, radius: radius, x: x, y: y, inner)
        } else if case let .blur(radius) = outermost {
            withBlur(radius: radius, inner)
        } else {
            withRenderEffect(outermost, bounds: bounds, inner)
        }
    }
}

// MARK: - Frame

/// One render effect open in prepaint (`GX-I`): the composed map from the
/// innermost effect's local points to window points, its inverse (`nil` when
/// degenerate), the clip at the outermost effect's entry in window points, and
/// the `clipBase` to restore.
struct PrepaintEffect {
    let composed: Affine2D
    let inverse: Affine2D?
    let outerClip: Bounds<Pixels>
    let savedClipBase: Int
}

/// A proposal wrapper's own registrations (`GX-P` item 1): its rect (window
/// points, in the space of the effects open where it registered), and what it
/// registered — each hitbox with its untranslated-by-clip rect and the clip in
/// force — and the range of accessibility records.
struct ShareCandidate {
    let rect: Bounds<Pixels>
    /// The clip in force at the registration, in the same space as `rect`
    /// (`GX-U` item 2: a record's pre-effect visible rect is `rect` cut by it).
    let clip: Bounds<Pixels>
    var hitboxes: [(index: Int, raw: Bounds<Pixels>, clip: Bounds<Pixels>)] = []
    var accessibility: Range<Int> = 0..<0
}

extension Frame {
    /// `bounds` moved by the scroll translation — the space primitives,
    /// hitboxes and an effect's anchor are in (`GX-P` item 4).
    func scrolled(_ bounds: Bounds<Pixels>) -> Bounds<Pixels> {
        Bounds(origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                             y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
               size: bounds.size)
    }

    /// `rect` (window points, already scrolled) as the platform should see it
    /// under the open prepaint effects and an element's own `ownEffects` over
    /// `bounds` — the bounding box of the transformed rect (`GX-I`: a focused
    /// field's caret handed to `setTextInputArea`).
    func effectBoundingBox(of rect: Bounds<Pixels>, ownEffects: [RenderEffectSpec] = [],
                           bounds: Bounds<Pixels>) -> Bounds<Pixels> {
        guard !prepaintEffects.isEmpty || !ownEffects.isEmpty else { return rect }
        var composed = prepaintEffects.last?.composed ?? .identity
        let scrolledBounds = scrolled(bounds)
        for effect in ownEffects.reversed() { composed = composed.concatenating(effect.affine(in: scrolledBounds)) }
        return composed.boundingBox(of: rect)
    }

    /// Prepaint inside `effect` (`GX-I`): composes its map onto the open ones,
    /// splits the clip (the clip in force becomes the outer clip, window
    /// space; clips pushed inside intersect in local space), transforms the
    /// registrations of enclosing proposal wrappers at the same rect
    /// (`GX-P` item 1), and runs `body`.
    func prepaintWithRenderEffect<R>(_ effect: RenderEffectSpec, bounds: Bounds<Pixels>, _ body: () -> R) -> R {
        effectScopesPushed += 1
        let rect = scrolled(bounds)
        let map = effect.affine(in: rect)
        let outerClip: Bounds<Pixels>
        if let top = prepaintEffects.last {
            // The clip at this entry is in the enclosing effect's local space:
            // its bounding box in window space, cut by that effect's outer clip
            // (divergence 109).
            outerClip = clipDepth > clipBase
                ? Self.intersect(top.outerClip, top.composed.boundingBox(of: activeClip))
                : top.outerClip
        } else {
            outerClip = activeClip
        }
        let composed = (prepaintEffects.last?.composed ?? .identity).concatenating(map)
        prepaintEffects.append(PrepaintEffect(composed: composed, inverse: composed.inverted,
                                              outerClip: outerClip, savedClipBase: clipBase))
        clipBase = clipDepth
        defer {
            clipBase = prepaintEffects.removeLast().savedClipBase
        }
        // The floor the effect's element entered at (`GX-U`): a legacy
        // element's effects open before any child enters, and a proposal
        // chain's layers enter no element between them, so it is still that
        // element's own — the chain itself needs no pass-through.
        shareWithEnclosingWrappers(at: rect, floor: shareFloorAtEntry)
        return body()
    }

    /// Runs `register` (a proposal wrapper's own registration) noting what it
    /// registers, then `content` with that noted as a share candidate
    /// (`GX-P` item 1). Free outside every effect but a candidate push.
    func sharingRegistrationsWithEffects<R>(at bounds: Bounds<Pixels>, register: () -> Void,
                                            content: () -> R) -> R {
        let rect = scrolled(bounds)
        let firstRecord = axEmissions.count
        shareCollecting.append(ShareCandidate(rect: rect, clip: activeClip))
        register()
        var candidate = shareCollecting.removeLast()
        candidate.accessibility = firstRecord..<axEmissions.count
        // A sharing wrapper is transparent (`GX-U`): candidates outside it
        // stay reachable from its content, through its own.
        return passingShareFloorThrough {
            shareCandidates.append(candidate)
            defer { shareCandidates.removeLast() }
            return content()
        }
    }

    /// Paint inside `effect` (`GX-G`): a scope mapping every primitive emitted
    /// in `body` — flattened on the CPU for a translation plus a uniform
    /// positive scale, a transform record otherwise, which splits the clip at
    /// entry. A flattening scope keeps the clip at its entry as `outer` too: a
    /// clip pushed inside it intersects nothing outside (`flatteningClipBase`)
    /// and, once mapped, is cut by that entry clip (`GX-X`, the LF-a fix). A
    /// degenerate map (a zero scale) paints nothing.
    func paintWithRenderEffect(_ effect: RenderEffectSpec, bounds: Bounds<Pixels>, _ body: () -> Void) {
        effectScopesPushed += 1
        let map = effect.affine(in: scrolled(bounds))
        guard map.determinant != 0, map.determinant.isFinite else { return }
        let device = map.scaledToDevice(scaleFactor)
        let flattens = device.isUniformPositiveScaleTranslation
        let outer = OuterMask(bounds: MUIBounds(activeClip.scaled(by: scaleFactor)),
                              radii: MUICorners(activeClipRadii.scaled(by: scaleFactor)),
                              depth: clipDepth)
        let scope = PaintScope(kind: .effect, effect: RenderEffect(affine: device), entryClipDepth: clipDepth,
                               flattens: flattens, outer: outer)
        let savedBase = clipBase, savedFlatteningBase = flatteningClipBase
        if flattens { flatteningClipBase = clipDepth } else { clipBase = clipDepth }
        paintScopes.append(scope)
        body()
        paintScopes.removeLast()
        clipBase = savedBase
        flatteningClipBase = savedFlatteningBase
    }

    /// A `Deferred`'s reset of the effect stack (`GX-G`), both phases: no open
    /// prepaint effect reaches its registrations, a barrier stops every open
    /// paint effect, and `clipBase` drops below the portal's root clip. A
    /// frame with no effect open pushes nothing.
    func withoutRenderEffects<R>(_ body: () -> R) -> R {
        let savedBase = clipBase
        clipBase = clipDepth
        defer { clipBase = savedBase }
        let savedEffects = prepaintEffects
        let savedCandidates = shareCandidates
        let savedFloors = (shareFloor, shareFloorAtEntry)
        prepaintEffects = []
        shareCandidates = []
        shareFloor = 0
        shareFloorAtEntry = 0
        defer {
            prepaintEffects = savedEffects
            shareCandidates = savedCandidates
            (shareFloor, shareFloorAtEntry) = savedFloors
        }
        guard paintScopes.contains(where: { $0.kind == .effect || $0.kind == .shadow || $0.kind == .blur })
        else { return body() }
        paintScopes.append(PaintScope(kind: .barrier, effect: .identity, entryClipDepth: clipDepth))
        defer { paintScopes.removeLast() }
        return body()
    }
}

/// The animation-store key of a legacy element's render-effect track (ruling
/// `GX-H`): a store key, never a `StateTable` slot, so the reserved names stay
/// seven (`theSevenRetentionSlotsAreMutuallyDistinct`).
@MainActor
func legacyEffectsAnimationKey(for id: GlobalElementID) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim-effects"))
}

/// A legacy element's `Decoration.renderEffects` at this frame (ruling
/// `GX-H`): every number of every effect (`RenderEffectSpec.numbers`) on one
/// store track at `legacyEffectsAnimationKey(for:)`, interpolated exactly as a
/// proposal layer's are. A change in the list's kinds (an effect added,
/// removed or of another kind) snaps the structure (`LR-AS`).
@MainActor
func animatedRenderEffects(_ declared: [RenderEffectSpec], for id: GlobalElementID, frame: Frame,
                           transaction: Animation?) -> [RenderEffectSpec] {
    let key = legacyEffectsAnimationKey(for: id)
    let kindsKey = GlobalElementID.child(of: id, at: 0, name: ElementID("$anim-effects.kinds"))
    let kinds = declared.map(\.kindTag)
    let numbers = declared.flatMap(\.numbers).map { Optional($0) }
    let store = frame.animationStore
    if store.value(at: kindsKey, as: [Int].self) != kinds {
        store.set(kinds, at: kindsKey)
        store.set(StoredNumberTracks(baseline: numbers, inFlight: [:]), at: key)
    }
    let values = animatedNumbers(numbers, at: key, frame: frame, transaction: transaction,
                                 range: -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude)
        .map { $0 ?? 0 }
    var out: [RenderEffectSpec] = []
    var cursor = 0
    for effect in declared {
        let count = effect.numbers.count
        out.append(effect.with(values[cursor..<cursor + count]))
        cursor += count
    }
    return out
}
