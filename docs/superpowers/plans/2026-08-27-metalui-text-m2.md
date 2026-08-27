# Text (M2, first cut) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `Text` element the layout engine measures and the renderer draws — shaped by CoreText, wrapped at its offered width, rasterized into an atlas, painted as `monochromeSprite`.

**Architecture:** A new Metal-free `MetalUIText` target owns font resolution, shaping, wrapping, metrics, glyph rasterization into CPU bitmaps and atlas packing, so all of it is testable headlessly against CoreText. `MetalUIRender` uploads the atlas and draws sprites; `MetalUI` attaches the `MeasureFunction` through `newLeaf`, which finally gives it a production caller. `MetalUILayout` is untouched.

**Tech Stack:** Swift 6.3, `swiftLanguageModes: [.v6]`, strict concurrency, Swift Testing, CoreText, Metal.

**Spec:** `docs/superpowers/specs/2026-08-27-text-m2-design.md` (and its parent, `docs/superpowers/specs/2026-08-24-metalui-design.md` §5.5, §6, §7.1)

## Global Constraints

- `swift build` and `swift test` must be **warning-free**. Warnings are defects to fix, never suppress.
- No third-party dependencies. No `.unsafeFlags`.
- **`MetalUILayout` must import only `MetalUICore`.** Verify with an *anchored* pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **`MetalUIText` must import no Metal.** Same anchored check. Rasterization and packing are CPU arithmetic and must stay testable without a GPU.
- **No golden may move.** This milestone adds a leaf measure function; the browser corpus has no text fixtures. A moved golden means something reached the engine's container path that should not have.
- **Pixel format is `bgra8Unorm`, never `_sRGB`.**
- **After editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, run `swift package clean`.** The header reaches its C target through a symlink SwiftPM does not track; Swift's view goes stale while Metal's refreshes, and the symptom is a vanished primitive that looks exactly like a shader bug.
- Use `swift package clean`, **never** `rm -rf .build`.
- **Mutation hygiene:** commit before mutating, and commit before editing a doc. `cp` a file aside and `cp` it back — `git checkout` restores nothing on an untracked file and discards *all* uncommitted work on a tracked one.
- **Suite integrity (taxonomy shape 11):** after every full run read the **summary line and test count**, never the exit status alone.
- **Ruling CS-M:** every mutation count under `--no-parallel` — a parallel run drops failing-test names from the log body.
- **Ruling CS-N / SI-H:** a mutation count is only reproducible with its spelling, and is stale the moment a test is added. Quote the exact edit beside any number, and prefer "this test reddens" to "N tests redden".
- **Ruling CS-C:** a test asserting something does **not** trap uses `await #expect(processExitsWith: .success)`. Bodies must be non-capturing.
- Every "cannot happen" comment names a **mechanism**, not a milestone.
- Read `docs/practices/verifying-tests-can-fail.md` before writing tests. It is the review standard.

---

### Task 1: The `MetalUIText` target, font resolution, and metrics

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MetalUIText/FontKey.swift`, `Sources/MetalUIText/FontResolver.swift`
- Test: `Tests/MetalUITextTests/FontResolutionTests.swift`

**Interfaces:**
- Produces: `struct FontKey: Hashable, Sendable` wrapping the resolved `CTFont`'s identity; `struct FontMetrics: Sendable { ascent, descent, leading: Double }`; `enum FontResolver { static func resolve(family: String?, size: Double) -> ResolvedFont }` and `struct ResolvedFont { let ctFont: CTFont; let key: FontKey; let metrics: FontMetrics }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreText
@testable import MetalUIText

/// **§6.1's measured trap.** Requesting `"SFMono-Regular"` by name on the target
/// machine returned a font whose PostScript name is `Helvetica`. A key built
/// from the requested name would serve one font's glyphs for another's.
@Test func theKeyComesFromTheRESOLVEDFontNotTheRequestedName() {
    let mono = FontResolver.resolve(family: "SFMono-Regular", size: 13)
    let helv = FontResolver.resolve(family: "Helvetica", size: 13)
    let resolvedMonoName = CTFontCopyPostScriptName(mono.ctFont) as String
    let resolvedHelvName = CTFontCopyPostScriptName(helv.ctFont) as String

    // Whatever the platform resolved these to, the KEY must follow the
    // resolution, not the request: same resolved font ⇒ same key, and a
    // different resolved font ⇒ a different key.
    if resolvedMonoName == resolvedHelvName {
        #expect(mono.key == helv.key)
    } else {
        #expect(mono.key != helv.key)
    }
}

@Test func theKeyDistinguishesSizes() {
    #expect(FontResolver.resolve(family: nil, size: 13).key
            != FontResolver.resolve(family: nil, size: 26).key)
}

/// Metrics come from CoreText, not from us. This asserts we report what it says.
@Test func metricsMatchCoreText() {
    let f = FontResolver.resolve(family: nil, size: 13)
    #expect(abs(f.metrics.ascent - CTFontGetAscent(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.descent - CTFontGetDescent(f.ctFont)) < 0.001)
    #expect(abs(f.metrics.leading - CTFontGetLeading(f.ctFont)) < 0.001)
}

