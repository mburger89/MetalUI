# MetalUI

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed) but written as idiomatic Swift.
Immediate-mode element tree, CoreText shaping with a glyph atlas, and a Metal
renderer that draws the whole window as instanced quads. Layout is mid-migration:
a CSS-flexbox engine verified against WebKit still lays out every legacy
element, and a SwiftUI-style proposal-layout path, with its own elements, is
being built beside it.

> **Status: experimental.** This is a working framework with a real demo app,
> not a shipping product. The API moves, the milestones below list what is
> genuinely done, and [`CLAUDE.md`](CLAUDE.md) documents the sharp edges more
> honestly than most READMEs would.

## Direction: SwiftUI behaviour, not CSS

SwiftUI is the design authority; CSS was the substrate. The current work
([plan](docs/superpowers/plans/2026-09-12-swiftui-alignment.md)) replaces the
CSS-derived layout model with SwiftUI's: a parent **proposes** a size, the
child **measures** its answer, the parent **places** it. The aim is
behavioural alignment, not source compatibility with SwiftUI. The CSS engine
and its WebKit goldens stay as migration evidence until each port is proven.

**This is in progress, not delivered.** Today the two engines sit side by
side, and which one runs is decided by the window's **root** element
(`Frame.computeRootLayout`, `Sources/MetalUI/Frame.swift`):

- **Legacy (CSS-derived):** `Box`, `Row`, `Column`, `Stack`, `ScrollView`,
  `List`, `Deferred`, `Text`, and their modifiers. This is still the default
  path, and the milestone demo uses it.
- **Proposal layout (new):** `HStack`, `VStack`, `ZStack`, `Spacer`,
  `Rectangle`, `Color`, `ProposalScrollView`, `Text(…).proposalLayout()`, the
  single-child wrappers `ProposalFrame`, `Padding`, `Background` and
  `FixedSize`, plus typed modifiers on `ProposalElementGroup`: `.frame` (fixed
  or min/ideal/max), `.padding(Edges)`, `.fixedSize`, `.background`, `.border`,
  `.clip`, `.opacity`, `.allowsHitTesting`, `.onTap`, `.overlay`,
  `.aspectRatio`, `.layoutPriority`. The algorithms live in `MetalUILayout`
  (`LayoutTree.computeNativeLayout`) as a closed set: `NativeNode` is a private
  enum. A custom element can register a leaf or any built-in node kind through
  the eleven public `LayoutPass.requestNative*` methods, but it cannot add a
  new container algorithm.

Limits of the proposal path, as of 2026-09-14:

- **Don't mix the two.** Proposal containers require `ProposalElementGroup`
  content, so the built-in legacy elements fail to compile inside them
  (`HStack { Text("x") }` is rejected). That boundary is a protocol whose
  requirement returns a `ProposalNodeID` only `MetalUI` can create, so a type
  that registers legacy nodes through it does not compile. Seven named holes
  remain (ruling `MC-G`), such as a legacy node registered as a side effect,
  which still traps at runtime. The other direction is not guarded: a proposal
  subtree inside `Column` compiles and nothing traps, but it is unsupported and
  what it draws is unmeasured.
- **Conditionals are partial.** `EitherGroup` does not conform to
  `ProposalElementGroup`, so `if … else` inside a proposal container does not
  compile. A bare `if` compiles, but the single-child wrappers (`.frame`,
  `.padding`, `ProposalFrame`, `Padding`, …) trap when it produces no node.
- **Nothing on it animates through `withAnimation`.** No proposal element or
  modifier calls the animation helpers, so every change snaps. The one fade is
  `ProposalScrollView`'s scroll indicator, which redraws itself the way
  `ScrollView`'s does.
- **Its SwiftUI numbers are recorded, not re-runnable.** The 8pt stack
  spacing, priority split, aspect fit/fill and similar values are
  written up as probe results in the plan and in test comments, but no probe
  source is committed.
- **Missing pieces:** no focus, key handling, AX nodes, `.id()`, baselines or
  alignment guides. `HStack`/`VStack` read only the cross-axis half of a
  nine-point `ProposalAlignment`.

There is still no iOS support: everything is macOS only.

## Requirements

macOS 14+, Swift 6.3 toolchain, a Metal-capable device.

## Try it

```bash
swift run -c release MetalUIDemo
```

Demo keys: **M** modal, **Space** theme, **F**/**Escape** focus, **=**/**-**
count, **A** animation, **Q** quit.

To open the all-proposal-layout preview window instead (stacks, a spacer,
priority panels, a `ProposalScrollView`, an `.onTap` toggle), run:

```bash
METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo
```

The value must be exactly `1`. The same keymap is installed, but the only key
that changes what the preview draws is **Space** (theme). **Q** still quits,
and the other keys act on state the preview never reads. Pointer input is
wired: the wheel goes to the `ProposalScrollView` and a click runs the toggle's
`.onTap`.

## Build and test

```bash
swift build
swift test --no-parallel
```

At `2456c69` (2026-09-15, after integrating plan tasks 3, 9 and 12) the suite
reports **1226 tests**. That total includes **97** layout goldens generated from
WebKit and **61** `swiftc -typecheck` guards.
Read the printed count rather than the exit status. The guards skip silently
when `.build` is not laid out the way they expect; see
[`CLAUDE.md`](CLAUDE.md) for how to count them.

## What it looks like

The legacy CSS-derived path, which the milestone demo uses:

```swift
import MetalUI
import Observation

@Observable
final class Counter { var count = 0 }

@MainActor
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

@MainActor
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

On an ordinary element, `.padding` **wraps** its receiver in a
`ModifiedElement` layer (one flat type however many `.padding`/`.frame` calls
you chain), so modifiers written after it configure that wrapper. That is why
`.padding` comes last above.

Environment values are scoped with `.environment(_:_:)`,
`.transformEnvironment`, `.disabled`, `.dynamicTypeSize` and `.theme`, read
with `@Environment` or `pass.environment`, and rooted at `Window.environment`.
A modifier written after a scope sits outside it, as in SwiftUI. The keymap's
type is `KeyBinding` (`Binding` is a deprecated alias).

A counter in the proposal vocabulary. Every ancestor up to the window root must
be a proposal element as well. Nested in a legacy container it still compiles,
but that case is unsupported and unmeasured:

```swift
@MainActor
func proposalContent(_ model: Counter) -> some Element {
    VStack(spacing: Pixels(12), alignment: .leading) {
        Text("Count \(model.count)").proposalLayout().font(size: 24)

        HStack(spacing: Pixels(12)) {
            Rectangle(width: Pixels(36), height: Pixels(36), color: .surfaceSecondary)
                .onTap(hoverColor: .accent) { model.count -= 1 }
            Spacer()
            Rectangle(width: Pixels(36), height: Pixels(36), color: .surfaceSecondary)
                .onTap(hoverColor: .accent) { model.count += 1 }
        }
        .frame(width: Pixels(200))
    }
    .padding(Edges(all: Pixels(16)))
    .background(.surface)
    .border(.separator, width: Pixels(1), cornerRadius: Pixels(8))
}
```

This is not a 200pt card like the legacy sample's. A native window root is
stored at the full window rect, and its own measurement is discarded
(`Frame.computeRootLayout`). `.background` and `.border` add no layout node:
they paint the bounds of the node they wrap. So, reading the source, the
background and border here would cover the whole window.

Both samples typecheck in Swift 6 mode against the modules built at `7cfcddc`.
Neither has been rendered for this README.

## How it is put together

Eight one-way-dependent targets:

| target | job |
|---|---|
| `MetalUICore` | geometry, colour, units, style types |
| `MetalUILayout` | both layout engines: the flexbox engine and the proposal-layout kernel (`ProposedSize`, `LayoutMeasurement`). It imports only `MetalUICore` and knows nothing about text |
| `MetalUIText` | font resolution, shaping, metrics, glyph rasterization, atlas packing — imports no Metal |
| `MetalUIShaderTypes` | the C header shared with the shaders |
| `MetalUIRender` | Metal pipeline, instanced quads, atlas upload |
| `MetalUIPlatform` | AppKit window, display link, event plumbing (AppKit is the only platform implementation) |
| `MetalUI` | the element API: legacy `Box`, `Row`, `Column`, `Stack`, `Text`, `ScrollView`, `List` and `Deferred`; proposal `HStack`, `VStack`, `ZStack`, `Spacer`, `Rectangle`, `Color`, `ProposalScrollView`, `ProposalText`, `ProposalFrame`, `Padding`, `Background` and `FixedSize`; plus `@State`, `@Observable` and animation |
| `MetalUIDemo` | the executable above |

The layout engines never learn what text is: they call a measure closure. The
renderer uploads a CPU-side glyph atlas and `MetalUIText` never learns that
Metal exists. Both edges point one way on purpose, so layout and the shelf
packer both verify headlessly with no GPU in the loop.

Three phases per frame — `requestLayout` → `prepaint` → `paint`. Paint-only
queries (`isHovered`, `isActive`, `isFocused`) are enforced by `swiftc
-typecheck` guards, because a prepaint-time answer would compile and lie.

Identity is structural: an element's id is its position in the tree, which is
what `@State`, focus and hover all key on.

## WebKit is the oracle for the legacy engine

The flexbox engine is checked against real browser output rather than against
its own opinions. 97 fixtures are laid out by WebKit and committed as goldens.
A golden that moves on a milestone that did not touch `Sources/MetalUILayout/`
means something reached the engine that should not have.

WebKit says nothing about the proposal-layout kernel. Its tests are
`ProposedSizeTests`, `NativeLayoutTests` and `NativeLayoutIntegrationTests`.
About a dozen of the integration tests cite a SwiftUI probe result in their
own doc comments. `NativeLayoutTests` cites none. The probes survive only as
prose, and most record no positive control.

Twelve measured divergences from CSS, SwiftUI or WebKit are tabled in
[`CLAUDE.md`](CLAUDE.md). Two are unfixed defects (15 and 19); the other ten
are deliberate decisions or known limits. Full entries with repros for eleven
of them are in
[`docs/record/04-divergences.md`](docs/record/04-divergences.md). The twelfth,
divergence 19 (one element value placed twice shares a `@State` box), is so far
recorded only in `CLAUDE.md`.

## Milestones

Done: element pipeline, flexbox sizing and wrapping, box model, text and font
resolution, clipping and scrolling, `Stack`, absolute positioning and portals,
input and focus, `@State` and `@Observable` reactivity, windowed `List`,
`Component`, animation.

In progress: SwiftUI behavioural alignment. The replacement inventory is
published; the proposal-layout kernel (task 2), typed modifier composition
(task 3), scoped environment values with a disabled state (task 9, with carried
items) and a macOS accessibility bridge (task 12's bridge half) exist beside
the legacy engine. No legacy container has been ported yet. The decisions
documents are prefixed `SA-`, `MC-`, `EV-` and `AB-`.

The accessibility bridge publishes text, click targets (as buttons), focusable
and adjustable elements, and `List` as a table, through `NSAccessibility`, with
`accessibilityLabel`, `accessibilityValue` and `accessibilityAdjustableAction`.
It is **not yet validated with VoiceOver**, and proposal-path elements publish
nothing.

Not done: VoiceOver validation, iOS, Reduce Motion, exit transitions,
transforms, and text colour animation.

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — the operating rules: architecture invariants,
  known divergences, and a table of APIs that are **declared but inert**
  (things that exist, compile and do nothing — verify, don't assume). It has a
  section on the proposal-layout path.
- [`docs/record/`](docs/record/README.md) — the full engineering record:
  eight sections split from the old `CLAUDE.md` (measurements, layout cost
  tables, what has been verified on real hardware, and what has not), plus
  [`09-swiftui-alignment.md`](docs/record/09-swiftui-alignment.md) for the
  proposal-layout work, `10`–`12` for tasks 3, 9 and 12, and
  [`13-integration-tasks-3-9-12.md`](docs/record/13-integration-tasks-3-9-12.md)
  for their integration.
- [`docs/superpowers/`](docs/superpowers/) — a decisions document per
  completed milestone, each ruling with its reasoning and what it costs if wrong.
- SwiftUI alignment:
  - [task plan](docs/superpowers/plans/2026-09-12-swiftui-alignment.md), with
    its current starting point
  - [layout replacement inventory](docs/superpowers/2026-09-12-swiftui-layout-replacement-inventory.md)
  - [native layout kernel spec](docs/superpowers/specs/2026-09-12-native-layout-kernel-design.md),
    written before the kernel and now behind it: the shipped kernel is a
    closed set of algorithms, not the protocol the spec describes
  - [typed modifier composition spec](docs/superpowers/specs/2026-09-12-typed-modifier-composition-design.md),
    which also differs from what shipped (`ModifiedContent` with a closed
    `LayoutModifier`); the design that shipped for the legacy path is the
    [modifier composition spec](docs/superpowers/specs/2026-09-15-modifier-composition-design.md)
  - [environment spec](docs/superpowers/specs/2026-09-15-environment-design.md)
    and [accessibility bridge spec](docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md)
- [`docs/practices/verifying-tests-can-fail.md`](docs/practices/verifying-tests-can-fail.md)
  — sixteen numbered shapes of test that cannot fail, every one observed here.

## License

MIT — see [`LICENSE`](LICENSE).
