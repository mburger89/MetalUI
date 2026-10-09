import MetalUICore
import MetalUILayout

// Plan task 13, lane 2 — modifier wrappers at their phase (rulings `AN-AA`,
// `AN-AB`, `AN-AC`, as amended by `AN-AH` item 3; spec
// `docs/superpowers/specs/2026-09-30-transactions-animation-design.md` §6.3).
//
// Every track here lives in the window's `AnimationStore`, never in
// `StateTable`: no table entry is minted, so no `TB-AH` threshold, pinned table
// count or reserved name moves, and a track its frame does not touch is dropped
// at the frame's end — content that leaves and returns starts fresh, SwiftUI's
// answer for a removed view (`AN-AB`). The recipes are the legacy helpers',
// unchanged: numbers through `animateField` (`AnimatedStyle.swift`), colours
// through `advanceColor` (`AnimatedColor.swift`), the frame's transaction first
// and the lexical slot as a fallback (`AN-AI` item 4).
//
// **The phase rule** (`AN-AA`): a number that needs neither the theme nor the
// pointer/focus state interpolates in LAYOUT, where the layer rewrites its own
// case (a frame's size, a padding, an opacity, a clip's radius, a border's
// width) and prepaint and paint read the rewritten value off the same frame
// timestamp; a colour token interpolates in PAINT, where the theme exists.
//
// **Keys** (store keys, not `StateTable` names): a proposal layer's tracks are
// named children of the layer's own id — `$anim-layer.<case>` for its numbers,
// `$anim-layer.background`/`$anim-layer.border` for its colours — so a case
// change at one id (a `.frame` becoming a `.padding`) is a first sighting and
// snaps. A legacy element's border colour is `$anim-border` under its id. A
// component op is `$anim-op<k>` under `.child(of: component, at: member)`.

/// The `AnimationStore` key of a legacy element's border-colour track (`AN-AH`
/// item 3). A store key, not a `StateTable` slot: the reserved names stay seven.
@MainActor
func borderColourStoreKey(for id: GlobalElementID) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim-border"))
}

/// The `AnimationStore` key of one of a proposal layer's tracks.
@MainActor
func layerAnimationKey(_ id: GlobalElementID, _ name: String) -> GlobalElementID {
    .child(of: id, at: 0, name: ElementID("$anim-layer.\(name)"))
}

/// The `AnimationStore` key of op `k` on member `member` of the component `id`
/// (`AN-AC`). Below the member's position, so two members' ops are separate
/// tracks (`aComponentsOpsAnimateEachMemberSeparately`); the member's own
/// `$anim` baseline is never read or written.
@MainActor
func componentOpAnimationKey(_ id: GlobalElementID, member: Int, op k: Int) -> GlobalElementID {
    .child(of: .child(of: id, at: member, name: nil), at: 0, name: ElementID("$anim-op\(k)"))
}

/// A colour's animated value (keyed on the declared `Color`, `CR-H`) on a track in the `AnimationStore` —
/// `animatedColor`'s recipe (`advanceColor`), stored in the store instead of on
/// `$anim-color`. A first sighting (no track: new, or dropped by a frame that
/// did not paint it) stores the baseline and paints the declared colour.
@MainActor
func storedAnimatedColor(_ color: Color, at key: GlobalElementID, pass: PaintPass) -> Hsla {
    let store = pass.frame.animationStore
    let context = pass.frame.colorContext
    guard let existing = store.value(at: key, as: AnimatedColorState.self) else {
        store.set(AnimatedColorState(color: color, inFlight: nil), at: key)
        return context.resolve(color)
    }
    let (state, value) = advanceColor(color, from: existing, context: context, now: pass.timestamp,
                                      transaction: pass.transaction ?? Animation.pendingTransaction)
    if state != existing { store.set(state, at: key) }
    if state.inFlight != nil {
        store.noteInterpolation()
        pass.frame.noteActiveAnimation()
    }
    return value
}

/// A list of numbers' baseline and in-flight fields, as one store entry — the
/// `AnimatedElementState` shape (ruling U) over positions instead of names.
///
/// **Measured strides** (2026-09-30, debug arm64, `AN-AF` item 3): this type is
/// **16** (two array references; the arrays' buffers are separate
/// allocations), stored in the store's `[GlobalElementID: Any]` as a
/// **32**-byte existential, inline (under the existential's 24-byte buffer);
/// `AnimatedColorState` (a colour track, the legacy border track included) is
/// **120**, above that buffer, so the existential boxes it — one heap box per
/// colour track; `AnimatedFieldState` is **88** per position in flight. One
/// entry per animatable layer, op or bordered element, present only while
/// produced (the store's one-frame drop).
struct StoredNumberTracks: Equatable {
    var baseline: [Double?]
    var inFlight: [String: AnimatedFieldState]
}