/// **§6.2's `opsz` pinning, and the reason it exists.** An unpinned system font
/// tracks point size on its optical-size axis, so advances stop scaling
/// linearly: §6.2 measured a 28-character label at 13pt = 164.804 and 26pt =
/// 301.703, which is -8.5% against 13 x 2 = 329.608. Positions computed from
/// base-size advances then drift under zoom.
@Test func advancesScaleLinearlyBecauseOpszIsPinned() {
    let small = FontResolver.resolve(family: nil, size: 13)
    let large = FontResolver.resolve(family: nil, size: 26)
    let text = "The quick brown fox jumps ov"   // 28 characters, per §6.2
    func advance(_ f: ResolvedFont) -> Double {
        let attr = NSAttributedString(string: text,
                                      attributes: [.font: f.ctFont])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attr),
                                          nil, nil, nil)
    }
    let ratio = advance(large) / advance(small)
    #expect(abs(ratio - 2.0) < 0.01)
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --no-parallel --filter FontResolutionTests`
Expected: FAIL — the target does not exist.

- [ ] **Step 3: Add the target to `Package.swift`**

Add `.target(name: "MetalUIText", dependencies: ["MetalUICore"])` and a matching `.testTarget(name: "MetalUITextTests", dependencies: ["MetalUIText"])`. **Do not** add it to `MetalUILayout`'s dependencies.

- [ ] **Step 4: Implement `FontKey`, `FontMetrics` and `FontResolver`**

`FontKey` must be derived from the **resolved** `CTFont` — its PostScript name *plus* size *plus* variation coordinates (`CTFontCopyVariation`) *plus* the matrix. Not the requested family. Say why at the declaration, naming §6.1's measurement as the mechanism.

`FontResolver.resolve` pins the `opsz` axis via a `CTFontDescriptor` variation attribute (§6.2), so advances scale linearly.

- [ ] **Step 5: Run the tests, then the whole suite**

Run: `swift test --no-parallel`
Expected: a summary line and the full count. **No golden may move.**

- [ ] **Step 6: Prove the guards**

```bash
# 1. Build FontKey from the REQUESTED family name instead of the resolved font.
#    Expect: report what reddens. On a machine where the two requests resolve to
#    the same font this may redden nothing — if so, SAY SO and say that the test
#    is machine-dependent, rather than claiming coverage. That is the honest
#    result and it is why the test brackets both outcomes.
# 2. Drop the opsz pin from the descriptor.
#    Expect: `advancesScaleLinearlyBecauseOpszIsPinned` reddens.
# 3. Drop `size` from FontKey.
#    Expect: `theKeyDistinguishesSizes` reddens.
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/MetalUIText Tests/MetalUITextTests
git commit -m "feat(text): MetalUIText target with resolved-font keys and pinned opsz"
```

---

### Task 2: Shaping and wrapping

**Files:**
- Create: `Sources/MetalUIText/ShapedText.swift`
- Test: `Tests/MetalUITextTests/ShapingTests.swift`

**Interfaces:**
- Consumes: `ResolvedFont`, `FontMetrics` from Task 1.
- Produces:
  ```swift
  public struct ShapedLine: Sendable { let line: CTLine; let advance: Double }
  public struct ShapedText: Sendable {
      public let lines: [ShapedLine]
      public let widestLine: Double
      public let totalHeight: Double
  }
  public enum Shaper {
      public static func shape(_ string: String, font: ResolvedFont,
                               wrappingAt width: Double?) -> ShapedText
  }
  ```
  `width == nil` means "one line, no wrapping".

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreText
@testable import MetalUIText

private let font = FontResolver.resolve(family: nil, size: 13)

@Test func anUnwrappedStringIsOneLineWhoseAdvanceMatchesCoreText() {
    let s = "Hello, world"
    let shaped = Shaper.shape(s, font: font, wrappingAt: nil)
    let attr = NSAttributedString(string: s, attributes: [.font: font.ctFont])
    let expected = CTLineGetTypographicBounds(
        CTLineCreateWithAttributedString(attr), nil, nil, nil)
    #expect(shaped.lines.count == 1)
    #expect(abs(shaped.widestLine - expected) < 0.001)
}

@Test func aStringWiderThanItsWidthWrapsToMoreThanOneLine() {
    let s = "The quick brown fox jumps over the lazy dog"
    let wide = Shaper.shape(s, font: font, wrappingAt: 1000)
    let narrow = Shaper.shape(s, font: font, wrappingAt: 80)
    #expect(wide.lines.count == 1)
    #expect(narrow.lines.count > 1)
    #expect(narrow.widestLine <= 80.001)
    #expect(narrow.totalHeight > wide.totalHeight)
}

/// Every line must come from CoreText's own break decisions, so a wrapped line
/// never exceeds the width it was given.
@Test func noWrappedLineExceedsTheOfferedWidth() {
    let s = "Supercalifragilistic expialidocious antidisestablishmentarianism"
    for width in [40.0, 90.0, 150.0, 400.0] {
        let shaped = Shaper.shape(s, font: font, wrappingAt: width)
        for line in shaped.lines {
            // A single unbreakable word may overflow; anything else may not.
            #expect(line.advance <= width + 0.001 || shaped.lines.count == 1
                    || line.advance == shaped.widestLine)
        }
    }
}

/// **The non-termination guard (spec §3.4).** `CTTypesetterSuggestLineBreak` at
/// width 0 may return a zero-length break, which turns the wrap loop into a
/// hang rather than a wrong answer. A zero-length break is a hard error, not a
/// skipped iteration: a silent guard would convert the hang into an infinite
/// quiet loop one refactor later.
@Test func shapingAtAZeroWidthTraps() async {
    await #expect(processExitsWith: .failure) {
        let f = FontResolver.resolve(family: nil, size: 13)
        _ = Shaper.shape("anything", font: f, wrappingAt: 0)
    }
}

@Test func shapingAtASmallPositiveWidthTerminates() async {
    await #expect(processExitsWith: .success) {
        let f = FontResolver.resolve(family: nil, size: 13)
        let shaped = Shaper.shape("a bb ccc", font: f, wrappingAt: 0.5)
        precondition(!shaped.lines.isEmpty)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --no-parallel --filter ShapingTests`
