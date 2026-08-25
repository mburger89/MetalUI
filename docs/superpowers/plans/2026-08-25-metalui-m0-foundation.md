# MetalUI Milestone 0 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS window that displays one GPU-rendered rounded rectangle with a border, drawn by an analytic SDF shader compiled at runtime, on a frame loop that idles at zero cost.

**Architecture:** Seven SwiftPM targets with one-way dependencies. Shared CPU/GPU struct layouts live in a single C header that is simultaneously a C include (via a symlink into the C target) and a runtime resource (copied with the Metal source). Shaders compile at app start with `MTLDevice.makeLibrary(source:)` because SwiftPM cannot compile `.metal` files. A GPU-side probe kernel asserts that Metal's view of every shared struct matches Swift's.

**Tech Stack:** Swift 6.3 (language mode v6, strict concurrency), Metal, AppKit, Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` — read §3 (module architecture), §7.1–7.3 (primitives, shader build, batching), §7.8 (color) before starting.

## Global Constraints

- **Swift tools version 6.3**, `swiftLanguageModes: [.v6]`. Strict concurrency is on; every concurrency warning is an error to fix, never to suppress.
- **No third-party dependencies. No `.unsafeFlags`.** The package must stay consumable as an ordinary SwiftPM dependency (spec §2).
- **v1 platforms are macOS and iOS.** M0 implements macOS only; do not add tvOS or visionOS code.
- **Compositing is gamma-encoded sRGB** (spec §7.8). Drawable pixel format is **`bgra8Unorm`**, never `bgra8Unorm_srgb` — an `_sRGB` target blends in linear space, which is the opposite of the decision. No linearization anywhere in the composite path.
- **Box model is `border-box`** (spec §5.2). Not exercised in M0 but do not write code assuming otherwise.
- **Typed units never implicitly convert.** Mixing `Pixels` and `DevicePixels` must be a compile error (spec §5.3). Do not conform unit types to `Numeric` — that would permit `Pixels * Pixels`.
- **UI types are `@MainActor`.** GPU primitive structs are plain data and `Sendable`.
- **One physical definition of every shared struct.** `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` is the real file; the C target's `include/` holds a **symlink** to it. Never create a second copy.

### Editing the shared header requires a clean build

**Verified on this machine.** Editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`
and running an ordinary `swift build` **does** re-copy the resource bundle
(`[1/2] Copying Shaders`), so the Metal side — compiled at runtime from that
bundle — sees the edit. **Swift's view of the C struct does not rebuild**: nothing
records a dependency on the header, because `shim.c` does not include it, so no
`.d` entry exists.

Consequence: any assertion about Swift-side values from that header — struct
layout, enum raw values — is untrustworthy after an incremental build. **Always
`rm -rf .build` before trusting a result that depends on a header edit**, and
never conclude a header-drift test is vacuous from an incremental run.

Adding `#include "MetalUIShaderTypes.h"` to `shim.c` was tried and does trigger a
rebuild, but the Swift-visible value was still stale, so it is not a fix and must
not be applied.

### Verified environment facts

These were confirmed on this machine (Swift 6.3.3, Xcode 27.0, macOS 26.6.2). Do not re-litigate them:

- SwiftPM's default build system **does not compile `.metal` files**. It emits `warning: found N file(s) which are unhandled`, reports `Build complete!`, and produces **no `.metallib`**. Declaring the file in `sources:` is a hard `error: unexpected input file`.
- `xcrun metal` is **absent by default** on Xcode 26/27 (`missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain`).
- `device.makeLibrary(source:options:)` **works with no Metal toolchain installed**.
- `MTLCompileOptions` has **no include search path**. `#include` from runtime-compiled source must not be relied on; prepend the header text instead.
- `resources: [.copy("Shaders")]` copies the **directory**, preserving `Shaders/` in the bundle. `.copy("Shaders/file.h")` **flattens** it to the bundle root. Look up resources accordingly.
- A symlink inside a copied resource directory is copied **as a symlink**, and its relative target does not resolve inside the bundle. This is why the real header lives with the shaders and the symlink points the other way.
- Swift imports the C struct directly, so **C↔Swift layout drift is impossible** — it is caught by the compiler. The runtime probe exists to catch **MSL↔C** divergence.

---

### Task 1: Package skeleton and geometry primitives

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MetalUICore/Geometry.swift`
- Delete: `Sources/MetalUI/MetalUI.swift`, `Tests/MetalUITests/MetalUITests.swift`
- Test: `Tests/MetalUICoreTests/GeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Point<Unit>`, `Size<Unit>`, `Bounds<Unit>`, `Edges<Unit>`, `Corners<Unit>`, `Axes<T>`, each with a memberwise `init` and conditional `Equatable`/`Hashable`/`Sendable`. `Bounds` exposes `minX/minY/maxX/maxY` and `contains(_:)` where `Unit: Comparable & AdditiveArithmetic`.

- [ ] **Step 1: Replace `Package.swift` with the target skeleton**

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MetalUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MetalUI", targets: ["MetalUI"]),
    ],
    targets: [
        .target(name: "MetalUICore"),
        .testTarget(name: "MetalUICoreTests", dependencies: ["MetalUICore"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Remove the template sources**

```bash
rm -rf Sources/MetalUI Tests/MetalUITests
mkdir -p Sources/MetalUICore Tests/MetalUICoreTests
```

- [ ] **Step 3: Write the failing test**

Create `Tests/MetalUICoreTests/GeometryTests.swift`:

```swift
import Testing
@testable import MetalUICore

@Test func boundsExposesEdges() {
    let b = Bounds(origin: Point(x: 10.0, y: 20.0), size: Size(width: 30.0, height: 40.0))
    #expect(b.minX == 10.0)
    #expect(b.minY == 20.0)
    #expect(b.maxX == 40.0)
    #expect(b.maxY == 60.0)
}

@Test func boundsContainsIsHalfOpen() {
    let b = Bounds(origin: Point(x: 0.0, y: 0.0), size: Size(width: 10.0, height: 10.0))
    #expect(b.contains(Point(x: 0.0, y: 0.0)))
    #expect(b.contains(Point(x: 9.99, y: 9.99)))
    #expect(!b.contains(Point(x: 10.0, y: 5.0)))   // max edge excluded
    #expect(!b.contains(Point(x: -0.01, y: 5.0)))
}

