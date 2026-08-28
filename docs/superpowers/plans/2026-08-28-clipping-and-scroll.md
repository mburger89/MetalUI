# Clipping and Scroll Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the renderer order primitives across types and clip them, then build a `ScrollView` on top.

**Architecture:** Four renderer tasks come first and have no element-facing surface — a draw list in `Scene` that makes z-order work across rects and glyphs, then `contentMask` made live in both fragment shaders. Five element tasks build on them: a clip/translate stack on `Frame`, a `ScrollView` whose offset lives in the state table, wheel routing through a scroll-region registry, and a fading overlay indicator.

**Tech Stack:** Swift 6.3 (`swiftLanguageModes: [.v6]`, strict concurrency), Metal, swift-testing (`@Test`/`#expect`/`#require`), AppKit.

**Spec:** `docs/superpowers/specs/2026-08-28-clipping-and-scroll-design.md`

## Global Constraints

- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **`MetalUIText` must not import Metal.** It is CoreText + Foundation.
- **Pixel format is `bgra8Unorm`, never `_sRGB`.** Atlas format is `.r8Unorm`.
- **After editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, run `swift package clean`.** The header reaches its C target through a symlink SwiftPM does not track; the symptom of skipping this is a vanished primitive that looks exactly like a shader bug.
- **No golden may move.** 67 goldens in `Tests/MetalUILayoutTests/Golden/`. This project does not touch the flex engine. A moved golden means stop and report, not regenerate.
- **Read the test-run summary line, never the exit status.** `swift test --no-parallel 2>&1 | grep "Test run with"`. Baseline at plan start: **445 tests**.
- **Any count a later loop indexes on must be `try #require`, not `#expect`.** `#expect` records and continues, so a wrong implementation returning fewer elements sends the next loop past the end of its own array and truncates the suite with no summary line.
- **Every new "cannot happen" comment names a mechanism, not a milestone.**
- **When a mutation measurement is recorded, name the tests it reddens — never only count them.** A count is stale the moment a later task adds a sensitive test (ruling SI-H).
- **Read `docs/practices/verifying-tests-can-fail.md` before writing tests.** Thirteen numbered shapes; shape 12 ("the oracle is the code under test") is the one this project is most exposed to, because clip tests are pixel tests that can trivially read their expectation from the same mask the shader read.

---

### Task 1: A draw list in `Scene`

**Files:**
- Modify: `Sources/MetalUIRender/Scene.swift`
- Modify: `Sources/MetalUIRender/Renderer.swift` (`encode`, lines ~130-150)
- Test: `Tests/MetalUIRenderTests/DrawListTests.swift` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `Scene.drawList: [DrawRun]`, `DrawRun { kind: PrimitiveKind, start: Int, count: Int }`, `PrimitiveKind { case rect, glyph }`. Task 2 asserts on `drawList`; no later task changes its shape.

**Context.** `Scene` holds `rects: [MUIRect]` and `glyphs: [MUIGlyph]`. `finalize()` sorts each array by `order` with a stable tiebreak on insertion index. `Renderer.encode` then does `if !scene.rects.isEmpty { encodeRects(...) }` followed by `if !scene.glyphs.isEmpty { encodeGlyphs(...) }` — all rects, then all glyphs, regardless of order. That is the defect.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUIRenderTests/DrawListTests.swift`:

```swift
import Testing
import MetalUIShaderTypes
@testable import MetalUIRender

private func rect(order: MUIUInt) -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                              size: MUISize(width: 10, height: 10)),
            contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                   size: MUISize(width: 1000, height: 1000)),
            background: MUIHsla(h: 0, s: 0, l: 0.5, a: 1),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: order, _reserved: 0)
}

private func glyph(order: MUIUInt) -> MUIGlyph {
    MUIGlyph(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                               size: MUISize(width: 8, height: 12)),
             atlasBounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                    size: MUISize(width: 8, height: 12)),
             color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
             order: order, _reserved: 0)
}

/// The draw list is the whole of spec §7.3's promise: "draw-call count is the
/// number of type transitions in z-order". Before it, `encode` drew every rect
/// and then every glyph, so a rect could never occlude text.
@Test func theDrawListIsOneRunPerTypeTransitionInZOrder() throws {
    var scene = Scene()
    scene.insert(rect(order: 0))
    scene.insert(glyph(order: 1))
    scene.insert(rect(order: 2))
    scene.finalize()

    let runs = scene.drawList
    try #require(runs.count == 3, "expected 3 type transitions, got \(runs.count)")
    #expect(runs[0].kind == .rect  && runs[0].start == 0 && runs[0].count == 1)
    #expect(runs[1].kind == .glyph && runs[1].start == 0 && runs[1].count == 1)
    #expect(runs[2].kind == .rect  && runs[2].start == 1 && runs[2].count == 1)
}

/// Consecutive same-kind primitives coalesce — that is what keeps the count at
/// "type transitions" rather than "primitives".
@Test func consecutiveSameKindPrimitivesCoalesceIntoOneRun() throws {
    var scene = Scene()
    scene.insert(rect(order: 0))
    scene.insert(rect(order: 1))
    scene.insert(glyph(order: 2))
    scene.insert(glyph(order: 3))
    scene.finalize()

    let runs = scene.drawList
    try #require(runs.count == 2, "expected 2 runs, got \(runs.count)")
    #expect(runs[0].kind == .rect  && runs[0].count == 2)
    #expect(runs[1].kind == .glyph && runs[1].count == 2)
}

/// **The tiebreak is load-bearing.** `finalize()`'s existing comment says
/// "painters at the same layer must stack predictably". A merged sort across two
/// arrays has no inherent order between them, so insertion sequence must be
/// carried explicitly — without it, equal-order rects and glyphs interleave
/// arbitrarily and a container's background can land on top of its own text.
@Test func equalOrdersKeepEmissionSequenceAcrossTypes() throws {
    var scene = Scene()
    scene.insert(glyph(order: 5))
    scene.insert(rect(order: 5))
    scene.finalize()

    let runs = scene.drawList
    try #require(runs.count == 2)
    #expect(runs[0].kind == .glyph, "the glyph was emitted first and must draw first")
    #expect(runs[1].kind == .rect)
}

/// Each kind's array is permuted so every run is contiguous within it. A run
/// that pointed at a non-contiguous span would draw the wrong instances.
@Test func eachRunIndexesAContiguousSpanOfItsOwnArray() throws {
    var scene = Scene()
    scene.insert(rect(order: 10))
    scene.insert(glyph(order: 0))
    scene.insert(rect(order: 20))
    scene.insert(glyph(order: 30))
    scene.finalize()

    // z-order: glyph(0), rect(10), rect(20), glyph(30) -> 3 runs
    let runs = scene.drawList
    try #require(runs.count == 3, "expected 3 runs, got \(runs.count)")
    #expect(runs[0].kind == .glyph && runs[0].start == 0 && runs[0].count == 1)
    #expect(runs[1].kind == .rect  && runs[1].start == 0 && runs[1].count == 2)
    #expect(runs[2].kind == .glyph && runs[2].start == 1 && runs[2].count == 1)
    // And the arrays are in z-order within themselves.
    #expect(scene.rects.map(\.order) == [10, 20])
    #expect(scene.glyphs.map(\.order) == [0, 30])
}