Expected: FAIL — `Shaper` does not exist.

- [ ] **Step 3: Implement `Shaper.shape`**

Build a `CFAttributedString`, create a `CTTypesetter`, and loop `CTTypesetterSuggestLineBreak` / `CTTypesetterCreateLine` at the offered width. `precondition` that each suggested break advances the index by at least one character, with the message naming the width — a zero-length break is the hang described above.

**Do not** implement §6.3's shape-once fast path or §6.4's UAX #14 subset. Re-typesetting per display line is the always-correct branch, which §6.3 requires for base-RTL paragraphs regardless; the fast path is M6 and is an optimisation over this.

- [ ] **Step 4: Run the tests, then the whole suite**

Run: `swift test --no-parallel`
Expected: a summary line and the full count. Goldens unmoved.

- [ ] **Step 5: Prove the guards**

```bash
# 1. Delete the zero-length-break precondition.
#    Expect: `shapingAtAZeroWidthTraps` reddens. **Run this one with a timeout**
#    — the failure mode without the guard is a hang, not a red test, so a bare
#    `swift test` will sit forever. Use `timeout 120 swift test --no-parallel …`
#    and report if it times out rather than reddens; that IS the finding.
# 2. Make `shape` ignore `wrappingAt` and always produce one line.
#    Expect: `aStringWiderThanItsWidthWrapsToMoreThanOneLine` reddens.
```

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUIText Tests/MetalUITextTests
git commit -m "feat(text): shaping and wrapping via CTTypesetter"
```

---

### Task 3: The shaping cache

**Files:**
- Create: `Sources/MetalUIText/ShapingCache.swift`
- Test: `Tests/MetalUITextTests/ShapingCacheTests.swift`

**Interfaces:**
- Consumes: `Shaper`, `ShapedText`, `FontKey`.
- Produces: `@MainActor public final class ShapingCache` with `func shaped(_ string: String, font: ResolvedFont, wrappingAt: Double?) -> ShapedText`, plus `private(set) var hits: Int` and `misses: Int`.

**Why this exists, so the work is calibrated.** §4.5's automatic minimum probes every item and an `auto`-cross item probes again, so a text leaf's `MeasureFunction` is called up to three times per layout, at up to three distinct widths. Uncached, that is three typesets per text node per frame.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import MetalUIText

private let font = FontResolver.resolve(family: nil, size: 13)

/// **The only test that can see whether the cache is a cache.** A `store` that
/// never stores leaves every other test green and the engine typesetting on
/// every probe.
@MainActor
@Test func theCacheIsActuallyConsulted() {
    let cache = ShapingCache()
    _ = cache.shaped("hello world", font: font, wrappingAt: 100)
    let after = cache.misses
    _ = cache.shaped("hello world", font: font, wrappingAt: 100)
    #expect(cache.hits > 0)
    #expect(cache.misses == after)
}

/// Width is in the key because wrapping is width-dependent. A key that dropped
/// it would serve one width's line breaks for another's.
@MainActor
@Test func twoWidthsDoNotShareOneEntry() {
    let cache = ShapingCache()
    let narrow = cache.shaped("The quick brown fox jumps over", font: font, wrappingAt: 60)
    let wide = cache.shaped("The quick brown fox jumps over", font: font, wrappingAt: 600)
    #expect(narrow.lines.count > wide.lines.count)
    #expect(cache.misses == 2)
}

@MainActor
@Test func twoFontSizesDoNotShareOneEntry() {
    let cache = ShapingCache()
    let small = cache.shaped("hello", font: FontResolver.resolve(family: nil, size: 13),
                             wrappingAt: nil)
    let large = cache.shaped("hello", font: FontResolver.resolve(family: nil, size: 26),
                             wrappingAt: nil)
    #expect(large.widestLine > small.widestLine)
    #expect(cache.misses == 2)
}

/// The cache is keyed on CONTENT, not on element identity — two elements
/// showing the same string shape once.
@MainActor
@Test func theSameStringFromTwoCallersSharesOneEntry() {
    let cache = ShapingCache()
    _ = cache.shaped("shared", font: font, wrappingAt: 200)
    _ = cache.shaped("shared", font: font, wrappingAt: 200)
    #expect(cache.misses == 1)
    #expect(cache.hits == 1)
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --no-parallel --filter ShapingCacheTests`
Expected: FAIL — `ShapingCache` does not exist.

- [ ] **Step 3: Implement the cache**

Key: `(string, FontKey, width)`. `width` is a `Double?` — hash it by `bitPattern` where present, as `MeasureKey` in `LayoutContext` does, and say at the declaration that a near-miss costs a recompute and never a wrong answer.

**It is deliberately not the `StateTable`.** §4.3 is for state that *cannot* be recomputed from the element values; a shaped line can be. Keying there would also key on identity and shape the same string twice. Say so at the declaration.