@Test func edgesAndCornersAreUniformConstructible() {
    #expect(Edges(all: 4.0) == Edges(top: 4.0, right: 4.0, bottom: 4.0, left: 4.0))
    #expect(Corners(all: 6.0) == Corners(topLeft: 6.0, topRight: 6.0, bottomRight: 6.0, bottomLeft: 6.0))
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `swift test --filter GeometryTests`
Expected: FAIL — `cannot find 'Bounds' in scope`.

- [ ] **Step 5: Implement the geometry types**

Create `Sources/MetalUICore/Geometry.swift`:

```swift
/// A point in a coordinate space parameterised by its unit type.
/// The `Unit` parameter is what prevents mixing logical and device pixels.
public struct Point<Unit> {
    public var x: Unit
    public var y: Unit
    public init(x: Unit, y: Unit) { self.x = x; self.y = y }
}

public struct Size<Unit> {
    public var width: Unit
    public var height: Unit
    public init(width: Unit, height: Unit) { self.width = width; self.height = height }
}

public struct Bounds<Unit> {
    public var origin: Point<Unit>
    public var size: Size<Unit>
    public init(origin: Point<Unit>, size: Size<Unit>) { self.origin = origin; self.size = size }
}

public struct Edges<Unit> {
    public var top: Unit
    public var right: Unit
    public var bottom: Unit
    public var left: Unit
    public init(top: Unit, right: Unit, bottom: Unit, left: Unit) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }
    public init(all v: Unit) { self.init(top: v, right: v, bottom: v, left: v) }
}

public struct Corners<Unit> {
    public var topLeft: Unit
    public var topRight: Unit
    public var bottomRight: Unit
    public var bottomLeft: Unit
    public init(topLeft: Unit, topRight: Unit, bottomRight: Unit, bottomLeft: Unit) {
        self.topLeft = topLeft; self.topRight = topRight
        self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
    }
    public init(all v: Unit) { self.init(topLeft: v, topRight: v, bottomRight: v, bottomLeft: v) }
}

public struct Axes<T> {
    public var horizontal: T
    public var vertical: T
    public init(horizontal: T, vertical: T) { self.horizontal = horizontal; self.vertical = vertical }
    public init(both v: T) { self.init(horizontal: v, vertical: v) }
}

extension Point: Equatable where Unit: Equatable {}
extension Point: Hashable where Unit: Hashable {}
extension Point: Sendable where Unit: Sendable {}
extension Size: Equatable where Unit: Equatable {}
extension Size: Hashable where Unit: Hashable {}
extension Size: Sendable where Unit: Sendable {}
extension Bounds: Equatable where Unit: Equatable {}
extension Bounds: Hashable where Unit: Hashable {}
extension Bounds: Sendable where Unit: Sendable {}
extension Edges: Equatable where Unit: Equatable {}
extension Edges: Hashable where Unit: Hashable {}
extension Edges: Sendable where Unit: Sendable {}
extension Corners: Equatable where Unit: Equatable {}
extension Corners: Hashable where Unit: Hashable {}
extension Corners: Sendable where Unit: Sendable {}
extension Axes: Equatable where T: Equatable {}
extension Axes: Sendable where T: Sendable {}

extension Bounds where Unit: AdditiveArithmetic {
    public var minX: Unit { origin.x }
    public var minY: Unit { origin.y }
    public var maxX: Unit { origin.x + size.width }
    public var maxY: Unit { origin.y + size.height }
}

extension Bounds where Unit: AdditiveArithmetic & Comparable {
    /// Half-open on the max edges, so adjacent bounds never both contain a point.
    public func contains(_ p: Point<Unit>) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `swift test --filter GeometryTests`
Expected: PASS, 3 tests.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(core): add geometry primitives and package skeleton"
```

---

### Task 2: Typed units

**Files:**
- Create: `Sources/MetalUICore/Units.swift`
- Test: `Tests/MetalUICoreTests/UnitsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Pixels`, `ScaledPixels`, `Rems` — each `Hashable`, `Comparable`, `Sendable`, `AdditiveArithmetic`, `ExpressibleByFloatLiteral`, `ExpressibleByIntegerLiteral`, with `*`/`/` by `Float`. **`DevicePixels` is deliberately narrower** — `Hashable`, `Comparable`, `Sendable` only. It wraps `Int32` because physical pixels are integral, so float literals and `* Float` are meaningless on it and must not compile. `Pixels.scaled(by:) -> ScaledPixels`. Enums `Length` (`.pixels`/`.rems`/`.percent`) and `Dimension` (`.length`/`.auto`).

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUICoreTests/UnitsTests.swift`:

```swift
import Testing
@testable import MetalUICore

@Test func pixelsSupportAdditiveArithmeticAndLiterals() {
    let a: Pixels = 10
    let b: Pixels = 2.5
    #expect((a + b).value == 12.5)
    #expect((a - b).value == 7.5)
    #expect(Pixels.zero.value == 0)
}

@Test func pixelsScaleByFloat() {
    let a: Pixels = 10
    #expect((a * 2.0).value == 20.0)
    #expect((a / 4.0).value == 2.5)
}

@Test func pixelsScaleIntoScaledPixels() {
    let a: Pixels = 10
    #expect(a.scaled(by: 2.0) == ScaledPixels(20))
}

@Test func unitsCompare() {
    #expect(Pixels(1) < Pixels(2))
    #expect(ScaledPixels(3) > ScaledPixels(2))
}

@Test func dimensionAndLengthAreDistinct() {
    #expect(Dimension.auto != Dimension.length(.pixels(10)))
    #expect(Length.percent(0.5) != Length.pixels(0.5))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter UnitsTests`
Expected: FAIL — `cannot find 'Pixels' in scope`.

- [ ] **Step 3: Implement the units**

Create `Sources/MetalUICore/Units.swift`:

```swift
/// Boilerplate shared by every scalar unit. Deliberately NOT `Numeric`:
/// `Pixels * Pixels` is meaningless and must not compile.
public protocol ScalarUnit: Hashable, Comparable, Sendable, AdditiveArithmetic,
                            ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    var value: Float { get set }
    init(_ value: Float)
}

extension ScalarUnit {
    public init(floatLiteral v: Double) { self.init(Float(v)) }
    public init(integerLiteral v: Int) { self.init(Float(v)) }
    public static var zero: Self { Self(0) }
    public static func < (l: Self, r: Self) -> Bool { l.value < r.value }
    public static func + (l: Self, r: Self) -> Self { Self(l.value + r.value) }
    public static func - (l: Self, r: Self) -> Self { Self(l.value - r.value) }
    public static func * (l: Self, r: Float) -> Self { Self(l.value * r) }
    public static func / (l: Self, r: Float) -> Self { Self(l.value / r) }
    public static prefix func - (v: Self) -> Self { Self(-v.value) }
}

/// Logical points, as the windowing system reports them.
public struct Pixels: ScalarUnit {
    public var value: Float
    public init(_ value: Float) { self.value = value }
    /// Convert to the render target's coordinate space.
    public func scaled(by factor: Float) -> ScaledPixels { ScaledPixels(value * factor) }
}

/// Logical points multiplied by the display scale factor. What shaders see.
public struct ScaledPixels: ScalarUnit {
    public var value: Float
    public init(_ value: Float) { self.value = value }
}

/// Physical device pixels, always integral.
public struct DevicePixels: Hashable, Comparable, Sendable {
    public var value: Int32
    public init(_ value: Int32) { self.value = value }
    public static func < (l: Self, r: Self) -> Bool { l.value < r.value }
}

/// Sizes relative to the root font size.
public struct Rems: ScalarUnit {
    public var value: Float
    public init(_ value: Float) { self.value = value }
}

/// A value that is always required. Has no `auto` case — see `Dimension`.
public enum Length: Hashable, Sendable {
    case pixels(Pixels)
    case rems(Rems)
    case percent(Float)
}

/// A sizing value, which may be automatic.
public enum Dimension: Hashable, Sendable {
    case length(Length)
    case auto
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter UnitsTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Verify units genuinely do not mix**

Create a scratch file and confirm it does NOT compile:

```bash
cat > /tmp/mixcheck.swift <<'EOF'
import MetalUICore
let bad = Pixels(1) + ScaledPixels(1)
EOF
swiftc -typecheck -I .build/debug/Modules /tmp/mixcheck.swift 2>&1 | grep -q "error" \
  && echo "GOOD: units do not mix" || echo "BAD: units mixed silently"
```

Expected: `GOOD: units do not mix`. Then `rm /tmp/mixcheck.swift`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(core): add typed units with no implicit conversion"
```

---

### Task 3: Color

**Files:**
- Create: `Sources/MetalUICore/Color.swift`
- Test: `Tests/MetalUICoreTests/ColorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Hsla` (`h`, `s`, `l`, `a` as `Float`, hue normalised 0–1), `Rgba` (`r`, `g`, `b`, `a`), `Hsla.toRgba()`, `Rgba.toHsla()`, statics `.white`, `.black`, `.transparent`, and `Hsla.rgb(_ hex: UInt32)`.

**Note:** These are **gamma-encoded sRGB** values throughout, per spec §7.8. There is no linearization here and none should be added.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUICoreTests/ColorTests.swift`:

```swift
import Testing
@testable import MetalUICore

private func close(_ a: Float, _ b: Float, _ tol: Float = 0.001) -> Bool { abs(a - b) < tol }

@Test func hslaToRgbaPrimaries() {
    let red = Hsla(h: 0, s: 1, l: 0.5, a: 1).toRgba()
    #expect(close(red.r, 1) && close(red.g, 0) && close(red.b, 0))

    let green = Hsla(h: 1.0 / 3.0, s: 1, l: 0.5, a: 1).toRgba()
    #expect(close(green.r, 0) && close(green.g, 1) && close(green.b, 0))

    let blue = Hsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1).toRgba()
    #expect(close(blue.r, 0) && close(blue.g, 0) && close(blue.b, 1))
}

@Test func hslaGreyscaleHasNoHue() {
    let grey = Hsla(h: 0.25, s: 0, l: 0.5, a: 1).toRgba()
    #expect(close(grey.r, 0.5) && close(grey.g, 0.5) && close(grey.b, 0.5))
}

@Test func hexRoundTripsThroughHsla() {
    let c = Hsla.rgb(0x3366CC).toRgba()
    #expect(close(c.r, 0x33 / 255.0))
    #expect(close(c.g, 0x66 / 255.0))
    #expect(close(c.b, 0xCC / 255.0))
}

@Test func rgbaToHslaRoundTrips() {
    let original = Rgba(r: 0.2, g: 0.6, b: 0.9, a: 1)
    let back = original.toHsla().toRgba()
    #expect(close(back.r, original.r) && close(back.g, original.g) && close(back.b, original.b))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ColorTests`
Expected: FAIL — `cannot find 'Hsla' in scope`.

- [ ] **Step 3: Implement colors**

Create `Sources/MetalUICore/Color.swift`:

```swift
import Foundation

/// Gamma-encoded sRGB, expressed as HSLA. Hue is normalised to 0..<1.
/// The compositor works in this space directly (spec §7.8) — do not linearize.
public struct Hsla: Hashable, Sendable {
    public var h: Float
    public var s: Float
    public var l: Float
    public var a: Float
    public init(h: Float, s: Float, l: Float, a: Float = 1) {
        self.h = h; self.s = s; self.l = l; self.a = a
    }

    public static let white = Hsla(h: 0, s: 0, l: 1, a: 1)
    public static let black = Hsla(h: 0, s: 0, l: 0, a: 1)
    public static let transparent = Hsla(h: 0, s: 0, l: 0, a: 0)

    public static func rgb(_ hex: UInt32, alpha: Float = 1) -> Hsla {
        Rgba(r: Float((hex >> 16) & 0xFF) / 255,
             g: Float((hex >> 8) & 0xFF) / 255,
             b: Float(hex & 0xFF) / 255,
             a: alpha).toHsla()
    }

    public func toRgba() -> Rgba {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Float, Float, Float) =
            switch hp {
            case ..<1: (c, x, 0)
            case ..<2: (x, c, 0)
            case ..<3: (0, c, x)
            case ..<4: (0, x, c)
            case ..<5: (x, 0, c)
            default:   (c, 0, x)
            }
        return Rgba(r: r + m, g: g + m, b: b + m, a: a)
    }
}

/// Gamma-encoded sRGB components in 0...1.
public struct Rgba: Hashable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
    public init(r: Float, g: Float, b: Float, a: Float = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public func toHsla() -> Hsla {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let l = (maxC + minC) / 2

        guard delta > 0 else { return Hsla(h: 0, s: 0, l: l, a: a) }

        let s = delta / (1 - abs(2 * l - 1))
        var h: Float
        if maxC == r {
            h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h /= 6
        if h < 0 { h += 1 }
        return Hsla(h: h, s: s, l: l, a: a)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ColorTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(core): add HSLA/RGBA colors in gamma-encoded sRGB"
```

---

### Task 4: Shared shader types header and the C target

**Files:**
- Create: `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` (the one real definition)
- Create: `Sources/MetalUIShaderTypes/include/MetalUIShaderTypes.h` (**symlink** to the above)
- Create: `Sources/MetalUIShaderTypes/shim.c`
- Create: `Sources/MetalUIRender/ShaderTypesBridge.swift`
- Modify: `Package.swift`
- Test: `Tests/MetalUIRenderTests/ShaderTypesTests.swift`

**Interfaces:**
- Consumes: `MetalUICore` (`Bounds`, `Corners`, `Edges`, `Hsla`, `ScaledPixels`).
- Produces: C structs `MUIPoint`, `MUISize`, `MUIBounds`, `MUIHsla`, `MUICorners`, `MUIEdges`, `MUIRect`; buffer-index enums `MUIRectBufferIndex`, `MUIProbeBufferIndex`. Swift-side converter `MUIRect.init(bounds:contentMask:background:borderColor:cornerRadii:borderWidths:order:)` taking `MetalUICore` types in `ScaledPixels`.

**The layout is the important part of this task.** The header must be readable by clang (for Swift's import) *and* copyable into the resource bundle (for runtime shader compilation). A symlink inside a copied resource directory does not resolve in the bundle, so the **real file lives with the shaders** and the C target symlinks to it — clang resolves that in-tree at build time.

- [ ] **Step 1: Create the directory layout and the symlink**

```bash
mkdir -p Sources/MetalUIRender/Shaders Sources/MetalUIShaderTypes/include Tests/MetalUIRenderTests
# Real file lives with the shaders (so `.copy("Shaders")` bundles it).
touch Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h
# C target sees it through a symlink, resolved in-tree by clang.
ln -sf ../../MetalUIRender/Shaders/MetalUIShaderTypes.h \
       Sources/MetalUIShaderTypes/include/MetalUIShaderTypes.h
echo 'void _metalui_shader_types_shim(void) {}' > Sources/MetalUIShaderTypes/shim.c
ls -l Sources/MetalUIShaderTypes/include/
```

Expected: `MetalUIShaderTypes.h -> ../../MetalUIRender/Shaders/MetalUIShaderTypes.h`

- [ ] **Step 2: Write the header**

Write `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`:

```c
#ifndef METALUI_SHADER_TYPES_H
#define METALUI_SHADER_TYPES_H

// This file is compiled two ways:
//   1. by clang, via a symlink in MetalUIShaderTypes/include, so Swift imports these structs
//   2. by the Metal compiler at runtime, textually prepended to shaders.metal
// Guard anything that only one of them understands.

#ifndef __METAL_VERSION__
#include <stdint.h>
typedef uint32_t MUIUInt;
#else
typedef uint MUIUInt;
#endif

typedef struct { float x, y; } MUIPoint;
typedef struct { float width, height; } MUISize;
typedef struct { MUIPoint origin; MUISize size; } MUIBounds;
typedef struct { float h, s, l, a; } MUIHsla;
typedef struct { float topLeft, topRight, bottomRight, bottomLeft; } MUICorners;
typedef struct { float top, right, bottom, left; } MUIEdges;

// All geometry is in ScaledPixels (logical points x display scale), matching
// the fragment shader's [[position]], which is in render-target pixels.
typedef struct {
    MUIBounds bounds;
    MUIBounds contentMask;
    MUIHsla background;
    MUIHsla borderColor;
    MUICorners cornerRadii;
    MUIEdges borderWidths;
    MUIUInt order;
    MUIUInt _reserved;
} MUIRect;

typedef enum {
    MUIRectBufferVertices = 0,
    MUIRectBufferRects    = 1,
    MUIRectBufferViewport = 2
} MUIRectBufferIndex;

typedef enum {
    MUIProbeBufferOut  = 0,
    MUIProbeBufferRect = 1
} MUIProbeBufferIndex;

#endif
```

- [ ] **Step 3: Wire the targets in `Package.swift`**

Replace the `targets:` array:

```swift
    targets: [
        .target(name: "MetalUICore"),
        .testTarget(name: "MetalUICoreTests", dependencies: ["MetalUICore"]),

        .target(name: "MetalUIShaderTypes"),

        .target(
            name: "MetalUIRender",
            dependencies: ["MetalUICore", "MetalUIShaderTypes"],
            resources: [.copy("Shaders")]
        ),
        .testTarget(name: "MetalUIRenderTests", dependencies: ["MetalUIRender"]),
    ],
```

- [ ] **Step 4: Write the failing test**

Create `Tests/MetalUIRenderTests/ShaderTypesTests.swift`:

```swift
import Testing
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

@Test func rectConvertsFromCoreTypes() {
    let r = MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(10), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(30), height: ScaledPixels(40))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: Hsla(h: 0.5, s: 0.4, l: 0.3, a: 1),
        borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(6)),
        borderWidths: Edges(all: ScaledPixels(2)),
        order: 3)

    #expect(r.bounds.origin.x == 10)
    #expect(r.bounds.size.height == 40)
    #expect(r.cornerRadii.bottomLeft == 6)
    #expect(r.borderWidths.top == 2)
    #expect(r.background.h == 0.5)
    #expect(r.borderColor.l == 1)
    #expect(r.order == 3)
}

@Test func bufferIndicesAreStable() {
    // These are contract with the shader; changing them silently breaks binding.
    #expect(MUIRectBufferVertices.rawValue == 0)
    #expect(MUIRectBufferRects.rawValue == 1)
    #expect(MUIRectBufferViewport.rawValue == 2)
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `swift test --filter ShaderTypesTests`
Expected: FAIL — no matching `MUIRect` initializer.

- [ ] **Step 6: Implement the Swift bridge**

Create `Sources/MetalUIRender/ShaderTypesBridge.swift`:

```swift
import MetalUICore
@_exported import MetalUIShaderTypes

extension MUIPoint {
    init(_ p: Point<ScaledPixels>) { self.init(x: p.x.value, y: p.y.value) }
}

extension MUISize {
    init(_ s: Size<ScaledPixels>) { self.init(width: s.width.value, height: s.height.value) }
}

extension MUIBounds {
    init(_ b: Bounds<ScaledPixels>) { self.init(origin: MUIPoint(b.origin), size: MUISize(b.size)) }
}

extension MUIHsla {
    init(_ c: Hsla) { self.init(h: c.h, s: c.s, l: c.l, a: c.a) }
}

extension MUICorners {
    init(_ c: Corners<ScaledPixels>) {
        self.init(topLeft: c.topLeft.value, topRight: c.topRight.value,
                  bottomRight: c.bottomRight.value, bottomLeft: c.bottomLeft.value)
    }
}

extension MUIEdges {
    init(_ e: Edges<ScaledPixels>) {
        self.init(top: e.top.value, right: e.right.value,
                  bottom: e.bottom.value, left: e.left.value)
    }
}

extension MUIRect {
    /// Build a GPU rect from framework types. All geometry must already be scaled.
    public init(
        bounds: Bounds<ScaledPixels>,
        contentMask: Bounds<ScaledPixels>,
        background: Hsla,
        borderColor: Hsla,
        cornerRadii: Corners<ScaledPixels>,
        borderWidths: Edges<ScaledPixels>,
        order: UInt32
    ) {
        self.init(bounds: MUIBounds(bounds),
                  contentMask: MUIBounds(contentMask),
                  background: MUIHsla(background),
                  borderColor: MUIHsla(borderColor),
                  cornerRadii: MUICorners(cornerRadii),
                  borderWidths: MUIEdges(borderWidths),
                  order: order,
                  _reserved: 0)
    }
}

```

**No `Sendable` extension is needed.** Swift 6 already imports an all-trivial C
struct as `Sendable`, verified cross-module. Declaring
`extension MUIRect: @unchecked Sendable {}` compiles but emits a
retroactive-conformance warning, and `@unchecked` would opt the type out of real
future checking. If a field is ever added that defeats the inference, annotate the
C struct at its single definition site with
`__attribute__((swift_attr("@Sendable")))` behind an `__has_attribute` guard —
never a Swift-side unchecked extension.

- [ ] **Step 7: Run the test to verify it passes**

Run: `swift test --filter ShaderTypesTests`
Expected: PASS, 2 tests.

- [ ] **Step 8: Confirm the header reached the resource bundle unbroken**

```bash
swift build
find .build -path '*MetalUI_MetalUIRender.bundle*' -name '*.h' -exec head -3 {} \;
```

Expected: prints the `#ifndef METALUI_SHADER_TYPES_H` guard. If it prints nothing, the symlink direction is wrong — the real file must be under `Shaders/`.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(render): add shared CPU/GPU shader types with single-definition layout"
```

---

### Task 5: Metal shader source

**Files:**
- Create: `Sources/MetalUIRender/Shaders/shaders.metal`

**Interfaces:**
- Consumes: the structs from Task 4 (prepended at runtime, not `#include`d).
- Produces: `rect_vertex`, `rect_fragment`, `abi_probe`.

**No test in this task** — the shader cannot be compiled until Task 6 provides the loader. Task 6 and Task 7 test it.

- [ ] **Step 1: Write the shader**

Create `Sources/MetalUIRender/Shaders/shaders.metal`:

```metal
// MetalUIShaderTypes.h is textually prepended by ShaderLibrary before compilation.
// Do NOT add an #include for it: MTLCompileOptions has no include search path.

#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Signed distance to a rounded box centred at the origin.
/// Negative inside, positive outside, in the same units as `p`.
static float rect_sdf(float2 p, float2 halfSize, float radius) {
    float2 d = abs(p) - halfSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

/// Radius of the corner nearest to `centerToPoint`.
static float pick_corner_radius(float2 centerToPoint, MUICorners radii) {
    if (centerToPoint.x < 0.0) {
        return centerToPoint.y < 0.0 ? radii.topLeft : radii.bottomLeft;
    }
    return centerToPoint.y < 0.0 ? radii.topRight : radii.bottomRight;
}

/// HSLA to gamma-encoded sRGB. No linearization: the compositor works in this
/// space directly (spec 7.8).
static float4 hsla_to_srgba(MUIHsla hsla) {
    float h = hsla.h * 6.0;
    float c = (1.0 - fabs(2.0 * hsla.l - 1.0)) * hsla.s;
    float x = c * (1.0 - fabs(fmod(h, 2.0) - 1.0));
    float m = hsla.l - c / 2.0;

    float3 rgb;
    if      (h < 1.0) rgb = float3(c, x, 0.0);
    else if (h < 2.0) rgb = float3(x, c, 0.0);
    else if (h < 3.0) rgb = float3(0.0, c, x);
    else if (h < 4.0) rgb = float3(0.0, x, c);
    else if (h < 5.0) rgb = float3(x, 0.0, c);
    else              rgb = float3(c, 0.0, x);

    return float4(rgb + m, hsla.a);
}

// ---------------------------------------------------------------------------
// Rect pipeline
// ---------------------------------------------------------------------------

struct RectVertexOut {
    float4 position [[position]];
    uint   rectID   [[flat]];
};

vertex RectVertexOut rect_vertex(
    uint vertexID   [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float2  *unitVertices [[buffer(MUIRectBufferVertices)]],
    constant MUIRect *rects        [[buffer(MUIRectBufferRects)]],
    constant MUISize &viewport     [[buffer(MUIRectBufferViewport)]]
) {
    float2 unit = unitVertices[vertexID];
    MUIRect r = rects[instanceID];

    float2 pos = float2(r.bounds.origin.x, r.bounds.origin.y)
               + unit * float2(r.bounds.size.width, r.bounds.size.height);

    // Pixel space (y down) to normalised device coordinates (y up).
    float2 ndc = pos / float2(viewport.width, viewport.height) * float2(2.0, -2.0)
               + float2(-1.0, 1.0);

    RectVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.rectID = instanceID;
    return out;
}

fragment float4 rect_fragment(
    RectVertexOut in [[stage_in]],
    constant MUIRect *rects [[buffer(MUIRectBufferRects)]]
) {
    MUIRect r = rects[in.rectID];

    float2 halfSize = float2(r.bounds.size.width, r.bounds.size.height) * 0.5;
    float2 center   = float2(r.bounds.origin.x, r.bounds.origin.y) + halfSize;
    float2 p        = in.position.xy - center;

    float radius = pick_corner_radius(p, r.cornerRadii);

    // Outer edge coverage. 0.5 is half a pixel: the antialiasing threshold.
    float outerAlpha = saturate(0.5 - rect_sdf(p, halfSize, radius));

    // Inner edge separates border from background.
    float2 border = float2(p.x < 0.0 ? r.borderWidths.left : r.borderWidths.right,
                           p.y < 0.0 ? r.borderWidths.top  : r.borderWidths.bottom);
    float innerRadius = max(radius - max(border.x, border.y), 0.0);
    float innerAlpha = saturate(0.5 - rect_sdf(p, max(halfSize - border, 0.0), innerRadius));

    float4 background  = hsla_to_srgba(r.background);
    float4 borderColor = hsla_to_srgba(r.borderColor);
    float4 color = mix(borderColor, background, innerAlpha);

    // Premultiplied output, to pair with a (one, oneMinusSourceAlpha) blend.
    return float4(color.rgb * color.a, color.a) * outerAlpha;
}

// ---------------------------------------------------------------------------
// ABI probe
//
// Reports Metal's view of the shared structs so a host test can compare it with
// Swift's. Catches MSL-vs-C layout divergence, which the Swift compiler cannot
// see. (C-vs-Swift divergence is impossible: Swift imports the same header.)
// ---------------------------------------------------------------------------

kernel void abi_probe(
    device MUIUInt   *out [[buffer(MUIProbeBufferOut)]],
    constant MUIRect &r   [[buffer(MUIProbeBufferRect)]]
) {
    out[0]  = (MUIUInt)sizeof(MUIRect);
    out[1]  = (MUIUInt)sizeof(MUIBounds);
    out[2]  = (MUIUInt)sizeof(MUIHsla);
    out[3]  = (MUIUInt)sizeof(MUICorners);
    out[4]  = (MUIUInt)sizeof(MUIEdges);
    // Field round-trip catches offset drift that sizes alone would miss.
    out[5]  = (MUIUInt)r.bounds.origin.x;
    out[6]  = (MUIUInt)r.bounds.size.height;
    out[7]  = (MUIUInt)r.contentMask.size.width;
    out[8]  = (MUIUInt)(r.background.h * 1000.0);
    out[9]  = (MUIUInt)(r.borderColor.a * 1000.0);
    out[10] = (MUIUInt)r.cornerRadii.bottomLeft;
    out[11] = (MUIUInt)r.borderWidths.left;
    out[12] = r.order;
}
```

- [ ] **Step 2: Confirm SwiftPM handled the file as a resource, not a source**

```bash
swift build 2>&1 | grep -i "unhandled" && echo "BAD: declare Shaders in resources" || echo "GOOD"
```

Expected: `GOOD`. A warning here means `resources: [.copy("Shaders")]` is missing from Task 4 Step 3.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(render): add rect SDF shader and ABI probe kernel"
```

---

### Task 6: Runtime shader compilation

**Files:**
- Create: `Sources/MetalUIRender/ShaderLibrary.swift`
- Test: `Tests/MetalUIRenderTests/ShaderLibraryTests.swift`

**Interfaces:**
- Consumes: the bundled resources from Tasks 4 and 5.
- Produces: `enum ShaderLibrary` with `static func combinedSource() throws -> String` and `static func make(device:) throws -> any MTLLibrary`; `enum ShaderLibraryError`.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUIRenderTests/ShaderLibraryTests.swift`:

```swift
import Testing
import Metal
@testable import MetalUIRender

@Test func combinedSourcePrependsHeaderBeforeShaders() throws {
    let src = try ShaderLibrary.combinedSource()
    let headerAt = try #require(src.range(of: "METALUI_SHADER_TYPES_H"))
    let shaderAt = try #require(src.range(of: "rect_fragment"))
    // The header must come first, or the shader cannot see the types.
    #expect(headerAt.lowerBound < shaderAt.lowerBound)
    #expect(src.contains("abi_probe"))
}

@Test func libraryCompilesAtRuntime() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let lib = try ShaderLibrary.make(device: device)
    #expect(lib.functionNames.contains("rect_vertex"))
    #expect(lib.functionNames.contains("rect_fragment"))
    #expect(lib.functionNames.contains("abi_probe"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ShaderLibraryTests`
Expected: FAIL — `cannot find 'ShaderLibrary' in scope`.

- [ ] **Step 3: Implement the loader**

Create `Sources/MetalUIRender/ShaderLibrary.swift`:

```swift
import Foundation
import Metal

public enum ShaderLibraryError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case compilationFailed(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name):
            "MetalUI shader resource missing from bundle: \(name)"
        case .compilationFailed(let message):
            "MetalUI shader compilation failed: \(message)"
        }
    }
}

/// Builds the Metal library at run time.
///
/// SwiftPM's default build system has no Metal build rule — a `.metal` file
/// beside Swift sources produces no metallib and only an "unhandled files"
/// warning — so shaders ship as resources and compile here instead. See spec 7.2.
public enum ShaderLibrary {
    /// The shared C header concatenated ahead of the Metal source.
    ///
    /// `MTLCompileOptions` exposes no include search path, so `#include` cannot
    /// be relied on from a runtime-compiled source string. Prepending is the
    /// supported route.
    public static func combinedSource() throws -> String {
        let bundle = Bundle.module

        guard let headerURL = bundle.url(forResource: "Shaders/MetalUIShaderTypes",
                                         withExtension: "h") else {
            throw ShaderLibraryError.resourceMissing("Shaders/MetalUIShaderTypes.h")
        }
        guard let shaderURL = bundle.url(forResource: "Shaders/shaders",
                                         withExtension: "metal") else {
            throw ShaderLibraryError.resourceMissing("Shaders/shaders.metal")
        }

        let header = try String(contentsOf: headerURL, encoding: .utf8)
        let shaders = try String(contentsOf: shaderURL, encoding: .utf8)
        return header + "\n" + shaders
    }

    public static func make(device: any MTLDevice) throws -> any MTLLibrary {
        let source = try combinedSource()
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw ShaderLibraryError.compilationFailed("\(error)")
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ShaderLibraryTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(render): compile shaders at runtime from bundled resources"
```

---

### Task 7: ABI probe test

**Files:**
- Test: `Tests/MetalUIRenderTests/ShaderABITests.swift`

**Interfaces:**
- Consumes: `ShaderLibrary.make(device:)`, `MUIRect`, `MUIProbeBufferIndex`.
- Produces: nothing. This task is pure safety net.

**Why this exists:** §7.2's original claim of "compiler-enforced agreement" between CPU and GPU is false under runtime compilation — nothing reads an `#include`. This test replaces that guarantee. It was verified to fail loudly when MSL and C disagree (injected drift produced `size 104 vs 100` plus every field shifted).

- [ ] **Step 1: Write the test**

Create `Tests/MetalUIRenderTests/ShaderABITests.swift`:

```swift
import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

/// Asserts Metal's view of the shared structs matches Swift's.
///
/// Swift imports the same C header the shader is built from, so C-vs-Swift drift
/// cannot happen. What CAN happen is MSL applying different packing or alignment
/// rules to the same declarations. That is invisible to the Swift compiler and
/// shows up as garbled geometry, so it is checked here.
@Test func metalAndSwiftAgreeOnSharedStructLayout() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let library = try ShaderLibrary.make(device: device)
    let function = try #require(library.makeFunction(name: "abi_probe"))
    let pipeline = try device.makeComputePipelineState(function: function)
    let queue = try #require(device.makeCommandQueue())

    // Distinct value per field, so a shifted offset produces a wrong number
    // rather than coincidentally matching.
    var rect = MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(11), y: ScaledPixels(12)),
                       size: Size(width: ScaledPixels(13), height: ScaledPixels(14))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(21), y: ScaledPixels(22)),
                            size: Size(width: ScaledPixels(23), height: ScaledPixels(24))),
        background: Hsla(h: 0.5, s: 0.25, l: 0.75, a: 1),
        borderColor: Hsla(h: 0.1, s: 0.2, l: 0.3, a: 0.4),
        cornerRadii: Corners(topLeft: ScaledPixels(1), topRight: ScaledPixels(2),
                             bottomRight: ScaledPixels(3), bottomLeft: ScaledPixels(4)),
        borderWidths: Edges(top: ScaledPixels(5), right: ScaledPixels(6),
                            bottom: ScaledPixels(7), left: ScaledPixels(8)),
        order: 9)

    let slots = 16
    let outBuffer = try #require(device.makeBuffer(length: slots * MemoryLayout<UInt32>.stride,
                                                   options: .storageModeShared))
    let inBuffer = try #require(device.makeBuffer(bytes: &rect,
                                                  length: MemoryLayout<MUIRect>.stride,
                                                  options: .storageModeShared))

    let commandBuffer = try #require(queue.makeCommandBuffer())
    let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(outBuffer, offset: 0, index: Int(MUIProbeBufferOut.rawValue))
    encoder.setBuffer(inBuffer, offset: 0, index: Int(MUIProbeBufferRect.rawValue))
    encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    #expect(commandBuffer.error == nil)

    let out = outBuffer.contents().bindMemory(to: UInt32.self, capacity: slots)

    // Sizes.
    #expect(Int(out[0]) == MemoryLayout<MUIRect>.size)
    #expect(Int(out[1]) == MemoryLayout<MUIBounds>.size)
    #expect(Int(out[2]) == MemoryLayout<MUIHsla>.size)
    #expect(Int(out[3]) == MemoryLayout<MUICorners>.size)
    #expect(Int(out[4]) == MemoryLayout<MUIEdges>.size)

    // Field round-trip.
    #expect(out[5] == 11)    // bounds.origin.x
    #expect(out[6] == 14)    // bounds.size.height
    #expect(out[7] == 23)    // contentMask.size.width
    #expect(out[8] == 500)   // background.h * 1000
    #expect(out[9] == 400)   // borderColor.a * 1000
    #expect(out[10] == 4)    // cornerRadii.bottomLeft
    #expect(out[11] == 8)    // borderWidths.left
    #expect(out[12] == 9)    // order
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `swift test --filter ShaderABITests`
Expected: PASS, 1 test.

- [ ] **Step 3: Prove the test can fail**

Temporarily add a field visible only to Metal, confirm the failure, then revert:

```bash
python3 - <<'PY'
p = "Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h"
s = open(p).read()
old = "typedef struct {\n    MUIBounds bounds;"
new = "typedef struct {\n#ifdef __METAL_VERSION__\n    uint mslOnlyField;\n#endif\n    MUIBounds bounds;"
assert old in s, "pattern not found"
open(p, "w").write(s.replace(old, new))
PY
rm -rf .build   # REQUIRED: Swift's view of the header does not rebuild incrementally
swift test --filter ShaderABITests 2>&1 | grep -c "Expectation failed"
git checkout Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h
rm -rf .build
swift test --filter ShaderABITests 2>&1 | tail -3
```

Expected: a non-zero count of failed expectations while drifted, then PASS after revert.

**The `rm -rf .build` calls are load-bearing, not hygiene.** Without them the
drifted run can come back green purely because Swift never recompiled, and you
would wrongly conclude the test is vacuous. If the drifted run passes *after* a
clean build, the test really is vacuous — stop and fix it before continuing.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(render): assert Metal and Swift agree on shared struct layout"
```

---

### Task 8: Scene

**Files:**
- Create: `Sources/MetalUIRender/Scene.swift`
- Test: `Tests/MetalUIRenderTests/SceneTests.swift`

**Interfaces:**
- Consumes: `MUIRect`.
- Produces: `struct Scene` with `rects: [MUIRect]`, `mutating func insert(_ rect: MUIRect)`, `mutating func clear()`, `var isEmpty: Bool`, and `mutating func finalize()` which stable-sorts by `order`.

**Note:** M0 has one primitive type, so batching is trivial. The sort exists now so ordering semantics are established before more primitives arrive (spec §7.3).

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUIRenderTests/SceneTests.swift`:

```swift
import Testing
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

private func rect(order: UInt32, x: Float) -> MUIRect {
    MUIRect(bounds: Bounds(origin: Point(x: ScaledPixels(x), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(1), height: ScaledPixels(1))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
            background: .white, borderColor: .black,
            cornerRadii: Corners(all: ScaledPixels(0)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: order)
}

@Test func sceneStartsEmptyAndClears() {
    var s = Scene()
    #expect(s.isEmpty)
    s.insert(rect(order: 0, x: 0))
    #expect(!s.isEmpty)
    s.clear()
    #expect(s.isEmpty)
}

@Test func finalizeSortsByOrder() {
    var s = Scene()
    s.insert(rect(order: 2, x: 20))
    s.insert(rect(order: 0, x: 0))
    s.insert(rect(order: 1, x: 10))
    s.finalize()
    #expect(s.rects.map(\.order) == [0, 1, 2])
}

@Test func finalizeIsStableForEqualOrders() {
    var s = Scene()
    s.insert(rect(order: 1, x: 100))
    s.insert(rect(order: 1, x: 200))
    s.insert(rect(order: 1, x: 300))
    s.finalize()
    // Insertion order must survive: painters at the same order layer in sequence.
    #expect(s.rects.map(\.bounds.origin.x) == [100, 200, 300])
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter SceneTests`
Expected: FAIL — `cannot find 'Scene' in scope`.

- [ ] **Step 3: Implement the scene**

Create `Sources/MetalUIRender/Scene.swift`:

```swift
import MetalUIShaderTypes

/// Primitives accumulated during a frame's paint phase.
///
/// M0 has a single primitive type. The `order` field and `finalize()` exist now
/// so z-ordering semantics are fixed before more primitives arrive (spec 7.3).
public struct Scene: Sendable {
    public private(set) var rects: [MUIRect] = []

    public init() {}

    public var isEmpty: Bool { rects.isEmpty }

    public mutating func insert(_ rect: MUIRect) {
        rects.append(rect)
    }

    public mutating func clear() {
        rects.removeAll(keepingCapacity: true)
    }

    /// Sorts primitives into paint order. Stable, so equal orders keep
    /// insertion sequence — painters at the same layer must stack predictably.
    public mutating func finalize() {
        rects = rects.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter SceneTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(render): add Scene with stable paint ordering"
```

---

### Task 9: Renderer

**Files:**
- Create: `Sources/MetalUIRender/Renderer.swift`
- Create: `Sources/MetalUIRender/RenderSurface.swift`
- Test: `Tests/MetalUIRenderTests/RendererTests.swift`

**Interfaces:**
- Consumes: `ShaderLibrary`, `Scene`, `MUIRect`, `MUIRectBufferIndex`.
- Produces:
  - `protocol RenderSurface: AnyObject` with `func nextFrame() throws -> SurfaceFrame` and `func present(_:in:)`.
  - `struct SurfaceFrame { var views: [SurfaceView]; var scaleFactor: Float }`.
  - `struct SurfaceView { var colorTexture: any MTLTexture; var viewport: MTLViewport; var projection: simd_float4x4; var rasterizationRateMap: (any MTLRasterizationRateMap)? }`.
  - `@MainActor final class Renderer` with `init(device:) throws`, `var device: any MTLDevice`, `var commandQueue: any MTLCommandQueue`, `func encode(_ scene: Scene, view: SurfaceView, in commandBuffer: any MTLCommandBuffer)`, and `func renderOffscreen(_ scene: Scene, size: Size<DevicePixels>) throws -> [UInt8]` for tests.

**Pixel format is `bgra8Unorm`** — see Global Constraints. Do not use `_sRGB`.

- [ ] **Step 1: Write the failing test**

Create `Tests/MetalUIRenderTests/RendererTests.swift`:

```swift
import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

private func bgra(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    let i = (y * width + x) * 4
    return (pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3])  // r, g, b, a
}

@Test func rendererDrawsAFilledRectWhereExpected() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(20), y: ScaledPixels(20)),
                       size: Size(width: ScaledPixels(60), height: ScaledPixels(60))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .white,
        borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    let inside = bgra(pixels, 50, 50, width: 100)
    #expect(inside.0 > 200 && inside.1 > 200 && inside.2 > 200)   // white fill
    #expect(inside.3 > 200)                                        // opaque

    let outside = bgra(pixels, 5, 5, width: 100)
    #expect(outside.3 < 40)                                        // cleared, transparent
}

@Test func cornerRadiusRoundsTheCorners() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                       size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .white, borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(30)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    // The extreme corner is outside a 30pt radius; the centre is inside.
    #expect(bgra(pixels, 1, 1, width: 100).3 < 40)
    #expect(bgra(pixels, 50, 50, width: 100).3 > 200)
}

@Test func borderPaintsADistinctColorAtTheEdge() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try Renderer(device: device)

    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                       size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))),
        background: .black,
        borderColor: .white,
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(10)),
        order: 0))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))

    let onBorder = bgra(pixels, 5, 50, width: 100)
    #expect(onBorder.0 > 200)                       // white border

    let inField = bgra(pixels, 50, 50, width: 100)
    #expect(inField.0 < 40 && inField.3 > 200)      // black fill, still opaque
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RendererTests`
Expected: FAIL — `cannot find 'Renderer' in scope`.

- [ ] **Step 3: Implement `RenderSurface`**

Create `Sources/MetalUIRender/RenderSurface.swift`:

```swift
import Metal
import simd