/// An empty scene produces no runs, so `encode`'s early return stays correct.
@Test func anEmptySceneHasAnEmptyDrawList() {
    var scene = Scene()
    scene.finalize()
    #expect(scene.drawList.isEmpty)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --no-parallel --filter DrawListTests 2>&1 | grep -E "error:|Test run with"`
Expected: compile failure — `value of type 'Scene' has no member 'drawList'`.

- [ ] **Step 3: Implement the draw list**

In `Sources/MetalUIRender/Scene.swift`, add above `Scene`:

```swift
/// Which pipeline a primitive belongs to. One case per instanced draw.
public enum PrimitiveKind: Sendable, Equatable { case rect, glyph }

/// One instanced draw: `count` primitives of `kind`, starting at `start` in
/// that kind's own array.
///
/// **The number of runs IS the draw-call count** (spec §7.3: "draw-call count
/// is the number of type transitions in z-order"). That makes the promise
/// assertable rather than architectural — see `DrawListTests`.
public struct DrawRun: Sendable, Equatable {
    public let kind: PrimitiveKind
    public let start: Int
    public let count: Int
}
```

Add the stored property beside `rects` and `glyphs`:

```swift
    /// Built by ``finalize()``. Empty until then.
    public private(set) var drawList: [DrawRun] = []
```

Add `drawList.removeAll(keepingCapacity: true)` to `clear()`.

Replace `finalize()` entirely:

```swift
    /// Sorts primitives into paint order **across types** and builds the draw
    /// list.
    ///
    /// Each kind keeps its own array, because each maps to one pipeline and one
    /// instanced draw and a heterogeneous array would be re-partitioned every
    /// frame. What changes here is that `order` now totally orders the scene:
    /// the merged index below is sorted once, each array is permuted into that
    /// global order so every run is contiguous within it, and the run
    /// boundaries fall wherever the kind changes.
    ///
    /// **The insertion-sequence tiebreak is load-bearing.** Painters at the same
    /// layer must stack predictably, and a merged sort across two arrays has no
    /// inherent order between them — the sequence number is what supplies one.
    /// Pinned by `equalOrdersKeepEmissionSequenceAcrossTypes`.
    public mutating func finalize() {
        // (order, sequence, kind, indexWithinKind)
        var merged: [(MUIUInt, Int, PrimitiveKind, Int)] = []
        merged.reserveCapacity(rects.count + glyphs.count)
        for (i, r) in rects.enumerated() { merged.append((r.order, sequence[.rect]![i], .rect, i)) }
        for (i, g) in glyphs.enumerated() { merged.append((g.order, sequence[.glyph]![i], .glyph, i)) }
        merged.sort { ($0.0, $0.1) < ($1.0, $1.1) }

        let sortedRects = merged.filter { $0.2 == .rect }.map { rects[$0.3] }
        let sortedGlyphs = merged.filter { $0.2 == .glyph }.map { glyphs[$0.3] }
        rects = sortedRects
        glyphs = sortedGlyphs

        drawList = []
        var rectCursor = 0
        var glyphCursor = 0
        for entry in merged {
            let kind = entry.2
            let cursor = kind == .rect ? rectCursor : glyphCursor
            if let last = drawList.last, last.kind == kind {
                drawList[drawList.count - 1] =
                    DrawRun(kind: kind, start: last.start, count: last.count + 1)
            } else {
                drawList.append(DrawRun(kind: kind, start: cursor, count: 1))
            }
            if kind == .rect { rectCursor += 1 } else { glyphCursor += 1 }
        }
    }
```

Add the sequence store and stamp it on insert. Replace the two `insert` methods and add the property:

```swift
    /// Emission sequence per kind, so `finalize()` can tiebreak equal orders
    /// across types. Not public: it is bookkeeping for one method.
    private var sequence: [PrimitiveKind: [Int]] = [.rect: [], .glyph: []]
    private var nextSequence = 0

    public mutating func insert(_ rect: MUIRect) {
        rects.append(rect)
        sequence[.rect]!.append(nextSequence)
        nextSequence += 1
    }

    public mutating func insert(_ glyph: MUIGlyph) {
        glyphs.append(glyph)
        sequence[.glyph]!.append(nextSequence)
        nextSequence += 1
    }
```

And in `clear()`, also reset `sequence = [.rect: [], .glyph: []]` and `nextSequence = 0`.

- [ ] **Step 4: Make `encode` walk the draw list**

In `Sources/MetalUIRender/Renderer.swift`, replace the two `if !scene.…isEmpty` blocks at the end of `encode` with:

```swift
        // **One draw per run, pipeline bound only when the kind changes.** This
        // is what makes a rect able to occlude text: before the draw list,
        // `encode` drew every rect and then every glyph regardless of `order`.
        for run in scene.drawList {
            switch run.kind {
            case .rect:
                try encodeRects(Array(scene.rects[run.start..<(run.start + run.count)]),
                                into: encoder, viewport: &viewport, projection: &projection)
            case .glyph:
                try encodeGlyphs(Array(scene.glyphs[run.start..<(run.start + run.count)]),
                                 into: encoder, viewport: &viewport, projection: &projection)
            }
        }
```

The existing per-array non-empty guards are now redundant — a run always has `count >= 1`, so `makeBuffer(bytes:length: 0)` is unreachable. Keep `encodeRects`/`encodeGlyphs` otherwise unchanged.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 450 tests in 0 suites passed` (445 + 5 new). If any existing renderer test fails, the permutation or the run boundaries are wrong — do not adjust the test.

- [ ] **Step 6: Measure the mutation and name what it reddens**

Apply this mutation, run `swift test --no-parallel`, record the reddened test **names** (not a count), then revert:

```swift
// in finalize(), drop the sequence tiebreak:
merged.sort { $0.0 < $1.0 }
```

Expected: `equalOrdersKeepEmissionSequenceAcrossTypes` reddens. If it does not, the sort is already stable by accident of input order and the test needs a case that distinguishes — a mutation that reddens nothing is a broken instrument or it is the finding.

- [ ] **Step 7: Commit**

```bash
git add Sources/MetalUIRender/Scene.swift Sources/MetalUIRender/Renderer.swift Tests/MetalUIRenderTests/DrawListTests.swift
git commit -m "feat: order primitives across types with a draw list

Scene.finalize sorted WITHIN each type and encode drew every rect then
every glyph, so a rect could never occlude text. Spec 7.3 promises
draw-call count equals type transitions in z-order; this delivers it and
makes the count assertable."
```

---

### Task 2: Pin that a rect occludes text

**Files:**
- Modify: `Sources/MetalUIRender/Scene.swift` (delete the stale sentence in `finalize()`'s doc and in `glyphs`' doc)
- Test: `Tests/MetalUIRenderTests/GlyphABITests.swift` (append)

**Interfaces:**
- Consumes: `Scene.drawList` from Task 1.
- Produces: nothing later tasks depend on.

**Context.** `Scene.swift` currently carries two claims that Task 1 falsified. On `glyphs`: "**They are drawn after every rect, whatever their `order`.**" And in `finalize()`'s doc: "it is wrong for a rect that should occlude text beneath it … **nothing in this repo can see a glyph painted through a rect.**" Both must go, and the second must be replaced by the test that now can see it. A stale "nothing can see this" reads as a live hazard.

`GlyphABITests.swift` already has helpers you must reuse: `packedAtlas(_:size:scaleFactor:) -> (GlyphAtlas, [AtlasSlot])`, `sprite(_:at:color:order:) -> MUIGlyph`, and `alpha(_:_:_:width:) -> UInt8`. There is an existing test `aRectAndAGlyphBothDrawInOneScene` — read it for the `renderOffscreen` idiom before writing this one.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MetalUIRenderTests/GlyphABITests.swift`:

```swift
/// An opaque rect at a higher order must cover text beneath it.
///
/// **This is the assertion `Scene.finalize`'s doc comment said could not
/// exist** — "nothing in this repo can see a glyph painted through a rect" —
/// and it could not, while `encode` drew every rect before every glyph. The
/// draw list is what makes it visible, so this test is the draw list's reason
/// for being rather than a detail of it.
///
/// The differential is the second half: the SAME two primitives with the orders
/// swapped must give the opposite answer. Without it this test passes on a
/// renderer that draws nothing but rects.
@Test @MainActor func anOpaqueRectAtAHigherOrderCoversTheTextBeneathIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlas(["H"])
    let slot = slots[0]
    renderer.upload(atlas)

    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    // A blue rect exactly covering the glyph's box.
    func cover(order: MUIUInt) -> MUIRect {
        MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 4, y: 4),
                                  size: MUISize(width: Float(slot.width),
                                                height: Float(slot.height))),
                contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                       size: MUISize(width: Float(side), height: Float(side))),
                background: MUIHsla(h: 0.6, s: 1, l: 0.5, a: 1),
                borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
                cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                order: order, _reserved: 0)
    }

    // Find a pixel the glyph definitely inks, so "covered" is meaningful.
    var inkX = -1, inkY = -1
    for row in 0..<slot.height where inkY < 0 {
        for column in 0..<slot.width {
            if atlas.pixels[(slot.y + row) * atlas.width + slot.x + column] > 200 {
                inkX = column; inkY = row; break
            }
        }
    }
    try #require(inkY >= 0, "the glyph must have a near-opaque pixel for this test to mean anything")

    // Rect ABOVE the glyph: the covered pixel is the rect's colour.
    var above = Scene()
    above.insert(sprite(slot, at: (x: 4, y: 4), color: .white, order: 0))
    above.insert(cover(order: 1))
    above.finalize()
    #expect(above.drawList.count == 2)
    let coveredPixels = try renderer.renderOffscreen(above, size: size)

    // Rect BELOW the glyph: the same pixel is the glyph's white.
    var below = Scene()
    below.insert(cover(order: 0))
    below.insert(sprite(slot, at: (x: 4, y: 4), color: .white, order: 1))
    below.finalize()
    #expect(below.drawList.count == 2)
    let textPixels = try renderer.renderOffscreen(below, size: size)

    // BGRA8: index 0 is blue, index 2 is red.
    let hit = (((4 + inkY) * side) + 4 + inkX) * 4
    #expect(coveredPixels[hit] > 200, "the rect's blue must win where it is on top")
    #expect(coveredPixels[hit + 2] < 80, "no white text may show through an opaque rect")
    #expect(textPixels[hit + 2] > 200, "with the orders swapped, the white glyph must win")
}
```

- [ ] **Step 2: Run it to verify it fails against the OLD renderer**

This step is a check that the test is meaningful, and it needs Task 1 reverted temporarily. Stash Task 1's `encode` change only:

Run: `git stash push Sources/MetalUIRender/Renderer.swift && swift test --no-parallel --filter anOpaqueRectAtAHigherOrderCoversTheTextBeneathIt 2>&1 | grep -E "recorded an issue|Test run with"; git stash pop`
Expected: FAIL on `the rect's blue must win where it is on top` — the old encode drew the rect first regardless of order.

- [ ] **Step 3: Run it against the new renderer**

Run: `swift test --no-parallel --filter anOpaqueRectAtAHigherOrderCoversTheTextBeneathIt 2>&1 | grep -E "Test run with"`
Expected: PASS.

- [ ] **Step 4: Delete the two falsified sentences**

In `Sources/MetalUIRender/Scene.swift`, the `glyphs` property doc currently reads:

```swift
    /// Glyph sprites (`monochromeSprite`, spec 7.1).
    ///
    /// **They are drawn after every rect, whatever their `order`.** See
    /// ``finalize()``.
```

Replace with:

```swift
    /// Glyph sprites (`monochromeSprite`, spec 7.1).
    ///
    /// Ordered against rects by ``finalize()``'s draw list, not after them —
    /// that sentence used to say the opposite and was true until the draw list
    /// landed.
```

And in `finalize()`'s doc, the paragraph beginning "**`order` sorts WITHIN a primitive type and not between them.**" through "nothing in this repo can see a glyph painted through a rect." must be deleted — Step 3 of Task 1 already replaced this doc comment wholesale, so verify no fragment of it survives with `grep -n "WITHIN a primitive\|painted through a rect" Sources/`.

- [ ] **Step 5: Verify the stale claims are gone repo-wide**

Run: `grep -rn "after every rect\|painted through a rect\|WITHIN a primitive" Sources/ Tests/ CLAUDE.md docs/`
Expected: no output. If `CLAUDE.md` or a spec repeats the claim, fix it here.

- [ ] **Step 6: Commit**

```bash
git add -A Sources/MetalUIRender/Scene.swift Tests/MetalUIRenderTests/GlyphABITests.swift
git commit -m "test: pin that a rect occludes text, and delete the claim that it cannot

Scene.finalize's doc said 'nothing in this repo can see a glyph painted
through a rect'. The draw list makes it visible; this is the test, with
the order-swapped differential, and the stale sentence is gone."
```

---

### Task 3: `contentMask` live in `rect_fragment`

**Files:**
- Modify: `Sources/MetalUIRender/Shaders/shaders.metal` (`rect_fragment`)
- Modify: `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` (comment only — no layout change)
- Test: `Tests/MetalUIRenderTests/ClipTests.swift` (create)

**Interfaces:**
- Consumes: nothing from Tasks 1-2.
- Produces: clipping semantics that Task 4 mirrors for glyphs and Task 5 drives from the CPU.

**Context.** `MUIRect.contentMask` is already in the ABI and already round-trips (`abi_probe` reads `r.contentMask.size.width`). It is one of the four fields CLAUDE.md's declared-but-inert table tracks. `Frame.fill` already fills it with the whole surface, which is what makes turning the shader on non-breaking.

**Do not use `discard_fragment()`.** There is no depth buffer so it buys nothing, and on some GPUs it disables early-Z for the whole shader. Multiply the alpha to zero instead.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUIRenderTests/ClipTests.swift`:

```swift
import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

/// A rect clipped to the left half of its own box.
///
/// **The expected values are built from the CLIP, not from the primitive.**
/// Reading the mask back off the `MUIRect` to decide what to assert would be
/// taxonomy shape 12 — the oracle being the code under test — which produced
/// four defects in M2. The x boundary here is a literal.
private func clippedRect(mask: MUIBounds) -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 10, y: 10),
                              size: MUISize(width: 40, height: 40)),
            contentMask: mask,
            background: MUIHsla(h: 0, s: 0, l: 1, a: 1),   // white
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: 0, _reserved: 0)
}

