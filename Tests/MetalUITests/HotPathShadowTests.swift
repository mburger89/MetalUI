import Testing
import MetalUICore
import MetalUILayout
import MetalUIPath
@testable import MetalUI

// Hot paths lane 2 (`HP-C`, `HP-E`, spec tests 14, 16-18): the plain-loop context-menu target, the
// stored `RasterKey` hash, one probe per shadow hit and the scalar bounding box.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private struct Lcg {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}

/// **HP.14 (spec test 14).** `Window.contextualTarget(in:at:where:)` (plain reverse loop) picks the same
/// index as the `lastIndex(where:)` closure form it replaced, over 3000 random lists of layered, nested,
/// region/opaque hitboxes where ids repeat so several candidates match one ancestor. Mutation: search
/// forward instead of in reverse.
@Test @MainActor func contextualTargetPicksTheSameHitboxAsTheClosureForm() throws {
    let root = GlobalElementID(component: .positional(0), parent: nil)
    let a = GlobalElementID.child(of: root, at: 0, name: nil)
    let b = GlobalElementID.child(of: a, at: 1, name: nil)
    let ids = [root, a, b]
    var rng = Lcg(state: 7)
    var ambiguous = 0
    func reference(_ boxes: [Hitbox], _ point: Point<Pixels>, _ wanted: (ContextualAttachment) -> Bool) -> Int? {
        func isRegion(_ box: Hitbox) -> Bool {
            guard !box.opaque, let attachment = box.handlers.contextual else { return false }
            return wanted(attachment)
        }
        guard let top = topmostHitbox(in: boxes, at: point, where: { $0.opaque || isRegion($0) }) else { return nil }
        let hit = boxes[top]
        if isRegion(hit) { return top }
        var cursor: GlobalElementID? = hit.id
        while let id = cursor {
            if let index = boxes.lastIndex(where: { $0.id == id && $0.layer == hit.layer && isRegion($0) && $0.contains(point) }) {
                if boxes.filter({ $0.id == id && $0.layer == hit.layer && isRegion($0) && $0.contains(point) }).count > 1 {
                    ambiguous += 1
                }
                return index
            }
            cursor = id.parent
        }
        return nil
    }
    var nonNil = 0, viaAncestor = 0
    for _ in 0..<3000 {
        var boxes: [Hitbox] = []
        for _ in 0..<(4 + rng.next(9)) {
            var handlers = Handlers()
            let kind = rng.next(3) // 0: none, 1: menu, 2: help
            if kind == 1 { handlers.contextual = ContextualAttachment(locatedMenu: { _ in MenuItems([]) }, help: nil) }
            if kind == 2 { handlers.contextual = ContextualAttachment(locatedMenu: nil, help: "tip") }
            let x = Float(rng.next(40)), y = Float(rng.next(40)), w = Float(30 + rng.next(70)), h = Float(30 + rng.next(70))
            boxes.append(Hitbox(bounds: Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h))),
                                id: ids[rng.next(3)], layer: rng.next(2), opaque: rng.next(4) == 0, scroll: nil,
                                handlers: handlers, origin: pt(x, y), shape: nil))
        }
        let point = pt(Float(rng.next(80)), Float(rng.next(80)))
        for wanted in [{ (c: ContextualAttachment) in c.menu != nil }, { (c: ContextualAttachment) in c.help != nil }] {
            let want = reference(boxes, point, wanted)
            let got = Window.contextualTarget(in: boxes, at: point, where: wanted)
            #expect(got == want, "list \(boxes.count) at \(point): \(String(describing: got)) vs \(String(describing: want))")
            if want != nil { nonNil += 1 }
            if let w = want, boxes[w].opaque == false, let top = topmostHitbox(in: boxes, at: point, where: { _ in true }),
               top != w { viaAncestor += 1 }
        }
    }
    try #require(nonNil > 100, "set up: the random lists reach a target often enough, got \(nonNil)")
    try #require(ambiguous > 15, "set up: several regions of one id and layer contain the point (the search direction decides), got \(ambiguous)")
    try #require(viaAncestor > 5, "set up: some answers come from the ancestor walk, got \(viaAncestor)")
}