/// One render destination for a frame.
///
/// Deliberately a list of views with an explicit projection rather than a bare
/// drawable: a stereo backend later returns two views with per-eye matrices and
/// a rate map, and the renderer needs no change (spec 3.2).
public struct SurfaceView {
    public var colorTexture: any MTLTexture
    public var viewport: MTLViewport
    public var projection: simd_float4x4
    public var rasterizationRateMap: (any MTLRasterizationRateMap)?

    public init(colorTexture: any MTLTexture,
                viewport: MTLViewport,
                projection: simd_float4x4 = matrix_identity_float4x4,
                rasterizationRateMap: (any MTLRasterizationRateMap)? = nil) {
        self.colorTexture = colorTexture
        self.viewport = viewport
        self.projection = projection
        self.rasterizationRateMap = rasterizationRateMap
    }
}

public struct SurfaceFrame {
    public var views: [SurfaceView]
    public var scaleFactor: Float
    public init(views: [SurfaceView], scaleFactor: Float) {
        self.views = views
        self.scaleFactor = scaleFactor
    }
}

@MainActor
public protocol RenderSurface: AnyObject {
    /// Acquire this frame's destinations. Throwing is an ordinary condition
    /// (no drawable available); the caller skips the frame and stays dirty.
    func nextFrame() throws -> SurfaceFrame
    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer)
}