@Test @MainActor func aRectIsPaintedOnlyInsideItsContentMask() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    // The rect spans x 10..<50. Clip it to x 10..<30.
    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 30, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)

    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    // Well inside the clip: painted.
    #expect(alphaAt(15, 25) > 200, "x=15 is inside both the rect and the clip")
    #expect(alphaAt(25, 25) > 200, "x=25 is inside both")
    // Well outside the clip but inside the rect: not painted.
    #expect(alphaAt(35, 25) < 20, "x=35 is inside the rect and outside the clip")
    #expect(alphaAt(45, 25) < 20, "x=45 is inside the rect and outside the clip")
    // Outside the rect entirely: not painted, clip or no clip.
    #expect(alphaAt(5, 25) < 20)
}

/// The differential: the identical rect with a full-surface mask paints all the
/// way across. Without this, the test above passes on a shader that paints
/// nothing beyond x=30 for an unrelated reason.
@Test @MainActor func theSameRectWithAFullMaskPaintsItsWholeWidth() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 64, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    #expect(alphaAt(35, 25) > 200, "unclipped, x=35 must be painted")
    #expect(alphaAt(45, 25) > 200, "unclipped, x=45 must be painted")
}

/// The clip edge is antialiased rather than a hard step. A half-pixel boundary
/// must produce a partially covered pixel, the same way the rect's own edge
/// does — a hard cutoff jags visibly on fractional boundaries.
@Test @MainActor func theClipEdgeIsAntialiasedLikeTheRectsOwnEdge() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    var scene = Scene()
    scene.insert(clippedRect(mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                             size: MUISize(width: 30.5, height: 64))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    let edge = alphaAt(30, 25)
    #expect(edge > 20 && edge < 235,
            "the pixel straddling a 30.5 boundary must be partially covered, got \(edge)")
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter ClipTests 2>&1 | grep -E "recorded an issue|Test run with"`
Expected: `aRectIsPaintedOnlyInsideItsContentMask` and `theClipEdgeIsAntialiasedLikeTheRectsOwnEdge` fail; `theSameRectWithAFullMaskPaintsItsWholeWidth` passes (the shader ignores the mask, so a full mask is indistinguishable).

- [ ] **Step 3: Add the mask helper and apply it**

In `Sources/MetalUIRender/Shaders/shaders.metal`, add above `rect_fragment`:

```metal
// Antialiased coverage of `p` inside an axis-aligned mask, in the same pixel
// space as `[[position]]`.
//
// **Not `discard_fragment()`.** There is no depth buffer, so discarding buys
// nothing, and on some GPUs it disables early-Z for the whole shader. Returning
// coverage keeps this composable with the SDF coverage the callers already
// compute, which is also what antialiases the clip edge: a hard step jags on a
// fractional boundary exactly as an unantialiased rect edge would.
static inline float mask_coverage(float2 p, MUIBounds mask) {
    float2 lo = float2(mask.origin.x, mask.origin.y);
    float2 hi = lo + float2(mask.size.width, mask.size.height);
    // 0.5 is half a pixel: the same antialiasing threshold `rect_sdf` uses.
    float2 inside = saturate(p - lo + 0.5) * saturate(hi - p + 0.5);
    return inside.x * inside.y;
}
```

In `rect_fragment`, change the final line from:

```metal
    return float4(color.rgb * color.a, color.a) * outerAlpha;
```

to:

```metal
    // Clip last, so it composes with the rounded-rect coverage above rather
    // than replacing it. A primitive is drawn where it intersects its mask.
    float clip = mask_coverage(in.pixelPosition, r.contentMask);
    return float4(color.rgb * color.a, color.a) * outerAlpha * clip;
```

- [ ] **Step 4: Update the header's stale comment**

In `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, the `contentMask` field comment currently says it is "CARRIED BUT NOT YET APPLIED" and that "Clipping arrives in M1 (spec 7.3)" — both now false, and the milestone reference was already wrong. Replace that comment block with:

```c
    // Axis-aligned clip, same space as `bounds`. `rect_fragment` multiplies
    // coverage by it, antialiased on the same half-pixel threshold as the
    // rect's own edge. The whole surface means "no clip" and is what
    // `Frame.fill` passes when no clip stack is active.
    MUIBounds contentMask;
```

**This is a comment-only edit — no field is added, moved or resized**, so `swift package clean` is not required by this task. Task 4 is the one that changes layout.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 453 tests in 0 suites passed` (450 + 3). **If any existing pixel test fails, stop** — it means some call site passes a mask that is not the whole surface, and that is a real bug rather than a test to adjust.

- [ ] **Step 6: Measure the mutation**

Apply, run the full suite, record reddened test **names**, revert:

```metal
// in mask_coverage, ignore the mask:
return 1.0;
```

Expected: `aRectIsPaintedOnlyInsideItsContentMask` and `theClipEdgeIsAntialiasedLikeTheRectsOwnEdge` redden.

Then a second mutation that separates AA from clipping — replace `mask_coverage`'s body with a hard step:

```metal
return (p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y) ? 1.0 : 0.0;
```

Expected: only `theClipEdgeIsAntialiasedLikeTheRectsOwnEdge` reddens. If it does not, that test is not measuring AA and must be fixed before proceeding.

- [ ] **Step 7: Commit**

```bash
git add Sources/MetalUIRender/Shaders/shaders.metal Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h Tests/MetalUIRenderTests/ClipTests.swift
git commit -m "feat: rect_fragment reads contentMask, antialiased

The field has round-tripped the ABI since M0 and been read by nothing.
Fragment mask rather than [[clip_distance]]: 7.3 rejected scissor rects
to avoid batch breaks and per-primitive mask data causes none either,
while clip_distance cannot clip to a rounded container at all."
```

---

### Task 4: `MUIGlyph` gains a `contentMask` — ABI change

**Files:**
- Modify: `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` (`MUIGlyph` struct, `abi_probe` output indices)
- Modify: `Sources/MetalUIRender/Shaders/shaders.metal` (`abi_probe`, `glyph_fragment`)
- Modify: `Sources/MetalUIRender/ShaderTypesBridge.swift` (the `MUIGlyph` convenience init)
- Modify: `Sources/MetalUI/Frame.swift` (`draw`, ~line 269)
- Modify: `Tests/MetalUIRenderTests/ShaderABITests.swift`
- Test: `Tests/MetalUIRenderTests/ClipTests.swift` (append)

**Interfaces:**
- Consumes: `mask_coverage` from Task 3.
- Produces: `MUIGlyph.contentMask`, and `Frame.draw` passing it. Task 5 supplies a real value.

**Context — read this before touching the header.** `MUIGlyph`'s doc says:

> There is deliberately NO `contentMask` here. `MUIRect` carries one that `rect_fragment` never reads, and a second inert field would be a second thing that looks implemented from the outside.

That reasoning expires **only because this task makes the field live in the same commit that adds it.** Do not add the field and defer the shader read to a later task.

**`swift package clean` is mandatory in this task.** The header reaches the C target through a symlink SwiftPM does not track, so Swift's view goes stale while Metal's refreshes. The symptom is glyphs vanishing, which looks exactly like a shader bug and is not one.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MetalUIRenderTests/ClipTests.swift`:

```swift
/// A glyph clipped to the left half of its box.
///
/// The expectation is built from the atlas bitmap and a literal boundary, not
/// from the sprite's own mask — shape 12 again, and the glyph path is where M2
/// actually got bitten by it.
@Test @MainActor func aGlyphIsPaintedOnlyInsideItsContentMask() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlasForClipping(["M"])
    let slot = slots[0]
    renderer.upload(atlas)

    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))
    let originX = 8, originY = 8
    try #require(slot.width >= 6, "need a glyph wide enough to clip through the middle")
    let cut = Float(originX + slot.width / 2)

    var scene = Scene()
    scene.insert(clippedSprite(slot, atX: Float(originX), y: Float(originY),
                               mask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                               size: MUISize(width: cut, height: Float(side)))))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)
    func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[((y * side) + x) * 4 + 3] }

    // Every device pixel of the glyph, checked against the atlas AND the cut.
    var inkLeft = 0
    var spilledRight = 0
    for row in 0..<slot.height {
        for column in 0..<slot.width {
            let coverage = atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
            guard coverage > 200 else { continue }
            let x = originX + column, y = originY + row
            if Float(x) + 0.5 < cut - 0.5 {
                if alphaAt(x, y) > 100 { inkLeft += 1 }
            } else if Float(x) + 0.5 > cut + 0.5 {
                if alphaAt(x, y) > 20 { spilledRight += 1 }
            }
        }
    }
    #expect(inkLeft > 0, "the glyph must still paint left of the cut")
    #expect(spilledRight == 0, "\(spilledRight) glyph pixels painted right of the clip")
}
```

