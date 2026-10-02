import MetalUICore
import MetalUIPrimitives

// Plan task 13, lane 3 — transitions (ruling `AN-AE` as amended by `AN-AH`
// items 1, 2, 4 and 6, and lane 3's own `AN-AK`). Spec
// `docs/superpowers/specs/2026-09-30-transactions-animation-design.md` §6.5;
// SwiftUI's side is `docs/probes/swiftui-transactions-animation.swift`, arms
// X0–X17c and R5–R10.

/// One edge of a rectangle — SwiftUI's `Edge`, for `AnyTransition.move(edge:)`
/// and `AnyTransition.push(from:)`.
public enum Edge: Sendable, Hashable, CaseIterable {
    case top, leading, bottom, trailing

    /// The unit direction from the rectangle's centre toward this edge, in
    /// the view's own size: `leading` is `(-1, 0)`, `bottom` `(0, 1)`.
    var direction: (x: Double, y: Double) {
        switch self {
        case .top: (0, -1)
        case .leading: (-1, 0)
        case .bottom: (0, 1)
        case .trailing: (1, 0)
        }
    }

    var opposite: Edge {
        switch self {
        case .top: .bottom
        case .leading: .trailing
        case .bottom: .top
        case .trailing: .leading
        }
    }
}

/// How an element enters when a conditional or a loop inserts it, and leaves
/// when one removes it — SwiftUI's `AnyTransition`, applied with
/// `.transition(_:)`.
///
/// ## Supported (each measured against SwiftUI, probe `swiftui-transactions-animation.swift`)
///
/// | spelling | insertion | removal | arm |
/// |---|---|---|---|
/// | `.identity` | instant | instant | X7 |
/// | `.opacity` | fades in from 0 | fades out to 0 | X1 |
/// | `.move(edge:)` | slides in from `edge` by the element's **own** size | slides out to `edge` | X2, X3, X3t, X3b |
/// | `.slide` | from leading | to trailing | X5 |
/// | `.offset(x:y:)` | from the offset | to the offset | X9 |
/// | `.scale`, `.scale(scale:anchor:)` | grows from `scale` (0 for `.scale`) about `anchor` (centre) | shrinks to it | X4, X4a |
/// | `.push(from:)` | fades in from `edge` | fades out to the opposite edge | X10 |
/// | `.asymmetric(insertion:removal:)` | its `insertion` | its `removal` | X6 |
/// | `a.combined(with: b)` | both | both | X8 |
///
/// **Where it applies.** Only to the outermost group of content an `if` (its
/// content, or an `if`/`else`/`switch` branch), a `ForEach` element or a `for`
/// iteration inserts or removes — `.transition` written directly on that
/// content, through transparent wrappers (`.animation(_:value:)`,
/// `.transaction`, `.environment`). A `.transition` nested deeper, or on
/// content that is never inserted or removed, does nothing (X15, X15b, X16).
/// Of two `.transition`s stacked on one content the outer applies (MetalUI's
/// own rule, unprobed; test 3.29).
/// Only a conditional **evaluated in the last frame** inserts: content in a
/// window's first render, content under a newly evaluated parent and a `List`
/// row entering its window are not insertions, and a `List` row leaving its
/// window is not a removal (X17, X17c; `TB-AH`). A changed `.id(_:)` outside a
/// loop is not a removal either (MetalUI's own scope, `AN-AK`).
///
/// **The animation** is the transaction in effect **at the conditional** — a
/// `withAnimation`, a `withTransaction`, or `.animation(_:value:)`/
/// `.transaction` written around the `if` — not at the transitioning content
/// (X13, X14). With no animation the insertion or removal is instant (X1n).
///
/// **Reduce Motion** (`EnvironmentValues.accessibilityReduceMotion`, read at
/// the transitioning content): every transition except `.identity` becomes
/// `.opacity`, on the same animation (R5…; R10 the control) — per side, so
/// `.asymmetric(insertion: .identity, removal: .move(edge: .top))` fades out and
/// inserts instantly.
///
/// **No default transition** — SwiftUI cross-fades an unannotated insertion
/// and removal (X0); MetalUI inserts and removes it instantly (divergence 98).
///
/// **How it is drawn.** An insertion paints the live content with the
/// transition's active state moving to identity: opacity multiplies every
/// primitive's alpha, a move/offset/slide/push translates the primitives, a
/// scale scales their bounds, corner radii and border widths about the anchor
/// point of the content's laid-out rectangle — a glyph resamples its atlas slot
/// (bilinear), so it is soft mid-flight and exact at the end. A clip in effect
/// where the content starts stays put; a clip set inside it moves and scales
/// with it. A removal paints a **ghost**: the content's last painted
/// primitives, frozen at their last place (they follow neither a scroll nor a
/// theme change during the removal), with the removal transition applied, on
/// the layer they had, **above the rest of that layer** — until the animation
/// lands. Neither registers anything but paint: **hit testing, focus and
/// accessibility use the final geometry** (an inserting element is hit where
/// it lands; a ghost has no hitbox, focus or accessibility node — its state is
/// already reset, `ID-C`/`DD-C`). Siblings move at once (divergence 96). A
/// removal during an insertion starts from the insertion's current progress,
/// and an insertion during a removal from the ghost's (MetalUI's own rule,
/// unprobed).
///
/// ## Not supported (absent, so they do not compile)
///
/// `.blurReplace` (guard `theUnsupportedTransitionsDoNotCompile`),
/// `.modifier(active:identity:)`, the `Transition` protocol and custom
/// transitions, `AnyTransition.animation(_:)` (a per-transition animation),
/// `matchedGeometryEffect`, `contentTransition`, a default transition on
/// unannotated content (divergence 98), a transition on a changed `.id(_:)`
/// outside a loop, `.id(_:)` written **outside** `.transition` on the inserted
/// content (`content.transition(.opacity).id("x")` — the `.id` numbers the
/// group under its name, so the group is no longer the conditional's content
/// and is inert; write `.id` inside, `content.id("x").transition(.opacity)`,
/// test 3.30), and an animated scroll offset — each would need its own
/// probe, and most a renderer feature (a blur, a per-primitive modifier) the
/// scene does not carry.
public struct AnyTransition: Sendable {
    indirect enum Kind: Sendable {
        case identity
        case opacity
        case move(Edge)
        case offset(x: Double, y: Double)
        case scale(Double, anchor: UnitPoint)
        case push(Edge)
        case asymmetric(insertion: Kind, removal: Kind)
        case combined(Kind, Kind)
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    /// No transition: inserted and removed instantly (X7).
    public static let identity = AnyTransition(.identity)
    /// Fades in from, and out to, fully transparent (X1).
    public static let opacity = AnyTransition(.opacity)
    /// In from the leading edge, out to the trailing edge (X5).
    public static let slide = AnyTransition(.asymmetric(insertion: .move(.leading), removal: .move(.trailing)))
    /// Grows from, and shrinks to, nothing about the centre (X4).
    public static let scale = AnyTransition(.scale(0, anchor: .center))

    /// Grows from, and shrinks to, `scale` about `anchor` of the content's own
    /// rectangle (X4a).
    public static func scale(scale: Double, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition(.scale(scale, anchor: anchor))
    }

    /// In from, and out to, `edge`, by the content's own size (X2, X3).
    public static func move(edge: Edge) -> AnyTransition { AnyTransition(.move(edge)) }

    /// In from, and out to, the content displaced by `(x, y)` (X9).
    public static func offset(x: Pixels = Pixels(0), y: Pixels = Pixels(0)) -> AnyTransition {
        AnyTransition(.offset(x: Double(x.value), y: Double(y.value)))
    }

    /// In from `edge` fading in, out toward the opposite edge fading out (X10).
    public static func push(from edge: Edge) -> AnyTransition { AnyTransition(.push(edge)) }

    /// `insertion` on the way in, `removal` on the way out (X6).
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(.asymmetric(insertion: insertion.kind, removal: removal.kind))
    }