public enum RenderSurfaceError: Error, CustomStringConvertible {
    case noDrawableAvailable
    public var description: String { "no drawable available this frame" }
}
```

- [ ] **Step 4: Implement the renderer**

Create `Sources/MetalUIRender/Renderer.swift`:

```swift
import Metal
import MetalUICore
import MetalUIShaderTypes

public enum RendererError: Error, CustomStringConvertible {
    case commandQueueUnavailable
    case functionMissing(String)
    case bufferAllocationFailed
    case encoderUnavailable

    public var description: String {
        switch self {
        case .commandQueueUnavailable: "could not create a Metal command queue"
        case .functionMissing(let n):  "shader function missing: \(n)"
        case .bufferAllocationFailed:  "could not allocate a Metal buffer"
        case .encoderUnavailable:      "could not create a Metal command encoder"
        }
    }
}

@MainActor
public final class Renderer {
    /// Gamma-encoded sRGB compositing (spec 7.8). NOT `_sRGB`: that format makes
    /// the hardware blend in linear space, which is the opposite of the decision.
    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue

    private let rectPipeline: any MTLRenderPipelineState
    private let unitVertexBuffer: any MTLBuffer

    public init(device: any MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        self.commandQueue = queue

        let library = try ShaderLibrary.make(device: device)
        guard let vertexFn = library.makeFunction(name: "rect_vertex") else {
            throw RendererError.functionMissing("rect_vertex")
        }
        guard let fragmentFn = library.makeFunction(name: "rect_fragment") else {
            throw RendererError.functionMissing("rect_fragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = Self.pixelFormat
        // Premultiplied source-over, matching the shader's premultiplied output.
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        self.rectPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        // Unit quad as a triangle strip: 4 vertices, no index buffer.
        var unitVertices: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1),
        ]
        guard let buffer = device.makeBuffer(
            bytes: &unitVertices,
            length: MemoryLayout<SIMD2<Float>>.stride * unitVertices.count,
            options: .storageModeShared
        ) else { throw RendererError.bufferAllocationFailed }
        self.unitVertexBuffer = buffer
    }

