# MetalUI Milestone 1a — Flexbox Layout Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A CSS Flexbox implementation in Swift that matches WebKit's layout on a corpus of browser-generated fixtures, within a cumulative-rounded 0.1pt tolerance.

**Architecture:** A pure, headless `MetalUILayout` target — no Metal, no window, no rendering. Layout is a function of style plus measure closures, so it is testable in isolation. Ground truth comes from a `WKWebView` that lays out fixture HTML and reports every node's `getBoundingClientRect()`; the same fixtures drive both the golden generator and the engine's tests.

**Tech Stack:** Swift 6.3, WebKit (test-only, for the oracle), Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` — read §5 in full (§5.1 decision, §5.2 style/box model, §5.3 units, §5.5 measure contract, §5.6 caching, §5.7 oracle, §5.8 module) before starting.

**Prior milestone:** M0 is merged. `docs/superpowers/2026-08-25-m0-decisions.md` records the 26 decisions taken during it; §"Carried into M1" names the debt this plan does *not* address and why.

## Global Constraints

- **Swift tools version 6.3**, `swiftLanguageModes: [.v6]`. Strict concurrency is on; every warning is an error to fix, never suppress.
- **No third-party dependencies. No `.unsafeFlags`.** WebKit is an Apple framework and is used only by the test target.
- **`MetalUILayout` must not import Metal, AppKit, or `MetalUIRender`.** Layout does not know rendering exists (spec §3.1). It may import `MetalUICore`.
- **`MetalUILayout` must not know text exists.** Leaves take a measure closure; the umbrella supplies one later (spec §3.1).
- **Box model is `border-box` only** (spec §5.2). `size`/`minSize`/`maxSize` include padding and border. No `boxSizing` property in v1. Every fixture's CSS must declare `box-sizing: border-box`.
- **Automatic minimum size (`min-width: auto`) IS implemented** (spec §5.2). Without it, text in a constrained row collapses to zero.
- **Units live in `MetalUICore`**, already shipped: `Pixels`, `ScaledPixels`, `Rems`, `DevicePixels`, `Length` (`.pixels`/`.rems`/`.percent`, no `auto`), `Dimension` (`.length`/`.auto`). Do not redefine them.
- **Out of scope for this plan:** CSS Grid (M1 later), block/inline layout, floats, writing modes, RTL, subgrid, and everything in M1b (elements, rendering, styling, theming).

### Verified environment facts

Confirmed on this machine before this plan was written. Do not re-derive them.

- **`WKWebView` lays out flexbox headlessly inside a `swift test` target** — no app bundle, no window, no run-loop pumping. A `navigationDelegate` continuation plus `evaluateJavaScript` is sufficient; two fixtures measured in 0.26s total.
- **WebKit quantizes to 1/64px and the error compounds.** Measured: 7 × `flex: 1 1 0` in a 100px row yields **14.28125** per child (not 14.285714 — that is 914/64), with x positions 0, 14.28125, 28.5625, 42.84375, 57.125, 71.40625, 85.6875. The last child's right edge lands at **99.96875**, short of its own parent by 0.03125px.
- Exact-integer cases are exact: 700px row, one 100px fixed child, two `flex: 1`/`flex: 2` children → **200 / 400 / 100** at x **0 / 200 / 600**.

These are why §5.7 mandates cumulative rounding and a 0.1pt tolerance rather than exact comparison.

### The staleness hazard from M0 still applies

Editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` does not reliably rebuild its dependents — it reaches the C target through a symlink SwiftPM does not track as a build input. **Nothing in this plan touches that header.** If you find yourself editing it, stop: you are outside this plan's scope. Should a build behave inexplicably, `swift package clean` (not `rm -rf .build`) is the remedy.

---

## File Structure

```
Sources/MetalUILayout/
  Style.swift            # the style model + box model; no algorithm
  LayoutTree.swift       # SoA node storage, arena-reset per pass
  MeasureFunction.swift  # the Layout<->leaf contract (spec §5.5)
  Resolve.swift          # lengths/dimensions/edges against a container
  Rounding.swift         # cumulative rounding, shared with the oracle
  FlexEngine.swift       # the §9 algorithm, orchestration only

  # Created by LATER task groups, not this plan:
  #   MeasureCache.swift   FlexLine.swift   Alignment.swift

Tests/MetalUILayoutTests/
  Oracle/
    LayoutOracle.swift       # WKWebView -> [NodeBox]
    GoldenFile.swift         # JSON codable + load/compare
    GenerateGoldens.swift    # regeneration entry point
  Fixtures/*.html            # plain CSS, one case each
  Golden/*.json              # generated; committed
  FlexEngineTests.swift      # corpus-driven, @Test(arguments:)
  RoundingTests.swift
  MeasureCacheTests.swift
```

Rounding lives in `Sources/`, not the test target, because the engine and the golden generator must apply the *identical* pass — a second implementation would drift and the corpus would silently validate the wrong thing.

---

### Task 1: Layout target skeleton and the style model

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MetalUILayout/Style.swift`
- Test: `Tests/MetalUILayoutTests/StyleTests.swift`

**Interfaces:**
- Consumes: `MetalUICore`'s `Length`, `Dimension`, `Edges<T>`, `Size<T>`, `Axes<T>`.
- Produces: `Style` (all properties below, memberwise-defaulted via `init()`), and the enums `Display`, `Position`, `FlexDirection`, `FlexWrap`, `Overflow`, `AlignItems`, `AlignSelf`, `AlignContent`, `JustifyContent`. `Style.default` static. `FlexDirection.isRow` / `.isReverse`.

- [ ] **Step 1: Add the target to `Package.swift`**

Insert into `targets:`, after the `MetalUICoreTests` entry:

```swift
        .target(name: "MetalUILayout", dependencies: ["MetalUICore"]),
        .testTarget(name: "MetalUILayoutTests", dependencies: ["MetalUILayout"]),
```

- [ ] **Step 2: Write the failing test**

Create `Tests/MetalUILayoutTests/StyleTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

@Test func defaultStyleMatchesCSSInitialValues() {
    let s = Style()
    #expect(s.display == .flex)
    #expect(s.position == .relative)
    #expect(s.flexDirection == .row)
    #expect(s.flexWrap == .noWrap)
    #expect(s.flexGrow == 0)
    #expect(s.flexShrink == 1)
    #expect(s.flexBasis == .auto)
    #expect(s.size == Size(width: Dimension.auto, height: Dimension.auto))
    #expect(s.alignItems == nil)     // nil means "stretch" at use site
    #expect(s.alignSelf == nil)      // nil means "inherit alignItems"
}

@Test func flexDirectionKnowsItsAxis() {
    #expect(FlexDirection.row.isRow)
    #expect(FlexDirection.rowReverse.isRow)
    #expect(!FlexDirection.column.isRow)
    #expect(!FlexDirection.columnReverse.isRow)
    #expect(!FlexDirection.row.isReverse)
    #expect(FlexDirection.rowReverse.isReverse)
    #expect(FlexDirection.columnReverse.isReverse)
}