Add these two helpers to the top of `ClipTests.swift` (they exist in `GlyphABITests.swift` but are `private` to that file — duplicated rather than shared, because making them internal would put atlas-packing helpers into the module's test surface for two callers):

```swift
import CoreText
import MetalUIText

private func packedAtlasForClipping(_ characters: [Character]) throws -> (GlyphAtlas, [AtlasSlot]) {
    let font = FontResolver.resolve(family: nil, size: 24)
    let atlas = GlyphAtlas(width: 128, height: 128)
    atlas.beginFrame()
    defer { atlas.endFrame() }
    var slots: [AtlasSlot] = []
    for character in characters {
        var utf16 = Array(String(character).utf16)
        var glyphIDs = [CGGlyph](repeating: 0, count: utf16.count)
        try #require(CTFontGetGlyphsForCharacters(font.ctFont, &utf16, &glyphIDs, utf16.count))
        let key = GlyphKey(font: font.key, glyph: glyphIDs[0], size: 24,
                           subpixelVariant: 0, scaleFactor: 1)
        slots.append(try #require(atlas.slot(for: key) {
            GlyphRaster.rasterize(glyph: glyphIDs[0], font: font,
                                  subpixelVariant: 0, scaleFactor: 1)
        }))
    }
    return (atlas, slots)
}

private func clippedSprite(_ slot: AtlasSlot, atX x: Float, y: Float,
                           mask: MUIBounds) -> MUIGlyph {
    MUIGlyph(bounds: MUIBounds(origin: MUIPoint(x: x, y: y),
                               size: MUISize(width: Float(slot.width),
                                             height: Float(slot.height))),
             atlasBounds: MUIBounds(origin: MUIPoint(x: Float(slot.x), y: Float(slot.y)),
                                    size: MUISize(width: Float(slot.width),
                                                  height: Float(slot.height))),
             contentMask: mask,
             color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
             order: 0, _reserved: 0)
}
```

- [ ] **Step 2: Run to verify it fails to compile**

Run: `swift test --no-parallel --filter aGlyphIsPaintedOnlyInsideItsContentMask 2>&1 | grep -E "error:" | head -3`
Expected: `extra argument 'contentMask' in call` — the field does not exist yet.

- [ ] **Step 3: Add the field to the header**

In `MetalUIShaderTypes.h`, replace the "There is deliberately NO `contentMask` here" paragraph and the struct with:

```c
typedef struct {
    MUIBounds bounds;        // destination, ScaledPixels
    MUIBounds atlasBounds;   // source, atlas texels
    // Axis-aligned clip, same space as `bounds`, read by `glyph_fragment`. This
    // struct deliberately had no such field while `MUIRect`'s was inert; it
    // gained one in the same commit that made both live.
    MUIBounds contentMask;
    MUIHsla   color;         // tint; the R8 atlas carries coverage only
    MUIUInt   order;
    MUIUInt   _reserved;
} MUIGlyph;
```

- [ ] **Step 4: Clean, because the header moved**

Run: `swift package clean`

Skipping this leaves Swift's view of the struct stale while Metal's refreshes. Glyphs then vanish or draw garbage, and it looks like a shader bug.

- [ ] **Step 5: Extend the ABI probe**

In `shaders.metal`'s `abi_probe`, `out[26]` is currently `g.order` and is the last index. Insert the mask round-trip before it and renumber:

```metal
    out[26] = (MUIUInt)g.contentMask.origin.x;
    out[27] = (MUIUInt)g.contentMask.size.width;
    out[28] = g.order;
```

In `Tests/MetalUIRenderTests/ShaderABITests.swift`, find where the probe's outputs are asserted and add the two new indices with the same idiom the file already uses for `r.contentMask.size.width` (index 7). The glyph's `sizeof` assertion at index 13 must be updated to the new stride — **read it back from the probe rather than hardcoding a number**, or the test asserts an accident.

- [ ] **Step 6: Apply the mask in `glyph_fragment`**

`glyph_fragment` currently ends:

```metal
    float alpha = tint.a * coverage;
    // Premultiplied output, to pair with a (one, oneMinusSourceAlpha) blend.
    return float4(tint.rgb * alpha, alpha);
```

Change to:

```metal
    // Same clip as `rect_fragment`, same helper, so a glyph and a rect under
    // one clip stack cut on exactly the same boundary. `in.position.xy` is the
    // fragment centre in render-target pixels, which is `contentMask`'s space.
    float clip = mask_coverage(in.position.xy, g.contentMask);
    float alpha = tint.a * coverage * clip;
    // Premultiplied output, to pair with a (one, oneMinusSourceAlpha) blend.
    return float4(tint.rgb * alpha, alpha);
```

`glyph_fragment` already re-reads `MUIGlyph g` from the buffer by `in.glyphID`; if the local is named differently, use the existing name.

- [ ] **Step 7: Update the two Swift call sites**

In `Sources/MetalUIRender/ShaderTypesBridge.swift` the `MUIGlyph` convenience init takes `bounds`, `slot`, `color`, `order`. Add a `contentMask: Bounds<ScaledPixels>` parameter and pass `MUIBounds(contentMask)` through, mirroring how the `MUIRect` init at lines 39-47 already does it.

In `Sources/MetalUI/Frame.swift`, `draw` builds the glyph at ~line 269. Pass the whole surface for now — Task 5 replaces this with the clip stack's value:

```swift
        let surface = Bounds(
            origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
            size: contentSize.scaled(by: scaleFactor))
        scene.insert(MUIGlyph(bounds: bounds, slot: packed.slot,
                              contentMask: surface, color: color, order: 0))
```

- [ ] **Step 8: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 454 tests in 0 suites passed`.

**If glyph tests fail with garbage pixels, you skipped Step 4.** Run `swift package clean` and re-run before debugging anything else.

- [ ] **Step 9: Measure the mutation**

Apply, run the full suite, record reddened test **names**, revert:

```metal
// in glyph_fragment, ignore the clip:
float alpha = tint.a * coverage;
```

Expected: `aGlyphIsPaintedOnlyInsideItsContentMask` reddens. Record whether any ABI test also reddens — it should not, since the field still round-trips.

- [ ] **Step 10: Commit**

```bash
git add -A Sources/MetalUIRender Sources/MetalUI/Frame.swift Tests/MetalUIRenderTests
git commit -m "feat: MUIGlyph carries a contentMask and glyph_fragment reads it

The struct deliberately had no such field while MUIRect's was inert. It
gains one in the same commit that makes it live, which is the rule the
declared-but-inert table exists to enforce. ABI change: swift package
clean is required after the header edit."
```

---

### Task 5: The clip/translate stack

**Files:**
- Modify: `Sources/MetalUI/Frame.swift` (stack storage, `fill`, `draw`)
- Modify: `Sources/MetalUI/Passes.swift` (`clipped` on `PrepaintPass` and `PaintPass`)
- Test: `Tests/MetalUITests/ClipStackTests.swift` (create)

**Interfaces:**
- Consumes: `contentMask` live in both shaders (Tasks 3-4).
- Produces:
  ```swift
  // on both PrepaintPass and PaintPass
  public func clipped(to bounds: Bounds<Pixels>,
                      offsetBy offset: Point<Pixels>,
                      _ body: () -> Void)
  // on Frame, internal
  var activeClip: Bounds<Pixels> { get }      // in logical points
  var activeOffset: Point<Pixels> { get }
  ```
  Task 6's `ScrollView` calls `clipped`; Task 7's registry reads `activeClip`.

**The rule this task establishes, and it must be in the doc comments:** translation and clipping are properties of the **emission**, not of the geometry. `bounds(of:)` keeps returning untranslated engine geometry; `fill` and `draw` apply the active translation and clip on the way into the `Scene`. This mirrors how `fill` already owns the scale factor — the pass exposes no `scaleFactor` because a caller who found one would double-apply it, and translation is the same hazard.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUITests/ClipStackTests.swift`:

```swift
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

/// A fill inside `clipped(to:offsetBy:)` is translated and masked on the way
/// into the scene, while `bounds(of:)` keeps returning engine geometry.
@Test @MainActor func aFillInsideAClipIsTranslatedAndMasked() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    var pass = PaintPass(frame: frame)
    pass.clipped(to: Bounds(origin: Point(x: Pixels(10), y: Pixels(10)),
                            size: Size(width: Pixels(50), height: Pixels(50))),
                 offsetBy: Point(x: Pixels(0), y: Pixels(-20))) {
        pass.fill(Bounds(origin: Point(x: Pixels(10), y: Pixels(30)),
                         size: Size(width: Pixels(50), height: Pixels(50))),
                  color: Hsla(h: 0, s: 0, l: 1, a: 1))
    }
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.bounds.origin.y == 10, "y 30 offset by -20 must reach the scene at 10")
    #expect(r.contentMask.origin.y == 10)
    #expect(r.contentMask.size.height == 50)
}

/// Nested clips INTERSECT. An inner clip larger than its outer must not widen
/// it — clamping the wrong way here is how a nested scroller paints over its
/// parent's chrome.
@Test @MainActor func nestedClipsIntersectRatherThanReplace() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    var pass = PaintPass(frame: frame)
    let outer = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                       size: Size(width: Pixels(60), height: Pixels(200)))
    let widerInner = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                            size: Size(width: Pixels(500), height: Pixels(200)))
    pass.clipped(to: outer, offsetBy: Point(x: Pixels(0), y: Pixels(0))) {
        pass.clipped(to: widerInner, offsetBy: Point(x: Pixels(0), y: Pixels(0))) {
            pass.fill(Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                             size: Size(width: Pixels(200), height: Pixels(10))),
                      color: Hsla(h: 0, s: 0, l: 1, a: 1))
        }
    }
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.contentMask.size.width == 60, "the inner clip must not widen the outer")
}

/// Translations compose by addition down the stack.
@Test @MainActor func nestedOffsetsCompose() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    var pass = PaintPass(frame: frame)
    let full = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                      size: Size(width: Pixels(200), height: Pixels(200)))
    pass.clipped(to: full, offsetBy: Point(x: Pixels(-5), y: Pixels(0))) {
        pass.clipped(to: full, offsetBy: Point(x: Pixels(-7), y: Pixels(0))) {
            pass.fill(Bounds(origin: Point(x: Pixels(100), y: Pixels(0)),
                             size: Size(width: Pixels(10), height: Pixels(10))),
                      color: Hsla(h: 0, s: 0, l: 1, a: 1))
        }
    }
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.bounds.origin.x == 88, "100 - 5 - 7")
}

/// The stack pops. A fill after the block is untranslated and unclipped.
@Test @MainActor func theStackPopsWhenTheBlockReturns() throws {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)),
                      scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(), glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    var pass = PaintPass(frame: frame)
    pass.clipped(to: Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                            size: Size(width: Pixels(10), height: Pixels(10))),
                 offsetBy: Point(x: Pixels(-50), y: Pixels(0))) { }
    pass.fill(Bounds(origin: Point(x: Pixels(100), y: Pixels(0)),
                     size: Size(width: Pixels(10), height: Pixels(10))),
              color: Hsla(h: 0, s: 0, l: 1, a: 1))
    let scene = frame.finalizedScene()
    let r = try #require(scene.rects.first)
    #expect(r.bounds.origin.x == 100, "the offset must not survive the block")
    #expect(r.contentMask.size.width == 200, "the clip must not survive the block")
}
```

If `Frame`'s initialiser signature differs, copy the exact one used by an existing test in `Tests/MetalUITests/` — do not guess. `grep -n "Frame(contentSize:" Tests/MetalUITests/*.swift` shows working call sites.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter ClipStackTests 2>&1 | grep -E "error:" | head -3`
Expected: `value of type 'PaintPass' has no member 'clipped'`.

- [ ] **Step 3: Add the stack to `Frame`**

In `Sources/MetalUI/Frame.swift`, add stored state near `scene`:

```swift
    /// Clip and translation, innermost last. Both are in **logical points**;
    /// `fill` and `draw` scale on the way to the scene as they already do.
    ///
    /// **This is emission state, not geometry.** `bounds(of:)` keeps returning
    /// what the engine computed, untranslated — a child that fills its own
    /// resolved bounds is translated automatically and needs to know nothing
    /// about scrolling. It is the same division `fill` already makes for the
    /// scale factor, and for the same reason: a caller who could see the value
    /// would apply it a second time.
    private var clipStack: [(clip: Bounds<Pixels>, offset: Point<Pixels>)] = []

    var activeClip: Bounds<Pixels> {
        clipStack.last?.clip ?? Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                       size: contentSize)
    }

    var activeOffset: Point<Pixels> {
        clipStack.last?.offset ?? Point(x: Pixels(0), y: Pixels(0))
    }

    /// Pushes an **intersected** clip and an **accumulated** offset.
    ///
    /// Intersection rather than replacement is what makes nesting correct: an
    /// inner clip wider than its outer must not widen it, or a nested scroller
    /// paints over its parent's chrome. Pinned by
    /// `nestedClipsIntersectRatherThanReplace`.
    func pushClip(_ bounds: Bounds<Pixels>, offset: Point<Pixels>) {
        let clip = Self.intersect(activeClip, bounds)
        let composed = Point(x: Pixels(activeOffset.x.value + offset.x.value),
                             y: Pixels(activeOffset.y.value + offset.y.value))
        clipStack.append((clip, composed))
    }

    func popClip() { clipStack.removeLast() }

    static func intersect(_ a: Bounds<Pixels>, _ b: Bounds<Pixels>) -> Bounds<Pixels> {
        let x0 = max(a.origin.x.value, b.origin.x.value)
        let y0 = max(a.origin.y.value, b.origin.y.value)
        let x1 = min(a.origin.x.value + a.size.width.value,
                     b.origin.x.value + b.size.width.value)
        let y1 = min(a.origin.y.value + a.size.height.value,
                     b.origin.y.value + b.size.height.value)
        return Bounds(origin: Point(x: Pixels(x0), y: Pixels(y0)),
                      size: Size(width: Pixels(max(0, x1 - x0)),
                                 height: Pixels(max(0, y1 - y0))))
    }
```

- [ ] **Step 4: Apply the stack in `fill` and `draw`**

In `fill`, replace the `surface` local and the `bounds:`/`contentMask:` arguments:

```swift
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        scene.insert(MUIRect(
            bounds: translated.scaled(by: scaleFactor),
            contentMask: activeClip.scaled(by: scaleFactor),
            background: color,
            borderColor: .transparent,
            cornerRadii: cornerRadii.scaled(by: scaleFactor),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0))
```

Delete `fill`'s now-false doc sentence "`contentMask` is the whole surface: nothing clips yet, and the fragment shader does not read the field in any case."

In `draw`, glyph geometry is already in device pixels, so the offset must be scaled before it is added and the clip scaled the same way:

```swift
        let dx = activeOffset.x.value * scaleFactor
        let dy = activeOffset.y.value * scaleFactor
        let placed = Bounds(
            origin: Point(x: ScaledPixels(bounds.origin.x.value + dx),
                          y: ScaledPixels(bounds.origin.y.value + dy)),
            size: bounds.size)
        scene.insert(MUIGlyph(bounds: placed, slot: packed.slot,
                              contentMask: activeClip.scaled(by: scaleFactor),
                              color: color, order: 0))
```

Use whatever local `draw` already computes for the glyph's device-pixel bounds in place of `bounds` above — read the method before editing.

- [ ] **Step 5: Expose `clipped` on both passes**

In `Sources/MetalUI/Passes.swift`, add to **both** `PaintPass` and `PrepaintPass`:

```swift
    /// Runs `body` with `bounds` intersected into the active clip and `offset`
    /// added to the active translation.
    ///
    /// **Closure form rather than push/pop, so an unbalanced stack is not
    /// expressible.** A `pushClip` without its `popClip` would silently clip
    /// every later sibling in the frame.
    ///
    /// **On `PrepaintPass` as well as `PaintPass`, and that is not symmetry for
    /// its own sake**: a scroll region's on-screen position depends on ancestor
    /// scrolls, so a nested `ScrollView` that its parent has scrolled out of
    /// view must not receive wheel events.
    public func clipped(to bounds: Bounds<Pixels>,
                        offsetBy offset: Point<Pixels>,
                        _ body: () -> Void) {
        frame.pushClip(bounds, offset: offset)
        defer { frame.popClip() }
        body()
    }
```

- [ ] **Step 6: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 458 tests in 0 suites passed`.

- [ ] **Step 7: Measure the mutations**

Three, applied one at a time, full suite each, reddened names recorded:

1. `pushClip` replaces instead of intersecting: `clipStack.append((bounds, composed))` → expect `nestedClipsIntersectRatherThanReplace`.
2. `pushClip` replaces the offset: `clipStack.append((clip, offset))` → expect `nestedOffsetsCompose`.
3. `clipped` omits the `defer { frame.popClip() }` → expect `theStackPopsWhenTheBlockReturns`.

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUI/Frame.swift Sources/MetalUI/Passes.swift Tests/MetalUITests/ClipStackTests.swift
git commit -m "feat: a clip and translate stack on Frame, exposed to prepaint and paint

Translation and clipping are properties of the EMISSION, not the
geometry: bounds(of:) keeps returning engine geometry and fill/draw
apply the stack. Same division fill already makes for the scale factor,
and for the same double-application reason."
```

---

### Task 6: `ScrollView` layout and offset

**Files:**
- Create: `Sources/MetalUI/ScrollView.swift`
- Test: `Tests/MetalUITests/ScrollViewTests.swift` (create)

**Interfaces:**
- Consumes: `PaintPass.clipped(to:offsetBy:)` (Task 5), `withState` (existing on all three passes).
- Produces:
  ```swift
  public enum ScrollAxis: Sendable, Equatable { case vertical, horizontal }
  public struct ScrollState: Sendable { public var offset: Double }
  public struct ScrollView<Content: ElementGroup>: Element { … }
  ```
  Task 7 registers the region; Task 9 paints the indicator.

**Context — the measured layout mechanism.** The spec's §5.2 table is the whole reason this shape is what it is. Probed against the real engine, five 40pt rows in a 200×100 viewport:

| content node | height | overflows |
|---|---|---|
| `min-height: auto` (default), `flexShrink: 0` | 200 | yes |
| `min-height: auto` (default), `flexShrink` default | 200 | yes |
| `min-height: 0`, `flexShrink: 0` | 200 | yes |
| `min-height: 0`, `flexShrink` default | **100** | **no** |

The overflow comes from **CSS Sizing §4.5's automatic minimum**, not from `flexShrink: 0`. Both are specified; `flexShrink: 0` is the one that survives an explicit `min-height: 0` up the chain. No engine change is needed.

Read `Sources/MetalUI/Box.swift` for the container idiom — `requestLayout` builds children bottom-up with a cursor starting at 0, `prepaint` recurses, `paint` emits its own background before recursing.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUITests/ScrollViewTests.swift`:

```swift
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

private func rowsColumn(count: Int, rowHeight: Double) -> Column<some ElementGroup> {
    Column {
        AnyElement(Box(style: {
            var s = Style()
            s.size = Size(width: .auto, height: .length(.pixels(Pixels(Float(rowHeight)))))
            return s
        }()))
    }
}

/// The content node overflows the viewport, which is what there is to scroll.
///
/// **The mechanism is §4.5's automatic minimum, not `flexShrink`** — measured,
/// and the differential is `aContentNodeWithAnExplicitZeroMinimumStillOverflows`
/// below. Getting this backwards produces a ScrollView whose content silently
/// equals its viewport and which therefore never scrolls.
@Test @MainActor func theContentNodeOverflowsTheViewport() throws {
    var view = ScrollView(.vertical) {
        Column {
            Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
            Box(style: fixedHeight(40)); Box(style: fixedHeight(40))
            Box(style: fixedHeight(40))
        }
    }
    let probe = try renderProbe(&view, viewport: Size(width: Pixels(200), height: Pixels(100)))
    #expect(probe.viewportHeight == 100)
    #expect(probe.contentHeight == 200, "five 40pt rows must measure 200, not the viewport's 100")
}

/// The offset clamps to `0 ... content - viewport` and never goes negative.
@Test @MainActor func theOffsetClampsToTheScrollableRange() {
    #expect(ScrollView<EmptyGroup>.clamp(offset: -30, content: 200, viewport: 100) == 0)
    #expect(ScrollView<EmptyGroup>.clamp(offset: 500, content: 200, viewport: 100) == 100)
    #expect(ScrollView<EmptyGroup>.clamp(offset: 40, content: 200, viewport: 100) == 40)
}

/// Content shorter than the viewport is not scrollable at all — a negative
/// range must clamp to zero rather than to a negative maximum.
@Test @MainActor func contentShorterThanTheViewportDoesNotScroll() {
    #expect(ScrollView<EmptyGroup>.clamp(offset: 25, content: 60, viewport: 100) == 0)
}

/// Clamping happens on READ, not on write. The wheel handler has no layout to
/// validate against, and the layout that would is a frame away.
@Test @MainActor func aStoredOffsetPastTheEndIsClampedWhenItIsRead() {
    #expect(ScrollView<EmptyGroup>.clamp(offset: 9_999, content: 200, viewport: 100) == 100)
}
```

Add these helpers at the top of the file:

```swift
private func fixedHeight(_ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: .auto, height: .length(.pixels(Pixels(h))))
    return s
}