- [ ] **Step 4: Run the tests, then the whole suite**

- [ ] **Step 5: Prove the guards**

```bash
# 1. Make the store a no-op.
#    Expect: `theCacheIsActuallyConsulted` reddens. Report whether anything
#    else does — if nothing else does, that is the finding this test exists for.
# 2. Drop `width` from the key.
#    Expect: `twoWidthsDoNotShareOneEntry` reddens.
# 3. Drop `FontKey` from the key.
#    Expect: `twoFontSizesDoNotShareOneEntry` reddens.
```

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUIText Tests/MetalUITextTests
git commit -m "feat(text): a content-keyed shaping cache"
```

---

### Task 4: `Text`, the measure function, and `newLeaf`'s first production caller

**Files:**
- Create: `Sources/MetalUI/Text.swift`
- Modify: `Sources/MetalUI/Frame.swift` (own a `ShapingCache`), `Package.swift` (`MetalUI` depends on `MetalUIText`)
- Test: `Tests/MetalUITests/TextMeasureTests.swift`

**Interfaces:**
- Consumes: `ShapingCache`, `ResolvedFont`, `ShapedText`.
- Produces: `public struct Text: Element, StyledElement` with `init(_ string: String)`, `.font(family:size:)`, `.foregroundColor(_:)`.

**This is the milestone's centre.** `newLeaf` is the only thing that attaches a `MeasureFunction` and **nothing in `Sources/` calls it** — after this task, something does, and `tree.measure()` stops being `nil` for a production node.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

/// Renders `Column { Text(text) }` into a frame `width` points wide and returns
/// the TEXT node's resolved bounds.
///
/// **`Frame.render` does not hand back the root node id**, so this drives the
/// element directly rather than through `render`. Check `LayoutPass`'s current
/// shape before writing this — it is `LayoutPass(frame:)` today and the frame's
/// `tree`, `requestNode` and `bounds(of:)` are all `internal`, so
/// `@testable import MetalUI` is required.
@MainActor
private func measuredTextBounds(_ text: String, in width: Double) -> (w: Double, h: Double) {
    let frame = Frame(contentSize: Size(width: Pixels(Float(width)), height: Pixels(600)),
                      scaleFactor: 1, stateTable: StateTable())
    var pass = LayoutPass(frame: frame)
    var column = Column { Text(text) }
    let id = GlobalElementID.child(of: nil, at: 0, name: nil)
    let (root, _) = column.requestLayout(id, pass: &pass)
    frame.computeRootLayout(root: root)
    // The column has exactly one child: the text node.
    let textNode = frame.tree.children(root)[0]
    let r = frame.tree.layout(textNode)
    return (r.width, r.height)
}

/// **`newLeaf` has a production caller.** Before this task nothing in `Sources/`
/// called it, so every production node's `tree.measure()` was nil and a leaf's
/// content size was dead while a container's was live.
@MainActor
@Test func aTextLeafCarriesAMeasureFunction() {
    let tree = LayoutTree(generation: 0)
    let ctx = LayoutContext(rootFontSize: 16)
    var text = Text("hello")
    var pass = LayoutPass(frame: Frame(contentSize: Size(width: Pixels(400), height: Pixels(200)),
                                       scaleFactor: 1, stateTable: StateTable()))
    let (node, _) = text.requestLayout(GlobalElementID.child(of: nil, at: 0, name: nil),
                                       pass: &pass)
    #expect(pass.frame.tree.measure(node) != nil)
    _ = ctx
    _ = tree
}

/// The three sizing modes, which is what §4.5 and §9.2 consume.
@MainActor
@Test func minContentIsTheLongestWordAndMaxContentIsTheWholeString() {
    let cache = ShapingCache()
    let font = FontResolver.resolve(family: nil, size: 13)
    let s = "a bb supercalifragilistic dd"
    let maxC = cache.shaped(s, font: font, wrappingAt: nil).widestLine
    let minC = cache.shaped(s, font: font, wrappingAt: 0.5).widestLine
    let longestWord = cache.shaped("supercalifragilistic", font: font, wrappingAt: nil).widestLine
    #expect(abs(minC - longestWord) < 0.5)
    #expect(maxC > minC)
}

/// **A long label wraps rather than overflowing**, which is the whole reason
/// wrapping is in this milestone rather than deferred: §4.5's automatic minimum
/// floors a text item at its longest word, not at its whole string.
@MainActor
@Test func aLongLabelInANarrowColumnWrapsRatherThanOverflowing() {
    let narrow = 120.0
    let size = measuredTextBounds("The quick brown fox jumps over the lazy dog", in: narrow)
    #expect(size.w <= narrow + 0.5)
    #expect(size.h > 20)      // more than one line
}

/// A `known` size wins over the measured one — `measureNode`'s existing
/// contract, exercised by a production leaf for the first time.
@MainActor
@Test func anExplicitWidthWinsOverTheMeasuredOne() {
    let tree = LayoutTree(generation: 0)
    let cache = ShapingCache()
    let font = FontResolver.resolve(family: nil, size: 13)
    let node = tree.newLeaf(style: {
        var s = Style()
        s.size = Size(width: .length(.pixels(Pixels(50))), height: .auto)
        return s
    }()) { known, available in
        textMeasure("a much longer string than fifty points",
                    font: font, cache: cache, known: known, available: available)
    }
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(400), height: .definite(200)))
    #expect(tree.layout(node).width == 50)
}
```

