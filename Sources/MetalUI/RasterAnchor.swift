import MetalUICore
import MetalUIPath
import MetalUIPrimitives

// C13 / PERF-a, lane 1 — translation-free raster keys (rulings `PF-A`, `PF-B`,
// `PF-I`, `PF-J`). Spec `docs/superpowers/specs/2026-10-09-shadow-cache-design.md`
// §3.
//
// At 2155f1e every CPU raster key held absolute positions, so a node moved by
// one pixel re-rasterized, re-blurred and re-uploaded every shadow it cast.
// Here a raster is made and keyed in **canonical coordinates**: its content
// translated by a creation-space anchor `R` (the content's minimum corner
// floored to the creation space's device grid), mapped by `full'` (the
// composed map's linear part with the fractional device anchor `f` as its
// translation), and placed at the integer device anchor `S`. A move by whole
// device pixels moves `R` and `S` and leaves the key bit-identical, so it hits
// and hands back the same `ImageTexture` (`TE-AF`). The raster is a function of
// the key alone (history-independent, test L1.4).

/// Where a canonical raster sits (`PF-A`): the creation-space anchor `R` the
/// content was translated by, the integer device shift `S` it is placed at,
/// the canonical map `full'`, and how its clip is keyed (`PF-B`).
struct RasterAnchor {
    /// How a raster's clip enters its key (`PF-B`, `PF-J`).
    enum Mode: Int {
        /// The raster's conservative extent lies inside its clip: the clip
        /// decides no byte and is not keyed.
        case uncut = 1
        /// The clip cuts the raster: keyed relative to `S`, so a move
        /// relative to the clip misses (spec §9 D2).
        case cut = 2
        /// A local mask (a clip pushed inside a rotation or non-uniform
        /// scale): 2155f1e's absolute key and raster, `R` and `S` zero (§9 D3).
        case localMask = 3
    }

    let mode: Mode
    /// `R`, in the content's creation space (zero in `.localMask`).
    let rx: Double, ry: Double
    /// `S`, in device pixels (zero in `.localMask`).
    let sx: Int, sy: Int
    /// `full'`: the composed map's linear part, translation `f = D − S`
    /// (the composed map itself in `.localMask`).
    let map: Affine2D

    /// The anchor of content whose creation-space anchor is `(rx, ry)` under
    /// `full`, whose conservative device extent is `extent`, placed by
    /// `placement`. Falls back to `.localMask` (absolute) when the placement
    /// has a local mask or the device anchor is not a usable integer.
    init(rx: Double, ry: Double, full: Affine2D, extent: RasterRect, placement: RasterPlacement) {
        let d = full.apply(rx, ry)
        let limit = 1_000_000_000.0
        guard placement.localMask == nil, rx.isFinite, ry.isFinite, d.x.isFinite, d.y.isFinite,
              abs(d.x) < limit, abs(d.y) < limit else {
            self.init(absolute: full)
            return
        }
        let fx = d.x.rounded(.down), fy = d.y.rounded(.down)
        self.init(mode: RasterAnchor.contains(placement.clip, extent) ? .uncut : .cut, rx: rx, ry: ry,
                  sx: Int(fx), sy: Int(fy),
                  map: Affine2D(a: full.a, b: full.b, c: full.c, d: full.d, tx: d.x - fx, ty: d.y - fy))
    }

    /// 2155f1e's absolute raster (`.localMask`).
    init(absolute full: Affine2D) {
        self.init(mode: .localMask, rx: 0, ry: 0, sx: 0, sy: 0, map: full)
    }

    private init(mode: Mode, rx: Double, ry: Double, sx: Int, sy: Int, map: Affine2D) {
        self.mode = mode
        self.rx = rx
        self.ry = ry
        self.sx = sx
        self.sy = sy
        self.map = map
    }

    /// Whether the raster's content is translated into canonical coordinates.
    var isCanonical: Bool { mode != .localMask }