/// **HP.16 (spec test 16, `HP-G`).** `RasterKey.storedHash` is the hash the key feeds (read back, not
/// inferred from `!=`): keys differing in only `words`, only `paths` or only `objects` store different
/// hashes, equal keys store equal hashes however they were built, and a hash updated by `add` after
/// construction is the one a key built in one go would store. `==` is not hash-only: two keys forced to
/// one stored hash with different words compare unequal. Mutations: skip `objects` in the fold; skip the
/// fold in `add(_: Int)`; make `==` compare the hash alone.
@Test @MainActor func aRasterKeyHashesFromItsStoredHash() throws {
    func geometry(_ n: Float) -> PathGeometry {
        var g = PathGeometry()
        g.move(to: PathPoint(x: 0, y: 0)); g.addLine(to: PathPoint(x: Double(n), y: Double(n)))
        g.addLine(to: PathPoint(x: Double(n), y: 0))
        return g
    }
    final class Token {}
    let t1 = Token(), t2 = Token()
    var base = RasterKey(); base.add(2); base.add(Float(1.5))
    var onlyWord = RasterKey(); onlyWord.add(2); onlyWord.add(Float(2.5))
    var onlyPath = base; onlyPath.addPath(geometry(3))
    var otherPath = base; otherPath.addPath(geometry(4))
    var onlyObject = base; onlyObject.addObject(ObjectIdentifier(t1))
    var otherObject = base; otherObject.addObject(ObjectIdentifier(t2))
    let hashes = [base, onlyWord, onlyPath, otherPath, onlyObject, otherObject].map(\.storedHash)
    #expect(Set(hashes).count == hashes.count, "six keys differing in one component store six hashes: \(hashes)")
    var again = RasterKey(); again.add(2); again.add(Float(1.5))
    #expect(again == base && again.storedHash == base.storedHash)
    var viaWords = RasterKey(); viaWords.addWords([2, UInt64(Float(1.5).bitPattern)])
    #expect(viaWords == base && viaWords.storedHash == base.storedHash, "adding words in bulk folds the same hash")
    var later = onlyObject; later.add(Int(9))
    var once = base; once.addObject(ObjectIdentifier(t1)); once.add(Int(9))
    #expect(later == once && later.storedHash == once.storedHash, "a word added after construction updates the hash")
    #expect(later.storedHash != onlyObject.storedHash, "and moves it")
    var h1 = Hasher(), h2 = Hasher()
    base.hash(into: &h1); again.hash(into: &h2)
    #expect(h1.finalize() == h2.finalize(), "equal keys hash alike through Hasher")
    let x = RasterKey(forcedHash: 5, words: [1]), y = RasterKey(forcedHash: 5, words: [2])
    try #require(x.storedHash == y.storedHash, "set up: the forced hashes collide")
    #expect(x != y, "equality compares the fields, not the hash alone")
    #expect(x == RasterKey(forcedHash: 5, words: [1]))
}

/// **HP.17 (spec test 17).** A shadow hit costs one key probe per cache (coverage, tint), a miss two:
/// `RasterCache.keyProbes` over a repeated shadow paint grows by 2 per shadow (one coverage, one tint) and
/// 0 coverage is made. Red before: the touched-set insert and the dictionary read were two probes each
/// (4 per shadow). Mutation: touch the entry through a second lookup.
@Test @MainActor func aShadowHitDoesNotRehashItsKey() throws {
    let h = WrapperHarness()
    func tree() -> some Element {
        Rectangle(width: Pixels(40), height: Pixels(40)).background(.accent).shadow(radius: Pixels(6), x: Pixels(2), y: Pixels(3))
    }
    h.frame(0, nil, tree())
    h.frame(0.1, nil, tree())
    let cache = h.store.rasters
    var shadows = 0
    cache.onRaster = { kind, _ in if case .shadow = kind { shadows += 1 } }
    let before = cache.keyProbes
    h.frame(0.2, nil, tree())
    cache.onRaster = nil
    try #require(shadows > 0, "set up: the frame asked for shadow rasters")
    let perFrame = cache.keyProbes - before
    #expect(cache.lastRasterizedPixels == 0 && cache.lastBlurredPixels == 0, "a hit makes no coverage")
    #expect(perFrame == 2 * shadows, "one coverage probe and one tint probe per hit (\(shadows) shadows), got \(perFrame)")
}

/// **HP.18 (spec test 18).** The scalar `boundingBox` equals the four-corner array form bit for bit over
/// random affines (rotation, negative scale, shear, translation) and bounds. Mutation: swap min and max
/// for y.
@Test func boundingBoxEqualsTheFourCornerArrayForm() {
    var rng = Lcg(state: 99)
    func unit() -> Double { Double(rng.next(2001) - 1000) / 100 }
    for _ in 0..<500 {
        let m = Affine2D(a: unit(), b: unit(), c: unit(), d: unit(), tx: unit() * 10, ty: unit() * 10)
        let b = MUIBounds(origin: MUIPoint(x: Float(unit()), y: Float(unit())),
                          size: MUISize(width: Float(abs(unit())), height: Float(abs(unit()))))
        let x = Double(b.origin.x), y = Double(b.origin.y), w = Double(b.size.width), h = Double(b.size.height)
        let corners = [m.apply(x, y), m.apply(x + w, y), m.apply(x, y + h), m.apply(x + w, y + h)]
        let minX = corners.map(\.x).min()!, maxX = corners.map(\.x).max()!
        let minY = corners.map(\.y).min()!, maxY = corners.map(\.y).max()!
        let want = MUIBounds(origin: MUIPoint(x: Float(minX), y: Float(minY)),
                             size: MUISize(width: Float(maxX - minX), height: Float(maxY - minY)))
        let got = m.boundingBox(of: b)
        #expect(got.origin.x.bitPattern == want.origin.x.bitPattern && got.origin.y.bitPattern == want.origin.y.bitPattern
                && got.size.width.bitPattern == want.size.width.bitPattern
                && got.size.height.bitPattern == want.size.height.bitPattern, "\(m) \(b)")
    }
}