    /// Encode one view's worth of the scene into an existing command buffer.
    public func encode(_ scene: Scene,
                       view: SurfaceView,
                       in commandBuffer: any MTLCommandBuffer) throws {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = view.colorTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw RendererError.encoderUnavailable
        }
        defer { encoder.endEncoding() }

        guard !scene.isEmpty else { return }

        encoder.setViewport(view.viewport)
        encoder.setRenderPipelineState(rectPipeline)

        var viewport = MUISize(width: Float(view.viewport.width),
                               height: Float(view.viewport.height))

        encoder.setVertexBuffer(unitVertexBuffer, offset: 0,
                                index: Int(MUIRectBufferVertices.rawValue))
        encoder.setVertexBytes(scene.rects,
                               length: MemoryLayout<MUIRect>.stride * scene.rects.count,
                               index: Int(MUIRectBufferRects.rawValue))
        encoder.setVertexBytes(&viewport, length: MemoryLayout<MUISize>.stride,
                               index: Int(MUIRectBufferViewport.rawValue))
        encoder.setFragmentBytes(scene.rects,
                                 length: MemoryLayout<MUIRect>.stride * scene.rects.count,
                                 index: Int(MUIRectBufferRects.rawValue))

        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4,
                               instanceCount: scene.rects.count)
    }

    /// Render to an offscreen texture and read the pixels back. Test support.
    public func renderOffscreen(_ scene: Scene,
                                size: Size<DevicePixels>) throws -> [UInt8] {
        let width = Int(size.width.value)
        let height = Int(size.height.value)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.bufferAllocationFailed
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RendererError.encoderUnavailable
        }

        let view = SurfaceView(
            colorTexture: texture,
            viewport: MTLViewport(originX: 0, originY: 0,
                                  width: Double(width), height: Double(height),
                                  znear: 0, zfar: 1))
        try encode(scene, view: view, in: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!,
                             bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height),
                             mipmapLevel: 0)
        }
        return pixels
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter RendererTests`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(render): add Renderer with instanced rect pipeline and RenderSurface seam"
```