    /// `rect` in canonical device coordinates (`− S`).
    func canonical(_ rect: RasterRect) -> RasterRect {
        RasterRect(x: rect.x - sx, y: rect.y - sy, width: rect.width, height: rect.height)
    }

    /// A canonical `rect` placed on the device (`+ S`).
    func placed(_ rect: RasterRect) -> RasterRect {
        RasterRect(x: rect.x + sx, y: rect.y + sy, width: rect.width, height: rect.height)
    }

    /// The anchor's part of a key: the mode word, `full'`, and the clip —
    /// canonical when it cuts, absolute (with the local mask) in
    /// `.localMask`, absent when it does not cut.
    func keyed(_ key: inout RasterKey, clip: RasterRect, placement: RasterPlacement) {
        key.add(mode.rawValue)
        key.add(map)
        switch mode {
        case .uncut: break
        case .cut: key.add(clip)
        case .localMask: placement.keyed(&key)
        }
    }

    /// `inner` lies inside `outer` (an empty `inner` does).
    static func contains(_ outer: RasterRect, _ inner: RasterRect) -> Bool {
        inner.isEmpty || (inner.x >= outer.x && inner.y >= outer.y && inner.maxX <= outer.maxX
                          && inner.maxY <= outer.maxY)
    }

    /// `v` floored to the grid of `1 / g`.
    static func floor(_ v: Double, grid g: Double) -> Double { (v * g).rounded(.down) / g }

    /// The device grid of a space mapped by `map`, in that space's units:
    /// `1 / s` for a uniform scale of 1, 2 or 4 (so `R` maps to whole device
    /// pixels exactly), else 1 (`PF-A` item 1). Returned as `s`.
    static func grid(of map: Affine2D) -> Double {
        map.b == 0 && map.c == 0 && map.a == map.d && (map.a == 1 || map.a == 2 || map.a == 4) ? map.a : 1
    }

    /// The minimum corner of `leaf`'s screen box floored to whole pixels, or
    /// `nil` for an empty or non-finite leaf.
    static func leafAnchor(_ leaf: [CapturedPrimitive]) -> (x: Double, y: Double)? {
        var minX = Float.infinity, minY = Float.infinity
        for q in leaf {
            let b = q.screenBounds
            minX = min(minX, b.origin.x)
            minY = min(minY, b.origin.y)
        }
        guard minX.isFinite, minY.isFinite else { return nil }
        return (Double(minX).rounded(.down), Double(minY).rounded(.down))
    }

    /// The minimum corner of `geometry`'s control points floored to the grid
    /// of `map` (an outline in points under `map`), or `nil` when empty.
    static func outlineAnchor(_ geometry: PathGeometry, map: Affine2D) -> (x: Double, y: Double)? {
        guard let box = geometry.controlPointBounds, box.minX.isFinite, box.minY.isFinite else { return nil }
        let g = grid(of: map)
        return (floor(box.minX, grid: g), floor(box.minY, grid: g))
    }
}

// MARK: - The conservative extent (`PF-J`)

/// A device rectangle in `Double` being unioned.
struct ExtentBox {
    var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity

    mutating func add(_ b: MUIBounds) {
        minX = min(minX, Double(b.origin.x))
        minY = min(minY, Double(b.origin.y))
        maxX = max(maxX, Double(b.origin.x) + Double(b.size.width))
        maxY = max(maxY, Double(b.origin.y) + Double(b.size.height))
    }

    mutating func add(_ o: ExtentBox) {
        minX = min(minX, o.minX); minY = min(minY, o.minY); maxX = max(maxX, o.maxX); maxY = max(maxY, o.maxY)
    }

