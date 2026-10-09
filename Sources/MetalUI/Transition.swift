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

/// What one paint scope does to every primitive emitted inside it, in the
/// scene's device pixels: an alpha multiplier and an affine map (ruling `GX-G`,
/// generalizing plan task 13's `TransitionEffect`). A transition's map is a
/// uniform scale about its anchor and a translation, computed exactly as
/// before — in `Float`, stored in `Double` without rounding — so transitions'
/// captured and emitted bytes do not move (test 2.26).
struct RenderEffect: Equatable {
    var alpha: Float = 1
    var affine = Affine2D.identity

    static let identity = RenderEffect()

    var isIdentity: Bool { self == .identity }

    init() {}

    init(alpha: Float = 1, affine: Affine2D) {
        self.alpha = alpha
        self.affine = affine
    }

    /// A transition's `atoms` at `activeness` over `rect` (device pixels):
    /// every scale about its anchor first, then every translation; alphas
    /// multiply. `Float` arithmetic, as plan task 13 computed it.
    init(atoms: [TransitionAtom], activeness a: Double, rect: MUIBounds, scaleFactor: Float) {
        var scale: Float = 1, tx: Float = 0, ty: Float = 0
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
        affine = Affine2D(a: Double(scale), d: Double(scale), tx: Double(tx), ty: Double(ty))
    }

    // The flattened map in `Float`, coefficient by coefficient — for a
    // transition exactly plan task 13's `scale * x + tx`.
    private var sx: Float { Float(affine.a) }
    private var sy: Float { Float(affine.d) }

    func map(_ b: MUIBounds) -> MUIBounds {
        MUIBounds(origin: MUIPoint(x: sx * b.origin.x + Float(affine.tx), y: sy * b.origin.y + Float(affine.ty)),
                  size: MUISize(width: sx * b.size.width, height: sy * b.size.height))
    }

    func map(_ c: MUICorners) -> MUICorners {
        MUICorners(topLeft: c.topLeft * sx, topRight: c.topRight * sx,
                   bottomRight: c.bottomRight * sx, bottomLeft: c.bottomLeft * sx)
    }