/// The animated values of `declared`, one track per position, in the
/// `AnimationStore` at `key`.
///
/// **What snaps**: a first sighting (the baseline is stored, `declared`
/// returned); `nil` ↔ a value and finite ↔ infinite at a position (no number
/// to interpolate from or to — and an infinite frame bound interpolated would
/// be a non-finite rect, `SA-K`); any change without a transaction. A value
/// still interpolating is clamped to `range` (an overshooting spring must not
/// reach a precondition — a negative size, an opacity above 1); a declared
/// value is never clamped.
///
/// Counts one interpolation per position in flight (`AnimationStore.
/// lastFrameInterpolations`, `aSettledProposalTreeInterpolatesNothing`) and
/// notes an active animation while any is (`AN-M`).
@MainActor
func animatedNumbers(_ declared: [Double?], at key: GlobalElementID, frame: Frame,
                     transaction: Animation?, range: ClosedRange<Double>) -> [Double?] {
    let store = frame.animationStore
    guard let existing = store.value(at: key, as: StoredNumberTracks.self) else {
        store.set(StoredNumberTracks(baseline: declared, inFlight: [:]), at: key)
        return declared
    }
    var inFlight = existing.inFlight
    var out = declared
    for i in declared.indices {
        let field = String(i)
        guard let d = declared[i], d.isFinite else {
            inFlight[field] = nil
            continue
        }
        let previous = i < existing.baseline.count ? existing.baseline[i] : nil
        let previousIsFinite = previous?.isFinite ?? false
        if inFlight[field] == nil && (!previousIsFinite || previous == d) { continue }
        let value = animateField(field, declared: d, declaredTag: 0, previous: previous ?? 0,
                                 previousTag: previousIsFinite ? 0 : 1, inFlight: &inFlight,
                                 transaction: transaction, now: frame.timestamp).value
        if inFlight[field] != nil {
            store.noteInterpolation()
            out[i] = min(max(value, range.lowerBound), range.upperBound)
        } else {
            out[i] = value
        }
    }
    let state = StoredNumberTracks(baseline: declared, inFlight: inFlight)
    if state != existing { store.set(state, at: key) }
    if !inFlight.isEmpty { frame.noteActiveAnimation() }
    return out
}