    /// The enclosing integer rectangle grown by `pad` on every side; empty
    /// when nothing was added.
    func rect(grownBy pad: Int) -> RasterRect {
        guard minX <= maxX, minY <= maxY else { return RasterRect(x: 0, y: 0, width: 0, height: 0) }
        let r = RasterRect.enclosing(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        return RasterRect(x: r.x - pad, y: r.y - pad, width: r.width + 2 * pad, height: r.height + 2 * pad)
    }
}

enum RasterExtent {
    /// Every device pixel `leaf` can cover under `map` (its creation space to
    /// the device), each primitive's box grown by its own reach: a nested
    /// shadow or blur by `BoxBlur.padding` of its own device sigma plus one
    /// pixel (`PF-J` item 1: not `ShadowPaint.bounds`' `3·radius`, which can be
    /// smaller than the boxes' reach), a stroke by `PathPaint.bounds`' miter
    /// pad. Masks are ignored: a superset.
    static func of(_ leaf: [CapturedPrimitive], map: Affine2D) -> ExtentBox {
        var box = ExtentBox()
        for q in leaf { box.add(of(q, map: map)) }
        return box
    }

    static func of(_ q: CapturedPrimitive, map: Affine2D) -> ExtentBox {
        let m = map.concatenating(q.transform?.affine ?? .identity)
        var box = ExtentBox()
        switch q.kind {
        case let .rect(r): box.add(m.boundingBox(of: r.bounds))
        case let .glyph(g): box.add(m.boundingBox(of: g.bounds))
        case let .image(i, _): box.add(m.boundingBox(of: i.bounds))
        case let .surface(s, _): box.add(m.boundingBox(of: s.bounds))
        case let .path(p): box.add(m.boundingBox(of: p.bounds))
        case let .gradient(g): box.add(m.boundingBox(of: g.bounds))
        case let .shadow(inner):
            let full = m.concatenating(inner.local)
            let ox = full.a * inner.dx + full.c * inner.dy, oy = full.b * inner.dx + full.d * inner.dy
            box = grown(of(inner.leaf, map: Affine2D.translation(x: ox, y: oy).concatenating(full)),
                        by: Double(BoxBlur.padding(sigma: inner.radius * full.linearScale) + 1))
        case let .blur(inner):
            let full = m.concatenating(inner.local)
            box = grown(of(inner.leaf, map: full), by: Double(BoxBlur.padding(sigma: inner.radius * full.linearScale) + 1))
        }
        return box
    }