`textMeasure(_:font:cache:known:available:)` is the free function `Text` builds its closure from; define it in `Text.swift` so a test can call it without an element.

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --no-parallel --filter TextMeasureTests`
Expected: FAIL — `Text` does not exist.

- [ ] **Step 3: Add the dependency and implement `textMeasure`**

`MetalUI` gains `MetalUIText` in `Package.swift`. `textMeasure` maps the spec's table:

| `available` | answer |
|---|---|
| `.maxContent` | `shaped(wrappingAt: nil)` — one line, full advance |
| `.minContent` | `shaped(wrappingAt: small positive)` — widest line |
| `.definite(w)` | `shaped(wrappingAt: w)` — widest line, `lines × lineHeight` |

`known` wins on either axis, per §5.5.

- [ ] **Step 4: Implement `Text` and give `Frame` a `ShapingCache`**

`Frame` holds the cache the way it holds the `StateTable` — **not owned by the frame**; the window owns it and hands the same instance to every frame. A per-frame cache would shape everything again each frame while every test still passed. Say that at the declaration; it is the same hazard `StateTable` records.

- [ ] **Step 5: Run the tests, then the whole suite**

Run: `swift test --no-parallel`
Expected: a summary line and the full count. **Goldens unmoved** — the corpus has no text fixtures, and a moved golden here means something reached the container path.

- [ ] **Step 6: Prove it**

```bash
# 1. Make `textMeasure` ignore `available` and always return the one-line size.
#    Expect: `aLongLabelInANarrowColumnWrapsRatherThanOverflowing` reddens.
# 2. Make `textMeasure` ignore `known`.
#    Expect: `anExplicitWidthWinsOverTheMeasuredOne` reddens.
# 3. Give `Frame` its own `ShapingCache` per frame instead of taking one.
#    Expect: report what reddens. If nothing does, SAY SO — that is the
#    `StateTable` hazard repeating, and it needs a test that renders two frames
#    and asserts the cache's miss count did not double.
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/MetalUI Tests/MetalUITests
git commit -m "feat(text): Text element, measure function, and newLeaf's first caller"
```

---

### Task 5: Glyph rasterization and the shelf packer

**Files:**
- Create: `Sources/MetalUIText/GlyphRaster.swift`, `Sources/MetalUIText/Atlas.swift`
- Test: `Tests/MetalUITextTests/AtlasTests.swift`

**Interfaces:**
- Consumes: `ResolvedFont`, `FontKey`.
- Produces:
  ```swift
  public struct GlyphKey: Hashable, Sendable {
      let font: FontKey; let glyph: CGGlyph
      let size: Double; let subpixelVariant: Int; let scaleFactor: Float
  }
  public struct GlyphImage: Sendable { let width, height: Int; let bytes: [UInt8] }  // R8
  public struct AtlasSlot: Sendable { let x, y, width, height: Int }
  public enum GlyphRaster {
      public static func rasterize(glyph: CGGlyph, font: ResolvedFont,
                                   subpixelVariant: Int, scaleFactor: Float) -> GlyphImage
  }
  public final class GlyphAtlas {
      public init(width: Int, height: Int)
      public func slot(for key: GlyphKey, rasterize: () -> GlyphImage) -> AtlasSlot?
      public private(set) var pixels: [UInt8]
      public private(set) var dirtyRect: (x: Int, y: Int, width: Int, height: Int)?
  }
  ```

**All CPU, no Metal.** This is the arithmetic that wants a test, and it must run on a machine with no GPU — CLAUDE.md records that the ABI probe already skips without a Metal device.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreText
@testable import MetalUIText

private func img(_ w: Int, _ h: Int) -> GlyphImage {
    GlyphImage(width: w, height: h, bytes: [UInt8](repeating: 255, count: w * h))
}

@Test func twoGlyphsNeverOverlapInTheAtlas() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    var slots: [AtlasSlot] = []
    for i in 0..<20 {
        let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                           glyph: CGGlyph(i), size: 13, subpixelVariant: 0, scaleFactor: 2)
        if let s = atlas.slot(for: key, rasterize: { img(9 + i % 5, 12) }) { slots.append(s) }
    }
    #expect(slots.count == 20)
    for (i, a) in slots.enumerated() {
        for b in slots[(i + 1)...] {
            let disjoint = a.x + a.width <= b.x || b.x + b.width <= a.x
                        || a.y + a.height <= b.y || b.y + b.height <= a.y
            #expect(disjoint)
        }
    }
}

@Test func theSameKeyReturnsTheSameSlotWithoutRasterizingTwice() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2)
    var rasterCount = 0
    let first = atlas.slot(for: key, rasterize: { rasterCount += 1; return img(10, 12) })
    let second = atlas.slot(for: key, rasterize: { rasterCount += 1; return img(10, 12) })
    #expect(rasterCount == 1)
    #expect(first?.x == second?.x && first?.y == second?.y)
}

/// **The five key components each matter.** §6.1 names them; this asserts none
/// is decorative. Dropping any one collapses two distinct glyph images onto one
/// slot, which paints the wrong glyph.
@Test func everyComponentOfTheGlyphKeyDiscriminates() {
    let f13 = FontResolver.resolve(family: nil, size: 13).key
    let f26 = FontResolver.resolve(family: nil, size: 26).key
    let base = GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2)
    #expect(base != GlyphKey(font: f26, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 2))
    #expect(base != GlyphKey(font: f13, glyph: 43, size: 13, subpixelVariant: 0, scaleFactor: 2))
    #expect(base != GlyphKey(font: f13, glyph: 42, size: 26, subpixelVariant: 0, scaleFactor: 2))
    #expect(base != GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 1, scaleFactor: 2))
    #expect(base != GlyphKey(font: f13, glyph: 42, size: 13, subpixelVariant: 0, scaleFactor: 1))
}

@Test func aGlyphTooLargeForTheAtlasReturnsNilRatherThanCorrupting() {
    let atlas = GlyphAtlas(width: 32, height: 32)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 1, size: 13, subpixelVariant: 0, scaleFactor: 2)
    #expect(atlas.slot(for: key, rasterize: { img(64, 64) }) == nil)
}

/// Rasterization goes through CoreText, and a rendered glyph is not blank.
@Test func aRasterizedGlyphHasInk() {
    let f = FontResolver.resolve(family: nil, size: 13)
    var glyph = CGGlyph(0)
    var ch: UniChar = 0x48   // "H"
    #expect(CTFontGetGlyphsForCharacters(f.ctFont, &ch, &glyph, 1))
    let image = GlyphRaster.rasterize(glyph: glyph, font: f, subpixelVariant: 0, scaleFactor: 2)
    #expect(image.bytes.contains { $0 > 0 })
}
```