    /// `primitive` under this effect, or `nil` when the result draws nothing
    /// (a degenerate map over transformed content).
    ///
    /// - A primitive with no transform under a `flattens` scope (every
    ///   transition; an effect whose map is a translation plus a uniform
    ///   positive scale) is mapped on the CPU: bounds, radii, border widths, and
    ///   its mask when `innerMask` (its clip was pushed inside the scope) — the
    ///   clip in effect at the scope's entry stays put.
    /// - Otherwise the map composes onto its transform record (`M ∘ T`). Its
    ///   local geometry never moves; its outer mask moves with a flattening map
    ///   when `outerMaskInner`, and under a non-flattening one becomes its
    ///   bounding box cut by the scope's own outer mask (divergence 109).
    func apply(to primitive: CapturedPrimitive, flattens: Bool, outer: OuterMask?) -> CapturedPrimitive? {
        var p = primitive
        if p.transform == nil && flattens {
            switch p.kind {
            case .rect(var r):
                r.bounds = map(r.bounds)
                if p.innerMask {
                    r.contentMask = map(r.contentMask)
                    r.maskCornerRadii = map(r.maskCornerRadii)
                }
                r.cornerRadii = map(r.cornerRadii)
                r.borderWidths = MUIEdges(top: r.borderWidths.top * sx, right: r.borderWidths.right * sx,
                                          bottom: r.borderWidths.bottom * sx, left: r.borderWidths.left * sx)
                r.background.a *= alpha
                r.borderColor.a *= alpha
                p.kind = .rect(r)
            case .glyph(var g):
                g.bounds = map(g.bounds)
                if p.innerMask {
                    g.contentMask = map(g.contentMask)
                    g.maskCornerRadii = map(g.maskCornerRadii)
                }
                g.color.a *= alpha
                p.kind = .glyph(g)
            case .image(var i, let texture):
                i.bounds = map(i.bounds)
                if p.innerMask {
                    i.contentMask = map(i.contentMask)
                    i.maskCornerRadii = map(i.maskCornerRadii)
                }
                i.opacity *= alpha
                p.kind = .image(i, texture: texture)
            case .surface(var q, let target):
                // The quad moves, never the target (MV-E item 2): a `.scale`
                // transition resamples it, it never reallocates.
                q.bounds = map(q.bounds)
                if p.innerMask {
                    q.contentMask = map(q.contentMask)
                    q.maskCornerRadii = map(q.maskCornerRadii)
                }
                q.opacity *= alpha
                p.kind = .surface(q, target: target)
            case .path(var path):
                // A path stays a vector until it reaches the scene (`GX-B`): the
                // map composes onto its own, so it is rasterized at the scale it
                // is drawn at.
                path.local = affine.concatenating(path.local)
                if p.innerMask {
                    path.contentMask = map(path.contentMask)
                    path.maskCornerRadii = map(path.maskCornerRadii)
                }
                path.color.a *= alpha
                p.kind = .path(path)
            case .shadow(var shadow):
                // A shadow's offset and blur follow the composed map (`GX-J`;
                // T10, T14): its leaf stays in creation space under `local`.
                shadow.local = affine.concatenating(shadow.local)
                if p.innerMask {
                    shadow.contentMask = map(shadow.contentMask)
                    shadow.maskCornerRadii = map(shadow.maskCornerRadii)
                }
                shadow.color.a *= alpha
                p.kind = .shadow(shadow)
            case .gradient(var gradient):
                // A gradient stays a vector, as a path does (`LK-J` item 4).
                gradient.local = affine.concatenating(gradient.local)
                if p.innerMask {
                    gradient.contentMask = map(gradient.contentMask)
                    gradient.maskCornerRadii = map(gradient.maskCornerRadii)
                }
                gradient.opacity *= alpha
                p.kind = .gradient(gradient)
            case .blur(var blur):
                // A blur's reach follows the composed map, as a shadow's does
                // (`LK-K`): its leaf stays in creation space under `local`.
                blur.local = affine.concatenating(blur.local)
                if p.innerMask {
                    blur.contentMask = map(blur.contentMask)
                    blur.maskCornerRadii = map(blur.maskCornerRadii)
                }
                blur.alpha *= alpha
                p.kind = .blur(blur)
            }
            return p
        }
        p.multiplyAlpha(alpha)
        guard var t = p.transform else {
            // A plain primitive under a non-flattening effect: its geometry is
            // already local (the scope split the clip at its entry, `GX-G`).
            guard let outer, affine.determinant != 0 else { return nil }
            p.transform = PrimitiveTransform(affine: affine, outerMask: outer.bounds,
                                             outerMaskRadii: outer.radii, outerDepth: outer.depth)
            return p
        }
        t.affine = affine.concatenating(t.affine)
        guard t.affine.determinant != 0, t.affine.determinant.isFinite else { return nil }
        if flattens {
            if p.outerMaskInner {
                t.outerMask = map(t.outerMask)
                t.outerMaskRadii = map(t.outerMaskRadii)
            }
        } else if let outer {
            if t.outerMask.size.width >= PrimitiveTransform.unboundedThreshold {
                t.outerMask = outer.bounds
                t.outerMaskRadii = outer.radii
            } else {
                let box = affine.boundingBox(of: t.outerMask)
                t.outerMask = box.intersection(outer.bounds)
                t.outerMaskRadii = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
            }
            t.outerDepth = outer.depth
        }
        p.transform = t
        return p
    }
}

/// A non-flattening effect scope's outer mask (`GX-G`): the clip in force at
/// its entry, in the space the scope's map maps into, and the clip depth it
/// was read at.
struct OuterMask {
    var bounds: MUIBounds
    var radii: MUICorners
    var depth: Int
}

/// A primitive's transform record carried by value (`GX-G`), so a ghost or a
/// drag preview replays transformed content in a later frame without reading a
/// stale scene index: the composed map (local device pixels → screen), the
/// outer mask in screen space, and the clip depth that mask was read at.
struct PrimitiveTransform {
    var affine: Affine2D
    var outerMask: MUIBounds
    var outerMaskRadii: MUICorners
    var outerDepth: Int

    /// A mask at least this wide (device pixels) is the unbounded local clip.
    static let unboundedThreshold: Float = 100_000

    /// The scene's record (`MUITransform`, `GX-F`).
    var record: MUITransform {
        MUITransform(a: Float(affine.a), b: Float(affine.b), c: Float(affine.c), d: Float(affine.d),
                     tx: Float(affine.tx), ty: Float(affine.ty), pixelScale: Float(affine.linearScale),
                     _reserved: 0, outerMask: outerMask, outerMaskRadii: outerMaskRadii)
    }
}