@Test func styleIsValueSemantic() {
    var a = Style()
    var b = a
    b.flexGrow = 5
    #expect(a.flexGrow == 0)
    #expect(b.flexGrow == 5)
    a.flexGrow = 9
    #expect(b.flexGrow == 5)
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter StyleTests`
Expected: FAIL — `no such module 'MetalUILayout'` or `cannot find 'Style' in scope`.

Note: SwiftPM refuses to configure a package containing an empty target. If you hit `target 'MetalUILayout' is empty`, create `Style.swift` with a single `// placeholder` line first, confirm the real red (`cannot find 'Style' in scope`), then replace it with the implementation. Do not commit the placeholder.

- [ ] **Step 4: Implement the style model**

Create `Sources/MetalUILayout/Style.swift`:

```swift
import MetalUICore

public enum Display: Sendable, Equatable { case flex, none }
public enum Position: Sendable, Equatable { case relative, absolute }
public enum FlexWrap: Sendable, Equatable { case noWrap, wrap, wrapReverse }
public enum Overflow: Sendable, Equatable { case visible, hidden, scroll }

public enum FlexDirection: Sendable, Equatable {
    case row, rowReverse, column, columnReverse

    /// True when the main axis is horizontal.
    public var isRow: Bool { self == .row || self == .rowReverse }
    /// True when items are placed from the far end of the main axis.
    public var isReverse: Bool { self == .rowReverse || self == .columnReverse }
}

public enum AlignItems: Sendable, Equatable {
    case flexStart, flexEnd, center, baseline, stretch
}

public enum AlignSelf: Sendable, Equatable {
    case flexStart, flexEnd, center, baseline, stretch
}

public enum AlignContent: Sendable, Equatable {
    case flexStart, flexEnd, center, stretch, spaceBetween, spaceAround, spaceEvenly
}

public enum JustifyContent: Sendable, Equatable {
    case flexStart, flexEnd, center, spaceBetween, spaceAround, spaceEvenly
}

/// A node's layout inputs.
///
/// Box model is border-box only (spec §5.2): `size`, `minSize` and `maxSize`
/// include padding and border. There is deliberately no `boxSizing` property.
public struct Style: Sendable, Equatable {
    // Box
    public var display: Display = .flex
    public var position: Position = .relative
    public var inset: Edges<Dimension> = Edges(all: .auto)
    public var size: Size<Dimension> = Size(width: .auto, height: .auto)
    public var minSize: Size<Dimension> = Size(width: .auto, height: .auto)
    public var maxSize: Size<Dimension> = Size(width: .auto, height: .auto)
    public var aspectRatio: Float? = nil
    public var margin: Edges<Dimension> = Edges(all: .length(.pixels(Pixels(0))))
    public var padding: Edges<Length> = Edges(all: .pixels(Pixels(0)))
    public var border: Edges<Length> = Edges(all: .pixels(Pixels(0)))
    public var overflow: Axes<Overflow> = Axes(both: .visible)

    // As a flex container
    public var flexDirection: FlexDirection = .row
    public var flexWrap: FlexWrap = .noWrap
    public var gap: Axes<Length> = Axes(both: .pixels(Pixels(0)))
    public var justifyContent: JustifyContent? = nil
    public var alignItems: AlignItems? = nil
    public var alignContent: AlignContent? = nil

    // As a flex item
    public var flexGrow: Float = 0
    public var flexShrink: Float = 1
    public var flexBasis: Dimension = .auto
    public var alignSelf: AlignSelf? = nil

    public init() {}

    public static let `default` = Style()
}
```

Note `margin` and `inset` are `Edges<Dimension>` because both accept `auto`; `padding` and `border` are `Edges<Length>` because neither does. That asymmetry is CSS's, not ours.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter StyleTests`
Expected: PASS, 3 tests.

- [ ] **Step 6: Confirm the layering constraint holds**

```bash
grep -rnE "^import (Metal|AppKit|UIKit|MetalUIRender|MetalUIPlatform)$" \
  Sources/MetalUILayout/ && echo "LAYERING VIOLATION" || echo "clean"
```

Expected: `clean`.

The `$` anchor and the explicit module list are both load-bearing. Without them
the pattern matches the *mandatory* `import MetalUICore` by prefix and reports a
violation on correct code — a check that can never pass is as useless as one that
can never fail.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(layout): add flexbox style model with border-box sizing"
```

---

### Task 2: Cumulative rounding

**Files:**
- Create: `Sources/MetalUILayout/Rounding.swift`
- Test: `Tests/MetalUILayoutTests/RoundingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct LayoutRect { var x, y, width, height: Double }` (Sendable, Equatable) and `func roundLayout(_ rects: [LayoutRect]) -> [LayoutRect]`, which rounds using **cumulative absolute** coordinates so widths never accumulate error.

**Why this exists.** Comparing raw sub-pixel values against WebKit is impossible — it quantizes to 1/64px and the error compounds (see Global Constraints). Both the engine and the golden generator apply this identical pass; a second copy would drift.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUILayoutTests/RoundingTests.swift`:

```swift
import Testing
@testable import MetalUILayout

@Test func roundingUsesCumulativeCoordinatesSoWidthsDoNotDrift() {
    // Three children of 33.333… in a 100 row. Naive per-width rounding gives
    // 33+33+33 = 99. Cumulative rounding must recover the missing pixel.
    let input = [
        LayoutRect(x: 0,       y: 0, width: 33.3333, height: 10),
        LayoutRect(x: 33.3333, y: 0, width: 33.3333, height: 10),
        LayoutRect(x: 66.6666, y: 0, width: 33.3333, height: 10),
    ]
    let out = roundLayout(input)
    #expect(out.map(\.x) == [0, 33, 67])
    #expect(out.map(\.width) == [33, 34, 33])
    #expect(out[2].x + out[2].width == 100)   // right edge is exact
}

@Test func roundingIsIdentityOnIntegers() {
    let input = [
        LayoutRect(x: 0,   y: 0,  width: 200, height: 50),
        LayoutRect(x: 200, y: 0,  width: 400, height: 50),
    ]
    #expect(roundLayout(input) == input)
}

@Test func roundingHandlesTheMeasuredWebKitCase() {
    // 7 x flex:1 in 100px, as WebKit actually reports it (1/64 quantised).
    let w = 14.28125
    let input = (0..<7).map { LayoutRect(x: Double($0) * w, y: 0, width: w, height: 10) }
    let out = roundLayout(input)
    // Every child lands on an integer boundary and the row closes at 100.
    #expect(out.allSatisfy { $0.x == $0.x.rounded() && $0.width == $0.width.rounded() })
    #expect(out[6].x + out[6].width == 100)
    #expect(out.map(\.width).reduce(0, +) == 100)
}

@Test func roundingRoundsYIndependentlyOfX() {
    let input = [LayoutRect(x: 0.4, y: 10.6, width: 5.2, height: 3.3)]
    let out = roundLayout(input)
    #expect(out[0].x == 0)
    #expect(out[0].y == 11)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RoundingTests`
Expected: FAIL — `cannot find 'roundLayout' in scope`.

- [ ] **Step 3: Implement rounding**

Create `Sources/MetalUILayout/Rounding.swift`:

```swift
/// An absolutely-positioned box in layout coordinates.
public struct LayoutRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

/// Round a layout to whole pixels without accumulating error.
///
/// Rounding each width independently loses up to half a pixel per box, and the
/// loss compounds across siblings — three 33.333 children in a 100 row become
/// 99. Rounding the *cumulative* edges instead and taking the difference keeps
/// every boundary exact, so a row always closes on its parent.
///
/// This is Taffy's `round_layout` strategy. The engine and the golden generator
/// must both call this function — a second implementation would drift and the
/// corpus would then validate the wrong thing.
public func roundLayout(_ rects: [LayoutRect]) -> [LayoutRect] {
    rects.map { r in
        let x0 = r.x.rounded()
        let x1 = (r.x + r.width).rounded()
        let y0 = r.y.rounded()
        let y1 = (r.y + r.height).rounded()
        return LayoutRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RoundingTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(layout): add cumulative rounding shared by engine and oracle"
```

Commit **before** mutating, not after. `git checkout <file>` silently restores
nothing when the file is still untracked, so a mutation performed first can
survive into the commit — the revert appears to succeed and does nothing.

- [ ] **Step 6: Prove the test can fail**

Now that the file is tracked, temporarily replace the body with naive
per-dimension rounding and confirm the drift test reddens:

```bash
python3 - <<'PY'
p = "Sources/MetalUILayout/Rounding.swift"
s = open(p).read()
old = """        let x0 = r.x.rounded()
        let x1 = (r.x + r.width).rounded()"""
new = """        let x0 = r.x.rounded()
        let x1 = x0 + r.width.rounded()   // MUTANT: naive, drifts"""
assert old in s
open(p, "w").write(s.replace(old, new))
PY
swift test --filter RoundingTests 2>&1 | grep -c "Expectation failed"
git checkout Sources/MetalUILayout/Rounding.swift
grep -c MUTANT Sources/MetalUILayout/Rounding.swift   # must print 0
swift test --filter RoundingTests 2>&1 | tail -2
git status --short                                     # must be empty
```

Expected: a non-zero failure count while mutated, then `0` from the grep and PASS
after revert, with a clean tree. If the mutant passes, the test is not
constraining the property and must be fixed before continuing. If the grep prints
anything but `0`, the revert did not take — fix it before going further.

---

### Task 3: The WebKit oracle

**Files:**
- Modify: `Package.swift` (test target needs no new dependency; WebKit is a system framework)
- Create: `Tests/MetalUILayoutTests/Oracle/LayoutOracle.swift`
- Create: `Tests/MetalUILayoutTests/Oracle/GoldenFile.swift`
- Test: `Tests/MetalUILayoutTests/OracleTests.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_fixed_and_grow.html`

**Interfaces:**
- Consumes: `roundLayout(_:)`, `LayoutRect`.
- Produces:
  - `struct NodeBox: Sendable, Equatable, Codable { let id: String; let x, y, width, height: Double }`
  - `@MainActor final class LayoutOracle` with `init(viewport: CGSize)` and `func measure(html: String) async throws -> [NodeBox]`
  - `struct GoldenFile: Codable, Sendable, Equatable { let fixture: String; let viewport: [Double]; let raw: [NodeBox]; let rounded: [NodeBox] }`
  - `func goldenURL(fixture: String) -> URL`, `func fixtureURL(name: String) -> URL`, `func loadGolden(_ name: String) throws -> GoldenFile`

**This task is verified feasible.** A `WKWebView` in a `swift test` process lays out flexbox with no app bundle, no window, and no run-loop pumping; a `navigationDelegate` continuation plus `evaluateJavaScript` is sufficient. Do not add `XCTestExpectation`-style pumping or a `RunLoop.run` call.

- [ ] **Step 1: Add fixture resources to the test target**

In `Package.swift`, change the `MetalUILayoutTests` target to:

```swift
        .testTarget(
            name: "MetalUILayoutTests",
            dependencies: ["MetalUILayout"],
            resources: [.copy("Fixtures"), .copy("Golden")]
        ),
```

Create the `Golden` directory so the resource declaration resolves:

```bash
mkdir -p Tests/MetalUILayoutTests/Fixtures Tests/MetalUILayoutTests/Golden
touch Tests/MetalUILayoutTests/Golden/.gitkeep
```

- [ ] **Step 2: Write the first fixture**

Create `Tests/MetalUILayoutTests/Fixtures/flex_row_fixed_and_grow.html`:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  #root { display: flex; flex-direction: row; width: 700px; height: 100px; }
  .a { flex: 1 1 0; }
  .b { flex: 2 1 0; }
  .c { width: 100px; }
</style></head><body>
  <div id="root" data-id="root">
    <div class="a" data-id="a"></div>
    <div class="b" data-id="b"></div>
    <div class="c" data-id="c"></div>
  </div>
</body></html>
```

Every fixture must declare `box-sizing: border-box` — the engine implements only that model, and CSS defaults to `content-box`.

- [ ] **Step 3: Write the failing test**

Create `Tests/MetalUILayoutTests/OracleTests.swift`:

```swift
import Testing
import Foundation
@testable import MetalUILayout

@MainActor
@Test func oracleMeasuresFlexboxFromAFixtureFile() async throws {
    let html = try String(contentsOf: fixtureURL(name: "flex_row_fixed_and_grow"), encoding: .utf8)
    let oracle = LayoutOracle(viewport: CGSize(width: 800, height: 600))
    let boxes = try await oracle.measure(html: html)

    let byID = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0) })
    #expect(boxes.count == 4)

    // 700 wide, 100 fixed, 600 free split 1:2 -> 200 / 400.
    #expect(try #require(byID["root"]).width == 700)
    #expect(try #require(byID["a"]).width == 200)
    #expect(try #require(byID["b"]).width == 400)
    #expect(try #require(byID["c"]).width == 100)
    #expect(try #require(byID["a"]).x == 0)
    #expect(try #require(byID["b"]).x == 200)
    #expect(try #require(byID["c"]).x == 600)
}

