# MetalUI

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed) but written as idiomatic Swift.
Immediate-mode element tree, a CSS-flexbox layout engine verified against
WebKit, CoreText shaping with a glyph atlas, and a Metal renderer that draws
the whole window as instanced quads.

> **Status: experimental.** This is a working framework with a real demo app,
> not a shipping product. The API moves, the milestones below list what is
> genuinely done, and [`CLAUDE.md`](CLAUDE.md) documents the sharp edges more
> honestly than most READMEs would.

## Requirements

macOS 14+, Swift 6.3 toolchain, a Metal-capable device.

## Try it

```bash
swift run -c release MetalUIDemo
```

Demo keys: **M** modal, **Space** theme, **F**/**Escape** focus, **=**/**-**
count, **A** animation, **Q** quit.

## Build and test

```bash
swift build
swift test --no-parallel
```

`swift test` prints one summary line per test target (six of them); the suite
total is their sum — 861 tests as of 2026-09-10, including 87 layout goldens
generated from WebKit.

## What it looks like

```swift
import MetalUI
import Observation

@Observable
final class Counter { var count = 0 }

func button(_ label: String, _ handler: @escaping @MainActor () -> Void) -> some Element {
    Box(decoration: Decoration(background: .surfaceSecondary, cornerRadius: Pixels(8))) {
        Text(label).font(size: 22)
    }
    .width(Pixels(36))
    .height(Pixels(36))
    .alignItems(.center)
    .justifyContent(.center)
    .hoverBackground(.accent)
    .onClick(handler)
}

func content(_ model: Counter) -> some Element {
    Column {
        Text("Count \(model.count)").font(size: 24)

        Row {
            button("-") { model.count -= 1 }
            button("+") { model.count += 1 }
        }
        .gap(Pixels(12))
    }
    .gap(Pixels(12))
    .padding(Pixels(16))
}
```

Reading `model.count` inside `content` is what subscribes the window to it:
the whole frame build is tracked, so the next mutation redraws without an
explicit invalidation call.

## How it is put together

Eight one-way-dependent targets:

| target | job |
|---|---|
| `MetalUICore` | geometry, colour, units, style types |
| `MetalUILayout` | the flexbox engine — imports only `MetalUICore`, knows nothing about text |
| `MetalUIText` | font resolution, shaping, metrics, glyph rasterization, atlas packing — imports no Metal |
| `MetalUIShaderTypes` | the C header shared with the shaders |
| `MetalUIRender` | Metal pipeline, instanced quads, atlas upload |
| `MetalUIPlatform` | AppKit window, display link, event plumbing |
| `MetalUI` | the element API — `Box`, `Row`, `Column`, `Stack`, `Text`, `ScrollView`, `List`, `Deferred`, `@State`, `@Observable`, animation |
| `MetalUIDemo` | the executable above |

The layout engine never learns what text is: it calls a `MeasureFunction`. The
renderer uploads a CPU-side glyph atlas and `MetalUIText` never learns that
Metal exists. Both edges point one way on purpose, so the layout engine and the
shelf packer both verify headlessly with no GPU in the loop.

Three phases per frame — `requestLayout` → `prepaint` → `paint`. Paint-only
queries (`isHovered`, `isActive`, `isFocused`) are enforced by `swiftc
-typecheck` guards, because a prepaint-time answer would compile and lie.

Identity is structural: an element's id is its position in the tree, which is
what `@State`, focus and hover all key on.

## WebKit is the layout oracle

The flexbox engine is checked against real browser output rather than against
its own opinions. 87 fixtures are laid out by WebKit and committed as goldens;
a moved golden on a milestone that did not touch `Sources/MetalUILayout/` means
something reached the engine that should not have.

Eleven measured, deliberate divergences from CSS, SwiftUI or WebKit are
catalogued in [`docs/record/04-divergences.md`](docs/record/04-divergences.md)
— each with a repro and the reason it is a decision rather than a defect.

## Milestones

Done: element pipeline, flexbox sizing and wrapping, box model, text and font
resolution, clipping and scrolling, `Stack`, absolute positioning and portals,
input and focus, `@State` and `@Observable` reactivity, windowed `List`,
`Component`, animation.

Not done: the accessibility bridge (AX nodes are built, nothing consumes them
yet), iOS, Reduce Motion, exit transitions, transforms, and text colour
animation.

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — the operating rules: architecture invariants,
  known divergences, and a table of APIs that are **declared but inert**
  (things that exist, compile and do nothing — verify, don't assume).
- [`docs/record/`](docs/record/README.md) — the full engineering record in
  eight sections: measurements, layout cost tables, what has been verified on
  real hardware, and what has not.
- [`docs/superpowers/`](docs/superpowers/) — a decisions document per
  milestone, each ruling with its reasoning and what it costs if wrong.
- [`docs/practices/verifying-tests-can-fail.md`](docs/practices/verifying-tests-can-fail.md)
  — sixteen numbered shapes of test that cannot fail, every one observed here.

## License

MIT — see [`LICENSE`](LICENSE).