    private static func grown(_ b: ExtentBox, by pad: Double) -> ExtentBox {
        guard b.minX <= b.maxX else { return b }
        return ExtentBox(minX: b.minX - pad, minY: b.minY - pad, maxX: b.maxX + pad, maxY: b.maxY + pad)
    }
}

// MARK: - Canonical content (`PF-A` item 1)

extension MUIBounds {
    /// Moved by `(dx, dy)` device pixels.
    func moved(_ dx: Double, _ dy: Double) -> MUIBounds {
        MUIBounds(origin: MUIPoint(x: origin.x + Float(dx), y: origin.y + Float(dy)), size: size)
    }
}

extension Affine2D {
    /// `T(dx, dy) ∘ self ∘ T(ax, ay)`: a map whose source moved by `−(ax, ay)`
    /// and whose target moved by `(dx, dy)`. The integer sums are taken first,
    /// so a pure translation stays exact.
    func reanchored(source ax: Double, _ ay: Double, target dx: Double, _ dy: Double) -> Affine2D {
        Affine2D(a: a, b: b, c: c, d: d, tx: tx + ((a * ax + c * ay) + dx), ty: ty + ((b * ax + d * ay) + dy))
    }
}

extension CapturedPrimitive {
    /// The primitive with its creation space moved by `(dx, dy)`: a
    /// primitive transform conjugated (`T(d)·A·T(−d)`, its outer mask moved,
    /// so its local space moves too), its content moved, and a nested
    /// outline's or leaf's own space re-anchored to its own floored minimum
    /// corner, so a layout move of nested content is invisible too.
    func movedCanonically(_ dx: Double, _ dy: Double) -> CapturedPrimitive {
        var p = self
        if var t = p.transform {
            let a = t.affine
            t.affine = Affine2D(a: a.a, b: a.b, c: a.c, d: a.d,
                                tx: a.tx + (dx - (a.a * dx + a.c * dy)), ty: a.ty + (dy - (a.b * dx + a.d * dy)))
            t.outerMask = t.outerMask.moved(dx, dy)
            p.transform = t
        }
        switch kind {
        case var .rect(r):
            r.bounds = r.bounds.moved(dx, dy); r.contentMask = r.contentMask.moved(dx, dy)
            p.kind = .rect(r)
        case var .glyph(g):
            g.bounds = g.bounds.moved(dx, dy); g.contentMask = g.contentMask.moved(dx, dy)
            p.kind = .glyph(g)
        case .image(var i, let texture):
            i.bounds = i.bounds.moved(dx, dy); i.contentMask = i.contentMask.moved(dx, dy)
            p.kind = .image(i, texture: texture)
        case .surface(var s, let target):
            s.bounds = s.bounds.moved(dx, dy); s.contentMask = s.contentMask.moved(dx, dy)
            p.kind = .surface(s, target: target)
        case let .path(path):
            p.kind = .path(path.movedCanonically(dx, dy))
        case let .gradient(gradient):
            p.kind = .gradient(gradient.movedCanonically(dx, dy))
        case let .shadow(shadow):
            p.kind = .shadow(shadow.movedCanonically(dx, dy))
        case let .blur(blur):
            p.kind = .blur(blur.movedCanonically(dx, dy))
        }
        return p
    }
}

extension PathPaint {
    /// The outline translated to its own floored anchor, `local` re-anchored
    /// and its target moved by `(dx, dy)`; the mask moved.
    func movedCanonically(_ dx: Double, _ dy: Double) -> PathPaint {
        var p = self
        if let (ax, ay) = RasterAnchor.outlineAnchor(geometry, map: local) {
            p.geometry = geometry.translated(dx: -ax, dy: -ay)
            p.local = local.reanchored(source: ax, ay, target: dx, dy)
        } else {
            p.local = local.reanchored(source: 0, 0, target: dx, dy)
        }
        p.contentMask = contentMask.moved(dx, dy)
        return p
    }
}

extension GradientPaint {
    /// As ``PathPaint/movedCanonically(_:_:)``, the axis and the strip
    /// rectangle moving with the outline.
    func movedCanonically(_ dx: Double, _ dy: Double) -> GradientPaint {
        var g = self
        if let (ax, ay) = RasterAnchor.outlineAnchor(geometry, map: local) {
            g.geometry = geometry.translated(dx: -ax, dy: -ay)
            g.axis = axis.offsetBy(dx: -ax, dy: -ay)
            g.strip = strip.map { GradientPaint.Strip(x: $0.x - ax, y: $0.y - ay, width: $0.width, height: $0.height,
                                                      radii: $0.radii) }
            g.local = local.reanchored(source: ax, ay, target: dx, dy)
        } else {
            g.local = local.reanchored(source: 0, 0, target: dx, dy)
        }
        g.contentMask = contentMask.moved(dx, dy)
        return g
    }
}

extension ShadowPaint {
    /// The leaf translated to its own floored anchor, `local` re-anchored and
    /// its target moved by `(dx, dy)`; the mask moved.
    func movedCanonically(_ dx: Double, _ dy: Double) -> ShadowPaint {
        var s = self
        let (ax, ay) = RasterAnchor.leafAnchor(leaf) ?? (0, 0)
        s.leaf = leaf.map { $0.movedCanonically(-ax, -ay) }
        s.local = local.reanchored(source: ax, ay, target: dx, dy)
        s.contentMask = contentMask.moved(dx, dy)
        return s
    }
}

extension BlurPaint {
    /// As ``ShadowPaint/movedCanonically(_:_:)``.
    func movedCanonically(_ dx: Double, _ dy: Double) -> BlurPaint {
        var b = self
        let (ax, ay) = RasterAnchor.leafAnchor(leaf) ?? (0, 0)
        b.leaf = leaf.map { $0.movedCanonically(-ax, -ay) }
        b.local = local.reanchored(source: ax, ay, target: dx, dy)
        b.contentMask = contentMask.moved(dx, dy)
        return b
    }
}
