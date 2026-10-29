# How do I run my app on Linux and Windows?

A MetalUI app is the same tree on macOS, Linux and Windows. What changes is the platform under it:
AppKit and Metal on macOS; SDL3 with MetalUI's portable text system on Linux and Windows. This guide
says how to start a cross-platform package, what the SDL backend draws for itself, how images and
fonts behave and where packaging lives. iOS, iPadOS, tvOS, watchOS and visionOS are a product
boundary, not a gap (`PB-A`; [`divergences.md`](../divergences.md#not-offered)). The reference is
[`api-overview.md`](../api-overview.md#backends-and-infrastructure--m); starting a project is
[`getting-started.md`](../getting-started.md#linux-and-windows---cross-platform).

Swift blocks in this guide are compiled by the test suite like the other guides'. **An SDL snippet
is not a swift block**: `SDLPlatform` lives in a package behind a trait that the guides' test target
does not build, so it is a `text` fence here, and the starter that `metalui new --cross-platform`
generates is what the Linux image and Windows CI build ([`README.md`](README.md#how-the-code-blocks-are-checked)).

## How do I start a package that runs everywhere?

```sh
swift run --package-path MetalUI metalui new MyApp --cross-platform
```

The generated `main.swift` picks the platform at compile time. Without the `SDL` trait on the
dependency, `SDLPlatform` is an unavailable declaration that names the trait, so a macOS app never
needs SDL.

```text
import MetalUI
#if canImport(MetalUISDL)
import MetalUIPortableText
import MetalUISDL
import MetalUISystemFonts
#endif

@MainActor
func makeApp() throws -> App {
    #if canImport(MetalUISDL)
    let resolver = try SystemFonts.resolver()
    return App(platform: try SDLPlatform(), textSystem: { PortableTextSystem(resolver: resolver) })
    #else
    return try App()
    #endif
}
```

Everything above `makeApp` is the same on every platform: the view tree, state, gestures and the
headless test harness ([`testing.md`](../testing.md)) do not change. The manifest, the traits and
the two portable text products named on every platform are in
[`getting-started.md`](../getting-started.md#linux-and-windows---cross-platform).

## What does the SDL backend draw for itself?

SDL has no menu bar, alert, toolbar or native menu to hand over, so the window draws them from the
same declarations; your code does not branch.

- The `App.commands` menu bar is a 25-point strip across the top of every window, opened by a click or
  F10, and a toolbar is a 39-point strip below it, with the root laid out underneath
  (divergences 195, 136). Pin: `aMenuBarThePlatformDeclinesIsDrawnAndDrivenThroughTheTree`.
- An `.alert` or `.confirmationDialog` is drawn above the window and held modal; a `.contextMenu` is
  MetalUI's drawn menu (pins: `aDeclinedAlertIsDrawnAndPressedThroughTheTree`,
  `aDrawnMenuIsDrivenThroughTheTree`).
- File dialogs are SDL's own, and a `ContentType` filters by **filename extension only**, so give a
  type its extensions (divergence 129). The block below declares one.
- `windowStyle: .hiddenTitleBar` makes an SDL window borderless **where the video driver can change a
  border**: the platform answers `true` and `titleBarInsets` reads a 32-point band plus the edge of the
  three window buttons the window draws itself (138 on the right on Linux and Windows, 70 on the left
  through SDL on macOS), all zero in full screen (divergence 175). Where the driver cannot — the
  `offscreen` driver of the Linux test image, measured — the platform answers `false`, the window keeps
  its system bar and the insets stay zero. Pins in `Backends/SDL/Tests/MetalUISDLTests/SDLChromeTests.swift`
  (`theStyleAnswerIsWhatTheDriverDid` on every driver, the rest on drivers with a window manager); a
  real Windows, X11 or Wayland window is human check group CW, not run.
- The drag is a set of regions published to `SDL_SetWindowHitTest`: the empty band and each
  `WindowDragGesture` handle, minus every control that needs the pointer, and the six-point edges and
  corners of a borderless window resize it. SDL takes the pointer events inside a region, so a hover
  inside the band is not delivered (divergences 276, 425, 426). `performWindowDrag()` still answers
  `false`; a handle moves the window through its region, not through the gesture. Double-click zoom
  on the band is not promised on Linux (human check CW6).
- A trackpad or hi-res wheel reads as a precise scroll: SDL forwards no device class, so MetalUI
  infers one from fractional deltas and ends the stream 0.15 s after the last event; set
  `SDLPlatform.Options.scrollPrecision` to `.disabled` for plain wheel events (divergences 845, 846).
- `SingleInstance.claim(id:forwarding:configuration:)` elects one running copy per user and forwards a
  second launch's arguments to it as an open-document event; `SDLPlatform.Options.applicationID` is the
  Wayland `app_id` / X11 `WM_CLASS` a `.desktop` file matches.
- A drop onto the window targets the deepest destination whatever its type (divergence 102).

```swift
import MetalUI

/// A document type the file dialogs can filter by extension off Apple.
let crossAcceptedTypes: [ContentType] = [
    ContentType("com.example.notes", conformingTo: [.json], filenameExtensions: ["notes", "json"])
]

/// A button whose shortcut is the platform's primary modifier: Command on Apple, Control elsewhere.
@MainActor
func crossSaveRoot(_ log: ShellLog) -> some Element {
    VStack {
        Button("Save") { log.entries.append("save") }.keyboardShortcut("s")
    }
}
```

`.keyboardShortcut` defaults to `EventModifiers.primary`, so the same line is ⌘S on macOS and ⌃S on
Linux and Windows; write `.command` only when you mean the Super key off Apple. A test sends the
primary-modified key and the shortcut fires (pin: `theCrossPlatformGuideThePrimaryModifierFiresTheShortcut`).
`ShellLog` is the small log class declared in the [presentations guide](presentations-and-app-shell.md).

## How do images and fonts behave?

PNG and JPEG are decoded by one vendored decoder on every platform, macOS included, so the pixels
are the same everywhere; colour profiles are ignored, where ImageIO would convert them (divergence 138).
A missing, corrupt or truncated file is `nil`, never a trap. Other formats go through ImageIO on macOS
and are `nil` elsewhere. SwiftUI's asset-catalog `Image(_:bundle:)` is not offered.

```swift
/// A bitmap built from bytes is the same on every platform; a file may be missing.
@MainActor
func crossImageRoot() -> some Element {
    let bitmap = ImageBitmap(width: 4, height: 4, rgba: [UInt8](repeating: 255, count: 64))
    return VStack { Image(bitmap, scale: 1, label: Text("Logo")) }
}

/// A file path that is not there answers `nil`.
@MainActor
func crossLogo(path: String) -> ImageBitmap? {
    ImageBitmap(contentsOfFile: path)
}
```

A test reads the labelled image from the accessibility tree and gets `nil` for a missing file (pin:
`theCrossPlatformGuideAMissingFileIsNil`; the decoder's own pins: `everyFixturePNGDecodesToItsLiteralPixels`,
`aCorruptPNGIsNil`).

To read pixels, decode once with `DecodedImage` (PNG and JPEG, the same decoder, MetalUI-only): `.grey`
gives one luma byte per pixel (a grey source exactly, otherwise Rec. 601 with alpha dropped), `.rgba` gives
straight-alpha bytes, and `orientation` is the file's EXIF tag, **reported and not applied** (a bitmap built
from the file draws its stored pixels, divergence 435). `applyingOrientation()` turns the pixels upright, and
`Image(_:scale:orientation:label:)` draws a bitmap turned by a tag you already read.

```swift
/// Decodes once: grey pixels to analyse, and an upright bitmap to draw.
func crossDecode(_ data: Data) -> (grey: DecodedImage, upright: ImageBitmap)? {
    guard let grey = DecodedImage(data: data, format: .grey),
          let colour = DecodedImage(data: data) else { return nil }
    return (grey, ImageBitmap(colour.applyingOrientation()))
}
```

A one-pixel PNG decodes to one grey byte and a 1x1 bitmap, and bytes that are not an image are `nil`
(pin: `theCrossPlatformGuideDecodesOnceAndRejectsGarbage`).

To refuse an image before any pixel is decoded, read its header: `ImageInfo(data:)` (or
`ImageInfo(contentsOfFile:)`, which seeks over the pixels) gives the format, the stored size, the EXIF
orientation, the bit depth and the channel count for PNG and JPEG, and is `nil` for anything else. It applies
no size limit of its own, so a 20000 x 20000 PNG reports its size although `DecodedImage` will not decode it.
`DecodedImage.Limits` runs that read first: an image over `maxInputBytes`, `maxSide` or `maxPixels` is `nil`
and the decoder never allocates for it.

```swift
/// Decodes only what fits: 16 MB of input, 8192 pixels a side, 24 million pixels.
func crossDecodeBounded(_ data: Data) -> (info: ImageInfo, image: DecodedImage)? {
    let limits = DecodedImage.Limits(maxInputBytes: 16 << 20, maxSide: 8192, maxPixels: 24_000_000)
    guard let info = ImageInfo(data: data),
          let image = DecodedImage(data: data, limits: limits) else { return nil }
    return (info, image)
}
```

A one-pixel PNG reports 1 x 1 and decodes inside the limits, a limit of zero pixels refuses it, and bytes that
are not an image are `nil` (pin: `theCrossPlatformGuideBoundsADecodeFromTheHeader`). Cancelling a decode that
is inside the limits is not offered.

Text uses CoreText on macOS and MetalUI's portable system (HarfBuzz shaping, FreeType glyphs,
libunibreak line breaking) elsewhere, measured against CoreText. Fonts come from the platform's
installed fonts through `SystemFonts.resolver()`; the one place you will see a difference is joined
Arabic with tracking or kerning, where the portable system places the extra space as a gap between
letters (divergence 157). A `.task` body starts synchronously inside the first frame on macOS 27,
and one frame late on macOS 14 to 25 (divergence 137).

## How do I run my own GPU work on SDL?

On macOS you reach Metal through `MetalView` and `MetalDrawContext`. On Linux and Windows the SDL
backend draws with SDL3's GPU API, and the product `MetalUISDLGPU` gives an app the same API: one
`import MetalUISDLGPU` brings a thin typed layer named after SDL_GPU (`SDLGPUDevice`, `SDLGPUBuffer`,
`SDLGPUComputePipeline`, `SDLGPUFence`) **and** every raw `SDL_` symbol, so what the layer omits is
still one call away on each object's `raw` pointer. It is MetalUI-only (SwiftUI has no GPU API) and
needs the `SDL` trait; a portable GPU API over Metal and SDL is not offered. These snippets are `text`
fences for the reason above.

```text
// Package.swift: the product comes with the SDL trait
.package(url: "https://github.com/mburger89/MetalUI.git", revision: "<commit>", traits: ["SDL"]),
.product(name: "MetalUISDLGPU", package: "MetalUI"),
```

**Compute needs no window.** `SDLGPUDevice.make()` creates and owns a device and answers `nil`, with
`SDLGPUDevice.lastFailure` naming why, when no GPU or driver answers. A kernel is HLSL you build once
with `swift package compile-shaders` (the recipe is section 4a of
[`packaging.md`](../packaging.md), which also shows the `CompileShadersOnBuild` plugin for plain `swift build`) and the library loads the blob for the device's driver together with
its reflection, so you never count bindings by hand. SDL_GPU has no append buffer: a read-write storage
buffer holds a counter in its first word and the payload after it, and each thread claims a slot with
`InterlockedAdd`.

```text
import MetalUISDLGPU

let device = SDLGPUDevice.make()!                      // owned; a missing GPU is nil, not a trap
let library = try SDLGPUShaderLibrary.locate(sourceTree: kernelsDirectory)
let pipeline = device.makeComputePipeline(try library.compute("append", for: device))!
let buffer = device.makeBuffer(size: 4 * (1 + n), usage: [.computeStorageRead, .computeStorageWrite])!
_ = await device.upload([UInt8](repeating: 0, count: 4 * (1 + n)), to: buffer)   // zero the counter

let fence = try await device.submitBatch { commandBuffer in     // recorded and submitted on a worker thread
    guard let pass = commandBuffer.beginComputePass(readWrite: [buffer]) else { return }
    pass.bind(pipeline)
    pass.push(uniform: threadCountBytes, at: 0)
    pass.dispatch(x: (n + 63) / 64, y: 1, z: 1)
    pass.end()                                          // every pass is ended inside the batch
}
await fence.wait()                                      // suspends; the main actor is never blocked
let bytes = await device.download(buffer, range: 0..<(4 * (1 + n)))!
```

The fence is waited for on a thread of its own, so `await fence.wait()` from the main actor lets the
window keep drawing. A command buffer is recorded and submitted only on the
worker thread inside `submitBatch`, and a batch that leaves a pass open is an error, not an undefined
submit. A batch is its own submission: it is not part of a window's frame.

**On the window's own device.** `SDLGPUDevice(borrowing: ctx)` wraps the device a `GPUSurface` draw
receives, not owned and never destroyed, so a buffer a batch filled is one the surface can draw.
SDL orders only the start of one submission before the next, so await the batch's fence before the
frame that reads its output. Keep the borrowed wrapper no longer than the window.

Shaders can also be compiled at run time: `SDLGPUShaderCompiler.shared(libraryPath:)` loads
libSDL3_shadercross when the app ships it and throws `compilerUnavailable` when it is absent
([`packaging.md`](../packaging.md)). A macOS app built without the `SDL` trait uses the same loader
through the `MetalUIShaderRuntime` product's `RuntimeShaderCompiler`.

Apps with their own SDL3 binding can ignore the layer: `SDLGPUDrawContext` still hands out `device`,
`commandBuffer` and `target` as raw pointers.

## Where do packaging and CI live?

Icons, bundles and document types are build-side, not API: [`packaging.md`](../packaging.md) has the
macOS `.app` and `.icns`, the Linux `.desktop` file and hicolor icons, and the Windows `.ico`
resource, each marked verified or unverified. An open-document event arrives as the platform
delivers it (divergence 176; the launch-argument recipe is in the same file). To test the cross-platform
behaviour without a screen, use the headless harness: its options answer as AppKit does by default
and as SDL does with `presentsAlertsNatively`, `presentsMenusNatively` and `showsToolbarNatively`
off ([`testing.md`](../testing.md)).

To prove the build starts on a runner with no display, open the real SDL window headless. A `text`
fence, because the SDL products do not build in the guide target (`DG-L`):

```text
let platform = try SDLPlatform(options: .headlessIfRequested())   // METALUI_SDL_HEADLESS=1 selects .headless
```

The full recipe, with its bounded loop, is in [`testing.md`](../testing.md#a-ci-smoke-test-of-the-real-window).

## Divergences you will hit

Each row is in [`divergences.md`](../divergences.md); the list is checked against it.

- divergence 102: an external drop on SDL targets the deepest destination whatever its type.
- divergence 129: off Apple a file dialog filters by filename extension only.
- divergence 136: where the platform has no toolbar the window draws a strip.
- divergence 137: a `.task` body starts one frame late on macOS 14 to 25.
- divergence 138: images are decoded by MetalUI's own decoder and colour profiles are ignored.
- divergence 157: tracking on joined Arabic is a gap, not a kashida, on Linux and Windows.
- divergence 176: an open-document event never opens a window.
- divergence 195: where the platform has no menu bar every window draws one.
- divergence 276: a window drag moves the window on AppKit only.

Back to the [guides](README.md), and [`api-overview.md`](../api-overview.md) for every declaration.