private struct ScrollProbe { var viewportHeight: Double; var contentHeight: Double }

@MainActor
private func renderProbe<E: Element>(_ element: inout E,
                                     viewport: Size<Pixels>) throws -> ScrollProbe {
    let frame = Frame(contentSize: viewport, scaleFactor: 1, stateTable: StateTable(),
                      shapingCache: ShapingCache(),
                      glyphAtlas: GlyphAtlas(width: 64, height: 64),
                      theme: Theme.forAppearance(.light))
    frame.render(&element)
    let ids = try #require(frame.lastScrollProbe)
    return ScrollProbe(viewportHeight: ids.viewport, contentHeight: ids.content)
}
```

`Frame.lastScrollProbe` does not exist and must not be added — replace this helper with whatever `Tests/MetalUITests/` already uses to read node bounds after a render (`grep -n "func render" Sources/MetalUI/Frame.swift` and the existing element tests show the idiom). **If no such affordance exists, assert on the painted rects instead** — the content node's height is observable as the extent of the emitted children — and say so in the test's doc comment.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter ScrollViewTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'ScrollView' in scope`.

- [ ] **Step 3: Implement `ScrollView`**

Create `Sources/MetalUI/ScrollView.swift`:

```swift
import MetalUICore
import MetalUILayout

public enum ScrollAxis: Sendable, Equatable { case vertical, horizontal }

/// Cross-frame scroll position, in logical points along the scroll axis.
public struct ScrollState: Sendable {
    public var offset: Double = 0
    public init(offset: Double = 0) { self.offset = offset }
}

/// A clipped, scrollable viewport over content taller (or wider) than itself.
///
/// **SwiftUI's shape, not CSS's** (ruling EP-5): `ScrollView { … }` rather than
/// `Box.overflow(.scroll)`. `Style.overflow` stays the substrate this element
/// writes into, the way `Column.init` writes `alignItems` without `Style`'s
/// default moving (ruling EP-8).
///
/// **Two layout nodes, and the reason is measured rather than assumed.** A
/// viewport node takes the offered size; a content node inside it overflows.
/// What makes it overflow is CSS Sizing §4.5's automatic minimum — `min-height:
/// auto` floors the content node at its content size, divergence FS-3's
/// mechanism — and NOT `flexShrink: 0`, which the first draft of the design
/// claimed. Measured 2026-08-28: with `min-height: auto` the content is 200pt
/// tall whatever `flexShrink` says; with an explicit `min-height: 0` AND the
/// default `flexShrink`, it collapses to the viewport's 100 and scrolling dies.
/// `flexShrink = 0` is set below as the belt to that braces — it is the only
/// one of the two that survives an explicit zero minimum up the chain.
///
/// **Scroll position is `StateTable` state, so it inherits §4.3's adoption
/// rule**: a `ScrollView` inside a vanishing `if` hands its offset to the
/// trailing sibling, and a list silently inheriting another list's scroll
/// position is a confusing thing to meet cold. The remedy is the
/// counter-intuitive one — name the **trailing sibling**, not the conditional
/// content.
public struct ScrollView<Content: ElementGroup>: Element {
    public var axis: ScrollAxis
    public var elementID: ElementID?
    public var content: Content