- [ ] **Step 2: Run them and confirm they fail**

- [ ] **Step 3: Implement `GlyphRaster.rasterize` and the shelf packer**

`CTFontDrawGlyphs` into a CGContext backed by an R8 buffer. §6.1's decisions carry unchanged, each with its reason at the code: **subpixel positioning** (a few fractional x-offsets, nearest wins — without it spacing visibly wobbles during horizontal scroll), **grayscale AA only** (macOS retired LCD subpixel AA), and **colour glyphs route to the polychrome atlas and skip tinting** — which is out of this milestone, so that path is a recorded gap rather than a silent one.

- [ ] **Step 4: Run the tests, then the whole suite**

- [ ] **Step 5: Prove the guards**

```bash
# 1. Make the shelf packer ignore the current shelf's height.
#    Expect: `twoGlyphsNeverOverlapInTheAtlas` reddens.
# 2. Drop `subpixelVariant` from GlyphKey's == and hash.
#    Expect: `everyComponentOfTheGlyphKeyDiscriminates` reddens.
# 3. Make `slot(for:)` rasterize on every call.
#    Expect: `theSameKeyReturnsTheSameSlotWithoutRasterizingTwice` reddens.
```

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUIText Tests/MetalUITextTests
git commit -m "feat(text): glyph rasterization and shelf packing"
```

---

### Task 6: Eviction, and the between-frames guard

**Files:**
- Modify: `Sources/MetalUIText/Atlas.swift`
- Test: `Tests/MetalUITextTests/AtlasEvictionTests.swift`

**Interfaces:**
- Produces: `GlyphAtlas.beginFrame()`, `endFrame()`, `evictUnusedSince(_ generation: Int)`, `private(set) var isBuildingFrame: Bool`, `private(set) var currentGeneration: Int`.

**Why this is its own task.** §6.2 makes eviction mandatory, and eviction is invisible when wrong: evict a glyph the current frame's scene still references and you get a wrong glyph or a blank, **on one frame, intermittently** — the hardest thing in this milestone to reproduce. The guard is the same shape as `LayoutTree.isLayingOut`, which this project already built.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import MetalUIText

@Test func evictingDuringFrameConstructionTraps() async {
    await #expect(processExitsWith: .failure) {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.beginFrame()
        atlas.evictUnusedSince(0)
    }
}

/// The positive control (ruling CS-C). Without it the test above passes when
/// `evictUnusedSince` traps unconditionally.
@Test func evictingBetweenFramesDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.beginFrame()
        atlas.endFrame()
        atlas.evictUnusedSince(0)
    }
}

@Test func aGlyphUsedThisFrameSurvivesEviction() {
    let atlas = GlyphAtlas(width: 128, height: 128)
    let key = GlyphKey(font: FontResolver.resolve(family: nil, size: 13).key,
                       glyph: 7, size: 13, subpixelVariant: 0, scaleFactor: 2)
    atlas.beginFrame()
    let slot = atlas.slot(for: key, rasterize: {
        GlyphImage(width: 8, height: 8, bytes: [UInt8](repeating: 255, count: 64))
    })
    atlas.endFrame()
    atlas.evictUnusedSince(atlas.currentGeneration)
    var rasterizedAgain = false
    atlas.beginFrame()
    let again = atlas.slot(for: key, rasterize: {
        rasterizedAgain = true
        return GlyphImage(width: 8, height: 8, bytes: [UInt8](repeating: 255, count: 64))
    })
    atlas.endFrame()
    #expect(rasterizedAgain == false)
    #expect(slot?.x == again?.x && slot?.y == again?.y)
}
```

- [ ] **Step 2: Run them and confirm they fail**

- [ ] **Step 3: Implement the generation counter and the guard**

Each slot records the generation it was last used in. `evictUnusedSince` drops slots older than the given generation, and `precondition(!isBuildingFrame)` with a message naming the hazard — a mechanism, not a milestone.