extension LayoutModifier {
    /// Rewrites this layer's numeric case to its animated value for `id`
    /// (`AN-AB`): `.frame`'s width and height, `.flexibleFrame`'s finite
    /// bounds, `.padding`'s insets, `.opacity`, `.clip`'s radius and `.border`'s
    /// width. Every other case — and every colour, which paint animates — is
    /// returned unchanged and touches no track: `fixedSize`, `layoutPriority`,
    /// `aspectRatio`, `allowsHitTesting`, a `clipShape`'s shape and every
    /// alignment snap (divergence 97).
    @MainActor
    mutating func animate(for id: GlobalElementID, pass: inout LayoutPass) {
        let frame = pass.frame
        let transaction = pass.transaction ?? Animation.pendingTransaction
        func numbers(_ name: String, _ values: [Double?], _ range: ClosedRange<Double>) -> [Double?] {
            animatedNumbers(values, at: layerAnimationKey(id, name), frame: frame,
                            transaction: transaction, range: range)
        }
        func px(_ value: Double?) -> Pixels? { value.map { Pixels(Float($0)) } }
        func raw(_ value: Pixels?) -> Double? { value.map { Double($0.value) } }
        let size = 0.0...Double.greatestFiniteMagnitude
        let any = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude
        switch self {
        case let .frame(width, height, alignment):
            let v = numbers("frame", [raw(width), raw(height)], size)
            self = .frame(width: px(v[0]), height: px(v[1]), alignment: alignment)
        case let .flexibleFrame(minW, idealW, maxW, minH, idealH, maxH, alignment):
            let v = numbers("flexibleFrame", [raw(minW), raw(idealW), raw(maxW),
                                              raw(minH), raw(idealH), raw(maxH)],
                            -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude)
            // An interpolated bound keeps the kernel's order (`SA-J`: max and
            // ideal non-negative, min ≤ ideal ≤ max), which an overshooting
            // spring on two bounds could break; a declared frame already holds it.
            func ordered(_ lo: Double?, _ mid: Double?, _ hi: Double?) -> (Double?, Double?, Double?) {
                let hi = hi.map { max($0, 0) }
                var mid = mid.map { max($0, 0) }
                if let m = mid, let h = hi { mid = min(m, h) }
                var lo = lo
                if let l = lo, let bound = mid ?? hi { lo = min(l, bound) }
                return (lo, mid, hi)
            }
            let w = ordered(v[0], v[1], v[2]), h = ordered(v[3], v[4], v[5])
            self = .flexibleFrame(minWidth: px(w.0), idealWidth: px(w.1), maxWidth: px(w.2),
                                  minHeight: px(h.0), idealHeight: px(h.1), maxHeight: px(h.2),
                                  alignment: alignment)
        case let .padding(insets):
            let v = numbers("padding", [raw(insets.top), raw(insets.right), raw(insets.bottom),
                                        raw(insets.left)],
                            -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude)
            self = .padding(Edges(top: px(v[0])!, right: px(v[1])!, bottom: px(v[2])!, left: px(v[3])!))
        case let .opacity(value):
            let v = numbers("opacity", [Double(value)], 0...1)
            self = .opacity(Float(v[0]!))
        case let .clip(cornerRadius):
            let v = numbers("clip", [raw(cornerRadius)], size)
            self = .clip(cornerRadius: px(v[0])!)
        case let .border(token, width, cornerRadius):
            let v = numbers("border", [raw(width)], size)
            self = .border(token, width: px(v[0])!, cornerRadius: cornerRadius)
        case let .rotationEffect(angle, anchor):
            // The angle and its anchor (`GX-H`; N1, N9).
            let v = numbers("rotationEffect", [angle.radians, anchor.x, anchor.y], any)
            self = .rotationEffect(Angle(radians: v[0]!), anchor: UnitPoint(x: v[1]!, y: v[2]!))
        case let .scaleEffect(x, y, anchor):
            // Both factors and their anchor (N2, N2b).
            let v = numbers("scaleEffect", [x, y, anchor.x, anchor.y], any)
            self = .scaleEffect(x: v[0]!, y: v[1]!, anchor: UnitPoint(x: v[2]!, y: v[3]!))
        case let .offset(x, y):
            // Both components (N3).
            let v = numbers("offset", [raw(x), raw(y)], any)
            self = .offset(x: px(v[0])!, y: px(v[1])!)
        case let .shadow(token, radius, x, y):
            // The radius and both offsets (`GX-J`; N4, N5); the colour in paint.
            let v = numbers("shadow", [raw(radius), raw(x), raw(y)], any)
            self = .shadow(token, radius: px(max(0, v[0]!))!, x: px(v[1])!, y: px(v[2])!)
        case let .blur(radius):
            // The radius (`LK-K` item 6, the shadow-radius precedent).
            let v = numbers("blur", [raw(radius)], size)
            self = .blur(radius: px(v[0])!)
        case .fixedSize, .aspectRatio, .layoutPriority, .background, .clipShape, .allowsHitTesting:
            break
        }
    }
}

extension ComponentModifierOp {
    /// This op's animated value on member `member` of the component `id`
    /// (`AN-AC`, B-7 fixed): an amend's pixel width and height, a wrap's pixel
    /// padding. An `.auto` axis (not named) and any non-pixel length snap.
    @MainActor
    func animated(for id: GlobalElementID, member: Int, op k: Int, pass: inout LayoutPass)
        -> ComponentModifierOp {
        let key = componentOpAnimationKey(id, member: member, op: k)
        let transaction = pass.transaction ?? Animation.pendingTransaction
        func pixels(_ length: Length) -> Double? {
            if case let .pixels(p) = length { return Double(p.value) }
            return nil
        }
        func pixels(_ dimension: Dimension) -> Double? {
            if case let .length(length) = dimension { return pixels(length) }
            return nil
        }
        switch self {
        case let .amend(patch):
            let v = animatedNumbers([pixels(patch.width), pixels(patch.height)], at: key, frame: pass.frame,
                                    transaction: transaction, range: 0...Double.greatestFiniteMagnitude)
            func dimension(_ value: Double?, _ declared: Dimension) -> Dimension {
                value.map { .length(.pixels(Pixels(Float($0)))) } ?? declared
            }
            return .amend(Size(width: dimension(v[0], patch.width), height: dimension(v[1], patch.height)))
        case let .wrap(style):
            let p = style.padding
            let v = animatedNumbers([pixels(p.top), pixels(p.right), pixels(p.bottom), pixels(p.left)],
                                    at: key, frame: pass.frame, transaction: transaction,
                                    range: -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude)
            func length(_ value: Double?, _ declared: Length) -> Length {
                value.map { .pixels(Pixels(Float($0))) } ?? declared
            }
            var animated = style
            animated.padding = Edges(top: length(v[0], p.top), right: length(v[1], p.right),
                                     bottom: length(v[2], p.bottom), left: length(v[3], p.left))
            return .wrap(animated)
        }
    }
}