    public init(_ axis: ScrollAxis = .vertical, elementID: ElementID? = nil,
                @ElementBuilder content: () -> Content) {
        self.axis = axis
        self.elementID = elementID
        self.content = content()
    }

    public struct Layout {
        public var node: LayoutNodeID       // viewport
        public var contentNode: LayoutNodeID
        var inner: Content.GroupLayout
    }

    /// `0 ... max(0, content - viewport)`.
    ///
    /// **Clamped on read, not on write.** The wheel handler that writes the
    /// offset has no access to the current layout, and the layout that would
    /// validate it does not exist until the next frame — so a stored value may
    /// legitimately be out of range when content shrinks between frames.
    static func clamp(offset: Double, content: Double, viewport: Double) -> Double {
        min(max(0, offset), max(0, content - viewport))
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, inner) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)

        var contentStyle = Style()
        contentStyle.flexDirection = axis == .vertical ? .column : .row
        // See the type's doc: the automatic minimum is what overflows; this is
        // the belt to it, surviving an explicit `min-height: 0` up the chain.
        contentStyle.flexShrink = 0
        let contentNode = pass.requestNode(style: contentStyle, children: children)

        var viewportStyle = Style()
        viewportStyle.flexDirection = axis == .vertical ? .column : .row
        // Written for the model's sake. The engine reads `overflow` nowhere
        // today — measured: removing this line moved no number in the layout
        // probe — so it documents intent rather than driving behaviour. See
        // CLAUDE.md's declared-but-inert table.
        viewportStyle.overflow = Axes(both: .scroll)
        let node = pass.requestNode(style: viewportStyle, children: [contentNode])

        return (node, Layout(node: node, contentNode: contentNode, inner: inner))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let offset = resolvedOffset(id, bounds: bounds, layout: layout, pass: pass)
        var result: Content.GroupPrepaint!
        pass.clipped(to: bounds, offsetBy: delta(-offset)) {
            result = content.prepaintGroup(layout: &layout.inner, pass: &pass)
        }
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        let offset = resolvedOffset(id, bounds: bounds, layout: layout, pass: pass)
        pass.clipped(to: bounds, offsetBy: delta(-offset)) {
            content.paintGroup(layout: &layout.inner, prepaint: &prepaint, pass: &pass)
        }
    }

    private func delta(_ v: Double) -> Point<Pixels> {
        axis == .vertical ? Point(x: Pixels(0), y: Pixels(Float(v)))
                          : Point(x: Pixels(Float(v)), y: Pixels(0))
    }

    func extent(_ size: Size<Pixels>) -> Double {
        Double(axis == .vertical ? size.height.value : size.width.value)
    }
}
```

Add `resolvedOffset` as a private helper on both pass types, or duplicate the three-line body in `prepaint` and `paint` — `PrepaintPass` and `PaintPass` are distinct types with no shared protocol, and `Passes.swift` records why a `StatefulPass` protocol is not an option (it would force `frame` public and leak `scaleFactor`). Duplicate rather than introduce one.

```swift
    // in prepaint, and again in paint with `pass: inout PaintPass`
    private func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                layout: Layout, pass: PrepaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: layout.contentNode).size)
        var stored: Double = 0
        pass.withState(id, initial: ScrollState()) { stored = $0.offset }
        return Self.clamp(offset: stored, content: content, viewport: viewport)
    }
```

- [ ] **Step 4: Run the tests**

Run: `swift test --no-parallel --filter ScrollViewTests 2>&1 | grep -E "recorded an issue|Test run with"`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 462 tests in 0 suites passed`.

- [ ] **Step 6: Add the differential the mechanism claim depends on**

The claim "the automatic minimum overflows, not `flexShrink`" is only checked if a test distinguishes them. Add:

```swift
/// **The differential that names the mechanism.** With an explicit
/// `min-height: 0` the automatic minimum is gone, and then `flexShrink: 0` is
/// the only thing keeping the content from collapsing to the viewport. Measured
/// against the engine 2026-08-28: without both, content = 100 and there is
/// nothing to scroll. This is what stops the doc comment above reverting to the
/// wrong mechanism.
@Test @MainActor func aContentNodeWithAnExplicitZeroMinimumStillOverflows() throws {
    let tree = LayoutTree(generation: 0)
    var row = Style()
    row.size = Size(width: .auto, height: .length(.pixels(Pixels(40))))
    let rows = (0..<5).map { _ in tree.newNode(style: row, children: []) }

    var content = Style()
    content.flexDirection = .column
    content.flexShrink = 0
    content.minSize = Size(width: .auto, height: .length(.pixels(Pixels(0))))
    let contentNode = tree.newNode(style: content, children: rows)

    var viewport = Style()
    viewport.flexDirection = .column
    viewport.size = Size(width: .length(.pixels(Pixels(200))),
                         height: .length(.pixels(Pixels(100))))
    let viewportNode = tree.newNode(style: viewport, children: [contentNode])

    computeLayout(tree, root: viewportNode,
                  available: AvailableSpaceSize(width: .definite(200), height: .definite(100)))
    #expect(tree.layout(contentNode).height == 200,
            "flexShrink: 0 must hold the content open once the automatic minimum is gone")
}
```

This test needs `@testable import MetalUILayout`; put it in `Tests/MetalUILayoutTests/ScrollLayoutTests.swift` instead if the import conflicts.

- [ ] **Step 7: Measure the mutation**

Remove `contentStyle.flexShrink = 0` from `ScrollView.requestLayout`, run the full suite, record reddened names, revert.

Expected: `aContentNodeWithAnExplicitZeroMinimumStillOverflows` reddens **and `theContentNodeOverflowsTheViewport` does not** — which is the measurement that proves the two mechanisms are distinct rather than the same one twice. If both stay green, `flexShrink: 0` is dead code and the doc comment must say so instead of claiming a role.

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUI/ScrollView.swift Tests/MetalUITests/ScrollViewTests.swift Tests/MetalUILayoutTests/ScrollLayoutTests.swift
git commit -m "feat: ScrollView, two layout nodes and a clamped offset in the state table

SwiftUI's shape per EP-5, not Box.overflow(.scroll). What makes the
content overflow is 4.5's automatic minimum, measured -- NOT flexShrink,
which the design's first draft claimed. Both are set and the
differential test is what keeps the doc comment honest."
```

---

### Task 7: Scroll-region registry and wheel routing

**Files:**
- Modify: `Sources/MetalUI/Frame.swift` (region store)
- Modify: `Sources/MetalUI/Passes.swift` (`registerScrollRegion` on `PrepaintPass`)
- Modify: `Sources/MetalUI/ScrollView.swift` (register in `prepaint`)
- Modify: `Sources/MetalUI/Window.swift` (`onInput` handling)
- Test: `Tests/MetalUITests/ScrollRoutingTests.swift` (create)

**Interfaces:**
- Consumes: `Frame.activeClip` (Task 5), `ScrollState` (Task 6).
- Produces: `PrepaintPass.registerScrollRegion(_:id:)`, `Frame.scrollRegions: [(bounds, id)]`, and `Window` mutating `ScrollState` on a wheel event.

**Context.** `PrepaintPass`'s own doc says a registry is "a store on `Frame` plus one method on `PrepaintPass`; input and focus bring theirs (M3)." This is that. It is a hitbox list scoped to scroll — §8.1's eventual signature is `insertHitbox(bounds, contentMask, opaque:)`, taking exactly the clip stack's product — and the next sub-project generalizes it. Say so in the doc comment; do not present it as the general hit-test system.

`ScrollEvent` already carries `position`, `delta`, `modifiers`, `isMomentum`, and `AppKitPlatform.scrollWheel` already populates all four from `NSEvent`.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUITests/ScrollRoutingTests.swift` with these four cases, using the existing fake platform in `Tests/MetalUITests/Fakes.swift` (read it first — `grep -n "class Fake" Tests/MetalUITests/Fakes.swift`):

