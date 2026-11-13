# Window container background - decisions (prefix `WB-`)

Alloy gap G40: the desktop shows through the window, blurred by macOS, behind the app's own translucent panels. Branch `feat/window-container-background` from master `e852cb12`; record 285. Class `A` for the spelling (SwiftUI's macOS 15 `containerBackground(_:for:)` with `.window`); divergence 241 (SDL). Next unused: `WB-I`.

Verified against the SDK: `ContainerBackgroundPlacement` is `@available(macOS 15.0)` for `.window` alone (`.tabView`, `.navigation`, `.navigationSplitView` are unavailable on macOS); `containerBackground<S: ShapeStyle>(_ style: S, for:)` and a `ViewBuilder` overload `containerBackground(for:alignment:content:)` exist. No on-screen SwiftUI probe was run (an agent cannot look at a screen): the mappings below are rulings, and human check WB1 compares them.

## WB-A: the API

`View.containerBackground(_ color: Color, for: ContainerBackgroundPlacement)`, a `ColorToken` spelling (disfavoured) and `containerBackground(_ material: Material, for:)`; `ContainerBackgroundPlacement.window` the only placement. There is no `ShapeStyle` generic (carried, `SS-G`), so each style is an overload; the content-closure overload is not offered (a view behind the window is what MetalUI's own root already is). Each is an `EnvironmentScope` write that changes no value and reports after its content builds (the window-preference family: `navigationTitle`, `windowDismissBehavior`). `Window` reconciles the last build's report against what the platform was last sent and tells the platform on change only (`PlatformWindow.setWindowBackdrop(_:) -> Bool`, `WindowBackdrop` = `.none` / `.material(WindowBackdropMaterial)` / `.color(r, g, b, a)`, gamma sRGB). A window that never sets one sends nothing.

## WB-B: the material mapping (AppKit)

`ultraThin` -> `.underWindowBackground`, `thin` -> `.sidebar`, `regular` -> `.popover`, `thick` -> `.sheet`, `ultraThick` -> `.windowBackground`, `bar` -> `.titlebar`. SwiftUI publishes no mapping; these are ordered by how much of the desktop each system material shows and are **unmeasured** against SwiftUI's own windows (human check WB1). A retune moves the table (`AppKitWindow.effectMaterial(for:)`), pinned by `everyBackdropLevelHasItsOwnEffectMaterial`.

## WB-C: SDL has no compositor blur

`SDLPlatform` keeps the protocol default and answers `false`. `Window` then paints the material's opaque grey (`Material.opaqueColor(in:)`, the Reduce Transparency grey `MT-F`) over the whole content, first in the frame, and a colour style as it is; it follows the scheme and goes when the style does. The answer arrives after the build that reported the style, so the fill is in the next frame (the platform answer dirties the window). Divergence 241.

## WB-D: precedence and depth

The first report in post-order wins, from any depth: an inner style beats an enclosing one, the first of two siblings beats the second; it reverts to the window's own background when the content leaves. SwiftUI's rule for a style set below the root is not probed (no on-screen window); Apple's documentation puts the style on the nearest enclosing container of that placement, the window. Revisit with the probe.

## WB-E: AppKit mechanics

A material: one `NSVisualEffectView` (`blendingMode = .behindWindow`, `state = .followsWindowActiveState`, so an inactive window loses vibrancy as every system window does) inserted **under the content view in the window's frame view** (`contentView.superview`), autoresized to it, so the host view, its responder state and its layer are untouched; the window is `isOpaque = false` with a clear background. The `CAMetalLayer` is already non-opaque (`MetalLayerSurface`) and the renderer already clears to transparent, so nothing else moves. A colour: the window's `backgroundColor` (`isOpaque = alpha >= 1`), no view. `.none` removes the view and restores the background colour and `isOpaque` the window had before the first backdrop. `invalidateShadow()` follows each flag change.

## WB-F: Reduce Transparency

`NSVisualEffectView` is documented to render solid under Reduce Transparency, but MetalUI sends the opaque material grey (`WB-C`'s) as a `.color` instead, so the window agrees with every other material site (`MT-D`, `MT-F`) and a test can read it. The blur returns when the setting does.

## WB-G: unset is today's behaviour

`sentBackdrop` starts `.none`; a window that never sets a style makes no platform call and draws no extra primitive (`aWindowWithoutAContainerBackgroundNeverTouchesThePlatformBackdrop`). The renderer's clear colour is unchanged (transparent, as before).

## WB-H: the requirement has a default

`setWindowBackdrop` is declared in `PlatformWindow` with a protocol-extension default of `false`, unlike the neighbouring requirements, so the ten test conformers and any outside conformer compile unchanged and get the SDL behaviour. `HeadlessPlatformWindow.Options.appliesWindowBackdrop` (default `true`) and `windowBackdropRequests` record and answer it.
