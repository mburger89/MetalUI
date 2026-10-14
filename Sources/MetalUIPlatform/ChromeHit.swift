import MetalUICore

// SDL custom window chrome (item S1, rulings `CW-E`, `CW-G`, `CW-H`; spec
// `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md`). A borderless SDL window is moved and resized by
// `SDL_SetWindowHitTest`, whose callback runs on the platform's thread and must answer synchronously from
// an immutable value: this file is that value's **specification** (`ChromeHitSnapshot.hit(at:)`, pure,
// portable) and the pure region function `Window` publishes through (`ChromeHitMap.carve`). The bridge's C
// `mui_chrome_hit` is checked against `hit(at:)` over a table of points (`CW-H`), the `BoxBlur` precedent.

/// What the platform should do with a press at a point of a borderless window (`CW-G`): leave it to the
/// app, move the window, or start resizing from an edge or corner.
public enum ChromeHit: Sendable, Equatable {
    /// An ordinary point: the app gets the pointer events.
    case normal
    /// Inside a drag region: the platform moves the window and the app sees no pointer events there
    /// (divergence 425).
    case draggable
    /// The top-left corner square.
    case resizeTopLeft
    /// The top edge.
    case resizeTop
    /// The top-right corner square.
    case resizeTopRight
    /// The right edge.
    case resizeRight
    /// The bottom-right corner square.
    case resizeBottomRight
    /// The bottom edge.
    case resizeBottom
    /// The bottom-left corner square.
    case resizeBottomLeft
    /// The left edge.
    case resizeLeft
}

/// Everything a platform's hit-test callback reads (`CW-H`): the window's size in points, the regions where
/// a press moves the window, and the resize rules. A value — the callback copies it under a lock and never
/// reads another MetalUI object. `hit(at:)` is the specification a C copy is checked against.
public struct ChromeHitSnapshot: Sendable, Equatable {
    /// The edge band's width in points (`CW-G`); a corner is a square of twice this.
    public static let resizeBorder: Float = 6
    /// The most drag regions a snapshot carries (`CW-E`): the bridge's C copy is a fixed array.
    public static let maximumRegions = 64

    /// The window's client size in points.
    public var size: Size<Pixels>
    /// The rects where a press moves the window, disjoint, in window points (`CW-M` 1).
    public var dragRegions: [Bounds<Pixels>]
    /// Whether the window has no system frame: only then does it resize from its edges.
    public var borderless: Bool
    /// Whether the window is maximised or fullscreen: then it has no edges.
    public var zoomedOrFullscreen: Bool
    /// Whether the window's width may change (its minimum and maximum differ).
    public var resizableHorizontally: Bool
    /// Whether the window's height may change.
    public var resizableVertically: Bool

    /// A snapshot of a window `size` points across with `dragRegions`; borderless windows resize from their
    /// edges unless `zoomedOrFullscreen` or fixed on an axis.
    public init(size: Size<Pixels>, dragRegions: [Bounds<Pixels>] = [], borderless: Bool = false,
                zoomedOrFullscreen: Bool = false, resizableHorizontally: Bool = true,
                resizableVertically: Bool = true) {
        self.size = size
        self.dragRegions = dragRegions
        self.borderless = borderless
        self.zoomedOrFullscreen = zoomedOrFullscreen
        self.resizableHorizontally = resizableHorizontally
        self.resizableVertically = resizableVertically
    }

    /// The answer for a press at `point`, in this order (`CW-G`): a corner square, an edge, a drag rect,
    /// normal. Edges apply only to a borderless, unzoomed window and only on an axis that can change; a
    /// corner needs both axes. A point outside the window is normal. Every comparison is half-open on the
    /// max side, as `Bounds.contains` is.
    public func hit(at point: Point<Pixels>) -> ChromeHit {
        let x = point.x.value, y = point.y.value
        let width = size.width.value, height = size.height.value
        guard x >= 0, y >= 0, x < width, y < height else { return .normal }
        if borderless && !zoomedOrFullscreen {
            let edge = Self.resizeBorder, corner = 2 * Self.resizeBorder
            let left = resizableHorizontally && x < edge
            let right = resizableHorizontally && x >= width - edge
            let top = resizableVertically && y < edge
            let bottom = resizableVertically && y >= height - edge
            if resizableHorizontally && resizableVertically {
                let nearLeft = x < corner, nearRight = x >= width - corner
                let nearTop = y < corner, nearBottom = y >= height - corner
                if nearTop && nearLeft { return .resizeTopLeft }
                if nearTop && nearRight { return .resizeTopRight }
                if nearBottom && nearLeft { return .resizeBottomLeft }
                if nearBottom && nearRight { return .resizeBottomRight }
            }
            if top { return .resizeTop }
            if bottom { return .resizeBottom }
            if left { return .resizeLeft }
            if right { return .resizeRight }
        }
        for region in dragRegions where region.contains(point) { return .draggable }
        return .normal
    }
}