```swift
import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

/// A wheel event inside a region moves that region's offset.
@Test @MainActor func aWheelEventInsideARegionScrollsIt() throws { /* … */ }

/// A wheel event outside every region moves nothing.
@Test @MainActor func aWheelEventOutsideEveryRegionScrollsNothing() throws { /* … */ }

/// **Reverse order: the topmost (last-registered) region wins.** Same rule
/// §8.1 states for hitboxes, arriving early because scroll needs it. Two
/// overlapping regions at the same point must not both scroll.
@Test @MainActor func theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove() throws { /* … */ }

/// Momentum deltas are applied identically to direct ones — the OS does the
/// physics and we accumulate. Building our own inertia now means building it
/// twice, once more for iOS and programmatic scrolling.
@Test @MainActor func momentumDeltasScrollLikeDirectOnes() throws { /* … */ }
```

**Write the bodies out in full when implementing** — the shape depends on `Fakes.swift`, which the implementer reads. Each must: build a `Window` over a `ScrollView` with known geometry, drive `platformWindow.onInput?(.scrollWheel(ScrollEvent(position:delta:modifiers:isMomentum:)))`, render, and assert on the resulting `ScrollState.offset` via the window's `stateTable`.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter ScrollRoutingTests 2>&1 | grep -E "error:" | head -3`
Expected: `value of type 'PrepaintPass' has no member 'registerScrollRegion'`.

- [ ] **Step 3: Add the store and the registration method**

In `Frame.swift`:

```swift
    /// Scroll regions registered this frame, in prepaint order.
    ///
    /// **A hitbox list scoped to scroll, and named as such rather than
    /// generalised.** §8.1's signature is `insertHitbox(bounds, contentMask,
    /// opaque:)` and takes exactly this stack's product; the hit-test
    /// sub-project widens this rather than replacing it.
    private(set) var scrollRegions: [(bounds: Bounds<Pixels>, id: GlobalElementID)] = []

    func registerScrollRegion(_ bounds: Bounds<Pixels>, id: GlobalElementID) {
        // The CLIPPED bounds, not the raw ones: a nested scroller its parent has
        // scrolled out of view must not receive wheel events.
        scrollRegions.append((Self.intersect(activeClip, bounds), id))
    }
```

In `Passes.swift`, on `PrepaintPass` only:

```swift
    /// Records a region that consumes scroll wheel events.
    ///
    /// Registration happens here rather than in `paint` because §8.1 requires
    /// it after positions resolve and before the first primitive is emitted.
    public func registerScrollRegion(_ bounds: Bounds<Pixels>, id: GlobalElementID) {
        frame.registerScrollRegion(bounds, id: id)
    }
```

In `ScrollView.prepaint`, register **outside** its own `clipped` block — the region is the viewport in its parent's space, not in its own scrolled space:

```swift
        pass.registerScrollRegion(bounds, id: id)
        pass.clipped(to: bounds, offsetBy: delta(-offset)) { … }
```

- [ ] **Step 4: Route the event in `Window`**

In `Window.swift`'s `platformWindow.onInput` closure, before `self.onInput?(event)`:

```swift
            if case .scrollWheel(let scroll) = event, self.applyScroll(scroll) {
                self.setNeedsRedraw()
                return true
            }
```

And add:

```swift
    /// Applies a wheel delta to the topmost scroll region under the pointer.
    ///
    /// **Reverse order**, the same rule §8.1 states: "dispatch walks them in
    /// reverse so the topmost opaque hit wins."
    ///
    /// Momentum deltas are applied identically to direct ones — `isMomentum` is
    /// read by nothing here on purpose. AppKit already ran the physics; a second
    /// simulation on top would fight it.
    ///
    /// **Not handled: scroll chaining.** An inner region already at its limit
    /// does not pass the remainder to an ancestor. That is a dispatch concern
    /// and belongs with the general hit-test work; its absence is a decision,
    /// not an oversight.
    private func applyScroll(_ event: ScrollEvent) -> Bool {
        guard let region = lastScrollRegions.last(where: { contains($0.bounds, event.position) })
        else { return false }
        stateTable.withState(region.id, initial: ScrollState()) {
            // Natural scrolling: a positive scrollingDeltaY means content moves
            // down, so the offset decreases.
            $0.offset -= Double(event.delta.y.value)
        }
        return true
    }
```

`lastScrollRegions` must be captured from the frame after each render, beside `lastScene`. Add `private(set) var lastScrollRegions: [(bounds: Bounds<Pixels>, id: GlobalElementID)] = []` and assign it in `drawFrameIfNeeded` where `lastScene = scene` already happens. Add a small `contains(_:_:)` helper on `Window`.

**A wheel event arriving before the first frame finds an empty list and scrolls nothing.** That is correct — there is no layout to route against — and the doc comment must say so rather than leaving it to be discovered.

- [ ] **Step 5: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 466 tests in 0 suites passed`.

- [ ] **Step 6: Measure the mutations**

1. `lastScrollRegions.first(where:)` instead of `.last(where:)` → expect `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove`.
2. `applyScroll` returns `false` unconditionally → expect all four routing tests.
3. `registerScrollRegion` stores the raw bounds rather than the intersected ones → record what reddens. **If nothing reddens, that is a coverage gap and a test for a nested scrolled-out region must be added** — prove the mutant behaves differently before banking it.

- [ ] **Step 7: Commit**

```bash
git add Sources/MetalUI Tests/MetalUITests/ScrollRoutingTests.swift
git commit -m "feat: scroll-region registry in prepaint, wheel routing in Window

A hitbox list scoped to scroll, named as such: 8.1's signature takes
exactly this stack's product and the hit-test sub-project widens this
rather than replacing it. Reverse walk, clipped bounds, momentum passed
through. Scroll chaining is deliberately absent and recorded."
```

---

### Task 8: `Frame.timestamp` and request-another-frame

**Files:**
- Modify: `Sources/MetalUIPlatform/Platform.swift` (`startDisplayLink` signature)
- Modify: `Sources/MetalUIPlatform/AppKit/AppKitPlatform.swift` (`displayLinkFired`)
- Modify: `Sources/MetalUI/Frame.swift` (`timestamp`, `requestAnotherFrame`)
- Modify: `Sources/MetalUI/Passes.swift` (`PaintPass.timestamp`, `PaintPass.requestAnotherFrame()`)
- Modify: `Sources/MetalUI/Window.swift` (pass the timestamp; honour the request)
- Modify: `Tests/MetalUITests/Fakes.swift` (fake platform's `startDisplayLink`)
- Test: `Tests/MetalUITests/FrameClockTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `PaintPass.timestamp: Double`, `PaintPass.requestAnotherFrame()`. Task 9's indicator uses both.

**Context — these are borrowed M4 primitives and the spec says so.** M4 owns "@Observable integration, dirty tracking, display-link scheduling, animation & easing." These two are the *inputs* to animation, not an animation system: one `Double` and one `Bool`. No easing curves, no animator, no interpolation. **M4's plan must not re-scope them** — the spec's §8 records the borrow.

Dirty tracking and link pausing already work: `setNeedsRedraw` unpauses, `drawFrameIfNeeded` pauses when clean. What is missing is only the element-facing way to ask for another frame.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUITests/FrameClockTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUI

/// An element that asks for another frame keeps the window dirty, so the
/// display link is not paused and a fade can run to completion.
///
/// Without this, a time-based animation stops the instant the last input event
/// stops arriving — the window goes clean, `drawFrameIfNeeded` pauses the link,
/// and the indicator freezes half-faded on screen.
@Test @MainActor func anElementThatRequestsAnotherFrameKeepsTheWindowDirty() throws {
    // Build a window over an element whose `paint` calls
    // `pass.requestAnotherFrame()`; render once; assert `window.needsRedraw`.
}

/// An element that does NOT ask leaves the window clean — the differential,
/// without which the test above passes on a window that is always dirty.
@Test @MainActor func anElementThatAsksForNothingLeavesTheWindowClean() throws {
    // Same, with an element that does not call it; assert `!window.needsRedraw`.
}

/// The frame's timestamp is the display link's, not a wall clock read at an
/// arbitrary point — two elements in one frame must see the same instant.
@Test @MainActor func everyElementInOneFrameSeesTheSameTimestamp() throws {
    // Two elements record `pass.timestamp`; assert they are equal and non-zero.
}
```

**Write these bodies in full when implementing**, using the fake platform in `Fakes.swift`, which must gain the new `startDisplayLink` signature.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter FrameClockTests 2>&1 | grep -E "error:" | head -3`
Expected: `value of type 'PaintPass' has no member 'requestAnotherFrame'`.

- [ ] **Step 3: Plumb the timestamp through the platform**

In `Sources/MetalUIPlatform/Platform.swift`:

```swift
    /// Begin delivering frame ticks. The callback runs on the main actor and
    /// receives the display link's timestamp in seconds.
    ///
    /// **The timestamp is the link's, not a wall-clock read.** Every element in
    /// one frame must see the same instant, and `CACurrentMediaTime()` sampled
    /// per element would not give them one.
    func startDisplayLink(_ tick: @escaping (Double) -> Void)
```

In `AppKitPlatform`:

```swift
    private var tick: ((Double) -> Void)?

    @objc private func displayLinkFired() {
        tick?(displayLink?.timestamp ?? 0)
    }
```

- [ ] **Step 4: Carry it to `Frame` and honour the request**

`Frame` gains `let timestamp: Double` (new init parameter, defaulted to `0` so existing test call sites keep compiling) and:

```swift
    /// Set by an element that needs another frame — an in-progress animation.
    ///
    /// **A borrowed M4 primitive** (spec §8 of the clipping/scroll design): the
    /// input to animation, not an animation system. `Window` reads it after
    /// render and marks itself dirty, which unpauses the display link.
    private(set) var wantsAnotherFrame = false

    func requestAnotherFrame() { wantsAnotherFrame = true }
```

`PaintPass` exposes both:

```swift
    /// This frame's display-link timestamp, in seconds. Identical for every
    /// element in one frame.
    public var timestamp: Double { frame.timestamp }

    /// Ask for another frame after this one — for an animation in progress.
    public func requestAnotherFrame() { frame.requestAnotherFrame() }
```

In `Window.drawFrameIfNeeded`, after `let scene = frame.finalizedScene()`:

```swift
        if frame.wantsAnotherFrame { setNeedsRedraw() }
```

And `Window` stores the latest tick timestamp, passing it into each `Frame`. Update the `startDisplayLink` call site to `{ [weak self] t in self?.lastTick = t; self?.drawFrameIfNeeded() }`.

- [ ] **Step 5: Update the fake platform**

`Tests/MetalUITests/Fakes.swift`'s fake `PlatformWindow` must match the new signature. Give it a way for a test to drive a tick with a chosen timestamp.

- [ ] **Step 6: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 469 tests in 0 suites passed`.

- [ ] **Step 7: Measure the mutation**

`Window` ignores `frame.wantsAnotherFrame` → expect `anElementThatRequestsAnotherFrameKeepsTheWindowDirty`.

- [ ] **Step 8: Commit**

```bash
git add -A Sources/MetalUIPlatform Sources/MetalUI Tests/MetalUITests
git commit -m "feat: a frame timestamp and a request-another-frame hook

Two M4 primitives borrowed deliberately and recorded in the spec so M4's
plan does not re-scope them. These are the INPUTS to animation, not an
animation system: one Double and one Bool, no easing, no animator."
```

---

### Task 9: The overlay indicator

**Files:**
- Modify: `Sources/MetalUI/ScrollView.swift`
- Test: `Tests/MetalUITests/ScrollIndicatorTests.swift` (create)

**Interfaces:**
- Consumes: `PaintPass.timestamp`, `PaintPass.requestAnotherFrame()` (Task 8), the draw list (Task 1).
- Produces: nothing later tasks depend on.

**Geometry.** Thumb extent = `viewport * (viewport / content)`, floored at 20pt. Thumb position = `(offset / (content - viewport)) * (viewport - thumbExtent)`. Inset 2pt from the trailing edge, 3pt wide, 3pt corner radius.

**Fade.** Fully opaque while a scroll happened within 0.6s; then linear to zero over 0.4s. `ScrollState` gains `lastScrollTime: Double`. While `timestamp - lastScrollTime < 1.0`, call `requestAnotherFrame()`.

**Ordering.** Painted **outside** the `clipped` block, after the content, so it does not scroll with the content and draws on top. This is the composition Task 1 exists for: the indicator is a rect over glyphs.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUITests/ScrollIndicatorTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUI

/// The indicator is emitted after the content, so the draw list puts it last.
///
/// **This is the composition the draw list was built for.** Before it, a rect
/// emitted after glyphs still drew beneath them, so an overlay indicator over a
/// list of text was not expressible at all.
@Test @MainActor func theIndicatorIsTheLastPrimitiveInTheScene() throws { }

/// No indicator when there is nothing to scroll.
@Test @MainActor func contentThatFitsDrawsNoIndicator() throws { }

/// The thumb is proportional to the viewport/content ratio and floored so it
/// never becomes an invisible sliver on a very long list.
@Test @MainActor func theThumbIsProportionalAndFlooredAtTwentyPoints() throws { }

/// The thumb reaches the bottom of its track exactly at the maximum offset —
/// an off-by-one here leaves a gap that looks like the list has more content.
@Test @MainActor func theThumbReachesTheEndOfItsTrackAtMaximumOffset() throws { }

/// While fading, the ScrollView asks for another frame; once faded, it stops.
///
/// The second half is what keeps an idle window idle — spec §4.4's "no frames
/// built and display link paused while idle" is an M4 exit criterion and this
/// must not break it early.
@Test @MainActor func theIndicatorRequestsFramesWhileFadingAndStopsWhenDone() throws { }
```

**Write all five bodies in full when implementing.**

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter ScrollIndicatorTests 2>&1 | grep -E "recorded an issue|error:" | head -3`

- [ ] **Step 3: Implement**

Add `lastScrollTime` to `ScrollState`; set it in `Window.applyScroll` from the window's `lastTick`. In `ScrollView.paint`, after the `clipped` block:

```swift
        let content = extent(pass.bounds(of: layout.contentNode).size)
        let viewport = extent(bounds.size)
        let scrollable = max(0, content - viewport)
        guard scrollable > 0 else { return }

        var lastScroll: Double = 0
        pass.withState(id, initial: ScrollState()) { lastScroll = $0.lastScrollTime }
        let age = pass.timestamp - lastScroll
        let alpha = age < 0.6 ? 1.0 : max(0, 1.0 - (age - 0.6) / 0.4)
        guard alpha > 0 else { return }
        if age < 1.0 { pass.requestAnotherFrame() }

        let thumb = max(20, viewport * (viewport / content))
        let travel = (offset / scrollable) * (viewport - thumb)
        // … fill a 3pt-wide rounded rect inset 2pt from the trailing edge …
```

Use `pass.theme` for the colour; if no suitable token exists, add one to `Theme` in this task and say so in the commit.

- [ ] **Step 4: Run the whole suite**

Run: `swift test --no-parallel 2>&1 | grep -E "error:|warning:|Test run with"`
Expected: `Test run with 474 tests in 0 suites passed`.

- [ ] **Step 5: Measure the mutations**

1. Indicator painted *inside* the `clipped` block → expect `theIndicatorIsTheLastPrimitiveInTheScene` (it will also scroll away).
2. `max(20, …)` → `viewport * (viewport / content)` → expect the floor test.
3. `if age < 1.0 { … }` removed → expect the fading test's second half.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI Tests/MetalUITests/ScrollIndicatorTests.swift
git commit -m "feat: a fading overlay scroll indicator

Painted outside the clip block and after the content, which is exactly
the rect-over-glyphs composition the draw list was built for. Stops
requesting frames once faded, so an idle window stays idle."
```

---

### Task 10: Demo, documentation, human verification

**Files:**
- Modify: `Sources/MetalUIDemo/main.swift`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-08-24-metalui-design.md` (§7.3)
- Create: `docs/superpowers/2026-08-28-clipping-scroll-decisions.md`

**Interfaces:**
- Consumes: everything.
- Produces: the record.

- [ ] **Step 1: Put a `ScrollView` in the demo**

Add a scrollable list of ~40 text rows in the main pane, inside a rounded, background-filled `Box`. It must exercise all four: clipping (rows cut at the container edge), scrolling with momentum, the indicator over text, and rounded-corner clipping.

- [ ] **Step 2: Run it and check the build**

Run: `swift package clean && swift build 2>&1 | grep -cE "error:|warning:"` → expect `0`.
Run: `swift run MetalUIDemo` and confirm it launches.

- [ ] **Step 3: Update `CLAUDE.md`'s declared-but-inert table**

Three rows change and the count line must be re-derived, not edited by eye:

- **`MUIRect.contentMask`** — delete the row. It is live.
- **`MUIRect.borderColor`/`borderWidths`** — unchanged; still blocked on the resolved width.
- **`position`, `inset`, `overflow`** — `overflow` is **still read by no production code**. Section 5.2's measurement showed removing it from the `ScrollView`'s viewport style moved no number. Keep it in the table and say that `ScrollView` writes it for the model's sake while the engine reads it nowhere — silence would read as "implemented".

Re-run the count: `grep -cE "^    public var " Sources/MetalUILayout/Style.swift` and state the number the file actually returns.

- [ ] **Step 4: Amend spec §7.3**

§7.3 says clipping is "per-primitive via `[[clip_distance]]`, not scissor rects." Amend to record what was built and why, keeping the batching argument that was §7.3's actual reason: a per-primitive mask in the instance buffer causes no state change either, `clip_distance` cannot clip to a rounded container, and `rect_fragment`'s SDF was already there. Also record that draw-call count is now assertable via `Scene.drawList.count`, and that N interleaved text rows cost 2N runs.

- [ ] **Step 5: Write the decisions doc**

Create `docs/superpowers/2026-08-28-clipping-scroll-decisions.md` with rulings prefixed **`CL-`** (namespaced per CLAUDE.md's convention; `CL-A`, `CL-B`, … lettered like `CS-`/`SI-`/`TX-`). At minimum: the fragment-mask-over-`clip_distance` choice, the automatic-minimum-not-`flexShrink` correction, the M4 borrow, and the absence of scroll chaining. Each ruling gets its reasoning and what it costs if wrong.

- [ ] **Step 6: Update CLAUDE.md's build line and target count**

Re-measure rather than trusting this plan's arithmetic:

```bash
swift package clean && swift test --no-parallel 2>&1 | grep "Test run with"
ls Tests/MetalUILayoutTests/Golden/*.json | wc -l
```

State the measured test count and confirm goldens are still 67.

- [ ] **Step 7: Human verification**

Ask the user to run `swift run MetalUIDemo` and report specifically on: whether rows are cut cleanly at the container's rounded edge, whether scrolling feels native with trackpad momentum, whether the indicator appears over the text and fades, and whether anything flickers.

**Record what the look could NOT establish**, as the M2 entry does — clip-edge antialiasing quality, fade timing, and whether scrolling feels native are all looks, and §9 of the spec names them.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "docs: record the clipping and scroll milestone

Demo has a scrollable list; CLAUDE.md's inert table loses contentMask
and keeps overflow with the measurement that says why; 7.3 amended to
the mechanism actually built; CL- decisions doc."
```

---

## Self-Review

**Spec coverage.** §2 → Task 1. §3.1 → Task 3. §3.2 → Task 4. §4 → Task 5. §5 → Task 6. §6 → Tasks 6 and 9. §7 → Task 7. §8 → Task 8. §9 → Task 10 Step 7. §10 → the mutation and test steps throughout. §11 → Task 10.

**Two gaps found and closed:** §11 criterion 3 (deleting `Scene.finalize`'s stale sentence) had no task and is now Task 2 Steps 4-5; §11 criterion 6 (`Style.overflow`'s table row) had no task and is now Task 10 Step 3.

**Placeholder scan.** Tasks 7, 8 and 9 name their test cases with full doc comments but leave three bodies to the implementer, because each depends on `Fakes.swift`, which the implementer must read and which this plan should not transcribe. Every such case says so explicitly and states what it must assert. Task 6 Step 1 flags that `Frame.lastScrollProbe` does not exist and gives the fallback.

**Type consistency.** `DrawRun`/`PrimitiveKind` (Task 1) are used unchanged in Tasks 2 and 9. `ScrollState` gains `lastScrollTime` in Task 9 having been introduced in Task 6 — noted at both ends. `clipped(to:offsetBy:_:)` has one signature across Tasks 5, 6 and 7. `startDisplayLink`'s signature changes in Task 8 and the fake is updated in the same task.

**Test-count arithmetic is cumulative and will drift** if a task adds a case this plan did not anticipate. Every task's step says to read the summary line; treat the predicted number as a check, not a gate.