@MainActor
@Test func oracleReportsSubPixelQuantization() async throws {
    // Documents WebKit's 1/64 quantisation, which is why comparisons are rounded.
    let html = """
    <!doctype html><html><head><style>
      * { box-sizing: border-box; margin: 0 } body { margin: 0 }
      #r { display: flex; width: 100px } #r > div { flex: 1 1 0 }
    </style></head><body><div id="r">\(String(repeating: "<div data-id=\"x\"></div>", count: 7))</div></body></html>
    """
    let oracle = LayoutOracle(viewport: CGSize(width: 400, height: 200))
    let boxes = try await oracle.measure(html: html)
    #expect(boxes.count == 7)
    // 100/7 = 14.2857…, quantised to 914/64 = 14.28125.
    #expect(boxes[0].width == 14.28125)
    // The row does NOT close on its parent — this is the compounding error.
    #expect(boxes[6].x + boxes[6].width == 99.96875)
}

@Test func goldenFileRoundTripsThroughJSON() throws {
    let g = GoldenFile(
        fixture: "demo",
        viewport: [800, 600],
        raw: [NodeBox(id: "root", x: 0, y: 0, width: 700, height: 100)],
        rounded: [NodeBox(id: "root", x: 0, y: 0, width: 700, height: 100)])
    let data = try JSONEncoder().encode(g)
    let back = try JSONDecoder().decode(GoldenFile.self, from: data)
    #expect(back == g)
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `swift test --filter OracleTests`
Expected: FAIL — `cannot find 'LayoutOracle' in scope`.

- [ ] **Step 5: Implement the oracle**

Create `Tests/MetalUILayoutTests/Oracle/LayoutOracle.swift`:

```swift
import Foundation
import WebKit

/// One element's border box, as the browser reports it.
public struct NodeBox: Sendable, Equatable, Codable {
    public let id: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// Lays out fixture HTML in WebKit and reads back every `[data-id]` box.
///
/// Runs headless inside `swift test` — no app bundle, no window, no run-loop
/// pumping. The navigation continuation is what makes that work.
@MainActor
public final class LayoutOracle: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    public init(viewport: CGSize) {
        webView = WKWebView(frame: CGRect(origin: .zero, size: viewport),
                            configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    public func measure(html: String) async throws -> [NodeBox] {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loaded = c
            webView.loadHTMLString(html, baseURL: nil)
        }

        let js = """
        (() => Array.from(document.querySelectorAll('[data-id]')).map(el => {
            const r = el.getBoundingClientRect();
            return { id: el.dataset.id, x: r.x, y: r.y, width: r.width, height: r.height };
        }))()
        """
        let raw = try await webView.evaluateJavaScript(js)
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.map { row in
            NodeBox(id: row["id"] as? String ?? "?",
                    x: row["x"] as? Double ?? .nan,
                    y: row["y"] as? Double ?? .nan,
                    width: row["width"] as? Double ?? .nan,
                    height: row["height"] as? Double ?? .nan)
        }
    }
}
```

- [ ] **Step 6: Implement golden-file handling**

Create `Tests/MetalUILayoutTests/Oracle/GoldenFile.swift`:

```swift
import Foundation
@testable import MetalUILayout

/// A fixture's browser-measured layout, raw and rounded.
///
/// `rounded` is what tests compare against; `raw` is kept for debugging a
/// disagreement, since it is what you would see in Safari's inspector.
public struct GoldenFile: Codable, Sendable, Equatable {
    public let fixture: String
    public let viewport: [Double]
    public let raw: [NodeBox]
    public let rounded: [NodeBox]
}

public func fixtureURL(name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "html")!
}

public func goldenURL(fixture: String) -> URL {
    Bundle.module.url(forResource: "Golden/\(fixture)", withExtension: "json")!
}

public func loadGolden(_ name: String) throws -> GoldenFile {
    try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: goldenURL(fixture: name)))
}

/// Apply the engine's rounding pass to browser output, so both sides are
/// compared in the same space.
public func roundBoxes(_ boxes: [NodeBox]) -> [NodeBox] {
    let rects = boxes.map { LayoutRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    return zip(boxes, roundLayout(rects)).map { box, r in
        NodeBox(id: box.id, x: r.x, y: r.y, width: r.width, height: r.height)
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter OracleTests`
Expected: PASS, 3 tests. The quantization test documents `14.28125` and `99.96875` — if those exact values differ on your machine, stop and report it; the tolerance design depends on them.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "test(layout): add WebKit layout oracle and golden-file format"
```

---

### Task 4: Golden generator

**Files:**
- Create: `Tests/MetalUILayoutTests/Oracle/GenerateGoldens.swift`
- Test: `Tests/MetalUILayoutTests/GeneratorTests.swift`

**Interfaces:**
- Consumes: `LayoutOracle`, `GoldenFile`, `roundBoxes(_:)`, `fixtureURL(name:)`.
- Produces: `@MainActor func generateGolden(fixture: String, viewport: CGSize) async throws -> GoldenFile` and `@MainActor func writeGolden(_ g: GoldenFile, toSourceTree root: String) throws`.

**Why a generator rather than hand-written goldens.** Hand-written expectations encode the author's belief about flexbox; browser-generated ones encode the specification as implemented. The whole point of the oracle is to remove our opinion from the ground truth.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUILayoutTests/GeneratorTests.swift`:

```swift
import Testing
import Foundation
@testable import MetalUILayout

@MainActor
@Test func generatorProducesRawAndRoundedForAFixture() async throws {
    let g = try await generateGolden(fixture: "flex_row_fixed_and_grow",
                                     viewport: CGSize(width: 800, height: 600))
    #expect(g.fixture == "flex_row_fixed_and_grow")
    #expect(g.viewport == [800, 600])
    #expect(g.raw.count == 4)
    #expect(g.rounded.count == g.raw.count)
    #expect(g.rounded.map(\.id) == g.raw.map(\.id))

    // This fixture is exact, so rounding is the identity.
    #expect(g.raw == g.rounded)
}

@MainActor
@Test func generatorRoundsWhenTheBrowserQuantizes() async throws {
    let g = try await generateGolden(fixture: "flex_row_seven_equal",
                                     viewport: CGSize(width: 400, height: 200))
    // Raw carries WebKit's 1/64 values; rounded closes the row on its parent.
    #expect(g.raw.contains { abs($0.width - 14.28125) < 1e-9 })
    let children = g.rounded.filter { $0.id != "root" }
    #expect(children.map(\.width).reduce(0, +) == 100)
}
```

- [ ] **Step 2: Add the second fixture**

Create `Tests/MetalUILayoutTests/Fixtures/flex_row_seven_equal.html`:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  #root { display: flex; flex-direction: row; width: 100px; height: 20px; }
  #root > div { flex: 1 1 0; }
</style></head><body>
  <div id="root" data-id="root">
    <div data-id="c0"></div><div data-id="c1"></div><div data-id="c2"></div>
    <div data-id="c3"></div><div data-id="c4"></div><div data-id="c5"></div>
    <div data-id="c6"></div>
  </div>
</body></html>
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter GeneratorTests`
Expected: FAIL — `cannot find 'generateGolden' in scope`.

- [ ] **Step 4: Implement the generator**

Create `Tests/MetalUILayoutTests/Oracle/GenerateGoldens.swift`:

```swift
import Foundation
import WebKit
@testable import MetalUILayout

@MainActor
public func generateGolden(fixture: String, viewport: CGSize) async throws -> GoldenFile {
    let html = try String(contentsOf: fixtureURL(name: fixture), encoding: .utf8)
    let oracle = LayoutOracle(viewport: viewport)
    let raw = try await oracle.measure(html: html)
    return GoldenFile(fixture: fixture,
                      viewport: [Double(viewport.width), Double(viewport.height)],
                      raw: raw,
                      rounded: roundBoxes(raw))
}

/// Write a golden into the *source tree*, not the build bundle, so it can be
/// committed. `root` is the package root.
public func writeGolden(_ g: GoldenFile, toSourceTree root: String) throws {
    let dir = URL(fileURLWithPath: root)
        .appendingPathComponent("Tests/MetalUILayoutTests/Golden", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(g).write(to: dir.appendingPathComponent("\(g.fixture).json"))
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter GeneratorTests`
Expected: PASS, 2 tests.

- [ ] **Step 6: Generate and commit the first two goldens**

Add a regeneration test that is normally disabled, then run it once. Append to `Tests/MetalUILayoutTests/GeneratorTests.swift`:

```swift
/// Regenerates every golden from its fixture. Disabled by default: it writes
/// into the source tree, and a golden that regenerates itself on every run
/// cannot catch a regression. Enable deliberately:
///   METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_REGENERATE_GOLDENS"] == "1"))
func regenerateAllGoldens() async throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // MetalUILayoutTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .path
    for (fixture, viewport) in allFixtures {
        let g = try await generateGolden(fixture: fixture, viewport: viewport)
        try writeGolden(g, toSourceTree: root)
    }
}

/// Every fixture in the corpus, with the viewport it is measured at.
@MainActor
let allFixtures: [(String, CGSize)] = [
    ("flex_row_fixed_and_grow", CGSize(width: 800, height: 600)),
    ("flex_row_seven_equal",    CGSize(width: 400, height: 200)),
]
```

Then run it once:

```bash
METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
ls Tests/MetalUILayoutTests/Golden/
cat Tests/MetalUILayoutTests/Golden/flex_row_fixed_and_grow.json
```

Expected: two `.json` files, the first showing widths 700/200/400/100.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test(layout): add golden generator and the first two fixtures"
```

---

### Task 5: Layout tree and the measure contract

**Files:**
- Create: `Sources/MetalUILayout/MeasureFunction.swift`
- Create: `Sources/MetalUILayout/LayoutTree.swift`
- Test: `Tests/MetalUILayoutTests/LayoutTreeTests.swift`

**Interfaces:**
- Consumes: `Style`, `LayoutRect`.
- Produces:
  - `enum AvailableSpace: Sendable, Equatable { case definite(Double), minContent, maxContent }`
  - `typealias MeasureFunction = @Sendable (_ known: OptionalSizeD, _ available: AvailableSpaceSize) -> SizeD`
  - `struct SizeD: Sendable, Equatable { var width, height: Double }`, `struct OptionalSizeD: Sendable, Equatable { var width, height: Double? }`, `struct AvailableSpaceSize: Sendable, Equatable { var width, height: AvailableSpace }`
  - `struct LayoutNodeID: Hashable, Sendable { let index: Int }`
  - `final class LayoutTree` with `newNode(style:children:) -> LayoutNodeID`, `newLeaf(style:measure:) -> LayoutNodeID`, `style(_:) -> Style`, `setStyle(_:_:)`, `children(_:) -> [LayoutNodeID]`, `measure(_:) -> MeasureFunction?`, `layout(_:) -> LayoutRect`, `setLayout(_:_:)`, `reset()`, `nodeCount: Int`

**The two-parameter measure contract is spec §5.5 and is not negotiable.** A known width of 100 obliges the leaf to *return* 100; an available width of 100 obliges it to *wrap at* 100 and return its natural width. Grid later needs "known in this axis, max-content in the other". Collapsing them breaks both.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUILayoutTests/LayoutTreeTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

@Test func treeStoresStyleAndChildren() {
    let tree = LayoutTree()
    var childStyle = Style()
    childStyle.flexGrow = 1
    let child = tree.newNode(style: childStyle, children: [])
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    let root = tree.newNode(style: rootStyle, children: [child])

    #expect(tree.nodeCount == 2)
    #expect(tree.children(root) == [child])
    #expect(tree.children(child).isEmpty)
    #expect(tree.style(child).flexGrow == 1)
    #expect(tree.style(root).flexDirection == .column)
}

@Test func leavesCarryAMeasureFunctionAndBranchesDoNot() throws {
    let tree = LayoutTree()
    let leaf = tree.newLeaf(style: Style()) { known, available in
        SizeD(width: known.width ?? 42, height: 7)
    }
    let branch = tree.newNode(style: Style(), children: [leaf])
    #expect(tree.measure(leaf) != nil)
    #expect(tree.measure(branch) == nil)

    let m = try #require(tree.measure(leaf))
    // Known width wins over available space.
    let sized = m(OptionalSizeD(width: 99, height: nil),
                  AvailableSpaceSize(width: .definite(500), height: .maxContent))
    #expect(sized.width == 99)
    #expect(sized.height == 7)
    // With no known width, the leaf returns its own natural size.
    let natural = m(OptionalSizeD(width: nil, height: nil),
                    AvailableSpaceSize(width: .maxContent, height: .maxContent))
    #expect(natural.width == 42)
}

@Test func resetClearsNodesForReuse() {
    let tree = LayoutTree()
    _ = tree.newNode(style: Style(), children: [])
    _ = tree.newNode(style: Style(), children: [])
    #expect(tree.nodeCount == 2)
    tree.reset()
    #expect(tree.nodeCount == 0)
    let fresh = tree.newNode(style: Style(), children: [])
    #expect(fresh.index == 0)   // indices restart, so the arena truly reuses storage
}

@Test func layoutResultsAreStoredPerNode() {
    let tree = LayoutTree()
    let n = tree.newNode(style: Style(), children: [])
    #expect(tree.layout(n) == LayoutRect(x: 0, y: 0, width: 0, height: 0))
    tree.setLayout(n, LayoutRect(x: 5, y: 6, width: 7, height: 8))
    #expect(tree.layout(n) == LayoutRect(x: 5, y: 6, width: 7, height: 8))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter LayoutTreeTests`
Expected: FAIL — `cannot find 'LayoutTree' in scope`.

- [ ] **Step 3: Implement the measure contract**

Create `Sources/MetalUILayout/MeasureFunction.swift`:

```swift
/// A concrete size in layout units.
public struct SizeD: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public static let zero = SizeD(width: 0, height: 0)
}

/// A size where either axis may be unknown.
public struct OptionalSizeD: Sendable, Equatable {
    public var width: Double?
    public var height: Double?
    public init(width: Double?, height: Double?) { self.width = width; self.height = height }
    /// Named `unspecified`, not `none`: a static `.none` on a non-Optional type
    /// shadows `Optional.none` at call sites and reads as "no size" rather than
    /// "both axes unknown".
    public static let unspecified = OptionalSizeD(width: nil, height: nil)
}

/// How much room a leaf may use in one axis.
public enum AvailableSpace: Sendable, Equatable {
    case definite(Double)
    /// Size to the smallest width that avoids overflow — the longest
    /// unbreakable run, for text.
    case minContent
    /// Size as if infinitely wide — a single line, for text. (Erratum 2026-09-10, TX-K: one line per hard line break.)
    case maxContent
}

public struct AvailableSpaceSize: Sendable, Equatable {
    public var width: AvailableSpace
    public var height: AvailableSpace
    public init(width: AvailableSpace, height: AvailableSpace) {
        self.width = width; self.height = height
    }
}

/// How layout asks a leaf how big it wants to be (spec §5.5).
///
/// The two parameters cannot collapse into one. A *known* width of 100 obliges
/// the leaf to return 100. An *available* width of 100 obliges it to wrap at 100
/// and report its natural width, which may be less. Grid additionally needs
/// "known in this axis, max-content in the other".
public typealias MeasureFunction = @Sendable (
    _ known: OptionalSizeD,
    _ available: AvailableSpaceSize
) -> SizeD
```

- [ ] **Step 4: Implement the tree**

Create `Sources/MetalUILayout/LayoutTree.swift`:

```swift
public struct LayoutNodeID: Hashable, Sendable {
    public let index: Int
    init(_ index: Int) { self.index = index }
}

/// Structure-of-arrays node storage, reset per layout pass.
///
/// Parallel arrays rather than a class per node: the engine walks these in tight
/// loops, and `reset()` keeps capacity so a per-frame rebuild does not
/// re-allocate. Nothing here knows what a leaf actually contains — text, images
/// and app content all arrive as a `MeasureFunction` (spec §3.1).
public final class LayoutTree {
    private var styles: [Style] = []
    private var childLists: [[LayoutNodeID]] = []
    private var measures: [MeasureFunction?] = []
    private var layouts: [LayoutRect] = []

    public init() {}

    public var nodeCount: Int { styles.count }

    public func newNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        styles.append(style)
        childLists.append(children)
        measures.append(nil)
        layouts.append(LayoutRect(x: 0, y: 0, width: 0, height: 0))
        return LayoutNodeID(styles.count - 1)
    }

    public func newLeaf(style: Style, measure: @escaping MeasureFunction) -> LayoutNodeID {
        let id = newNode(style: style, children: [])
        measures[id.index] = measure
        return id
    }

    public func style(_ id: LayoutNodeID) -> Style { styles[id.index] }
    public func setStyle(_ id: LayoutNodeID, _ s: Style) { styles[id.index] = s }
    public func children(_ id: LayoutNodeID) -> [LayoutNodeID] { childLists[id.index] }
    public func measure(_ id: LayoutNodeID) -> MeasureFunction? { measures[id.index] }
    public func layout(_ id: LayoutNodeID) -> LayoutRect { layouts[id.index] }
    public func setLayout(_ id: LayoutNodeID, _ r: LayoutRect) { layouts[id.index] = r }

    /// Drop every node but keep the allocated capacity.
    public func reset() {
        styles.removeAll(keepingCapacity: true)
        childLists.removeAll(keepingCapacity: true)
        measures.removeAll(keepingCapacity: true)
        layouts.removeAll(keepingCapacity: true)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter LayoutTreeTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(layout): add layout tree storage and the measure contract"
```

---

### Task 6: Resolving styles against a container

**Files:**
- Create: `Sources/MetalUILayout/Resolve.swift`
- Test: `Tests/MetalUILayoutTests/ResolveTests.swift`

**Interfaces:**
- Consumes: `Style`, `Length`, `Dimension` (from `MetalUICore`), `SizeD`, `OptionalSizeD`.
- Produces, all in an `extension`-free free-function style:
  - `func resolveLength(_ l: Length, against parent: Double?, rootFontSize: Double) -> Double?`
  - `func resolveDimension(_ d: Dimension, against parent: Double?, rootFontSize: Double) -> Double?`
  - `func resolveEdges(_ e: Edges<Length>, against parent: Double?, rootFontSize: Double) -> ResolvedEdges`
  - `struct ResolvedEdges: Sendable, Equatable { var top, right, bottom, left: Double; var horizontal: Double; var vertical: Double }`
  - `func clamp(_ value: Double, min: Double?, max: Double?) -> Double`

**Percentage resolution is where layout engines get subtly wrong.** A percentage resolves against the *containing block's* size in that axis, and is treated as `auto` when that size is indefinite. `rootFontSize` is fixed at 16 for now — `Rems` becomes dynamic when theming lands in M1b.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUILayoutTests/ResolveTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUILayout

@Test func lengthsResolveByKind() {
    #expect(resolveLength(.pixels(Pixels(12)), against: 400, rootFontSize: 16) == 12)
    #expect(resolveLength(.rems(Rems(2)), against: 400, rootFontSize: 16) == 32)
    #expect(resolveLength(.percent(0.25), against: 400, rootFontSize: 16) == 100)
}

@Test func percentagesAgainstAnIndefiniteParentAreUnresolvable() {
    // CSS treats a percentage against an indefinite containing block as auto.
    #expect(resolveLength(.percent(0.5), against: nil, rootFontSize: 16) == nil)
    // Absolute units do not care about the parent.
    #expect(resolveLength(.pixels(Pixels(10)), against: nil, rootFontSize: 16) == 10)
    #expect(resolveLength(.rems(Rems(1)), against: nil, rootFontSize: 16) == 16)
}

@Test func autoDimensionIsUnresolvable() {
    #expect(resolveDimension(.auto, against: 400, rootFontSize: 16) == nil)
    #expect(resolveDimension(.length(.percent(0.5)), against: 400, rootFontSize: 16) == 200)
}

@Test func edgesResolveAndSumPerAxis() {
    let e = Edges<Length>(top: .pixels(Pixels(1)), right: .pixels(Pixels(2)),
                          bottom: .pixels(Pixels(3)), left: .pixels(Pixels(4)))
    let r = resolveEdges(e, against: 100, rootFontSize: 16)
    #expect(r.top == 1 && r.right == 2 && r.bottom == 3 && r.left == 4)
    #expect(r.horizontal == 6)   // left + right
    #expect(r.vertical == 4)     // top + bottom
}

@Test func edgePercentagesResolveAgainstTheInlineAxisOnly() {
    // CSS resolves ALL padding/margin percentages against the containing
    // block's WIDTH, including the vertical ones. This surprises people.
    let e = Edges<Length>(all: .percent(0.1))
    let r = resolveEdges(e, against: 200, rootFontSize: 16)
    #expect(r.top == 20 && r.bottom == 20)
}

@Test func clampRespectsBothBounds() {
    #expect(clamp(50, min: 10, max: 100) == 50)
    #expect(clamp(5,  min: 10, max: 100) == 10)
    #expect(clamp(500, min: 10, max: 100) == 100)
    #expect(clamp(50, min: nil, max: nil) == 50)
    // min wins when the bounds conflict, per CSS.
    #expect(clamp(50, min: 200, max: 100) == 200)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ResolveTests`
Expected: FAIL — `cannot find 'resolveLength' in scope`.

- [ ] **Step 3: Implement resolution**

Create `Sources/MetalUILayout/Resolve.swift`:

```swift
import MetalUICore

public struct ResolvedEdges: Sendable, Equatable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public var horizontal: Double { left + right }
    public var vertical: Double { top + bottom }

    public static let zero = ResolvedEdges(top: 0, right: 0, bottom: 0, left: 0)
}

/// Resolve a length against its containing block.
///
/// Returns nil when the value cannot be resolved — a percentage against an
/// indefinite parent. CSS treats that as `auto`, and callers must too.
public func resolveLength(_ l: Length, against parent: Double?, rootFontSize: Double) -> Double? {
    switch l {
    case .pixels(let p): Double(p.value)
    case .rems(let r):   Double(r.value) * rootFontSize
    case .percent(let f): parent.map { Double(f) * $0 }
    }
}

public func resolveDimension(_ d: Dimension, against parent: Double?, rootFontSize: Double) -> Double? {
    switch d {
    case .auto: nil
    case .length(let l): resolveLength(l, against: parent, rootFontSize: rootFontSize)
    }
}

/// Resolve all four edges. Percentages resolve against `parent`, which callers
/// must supply as the containing block's **width** even for top and bottom —
/// that is CSS's rule, not a simplification.
public func resolveEdges(_ e: Edges<Length>, against parent: Double?, rootFontSize: Double) -> ResolvedEdges {
    func r(_ l: Length) -> Double {
        resolveLength(l, against: parent, rootFontSize: rootFontSize) ?? 0
    }
    return ResolvedEdges(top: r(e.top), right: r(e.right), bottom: r(e.bottom), left: r(e.left))
}

/// Clamp to min/max, with min taking precedence when they conflict (CSS §10.4).
public func clamp(_ value: Double, min lower: Double?, max upper: Double?) -> Double {
    var v = value
    if let upper { v = Swift.min(v, upper) }
    if let lower { v = Swift.max(v, lower) }
    return v
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ResolveTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(layout): resolve lengths, dimensions and edges against a container"
```

---

### Task 7: Single-line flex with fixed sizes

**Files:**
- Create: `Sources/MetalUILayout/FlexEngine.swift`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_row_three_fixed.html`
- Create: `Tests/MetalUILayoutTests/Fixtures/flex_column_three_fixed.html`
- Test: `Tests/MetalUILayoutTests/FlexEngineTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1, 2, 5, 6.
- Produces: `func computeLayout(_ tree: LayoutTree, root: LayoutNodeID, available: AvailableSpaceSize, rootFontSize: Double = 16) ` — mutates the tree's stored layouts in place, positions **absolute to the root**. Also `func assertMatchesGolden(_ tree: LayoutTree, root: LayoutNodeID, ids: [LayoutNodeID: String], golden: GoldenFile, tolerance: Double)` in the test target.

**Scope of this task only:** row and column, no grow/shrink, no wrap, no alignment beyond the default flex-start packing, no absolute positioning. Later tasks layer those on. Do not implement them early — each has its own fixtures and its own review.

- [ ] **Step 1: Write the two fixtures**

Create `Tests/MetalUILayoutTests/Fixtures/flex_row_three_fixed.html`:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  #root { display: flex; flex-direction: row; width: 300px; height: 50px; }
  .x { width: 60px; height: 20px; }
  .y { width: 90px; height: 30px; }
  .z { width: 40px; height: 50px; }
</style></head><body>
  <div id="root" data-id="root">
    <div class="x" data-id="x"></div>
    <div class="y" data-id="y"></div>
    <div class="z" data-id="z"></div>
  </div>
</body></html>
```

Create `Tests/MetalUILayoutTests/Fixtures/flex_column_three_fixed.html` — identical but `flex-direction: column`, `width: 120px; height: 400px` on `#root`:

```html
<!doctype html>
<html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; padding: 0; border: 0; }
  body { margin: 0; }
  #root { display: flex; flex-direction: column; width: 120px; height: 400px; }
  .x { width: 60px; height: 20px; }
  .y { width: 90px; height: 30px; }
  .z { width: 40px; height: 50px; }
</style></head><body>
  <div id="root" data-id="root">
    <div class="x" data-id="x"></div>
    <div class="y" data-id="y"></div>
    <div class="z" data-id="z"></div>
  </div>
</body></html>
```

- [ ] **Step 2: Write the failing test**

Create `Tests/MetalUILayoutTests/FlexEngineTests.swift`:

```swift
import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// Build a tree from a fixture's shape by hand, run layout, and compare every
/// node against the browser's answer for the same fixture.
// Qualified: `Foundation.Dimension` (a Measurement unit) collides with
// `MetalUICore.Dimension` once Foundation is imported, and the test file
// imports it for CGSize.
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

@Test func rowPacksFixedChildrenLeftToRight() {
    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(50))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 300, height: 50))
    #expect(tree.layout(x) == LayoutRect(x: 0,   y: 0, width: 60, height: 20))
    #expect(tree.layout(y) == LayoutRect(x: 60,  y: 0, width: 90, height: 30))
    #expect(tree.layout(z) == LayoutRect(x: 150, y: 0, width: 40, height: 50))
}

@Test func columnPacksFixedChildrenTopToBottom() {
    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(120), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(x) == LayoutRect(x: 0, y: 0,  width: 60, height: 20))
    #expect(tree.layout(y) == LayoutRect(x: 0, y: 20, width: 90, height: 30))
    #expect(tree.layout(z) == LayoutRect(x: 0, y: 50, width: 40, height: 50))
}

@MainActor
@Test func rowOfFixedChildrenMatchesWebKit() async throws {
    let golden = try await generateGolden(fixture: "flex_row_three_fixed",
                                          viewport: CGSize(width: 800, height: 600))
    let byID = Dictionary(uniqueKeysWithValues: golden.rounded.map { ($0.id, $0) })

    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(50))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    for (node, id) in [(root, "root"), (x, "x"), (y, "y"), (z, "z")] {
        let ours = tree.layout(node)
        let theirs = try #require(byID[id])
        #expect(abs(ours.x - theirs.x) <= 0.1, "\(id).x: ours \(ours.x) vs WebKit \(theirs.x)")
        #expect(abs(ours.y - theirs.y) <= 0.1, "\(id).y: ours \(ours.y) vs WebKit \(theirs.y)")
        #expect(abs(ours.width - theirs.width) <= 0.1, "\(id).w: ours \(ours.width) vs WebKit \(theirs.width)")
        #expect(abs(ours.height - theirs.height) <= 0.1, "\(id).h: ours \(ours.height) vs WebKit \(theirs.height)")
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter FlexEngineTests`
Expected: FAIL — `cannot find 'computeLayout' in scope`.

- [ ] **Step 4: Implement single-line fixed layout**

Create `Sources/MetalUILayout/FlexEngine.swift`:

```swift
import MetalUICore

/// Compute layout for `root` and every descendant, writing absolute rects into
/// the tree.
///
/// This milestone implements CSS Flexbox §9 incrementally. Right now: a single
/// line, fixed sizes, flex-start packing. Grow/shrink, alignment, wrapping and
/// absolute positioning arrive in later tasks, each with its own fixtures.
public func computeLayout(
    _ tree: LayoutTree,
    root: LayoutNodeID,
    available: AvailableSpaceSize,
    rootFontSize: Double = 16
) {
    let rootSize = resolveNodeSize(tree, root, parent: .unspecified,
                                   available: available, rootFontSize: rootFontSize)
    tree.setLayout(root, LayoutRect(x: 0, y: 0, width: rootSize.width, height: rootSize.height))
    layoutChildren(tree, root, containerOrigin: (0, 0), containerSize: rootSize,
                   rootFontSize: rootFontSize)
}

/// Resolve a node's own border-box size from its style.
private func resolveNodeSize(
    _ tree: LayoutTree,
    _ node: LayoutNodeID,
    parent: OptionalSizeD,
    available: AvailableSpaceSize,
    rootFontSize: Double
) -> SizeD {
    let s = tree.style(node)

    func axis(_ dim: Dimension, _ minDim: Dimension, _ maxDim: Dimension,
              parentExtent: Double?, availableExtent: AvailableSpace) -> Double {
        let resolved = resolveDimension(dim, against: parentExtent, rootFontSize: rootFontSize)
        let lower = resolveDimension(minDim, against: parentExtent, rootFontSize: rootFontSize)
        let upper = resolveDimension(maxDim, against: parentExtent, rootFontSize: rootFontSize)
        let base: Double
        if let resolved {
            base = resolved
        } else if case .definite(let d) = availableExtent {
            base = d
        } else {
            base = 0
        }
        return clamp(base, min: lower, max: upper)
    }

    return SizeD(
        width: axis(s.size.width, s.minSize.width, s.maxSize.width,
                    parentExtent: parent.width, availableExtent: available.width),
        height: axis(s.size.height, s.minSize.height, s.maxSize.height,
                     parentExtent: parent.height, availableExtent: available.height))
}

/// Place a container's children along its main axis, packed from the start.
private func layoutChildren(
    _ tree: LayoutTree,
    _ container: LayoutNodeID,
    containerOrigin: (Double, Double),
    containerSize: SizeD,
    rootFontSize: Double
) {
    let s = tree.style(container)
    let kids = tree.children(container)
    guard !kids.isEmpty else { return }

    let isRow = s.flexDirection.isRow
    let gap = resolveLength(isRow ? s.gap.horizontal : s.gap.vertical,
                            against: isRow ? containerSize.width : containerSize.height,
                            rootFontSize: rootFontSize) ?? 0

    var cursor: Double = 0
    for kid in kids where tree.style(kid).display != .none {
        let kidSize = resolveNodeSize(
            tree, kid,
            parent: OptionalSizeD(width: containerSize.width, height: containerSize.height),
            available: AvailableSpaceSize(width: .definite(containerSize.width),
                                          height: .definite(containerSize.height)),
            rootFontSize: rootFontSize)

        let x = containerOrigin.0 + (isRow ? cursor : 0)
        let y = containerOrigin.1 + (isRow ? 0 : cursor)
        tree.setLayout(kid, LayoutRect(x: x, y: y, width: kidSize.width, height: kidSize.height))

        layoutChildren(tree, kid, containerOrigin: (x, y), containerSize: kidSize,
                       rootFontSize: rootFontSize)

        cursor += (isRow ? kidSize.width : kidSize.height) + gap
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter FlexEngineTests`
Expected: PASS, 3 tests. The WebKit comparison is the one that matters — if the hand-written expectations pass but the browser comparison fails, trust the browser and fix the engine.

- [ ] **Step 6: Add both fixtures to the corpus list and compare the column case**

The column fixture is generated but never compared — add a WebKit comparison for
it mirroring `rowOfFixedChildrenMatchesWebKit`, or the fixture is dead weight that
proves nothing.


In `Tests/MetalUILayoutTests/GeneratorTests.swift`, extend `allFixtures`:

```swift
@MainActor
let allFixtures: [(String, CGSize)] = [
    ("flex_row_fixed_and_grow", CGSize(width: 800, height: 600)),
    ("flex_row_seven_equal",    CGSize(width: 400, height: 200)),
    ("flex_row_three_fixed",    CGSize(width: 800, height: 600)),
    ("flex_column_three_fixed", CGSize(width: 800, height: 600)),
]
```

Regenerate and commit the goldens:

```bash
METALUI_REGENERATE_GOLDENS=1 swift test --filter regenerateAllGoldens
ls Tests/MetalUILayoutTests/Golden/
```

Expected: four `.json` files.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(layout): single-line flex with fixed sizes, verified against WebKit"
```

---

## Milestone 1a exit criteria

All must hold before starting the grow/shrink work:

- [ ] `swift test` passes with no warnings
- [ ] `rm -rf .build && swift build` emits no warnings and no "unhandled files"
- [ ] `MetalUILayout` imports neither Metal, AppKit, nor `MetalUIRender` (Task 1 Step 6)
- [ ] Four goldens are committed and were browser-generated, not hand-written
- [ ] `roundLayout` has been demonstrated to fail under naive per-dimension rounding (Task 2 Step 5)
- [ ] Every fixture's CSS declares `box-sizing: border-box`

## What comes next, and is deliberately NOT in this plan

Each is its own task group with its own fixtures, added on top of Task 7:

- **Flex base size and the freeze loop** — `flex-grow`, `flex-shrink`, `flex-basis`, the §9.7 resolve-flexible-lengths algorithm
- **Alignment** — `justify-content`, `align-items`, `align-self`, `align-content`
- **Multi-line** — `flex-wrap`, line collection, cross-axis stacking
- **Absolute positioning** — `position: absolute` against the padding box
- **Automatic minimum size** — `min-width: auto` (spec §5.2 requires it in v1)
- **Aspect ratio**, `min`/`max` interaction with flexing
- **`MeasureCache`** — the correctness-guarding key from spec §5.6, once leaves exist to measure
- **Grid** — a separate plan entirely

Also deliberately deferred, from M0's carried debt: gating the ABI probe on an env var (no CI exists yet), making the shared header a tracked build input, and replacing the pixel-format constant pin with a blend-readback guard. None of them block layout work.