- [ ] **Step 4: Run the tests, then the whole suite**

- [ ] **Step 5: Prove the guards**

```bash
# 1. Delete the `precondition(!isBuildingFrame)`.
#    Expect: `evictingDuringFrameConstructionTraps` reddens, and NOTHING else.
#    If something else reddens, say what — that would mean another test depends
#    on the guard rather than on the behaviour.
# 2. Make `slot(for:)` not stamp the generation.
#    Expect: `aGlyphUsedThisFrameSurvivesEviction` reddens.
```

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUIText Tests/MetalUITextTests
git commit -m "feat(text): atlas eviction, and it may only run between frames"
```

---

### Task 7: The renderer path — `MUIGlyph`, the shader, and the upload

**Files:**
- Modify: `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, `Sources/MetalUIRender/Shaders/shaders.metal`, `Sources/MetalUIRender/Scene.swift`, `Sources/MetalUIRender/Renderer.swift`, `Package.swift`
- Test: `Tests/MetalUIRenderTests/GlyphABITests.swift`

**Interfaces:**
- Consumes: `AtlasSlot`, `GlyphAtlas` from Tasks 5-6.
- Produces: `MUIGlyph` in the shared header; `Scene.glyphs: [MUIGlyph]` and `Scene.insert(_ glyph: MUIGlyph)`; a `glyph_vertex`/`glyph_fragment` pair sampling the R8 atlas and tinting.

**The header is compiled twice — by clang through a symlink and by the Metal compiler at runtime.** After editing it, `swift package clean` is **mandatory**; SwiftPM does not track that symlink, so Swift's view goes stale while Metal's refreshes and the symptom is a vanished primitive that looks exactly like a shader bug.

- [ ] **Step 1: Add `MUIGlyph` to the shared header**

```c
typedef struct {
    MUIBounds bounds;        // destination, ScaledPixels
    MUIBounds atlasBounds;   // source, atlas texels
    MUIHsla   color;         // tint; the R8 atlas carries coverage only
    MUIUInt   order;
    MUIUInt   _reserved;
} MUIGlyph;
```

- [ ] **Step 2: `swift package clean`, then extend the ABI probe**

The existing `abi_probe` proves a struct's field offsets survive the MSL boundary. Add the same for `MUIGlyph` — read one field back and assert it. **This is the only test in the milestone that touches the GPU, and it skips without a Metal device**, which CLAUDE.md already lists as a guarantee that must be a required, non-gateable CI job.

- [ ] **Step 3: Write the failing test**

```swift
import Testing
@testable import MetalUIRender

private func makeGlyph(order: MUIUInt, x: Float = 0) -> MUIGlyph {
    MUIGlyph(
        bounds: MUIBounds(origin: MUIPoint(x: x, y: 0),
                          size: MUISize(width: 8, height: 12)),
        atlasBounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                               size: MUISize(width: 8, height: 12)),
        color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
        order: order,
        _reserved: 0)
}

private func makeRect() -> MUIRect {
    MUIRect(
        bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                          size: MUISize(width: 10, height: 10)),
        contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                               size: MUISize(width: 100, height: 100)),
        background: MUIHsla(h: 0, s: 0, l: 0, a: 1),
        borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
        cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
        borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
        order: 0,
        _reserved: 0)
}

@Test func sceneKeepsGlyphsAndRectsInSeparateLists() {
    var scene = Scene()
    scene.insert(makeRect())
    scene.insert(makeGlyph(order: 0))
    #expect(scene.rects.count == 1)
    #expect(scene.glyphs.count == 1)
}

/// Stable, so equal orders keep emission sequence — the same guarantee
/// `finalize` already gives rects.
@Test func finalizeSortsGlyphsStablyByOrder() {
    var scene = Scene()
    for (i, order) in ([2, 0, 1, 0] as [MUIUInt]).enumerated() {
        scene.insert(makeGlyph(order: order, x: Float(i)))
    }
    scene.finalize()
    #expect(scene.glyphs.map(\.order) == [0, 0, 1, 2])
    // The two order-0 glyphs keep their emission order: x = 1 then x = 3.
    #expect(scene.glyphs[0].bounds.origin.x == 1)
    #expect(scene.glyphs[1].bounds.origin.x == 3)
}
```

**Check `MUIRect`'s field list against the header before writing `makeRect`** — it is the ABI and it may have gained a field. `sed -n '/typedef struct {/,/} MUIRect;/p' Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`.

- [ ] **Step 4: Implement the shader pair and the upload**

`glyph_fragment` samples the R8 atlas and multiplies coverage by the tint. Pixel format stays `bgra8Unorm` — an `_sRGB` target makes the hardware blend in linear space, and this framework composites in gamma-encoded sRGB by design (§7.8).

- [ ] **Step 5: `swift package clean && swift build`, then the whole suite**

- [ ] **Step 6: Prove it**

```bash
# 1. Change MUIGlyph's field order in the header WITHOUT `swift package clean`.
#    Expect: report what happens. This is the trap CLAUDE.md documents; the
#    result is worth recording precisely because it is confusing.
# 2. Make `finalize` sort glyphs unstably (sort by order alone).
#    Expect: `finalizeSortsGlyphsStablyByOrder` reddens.
```

- [ ] **Step 7: Commit**