/// The pure region function behind `Window`'s published drag regions (`CW-E`): rect subtraction, not a point
/// lookup. It reads rects and nothing else, so it is not a second hit-testing ranking (`CW-J`).
package enum ChromeHitMap {
    /// `candidates` minus every `blocker`, made disjoint, in reading order (top to bottom, then left to
    /// right), deduplicated by value, cut at `limit`. `truncated` counts the rects past the limit — the
    /// area that is simply not draggable. Rects of no area are dropped.
    package static func carve(candidates: [Bounds<Pixels>], blockers: [Bounds<Pixels>],
                              limit: Int) -> (rects: [Bounds<Pixels>], truncated: Int) {
        carve(ranked: candidates.map { ($0, blockers) }, limit: limit)
    }

    /// As `carve(candidates:blockers:limit:)`, each candidate with **its own** blockers (`CW-V`: only a
    /// hitbox ranked above a candidate may carve it). Earlier candidates' accepted pieces still carve later
    /// ones, so the result stays disjoint.
    package static func carve(ranked: [(candidate: Bounds<Pixels>, blockers: [Bounds<Pixels>])],
                              limit: Int) -> (rects: [Bounds<Pixels>], truncated: Int) {
        var accepted: [Bounds<Pixels>] = []
        for (candidate, blockers) in ranked {
            var pieces = [candidate]
            for blocker in blockers + accepted {
                pieces = pieces.flatMap { subtract(blocker, from: $0) }
                if pieces.isEmpty { break }
            }
            accepted += pieces
        }
        var ordered: [Bounds<Pixels>] = []
        for rect in accepted.sorted(by: reads) where rect.size.width.value > 0 && rect.size.height.value > 0 {
            if ordered.last != rect { ordered.append(rect) }
        }
        let cut = max(0, ordered.count - limit)
        return (Array(ordered.prefix(limit)), cut)
    }

    /// Whether `a` comes before `b` in reading order.
    private static func reads(_ a: Bounds<Pixels>, _ b: Bounds<Pixels>) -> Bool {
        if a.origin.y.value != b.origin.y.value { return a.origin.y.value < b.origin.y.value }
        if a.origin.x.value != b.origin.x.value { return a.origin.x.value < b.origin.x.value }
        if a.size.height.value != b.size.height.value { return a.size.height.value < b.size.height.value }
        return a.size.width.value < b.size.width.value
    }

    /// `rect` minus `blocker`: `rect` itself when they do not overlap, else the strip above, the pieces left
    /// and right of the blocker in its rows, and the strip below.
    private static func subtract(_ blocker: Bounds<Pixels>, from rect: Bounds<Pixels>) -> [Bounds<Pixels>] {
        let rx0 = rect.origin.x.value, ry0 = rect.origin.y.value
        let rx1 = rx0 + rect.size.width.value, ry1 = ry0 + rect.size.height.value
        let bx0 = max(blocker.origin.x.value, rx0), by0 = max(blocker.origin.y.value, ry0)
        let bx1 = min(blocker.origin.x.value + blocker.size.width.value, rx1)
        let by1 = min(blocker.origin.y.value + blocker.size.height.value, ry1)
        guard bx0 < bx1, by0 < by1 else { return [rect] }
        func make(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> Bounds<Pixels> {
            Bounds(origin: Point(x: Pixels(x0), y: Pixels(y0)),
                   size: Size(width: Pixels(x1 - x0), height: Pixels(y1 - y0)))
        }
        var pieces: [Bounds<Pixels>] = []
        if by0 > ry0 { pieces.append(make(rx0, ry0, rx1, by0)) }
        if bx0 > rx0 { pieces.append(make(rx0, by0, bx0, by1)) }
        if bx1 < rx1 { pieces.append(make(bx1, by0, rx1, by1)) }
        if by1 < ry1 { pieces.append(make(rx0, by1, rx1, ry1)) }
        return pieces
    }
}