    /// This transition and `other` together (X8).
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(.combined(kind, other.kind))
    }

    /// The atomic effects this transition applies on one side — `[]` for
    /// identity. Under Reduce Motion anything but identity is `[.opacity]`
    /// (R5…).
    func atoms(insertion: Bool, reduceMotion: Bool) -> [TransitionAtom] {
        let atoms = kind.atoms(insertion: insertion)
        return reduceMotion && !atoms.isEmpty ? [.opacity] : atoms
    }
}

/// One component of a resolved transition, at full activeness.
enum TransitionAtom: Equatable {
    /// Alpha multiplied by `1 − activeness`.
    case opacity
    /// Displaced by `(sizeX × width + x, sizeY × height + y) × activeness`.
    case translate(sizeX: Double, sizeY: Double, x: Double, y: Double)
    /// Scaled by `1 + (scale − 1) × activeness` about `anchor` of the rect.
    case scale(Double, anchor: UnitPoint)
}

extension AnyTransition.Kind {
    func atoms(insertion: Bool) -> [TransitionAtom] {
        switch self {
        case .identity:
            return []
        case .opacity:
            return [.opacity]
        case .move(let edge):
            return [.translate(sizeX: edge.direction.x, sizeY: edge.direction.y, x: 0, y: 0)]
        case .offset(let x, let y):
            return [.translate(sizeX: 0, sizeY: 0, x: x, y: y)]
        case .scale(let scale, let anchor):
            return [.scale(scale, anchor: anchor)]
        case .push(let edge):
            let toward = insertion ? edge : edge.opposite
            return [.opacity, .translate(sizeX: toward.direction.x, sizeY: toward.direction.y, x: 0, y: 0)]
        case .asymmetric(let insertionKind, let removalKind):
            return insertion ? insertionKind.atoms(insertion: true) : removalKind.atoms(insertion: false)
        case .combined(let first, let second):
            return first.atoms(insertion: insertion) + second.atoms(insertion: insertion)
        }
    }
}

/// A resolved transition at one activeness, in the scene's device pixels: an
/// alpha multiplier and the affine map `p′ = scale × p + (tx, ty)`.
struct TransitionEffect: Equatable {
    var alpha: Float = 1
    var scale: Float = 1
    var tx: Float = 0
    var ty: Float = 0