---

### Task 10: Platform layer and the AppKit window

**Files:**
- Create: `Sources/MetalUIPlatform/Platform.swift`
- Create: `Sources/MetalUIPlatform/InputEvent.swift`
- Create: `Sources/MetalUIPlatform/AppKit/AppKitPlatform.swift`
- Create: `Sources/MetalUIPlatform/AppKit/MetalLayerSurface.swift`
- Modify: `Package.swift`
- Test: `Tests/MetalUIPlatformTests/PlatformTests.swift`

**Interfaces:**
- Consumes: `MetalUICore`, `MetalUIRender` (`RenderSurface`, `SurfaceFrame`, `SurfaceView`, `Renderer.pixelFormat`).
- Produces:
  - `enum InputEvent` with `.mouseDown`, `.mouseUp`, `.mouseMoved`, `.scrollWheel`, `.keyDown`, `.keyUp`, `.modifiersChanged`, plus payload structs `MouseEvent`, `ScrollEvent`, `KeyEvent`.
  - `protocol PlatformWindow: AnyObject` with `contentSize: Size<Pixels>`, `scaleFactor: Float`, `surface: any RenderSurface`, `title: String`, `onInput`, `onResize`, `onClose`, `func startDisplayLink(_:)`, `func setDisplayLinkPaused(_:)`.
  - `protocol Platform: AnyObject` with `func openWindow(title:size:) throws -> any PlatformWindow` and `func run()`.
  - `final class AppKitPlatform: Platform`, `final class MetalLayerSurface: RenderSurface`.

- [ ] **Step 1: Add the target to `Package.swift`**

Insert after the `MetalUIRenderTests` entry:

```swift
        .target(
            name: "MetalUIPlatform",
            dependencies: ["MetalUICore", "MetalUIRender"]
        ),
        .testTarget(name: "MetalUIPlatformTests", dependencies: ["MetalUIPlatform"]),
```

- [ ] **Step 2: Write the failing test**

Create `Tests/MetalUIPlatformTests/PlatformTests.swift`:

```swift
import Testing
import Metal
import MetalUICore
@testable import MetalUIPlatform

@MainActor
@Test func openWindowProducesASurfaceSizedToItsContent() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device)
    let window = try platform.openWindow(title: "Test",
                                         size: Size(width: Pixels(400), height: Pixels(300)))

    #expect(window.contentSize.width.value == 400)
    #expect(window.contentSize.height.value == 300)
    #expect(window.scaleFactor >= 1.0)

    let frame = try window.surface.nextFrame()
    #expect(frame.views.count == 1)
    // Surface is sized in device pixels, so it tracks the scale factor.
    #expect(frame.views[0].colorTexture.width == Int(400 * window.scaleFactor))
    #expect(frame.scaleFactor == window.scaleFactor)
}

@MainActor
@Test func windowTitleRoundTrips() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = AppKitPlatform(device: device)
    let window = try platform.openWindow(title: "Initial",
                                         size: Size(width: Pixels(200), height: Pixels(200)))
    #expect(window.title == "Initial")
    window.title = "Changed"
    #expect(window.title == "Changed")
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter PlatformTests`
Expected: FAIL — `cannot find 'AppKitPlatform' in scope`.

- [ ] **Step 4: Implement the input event model**

Create `Sources/MetalUIPlatform/InputEvent.swift`:

```swift
import MetalUICore

public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let shift   = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option  = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
}

public struct MouseEvent: Sendable {
    public var position: Point<Pixels>
    public var modifiers: Modifiers
    public var clickCount: Int
    public init(position: Point<Pixels>, modifiers: Modifiers = [], clickCount: Int = 1) {
        self.position = position; self.modifiers = modifiers; self.clickCount = clickCount
    }
}

public struct ScrollEvent: Sendable {
    public var position: Point<Pixels>
    public var delta: Point<Pixels>
    public var modifiers: Modifiers
    /// Trackpad phase. Honouring this is what makes scrolling feel native
    /// rather than web-like (spec 8.2).
    public var isMomentum: Bool
    public init(position: Point<Pixels>, delta: Point<Pixels>,
                modifiers: Modifiers = [], isMomentum: Bool = false) {
        self.position = position; self.delta = delta
        self.modifiers = modifiers; self.isMomentum = isMomentum
    }
}

public struct KeyEvent: Sendable {
    /// Matching uses this, not a physical key code — physical matching is the
    /// long-standing source of Dvorak and AZERTY breakage (spec 8.3).
    public var charactersIgnoringModifiers: String
    public var characters: String
    public var modifiers: Modifiers
    public var isRepeat: Bool
    public init(charactersIgnoringModifiers: String, characters: String,
                modifiers: Modifiers = [], isRepeat: Bool = false) {
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.characters = characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

public enum InputEvent: Sendable {
    case mouseDown(MouseEvent)
    case mouseUp(MouseEvent)
    case mouseMoved(MouseEvent)
    case scrollWheel(ScrollEvent)
    case keyDown(KeyEvent)
    case keyUp(KeyEvent)
    case modifiersChanged(Modifiers)
    // Reserved: focusMove (tvOS), spatial (visionOS). See spec 3.2.
}
```