```bash
git add Sources/MetalUIRender Package.swift Tests/MetalUIRenderTests
git commit -m "feat(render): MUIGlyph, the glyph shader, and atlas upload"
```

---

### Task 8: The demo, the human look, and the claims this milestone falsified

**Files:**
- Modify: `Sources/MetalUIDemo/main.swift`, `CLAUDE.md`
- Create: `docs/superpowers/2026-08-27-text-m2-decisions.md`

- [ ] **Step 1: Put text in the demo**

Add a `Text` to the demo's sidebar and a wrapping paragraph in the body, so both the single-line and wrapped paths are visible. The paragraph must be long enough to wrap at the default window width and re-wrap when the window is resized.

- [ ] **Step 2: Run it and look at it**

```bash
swift run MetalUIDemo
```

**No test can establish this**, and the spec says so: there is no WebKit oracle for text rendering as there is for layout, and the ABI probe skips without a device. **Look for the three failure modes by name:**

- **wrong glyph** → an atlas key collision (the `resolvedFontKey` trap)
- **fuzzy or wobbling text** → subpixel variant ignored, or `scaleFactor` missing from the key
- **blank runs, intermittent** → eviction during a frame

Resize the window and watch the paragraph re-wrap. **Report what you saw; do not write a human-verified claim into CLAUDE.md yourself** — the controller records it.

- [ ] **Step 3: Write the decisions doc**

`docs/superpowers/2026-08-27-text-m2-decisions.md`, matching `docs/superpowers/2026-08-27-structural-identity-decisions.md`'s shape: each ruling with its reasoning and what it costs if wrong. Prefix `TX-`. Add it to CLAUDE.md's "Start here" list and its ruling-namespace note. **Sweep case-insensitively for an existing `TX-` before using it** — this session has caused two ruling-ID collisions, both caught by an implementer rather than by the sweep.

- [ ] **Step 4: Retire the claims this milestone falsified**

- **Delete `MeasureFunction` / `newLeaf`'s inert row.** It has a production caller now. Re-measure with `grep -rn "newLeaf" Sources/` and quote the result.
- **`AlignItems.baseline`'s row loses its stated blocker.** It says baseline *"needs font metrics that arrive with the text system in M2."* The metrics now exist — but the implementation is engine work in `crossAxisOffset` plus AL-6's `wrap-reverse` clause, which is not an offset flip. **Update the row to say the blocker is gone and the work is not done.** Leaving "needs M2" standing after M2 is the shape this project has corrected nine times.
- Sweep `grep -rniE "until M2|needs M2|M2 brings|text system" Sources/ CLAUDE.md docs/` and correct each — **do not delete**; a comment that named a real gap should say what replaced it.
- Update every test count by re-running and reading the summary line.

- [ ] **Step 5: Commit**

```bash
git add Sources/MetalUIDemo CLAUDE.md docs/superpowers
git commit -m "docs: record M2's rulings and retire the text-system blockers"
```

## Exit criteria

- [ ] `swift test` completes with a **summary line** and the full count; `swift package clean && swift build` warning-free
- [ ] `MetalUILayout` still imports only `MetalUICore`; **`MetalUIText` imports no Metal** (anchored greps)
- [ ] `newLeaf` has a production caller and its inert row is **deleted**
- [ ] A text leaf's min-content is its longest word, pinned
- [ ] A long label in a narrow container **wraps rather than overflowing**, pinned
- [ ] An explicit width wins over the measured one, pinned
- [ ] Shaping at width 0 traps rather than hangs, with a positive control
- [ ] Eviction cannot run during frame construction, with a positive control
- [ ] Every mutation named in Tasks 1–7 measured under `--no-parallel` with its exact edit quoted
- [ ] **`swift run MetalUIDemo` shows wrapped text — verified by a human**, with the three failure modes looked for by name and the result recorded in CLAUDE.md
- [ ] **No golden moved** — the corpus has no text fixtures
- [ ] Every new "cannot happen" comment names a **mechanism**, not a milestone

## Deliberately NOT in this plan

- **The shape-once/wrap-by-advances fast path** (§6.3) and the **hand-rolled UAX #14 subset** (§6.4) — optimisations over a working implementation. M6.
- **MSDF glyphs** — decided for the node canvas, sequenced with the canvas at M5 (§6.2, revised 2026-08-27).
- **Selection, caret, hit-testing, IME** (§6.6). M6.
- **Baseline alignment.** This milestone removes its blocker without implementing it.
- **Rich text** — one font, one size, one colour per `Text`.
- **Colour emoji.** The polychrome path is recorded as a gap, not built.

## Risks carried in

- **Nothing in this repo can see a wrong glyph, a wrong atlas coordinate, or a blank run.** No WebKit oracle for text rendering; the ABI probe skips without a device. The human look is the only check, which is why the three failure modes are named in advance.
- **Eviction is the subtlest thing here.** Its failure is one wrong frame, intermittently. The between-frames guard is the whole defence, and its own test is the only thing pinning it.
- **The shaping cache is invisible.** A store that never stores leaves the engine correct and typesetting three times per node per frame. `theCacheIsActuallyConsulted` is the only guard.
- **`opsz` pinning is load-bearing for M5.** §6.2 measured −8.5% advance drift at 2× without it. It is tested here at 13/26pt, but its consequence lands on the canvas.
- **The header symlink.** Editing `MetalUIShaderTypes.h` without `swift package clean` produces a vanished primitive that looks exactly like a shader bug.