    static let identity = TransitionEffect()

    var isIdentity: Bool { self == .identity }

    /// `atoms` at `activeness` over `rect` (device pixels): every scale about
    /// its anchor first, then every translation; alphas multiply.
    init(atoms: [TransitionAtom], activeness a: Double, rect: MUIBounds, scaleFactor: Float) {
        for atom in atoms {
            guard case .scale(let target, let anchor) = atom else { continue }
            let s = Float(1 + (target - 1) * a)
            let ax = rect.origin.x + Float(anchor.x) * rect.size.width
            let ay = rect.origin.y + Float(anchor.y) * rect.size.height
            // p' = s (p − A) + A, composed after the map so far.
            tx = s * tx + (1 - s) * ax
            ty = s * ty + (1 - s) * ay
            scale *= s
        }
        for atom in atoms {
            switch atom {
            case .opacity:
                alpha *= Float(min(max(1 - a, 0), 1))
            case .translate(let sizeX, let sizeY, let x, let y):
                tx += Float((sizeX * Double(rect.size.width) + x * Double(scaleFactor)) * a)
                ty += Float((sizeY * Double(rect.size.height) + y * Double(scaleFactor)) * a)
            case .scale:
                break
            }
        }
    }

    init() {}

    func map(_ b: MUIBounds) -> MUIBounds {
        MUIBounds(origin: MUIPoint(x: scale * b.origin.x + tx, y: scale * b.origin.y + ty),
                  size: MUISize(width: scale * b.size.width, height: scale * b.size.height))
    }

    func map(_ c: MUICorners) -> MUICorners {
        MUICorners(topLeft: c.topLeft * scale, topRight: c.topRight * scale,
                   bottomRight: c.bottomRight * scale, bottomLeft: c.bottomLeft * scale)
    }

    /// `primitive` under this effect. `innerMask`: its clip was set inside the
    /// transitioning content, so the clip moves and scales with it; otherwise
    /// the clip in effect at the content's entry stays put.
    func apply(to primitive: CapturedPrimitive) -> CapturedPrimitive {
        switch primitive {
        case .rect(var r, let layer, let inner):
            r.bounds = map(r.bounds)
            if inner {
                r.contentMask = map(r.contentMask)
                r.maskCornerRadii = map(r.maskCornerRadii)
            }
            r.cornerRadii = map(r.cornerRadii)
            r.borderWidths = MUIEdges(top: r.borderWidths.top * scale, right: r.borderWidths.right * scale,
                                      bottom: r.borderWidths.bottom * scale, left: r.borderWidths.left * scale)
            r.background.a *= alpha
            r.borderColor.a *= alpha
            return .rect(r, layer: layer, innerMask: inner)
        case .glyph(var g, let layer, let inner):
            g.bounds = map(g.bounds)
            if inner {
                g.contentMask = map(g.contentMask)
                g.maskCornerRadii = map(g.maskCornerRadii)
            }
            g.color.a *= alpha
            return .glyph(g, layer: layer, innerMask: inner)
        case .image(var i, let texture, let layer, let inner):
            i.bounds = map(i.bounds)
            if inner {
                i.contentMask = map(i.contentMask)
                i.maskCornerRadii = map(i.maskCornerRadii)
            }
            i.opacity *= alpha
            return .image(i, texture: texture, layer: layer, innerMask: inner)
        case .surface(var q, let target, let layer, let inner):
            // The quad moves, never the target (MV-E item 2): a `.scale`
            // transition resamples it, it never reallocates.
            q.bounds = map(q.bounds)
            if inner {
                q.contentMask = map(q.contentMask)
                q.maskCornerRadii = map(q.maskCornerRadii)
            }
            q.opacity *= alpha
            return .surface(q, target: target, layer: layer, innerMask: inner)
        }
    }
}

/// One primitive a transitioning group emitted, as the scene received it before
/// the group's own effect — what a ghost replays. `innerMask` is relative to
/// the capturing group: whether its clip was pushed inside the group.
enum CapturedPrimitive {
    case rect(MUIRect, layer: Int, innerMask: Bool)
    case glyph(MUIGlyph, layer: Int, innerMask: Bool)
    case image(MUIImage, texture: ImageTexture, layer: Int, innerMask: Bool)
    /// An app-owned surface's quad over its render target (MetalView, ruling
    /// `MV-D`): a ghost or a drag preview replays the quad and so references
    /// the target, with no draw request — it shows the last contents.
    case surface(MUIImage, target: SurfaceTarget, layer: Int, innerMask: Bool)

    func withInnerMask(_ inner: Bool) -> CapturedPrimitive {
        switch self {
        case .rect(let r, let layer, _): .rect(r, layer: layer, innerMask: inner)
        case .glyph(let g, let layer, _): .glyph(g, layer: layer, innerMask: inner)
        case .image(let i, let t, let layer, _): .image(i, texture: t, layer: layer, innerMask: inner)
        case .surface(let q, let t, let layer, _): .surface(q, target: t, layer: layer, innerMask: inner)
        }
    }
}