- [ ] **Step 5: Implement the platform protocols**

Create `Sources/MetalUIPlatform/Platform.swift`:

```swift
import MetalUICore
import MetalUIRender

@MainActor
public protocol PlatformWindow: AnyObject {
    var contentSize: Size<Pixels> { get }
    var scaleFactor: Float { get }
    var surface: any RenderSurface { get }
    var title: String { get set }

    var onInput: ((InputEvent) -> Bool)? { get set }
    var onResize: ((Size<Pixels>, Float) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }

    /// Begin delivering frame ticks. The callback runs on the main actor.
    func startDisplayLink(_ tick: @escaping () -> Void)
    /// Pausing lets an idle window permit display downclocking (spec 4.4).
    func setDisplayLinkPaused(_ paused: Bool)
}

@MainActor
public protocol Platform: AnyObject {
    func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow
    func run()
}

public enum PlatformError: Error, CustomStringConvertible {
    case windowCreationFailed
    public var description: String { "could not create a platform window" }
}
```

- [ ] **Step 6: Implement the CAMetalLayer surface**

Create `Sources/MetalUIPlatform/AppKit/MetalLayerSurface.swift`:

```swift
#if os(macOS)
import AppKit
import Metal
import QuartzCore
import MetalUIRender

/// Flat single-view surface backed by a CAMetalLayer.
@MainActor
final class MetalLayerSurface: RenderSurface {
    private let layer: CAMetalLayer
    private var currentDrawable: (any CAMetalDrawable)?

    init(device: any MTLDevice) {
        layer = CAMetalLayer()
        layer.device = device
        // Gamma-encoded sRGB compositing; see Renderer.pixelFormat and spec 7.8.
        layer.pixelFormat = Renderer.pixelFormat
        layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        layer.isOpaque = false
        layer.framebufferOnly = true
    }

    var backingLayer: CAMetalLayer { layer }

    func resize(pixelSize: CGSize, scaleFactor: CGFloat) {
        layer.drawableSize = pixelSize
        layer.contentsScale = scaleFactor
    }

    func nextFrame() throws -> SurfaceFrame {
        guard let drawable = layer.nextDrawable() else {
            // Ordinary condition, not an error. Caller skips and stays dirty.
            throw RenderSurfaceError.noDrawableAvailable
        }
        currentDrawable = drawable

        let view = SurfaceView(
            colorTexture: drawable.texture,
            viewport: MTLViewport(originX: 0, originY: 0,
                                  width: Double(drawable.texture.width),
                                  height: Double(drawable.texture.height),
                                  znear: 0, zfar: 1))
        return SurfaceFrame(views: [view], scaleFactor: Float(layer.contentsScale))
    }

    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer) {
        if let drawable = currentDrawable {
            commandBuffer.present(drawable)
            currentDrawable = nil
        }
    }
}
#endif
```

- [ ] **Step 7: Implement the AppKit platform and window**

Create `Sources/MetalUIPlatform/AppKit/AppKitPlatform.swift`:

```swift
#if os(macOS)
import AppKit
import Metal
import QuartzCore
import MetalUICore
import MetalUIRender

/// Hosts the CAMetalLayer and funnels AppKit events into InputEvent.
@MainActor
final class MetalHostView: NSView {
    var onInput: ((InputEvent) -> Bool)?
    var onGeometryChange: (() -> Void)?

    private let surface: MetalLayerSurface

    init(surface: MetalLayerSurface) {
        self.surface = surface
        super.init(frame: .zero)
        // Order matters: assign the layer first. Setting `wantsLayer` first makes
        // AppKit create its own backing layer, and the CAMetalLayer is discarded.
        layer = surface.backingLayer
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }   // top-left origin, matching our geometry

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onGeometryChange?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onGeometryChange?()
    }

    private func point(_ event: NSEvent) -> Point<Pixels> {
        let p = convert(event.locationInWindow, from: nil)
        return Point(x: Pixels(Float(p.x)), y: Pixels(Float(p.y)))
    }

    private func modifiers(_ event: NSEvent) -> Modifiers {
        var m: Modifiers = []
        if event.modifierFlags.contains(.shift) { m.insert(.shift) }
        if event.modifierFlags.contains(.control) { m.insert(.control) }
        if event.modifierFlags.contains(.option) { m.insert(.option) }
        if event.modifierFlags.contains(.command) { m.insert(.command) }
        return m
    }

    override func mouseDown(with event: NSEvent) {
        _ = onInput?(.mouseDown(MouseEvent(position: point(event),
                                           modifiers: modifiers(event),
                                           clickCount: event.clickCount)))
    }

    override func mouseUp(with event: NSEvent) {
        _ = onInput?(.mouseUp(MouseEvent(position: point(event),
                                         modifiers: modifiers(event),
                                         clickCount: event.clickCount)))
    }

    // NOTE: mouseMoved only fires once a tracking area exists. M0 does not add
    // one, because nothing depends on hover yet; M3 adds it with hit testing.
    // Do not debug "mouseMoved never fires" here — it is expected until then.
    override func mouseMoved(with event: NSEvent) {
        _ = onInput?(.mouseMoved(MouseEvent(position: point(event),
                                            modifiers: modifiers(event))))
    }

    override func scrollWheel(with event: NSEvent) {
        let momentum = event.momentumPhase != []
        _ = onInput?(.scrollWheel(ScrollEvent(
            position: point(event),
            delta: Point(x: Pixels(Float(event.scrollingDeltaX)),
                         y: Pixels(Float(event.scrollingDeltaY))),
            modifiers: modifiers(event),
            isMomentum: momentum)))
    }

    override func keyDown(with event: NSEvent) {
        _ = onInput?(.keyDown(KeyEvent(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            characters: event.characters ?? "",
            modifiers: modifiers(event),
            isRepeat: event.isARepeat)))
    }

    override func keyUp(with event: NSEvent) {
        _ = onInput?(.keyUp(KeyEvent(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            characters: event.characters ?? "",
            modifiers: modifiers(event))))
    }

    override func flagsChanged(with event: NSEvent) {
        _ = onInput?(.modifiersChanged(modifiers(event)))
    }
}

@MainActor
final class AppKitWindow: NSObject, PlatformWindow, NSWindowDelegate {
    private let window: NSWindow
    private let hostView: MetalHostView
    private let metalSurface: MetalLayerSurface
    private var displayLink: CADisplayLink?
    private var tick: (() -> Void)?

    var onInput: ((InputEvent) -> Bool)?
    var onResize: ((Size<Pixels>, Float) -> Void)?
    var onClose: (() -> Void)?

    init(device: any MTLDevice, title: String, size: Size<Pixels>) throws {
        metalSurface = MetalLayerSurface(device: device)
        hostView = MetalHostView(surface: metalSurface)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: CGFloat(size.width.value),
                                height: CGFloat(size.height.value)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = title
        window.contentView = hostView
        window.center()

        super.init()
        window.delegate = self
        hostView.onInput = { [weak self] event in self?.onInput?(event) ?? false }
        hostView.onGeometryChange = { [weak self] in self?.syncSurfaceGeometry() }
        syncSurfaceGeometry()
    }

    var contentSize: Size<Pixels> {
        let f = hostView.bounds.size
        return Size(width: Pixels(Float(f.width)), height: Pixels(Float(f.height)))
    }

    var scaleFactor: Float { Float(window.backingScaleFactor) }

    var surface: any RenderSurface { metalSurface }

    var title: String {
        get { window.title }
        set { window.title = newValue }
    }

    func makeKeyAndVisible() {
        window.makeKeyAndOrderFront(nil)
    }

    private func syncSurfaceGeometry() {
        let scale = window.backingScaleFactor
        let bounds = hostView.bounds.size
        let pixelSize = CGSize(width: max(bounds.width * scale, 1),
                               height: max(bounds.height * scale, 1))
        metalSurface.resize(pixelSize: pixelSize, scaleFactor: scale)
        onResize?(contentSize, Float(scale))
    }

    func startDisplayLink(_ tick: @escaping () -> Void) {
        self.tick = tick
        // NSView.displayLink supersedes CVDisplayLink, deprecated in full as of
        // macOS 15. It returns a CADisplayLink and fires on the main run loop,
        // so there is no thread hop into the MainActor frame (spec 4.4).
        let link = hostView.displayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func setDisplayLinkPaused(_ paused: Bool) {
        displayLink?.isPaused = paused
    }

    @objc private func displayLinkFired() {
        tick?()
    }

    func windowWillClose(_ notification: Notification) {
        displayLink?.invalidate()
        displayLink = nil
        onClose?()
    }
}

@MainActor
public final class AppKitPlatform: Platform {
    private let device: any MTLDevice
    private var windows: [AppKitWindow] = []

    public init(device: any MTLDevice) {
        self.device = device
    }

    public func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
        let window = try AppKitWindow(device: device, title: title, size: size)
        windows.append(window)
        window.makeKeyAndVisible()
        return window
    }

    public func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
#endif
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `swift test --filter PlatformTests`
Expected: PASS, 2 tests.

If `nextDrawable()` returns nil because the window is never displayed in a test process, make the test tolerate it by asserting on `RenderSurfaceError.noDrawableAvailable` instead of the texture size — but only after confirming the window and layer geometry are correct.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(platform): add AppKit window, CAMetalLayer surface, and input events"
```

---

### Task 11: App, frame loop, and the demo