/// One primitive as a paint scope receives it — what a transition's ghost and
/// a drag preview replay (`GX-G`). `innerMask` and `outerMaskInner` are
/// relative to the scope that last read it: whether its own clip, and its
/// transform's outer mask, were pushed inside that scope.
struct CapturedPrimitive {
    enum Kind {
        case rect(MUIRect)
        case glyph(MUIGlyph)
        case image(MUIImage, texture: ImageTexture)
        /// An app-owned surface's quad over its render target (MetalView,
        /// ruling `MV-D`): a ghost or a drag preview replays the quad and so
        /// references the target, with no draw request — it shows the last
        /// contents.
        case surface(MUIImage, target: SurfaceTarget)
        /// A path, still a vector (`GX-B`): rasterized at `insertIntoScene`.
        case path(PathPaint)
        /// One leaf's shadow (`GX-J`): rasterized at `insertIntoScene`, drawn
        /// just before its leaf.
        case shadow(ShadowPaint)
        /// A gradient, still a vector (`LK-J` item 4): rasterized at
        /// `insertIntoScene`.
        case gradient(GradientPaint)
        /// One leaf blurred (`LK-K`): rasterized in colour at
        /// `insertIntoScene`, in its leaf's place.
        case blur(BlurPaint)
    }

    var kind: Kind
    var layer: Int
    var innerMask: Bool
    var transform: PrimitiveTransform? = nil
    var outerMaskInner = false

    static func rect(_ r: MUIRect, layer: Int, innerMask: Bool) -> CapturedPrimitive {
        CapturedPrimitive(kind: .rect(r), layer: layer, innerMask: innerMask)
    }

    static func glyph(_ g: MUIGlyph, layer: Int, innerMask: Bool) -> CapturedPrimitive {
        CapturedPrimitive(kind: .glyph(g), layer: layer, innerMask: innerMask)
    }

    static func image(_ i: MUIImage, texture: ImageTexture, layer: Int, innerMask: Bool) -> CapturedPrimitive {
        CapturedPrimitive(kind: .image(i, texture: texture), layer: layer, innerMask: innerMask)
    }

    static func surface(_ q: MUIImage, target: SurfaceTarget, layer: Int, innerMask: Bool) -> CapturedPrimitive {
        CapturedPrimitive(kind: .surface(q, target: target), layer: layer, innerMask: innerMask)
    }

    /// The primitive's own bounds, in (local) device pixels.
    var bounds: MUIBounds {
        switch kind {
        case .rect(let r): r.bounds
        case .glyph(let g): g.bounds
        case .image(let i, _): i.bounds
        case .surface(let q, _): q.bounds
        case .path(let path): path.bounds
        case .shadow(let shadow): shadow.bounds
        case .gradient(let gradient): gradient.bounds
        case .blur(let blur): blur.bounds
        }
    }

    /// The clip depth this primitive's own mask was read at, given the depth at
    /// its emission: a shadow's mask is its scope's entry clip (`GX-J`).
    func maskDepth(emittedAt depth: Int) -> Int {
        if case let .shadow(shadow) = kind { return shadow.entryDepth }
        if case let .blur(blur) = kind { return blur.entryDepth }
        return depth
    }

    /// Where it lands on screen: its bounds, or their bounding box under its
    /// transform.
    var screenBounds: MUIBounds {
        guard let transform else { return bounds }
        return transform.affine.boundingBox(of: bounds)
    }

    mutating func multiplyAlpha(_ alpha: Float) {
        guard alpha != 1 else { return }
        switch kind {
        case .rect(var r):
            r.background.a *= alpha
            r.borderColor.a *= alpha
            kind = .rect(r)
        case .glyph(var g):
            g.color.a *= alpha
            kind = .glyph(g)
        case .image(var i, let texture):
            i.opacity *= alpha
            kind = .image(i, texture: texture)
        case .surface(var q, let target):
            q.opacity *= alpha
            kind = .surface(q, target: target)
        case .path(var path):
            path.color.a *= alpha
            kind = .path(path)
        case .shadow(var shadow):
            shadow.color.a *= alpha
            kind = .shadow(shadow)
        case .gradient(var gradient):
            gradient.opacity *= alpha
            kind = .gradient(gradient)
        case .blur(var blur):
            blur.alpha *= alpha
            kind = .blur(blur)
        }
    }
}

extension MUIBounds {
    /// The overlap of two bounds, empty (zero size at the first's origin
    /// clamp) when they do not meet.
    func intersection(_ other: MUIBounds) -> MUIBounds {
        let minX = max(origin.x, other.origin.x), minY = max(origin.y, other.origin.y)
        let maxX = min(origin.x + size.width, other.origin.x + other.size.width)
        let maxY = min(origin.y + size.height, other.origin.y + other.size.height)
        return MUIBounds(origin: MUIPoint(x: minX, y: minY),
                         size: MUISize(width: max(maxX - minX, 0), height: max(maxY - minY, 0)))
    }
}