**Files:**
- Create: `Sources/MetalUI/App.swift`
- Create: `Sources/MetalUI/Window.swift`
- Create: `Sources/MetalUIDemo/main.swift`
- Modify: `Package.swift`
- Test: `Tests/MetalUITests/FrameLoopTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `@MainActor final class App` with `init(device:) throws`, `func openWindow(title:size:content:) throws -> Window`, `func run()`; `@MainActor final class Window` with `var needsRedraw: Bool`, `func setNeedsRedraw()`, `func drawFrameIfNeeded()`, and `var framesDrawn: Int` for tests.

**This task delivers the milestone exit criterion.**

- [ ] **Step 1: Add the targets to `Package.swift`**

Append to `targets:`:

```swift
        .target(
            name: "MetalUI",
            dependencies: ["MetalUICore", "MetalUIRender", "MetalUIPlatform"]
        ),
        .testTarget(name: "MetalUITests", dependencies: ["MetalUI"]),
        .executableTarget(name: "MetalUIDemo", dependencies: ["MetalUI"]),
```

And add the executable product:

```swift
    products: [
        .library(name: "MetalUI", targets: ["MetalUI"]),
        .executable(name: "MetalUIDemo", targets: ["MetalUIDemo"]),
    ],
```

- [ ] **Step 2: Write the failing test**

Create `Tests/MetalUITests/FrameLoopTests.swift`:

```swift
import Testing
import Metal
import MetalUICore
import MetalUIRender
@testable import MetalUI

@MainActor
@Test func windowDrawsOnlyWhenDirty() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let app = try App(device: device)
    let window = try app.openWindow(title: "Loop",
                                    size: Size(width: Pixels(200), height: Pixels(200)),
                                    startsDisplayLink: false) { scene, _ in
        scene.insert(MUIRect(
            bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(10), height: ScaledPixels(10))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(200), height: ScaledPixels(200))),
            background: .white, borderColor: .white,
            cornerRadii: Corners(all: ScaledPixels(0)),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0))
    }

    // A new window starts dirty so the first frame paints.
    #expect(window.needsRedraw)
    window.drawFrameIfNeeded()
    let afterFirst = window.framesDrawn
    #expect(afterFirst == 1)

    // Clean window does no work.
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == afterFirst)

    // Marking dirty schedules exactly one more.
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == afterFirst + 1)
}

@MainActor
@Test func multipleDirtyMarksCoalesceIntoOneFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let app = try App(device: device)
    let window = try app.openWindow(title: "Coalesce",
                                    size: Size(width: Pixels(100), height: Pixels(100)),
                                    startsDisplayLink: false) { _, _ in }

    window.drawFrameIfNeeded()
    let base = window.framesDrawn

    window.setNeedsRedraw()
    window.setNeedsRedraw()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == base + 1)
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter FrameLoopTests`
Expected: FAIL — `cannot find 'App' in scope`.

- [ ] **Step 4: Implement `Window`**

Create `Sources/MetalUI/Window.swift`:

```swift
import Metal
import MetalUICore
import MetalUIRender
import MetalUIPlatform

/// Fills the scene for one frame. Replaced by the element pipeline in M1.
public typealias FrameContent = @MainActor (inout Scene, Size<ScaledPixels>) -> Void

@MainActor
public final class Window {
    private let platformWindow: any PlatformWindow
    private let renderer: Renderer
    private let content: FrameContent
    private var scene = Scene()

    /// Set by input, resize, or content invalidation. A frame is built only
    /// when this (or an active animation) says so — an idle window costs
    /// nothing (spec 4.4).
    public private(set) var needsRedraw: Bool = true

    /// Test observability: how many frames actually reached the GPU.
    public private(set) var framesDrawn: Int = 0

    init(platformWindow: any PlatformWindow,
         renderer: Renderer,
         content: @escaping FrameContent,
         startsDisplayLink: Bool = true) {
        self.platformWindow = platformWindow
        self.renderer = renderer
        self.content = content

        platformWindow.onResize = { [weak self] _, _ in self?.setNeedsRedraw() }
        platformWindow.onInput = { [weak self] _ in
            self?.setNeedsRedraw()
            return false
        }
        // Tests pass false so frame counts stay deterministic: a running link
        // could tick between assertions and inflate `framesDrawn`.
        if startsDisplayLink {
            platformWindow.startDisplayLink { [weak self] in self?.drawFrameIfNeeded() }
        }
    }

    public func setNeedsRedraw() {
        needsRedraw = true
        platformWindow.setDisplayLinkPaused(false)
    }

    public func drawFrameIfNeeded() {
        guard needsRedraw else {
            // Nothing to do: let the display idle rather than spinning.
            platformWindow.setDisplayLinkPaused(true)
            return
        }
        needsRedraw = false

        let frame: SurfaceFrame
        do {
            frame = try platformWindow.surface.nextFrame()
        } catch {
            // No drawable is an ordinary condition. Stay dirty and retry.
            needsRedraw = true
            return
        }

        guard let view = frame.views.first,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            needsRedraw = true
            return
        }

        let size = Size(width: ScaledPixels(Float(view.viewport.width)),
                        height: ScaledPixels(Float(view.viewport.height)))

        scene.clear()
        content(&scene, size)
        scene.finalize()

        do {
            try renderer.encode(scene, view: view, in: commandBuffer)
        } catch {
            needsRedraw = true
            return
        }

        platformWindow.surface.present(frame, in: commandBuffer)
        commandBuffer.commit()
        framesDrawn += 1
    }
}
```

- [ ] **Step 5: Implement `App`**

Create `Sources/MetalUI/App.swift`:

```swift
import Metal
import MetalUICore
import MetalUIRender
import MetalUIPlatform

public enum AppError: Error, CustomStringConvertible {
    case noMetalDevice
    public var description: String { "no Metal device is available on this system" }
}

@MainActor
public final class App {
    public let device: any MTLDevice
    private let renderer: Renderer
    private let platform: any Platform
    private var windows: [Window] = []

    public convenience init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw AppError.noMetalDevice }
        try self.init(device: device)
    }

    public init(device: any MTLDevice) throws {
        self.device = device
        self.renderer = try Renderer(device: device)
        self.platform = AppKitPlatform(device: device)
    }

    @discardableResult
    public func openWindow(title: String,
                           size: Size<Pixels>,
                           startsDisplayLink: Bool = true,
                           content: @escaping FrameContent) throws -> Window {
        let platformWindow = try platform.openWindow(title: title, size: size)
        let window = Window(platformWindow: platformWindow,
                            renderer: renderer,
                            content: content,
                            startsDisplayLink: startsDisplayLink)
        windows.append(window)
        return window
    }

    public func run() {
        platform.run()
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter FrameLoopTests`
Expected: PASS, 2 tests.

- [ ] **Step 7: Write the demo**

Create `Sources/MetalUIDemo/main.swift`:

```swift
import MetalUI
import MetalUICore
import MetalUIRender

@MainActor
func runDemo() throws {
    let app = try App()

    try app.openWindow(title: "MetalUI — Milestone 0",
                       size: Size(width: Pixels(640), height: Pixels(400))) { scene, size in
        // One rounded rect with a border, centred, drawn entirely by an
        // analytic SDF — no rasterization, crisp at any scale factor.
        let boxSize = Size(width: ScaledPixels(320), height: ScaledPixels(180))
        let origin = Point(x: ScaledPixels((size.width.value - boxSize.width.value) / 2),
                           y: ScaledPixels((size.height.value - boxSize.height.value) / 2))

        scene.insert(MUIRect(
            bounds: Bounds(origin: origin, size: boxSize),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: size),
            background: .rgb(0x1E293B),
            borderColor: .rgb(0x38BDF8),
            cornerRadii: Corners(all: ScaledPixels(16)),
            borderWidths: Edges(all: ScaledPixels(3)),
            order: 0))
    }

    app.run()
}

try runDemo()
```

- [ ] **Step 8: Verify the milestone exit criterion**

```bash
swift run MetalUIDemo
```

Expected: a 640×400 window containing a centred dark slate rounded rectangle with a 3pt sky-blue border and 16pt corners. Check by eye:
- corners are smoothly antialiased, not stair-stepped
- the border is even on all four sides
- resizing the window keeps the rectangle centred
- the rectangle stays crisp when dragged between a Retina and non-Retina display, if you have one

Close the window to exit.

- [ ] **Step 9: Confirm the idle path does no work**

With the demo running and the window untouched, confirm CPU usage settles near zero:

```bash
swift run MetalUIDemo &
sleep 5
ps -o %cpu,comm -p $(pgrep -f MetalUIDemo | head -1)
```

Expected: well under 1% CPU while idle. A steady few percent means the display link is not being paused — check `setDisplayLinkPaused` in `Window.drawFrameIfNeeded`.

Then `kill %1`.

- [ ] **Step 10: Run the whole suite**

Run: `swift test`
Expected: all tests pass, no warnings.

```bash
swift build 2>&1 | grep -iE "warning|unhandled" && echo "FIX WARNINGS" || echo "clean"
```

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: milestone 0 — window rendering an SDF rounded rect with a border"
```

---

## Milestone 0 exit criteria

All of the following must hold before starting M1:

- [ ] `swift test` passes with no warnings
- [ ] `swift build` emits no "unhandled files" warning
- [ ] `swift run MetalUIDemo` shows a centred rounded rectangle with an antialiased border
- [ ] The demo idles below 1% CPU with the window untouched
- [ ] The ABI probe test has been demonstrated to fail under injected MSL-only drift (Task 7, Step 3)
- [ ] `Pixels` and `ScaledPixels` do not implicitly convert (Task 2, Step 5)
- [ ] There is exactly one physical copy of `MetalUIShaderTypes.h`, with the C target reaching it by symlink

## What M0 deliberately does not include

Do not build these now; they belong to later milestones and building them early will encode assumptions the spec has not settled:

- Any `Element`, `Component`, or layout code (M1)
- Text, fonts, or glyph atlases (M2)
- Hit testing, focus, or event dispatch beyond marking the window dirty (M3)
- `@Observable` integration (M4)
- Grid, paths, images, or `MetalView` (M5)
- Multi-view/stereo rendering — `SurfaceFrame.views` is a list so visionOS is additive later, but M0 renders `views[0]` only
