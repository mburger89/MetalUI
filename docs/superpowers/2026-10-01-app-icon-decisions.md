# App icon — decisions

Rulings for the application icon (user request 2026-10-01; **not a plan
task**). Spec: [`specs/2026-10-01-app-icon-design.md`](specs/2026-10-01-app-icon-design.md).
Record: `../record/70-app-icon.md` (§69 is the concurrent `metal-view` line's).

Prefix **`AI-`**, lettered. **Next unused: `AI-N`.** (This line moves in the
commit that appends a ruling; read the last `## AI-` heading.)

Branch `feat/app-icon` from `330f02b` (master: drag and drop merged, PR #36).
Baseline at `330f02b`: **2028 tests in 3 suites, 0 goldens, 125 typecheck
guards**, `Backends/SDL` 22 + 41, public census 1940 declarations in 99
families, 69 live divergences (next label 103).

**Carried items.** No decisions doc's "Carried…" section names an icon, and
nothing in `Sources/` or `Backends/` sets one today:
`grep -rn "applicationIconImage\|SDL_SetWindowIcon" Sources Backends` reads 0
hits at `330f02b`.

**Evidence that SwiftUI has no runtime icon API** (measured 2026-10-01, Xcode
beta, macOS SDK 27.0): every identifier containing `icon`/`Icon` in
`SwiftUI.framework/…/arm64e-apple-macos.swiftinterface` is a label style
(`TitleAndIconLabelStyle`, `IconOnlyLabelStyle`, `titleAndIcon`, `iconOnly`,
`labelReservedIconWidth`, `labelIconToTitleSpacing`, `buttonIconOnly`), a
preview (`PreviewIcon`), `dialogIcon` (a `confirmationDialog`'s image) or
`assistiveAccessNavigationIcon` — no application, Dock or window icon. A
SwiftUI app's icon is the bundle's (asset catalog `AppIcon`, or
`CFBundleIconFile`); `NSApplication.applicationIconImage` is AppKit's runtime
override. This feature is therefore **MetalUI-only by design** (inventory
class M), not a SwiftUI alignment, and invents no SwiftUI analogue.

## AI-A — one application-wide icon, `App.icon: [ImageBitmap]`

**Ruling.** The public surface is one settable property on `App`:

```swift
@MainActor public final class App {
    public var icon: [ImageBitmap] { get set }   // default []
}
```

- **Application level only.** No per-window icon, no `App` init parameter.
  AppKit has exactly one application icon (the Dock's); SDL3's icon is per
  window but every desktop shell shows one application's windows under one
  icon, and the SDL platform applies the one icon to every window (`AI-F`).
- **A set of bitmaps, not one.** Several sizes of one picture: AppKit holds
  them as representations of one `NSImage`; SDL3 as a primary surface plus
  alternates (`SDL_AddSurfaceAlternateImage`), picking by display scale.
- **Set before or after windows open, and at runtime**: every assignment
  reaches the platform at once (`AI-C`).
- `[]` (the default) means *the platform's own icon* — the bundle's, else the
  system's generic one (`AI-E`, `AI-F` for what each platform can restore).
- **No init parameter**: `App` has three initialisers (two macOS-only); a
  parameter on each triples the surface for nothing a property set before
  `openWindow` does not already give.

**Reasoning.** The spelling names the thing the operating system shows (the
application's icon), takes the portable bitmap type `Image` already uses
(`TE-AL`: no Apple image type crosses the portable surface), and is a
property because SwiftUI has nothing to align with (evidence above) and a
property is the least surface that covers launch-time and runtime.

**Cost if wrong.** A per-window icon is additive later (a `Window.icon`
beside this one); removing a per-window API someone used would not be.

## AI-B — the platform requirement: `Platform.setApplicationIcon(_:)`, no default

**Ruling.** `Platform` (not `PlatformWindow`) gains

```swift
func setApplicationIcon(_ images: [ImageTexture])
```

with **no default implementation** — `AB-R`/`EV-AB`/`DN-C`'s rule: a
conformer that forgets it fails to compile rather than silently showing the
generic icon. Implemented honestly by `AppKitPlatform` (`AI-E`),
`SDLPlatform` (`AI-F`) and the test fake `FakePlatform` (new, records every
call). Pinned by the plain-import guard
`aPlatformWithoutSetApplicationIconDoesNotCompile`. **Migration**: a
`Platform` conformer outside this repository adds
`func setApplicationIcon(_: [ImageTexture]) {}`.

- **`ImageTexture`, not `ImageBitmap`**: `MetalUIPlatform` imports only
  `MetalUICore` and `MetalUIScene`; `ImageBitmap` lives in `MetalUI`, which
  depends on `MetalUIPlatform`. `ImageTexture` (`MetalUIScene`, premultiplied
  RGBA8, sRGB, immutable) is the bitmap's own storage, so `App` hands over
  `bitmap.texture` with no copy.
- **On `Platform`, not `PlatformWindow`**: the icon is the application's
  (`AI-A`); a window requirement would make AppKit set one global value from
  every window. Consequence: no `PlatformWindow` conformer or the three
  `PlatformWindow` compile-guard conformers change.
- **Contract the platform may assume** (`App` guarantees it, `AI-C`): the
  list is ordered smallest area first, holds no two bitmaps of one
  `width × height`, and `[]` means "restore the platform's own icon as far as
  it can".
- Returns nothing and throws nothing (`AI-D`).

**Cost if wrong.** A default implementation could be added later without
breaking anyone; removing one could not (the `DN-C` argument).

## AI-C — what `App` does with an assignment

**Ruling.**
1. **An `App` that never assigns `icon` never calls the platform** — a bundled
   app's own icon is never overwritten by an empty list at launch.
2. **Every assignment calls `setApplicationIcon` exactly once**, synchronously,
   on the main actor — no equality short-circuit (`ImageBitmap` is not
   `Equatable`; re-assigning the same bitmaps is harmless and cheap).
3. **Normalized before the call**: sorted by `width × height` ascending,
   stable; a bitmap whose `width × height` pair repeats an earlier one is
   dropped (the first written wins). The textures passed are the bitmaps' own
   (`ObjectIdentifier`-identical — no copy).
4. **`icon` reads back exactly what was assigned** (unsorted, duplicates kept)
   — the normalization is the platform contract, not the property's value.

**Reasoning.** Normalizing once in portable code keeps both platforms simple
and puts the rule where a fake can pin it headless.

## AI-D — invalid input: no new trap; platform failure is not surfaced

**Ruling.**
- Every `ImageBitmap` is already valid: a zero side or a byte count other than
  `width × height × 4` traps at construction (`ImageBitmap.init`, pinned by
  the existing exit test `anImageBitmapOfTheWrongByteCountOrAZeroSideTraps`).
  So `App.icon` adds **no trap and no refusal**: any list — non-square, any
  size, one bitmap or many — is accepted.
- A platform that cannot apply an icon (SDL3 answers `false` from
  `SDL_SetWindowIcon`, e.g. Wayland without `xdg-toplevel-icon-v1`) **does not
  report it**: the setter is non-throwing and best-effort, as
  `PlatformWindow.title`'s setter already is (`mui_window_set_title`'s result
  is discarded). `SDLWindow` records each application's result internally so
  a test can read it.

**Cost if wrong.** A throwing or `Bool`-returning variant is additive; making
the property throw later is not possible (a property setter cannot throw).

## AI-E — AppKit: premultiplied bytes straight into one `NSImage`

**Ruling.** `AppKitPlatform.setApplicationIcon(_:)`:
1. Builds one `NSImage`: per texture a `CGImage` over the texture's bytes
   **as stored** — 8 bits per component, 32 per pixel, `width × 4` bytes per
   row, `CGColorSpace.sRGB`, `CGImageAlphaInfo.premultipliedLast |
   CGBitmapInfo.byteOrder32Big` — wrapped in an `NSBitmapImageRep`. No
   un-premultiply and no re-premultiply: `ImageTexture` is already
   premultiplied sRGB (`TE-AF`), and labelling it `premultipliedLast` makes
   CoreGraphics composite it as is. (Labelling it `.last` would make CG
   premultiply a second time: stored (100, 50, 25, 128) would draw as
   (50, 25, 13, 128).)
2. The image's `size` is the largest texture's pixel size; every rep's `size`
   is set to it, so the reps are resolutions of one picture (AppKit picks by
   pixel density).
3. Assigns `NSApplication.shared.applicationIconImage`; `[]` assigns `nil`,
   which restores the bundle's icon, else the generic executable icon.
4. **Stores the image and re-assigns it in `run()`** right after
   `setActivationPolicy(.regular)`. Defensive and **unmeasured**: whether an
   unbundled executable's launch resets an icon assigned before `run()` is not
   observable headless (no test process is a `.regular` app with a Dock tile);
   human check **O1** looks.

**Pin.** The conversion is an internal pure function
(`AppKitIcon.image(from:) -> NSImage?`, `MetalUIAppKit`) pinned pixel for
pixel; the platform method is pinned by reading `applicationIconImage` back
(and restoring `nil` after).

## AI-F — SDL: straight alpha, one surface per application, every window

**Ruling.** `SDLPlatform.setApplicationIcon(_:)`:
1. **Straight alpha.** SDL surfaces are straight (non-premultiplied) alpha by
   convention — `SDL_BLENDMODE_BLEND` is straight-alpha blending and
   premultiplying is the explicit `SDL_PremultiplyAlpha`/
   `SDL_BLENDMODE_BLEND_PREMULTIPLIED` — and the Windows (`CreateIconIndirect`
   32-bpp DIB) and X11 (`_NET_WM_ICON`) icon formats SDL converts to are
   straight. So each premultiplied texture is **un-premultiplied** in Swift
   (`SDLIcon.straightRGBA(_:)`, internal, pure): per texel with alpha `a`,
   `a == 0` → (0, 0, 0, 0); else each colour `c` → `min(255, (c × 255 + a / 2) / a)`
   in integer arithmetic (the clamp covers a texture built through
   `ImageTexture(premultipliedRGBA:)` with a colour above its alpha). Lossy
   at low alpha, by one level at most for a value that came through
   `ImageBitmap(width:height:rgba:)`'s premultiply: (100, 50, 25, 128) →
   (199, 100, 50, 128) where the author wrote (200, 100, 50, 128).
2. **The surface is built in C** (`SDLBridge.c`, the existing pattern):
   `mui_icon_surface_create(w, h, rgba)` — `SDL_CreateSurface(w, h,
   SDL_PIXELFORMAT_RGBA32)` (byte order R, G, B, A on every endianness),
   copied row by row through the surface's `pitch`;
   `mui_icon_surface_add_alternate(primary, image)`;
   `mui_window_set_icon(window, surface) -> bool`;
   `mui_surface_destroy(surface)`. The pixel-format value Swift compares
   against is a C-exported `uint32_t` constant, never a C enum's `rawValue`
   (the Windows `Int32`/`UInt32` hazard).
3. **Primary = the first (smallest) texture; every other is an alternate**
   (`SDL_SetWindowIcon`'s documented rule: the primary is the 100%-scale
   image, the alternates high-DPI versions).
4. **Applied to every open window, and to every window opened afterwards**
   (`openSDLWindow` applies the stored icon before returning). The platform
   stores the textures, builds a surface per application, applies it to the
   windows, and destroys it at once (SDL copies or converts the icon inside
   `SDL_SetWindowIcon`), so no surface outlives the call.
5. **`[]` cannot clear on SDL**: SDL3 offers no way to restore a window's
   default icon, and `NULL` is never passed. Open windows keep the last icon;
   windows opened later get none (the system default). Documented on the
   method; not a divergence (SwiftUI has nothing to diverge from).
6. On macOS SDL's Cocoa backend sets the application's Dock icon from the
   window icon, so the SDL demo on macOS shows it in the Dock (human check
   **O2**).

**Cost if wrong.** If some SDL backend expects premultiplied input, a
half-transparent edge renders slightly dark — visible only in the human
checks (O3/O4), cheap to flip in one function.

## AI-G — the demo's icon is generated, not an asset

**Ruling.** `MetalUIDemoContent` gains `public func demoIcon() -> [ImageBitmap]`:
six square bitmaps, 16, 32, 64, 128, 256 and 512 px, drawn by a pure,
deterministic function (a `#2F6FEB` rounded square, corner radius 0.22 s, with a white disc of
radius 0.28 s at its centre; each pixel classified by its centre — binary
coverage, no anti-aliasing, so every value is exactly pinnable; spec §3). Both demos assign
`app.icon = demoIcon()` before opening a window (`Sources/MetalUIDemo/main.swift`,
`Backends/SDL/Sources/MetalUISDLDemo/main.swift`). The icon is not part of any
element tree, so the fourteen offscreen images, `DemoFrameDeterminismTests`
and `everyProductionTreeBuildsOnAOneMegabyteThread` cannot see it.

## AI-H — packaging is build-side documentation, not framework API

**Ruling.** `docs/packaging.md` (new) describes shipping a real icon with the
platform's own mechanism — a macOS `.app` bundle (`Info.plist`
`CFBundleIconFile` + an `.icns` from `iconutil`), a Linux `.desktop` file
plus the hicolor icon theme, a Windows `.ico` embedded through a `.rc`
resource — each marked **build-side, not framework API**; every command is
either run during the lane and marked verified, or marked **unverified**.
`App.icon` is the runtime override that works with no bundle at all; the
document says that a bundled app normally needs neither.

## AI-I — `applicationIconImage`'s getter is a snapshot: pin the conversion and the platform's own copy (critic round)

**Ruling.** `AI-E`'s pin is corrected. Measured 2026-10-01 (macOS 27, a
script setting `NSApplication.shared.applicationIconImage` in an unbundled
process): the getter **never returns the assigned object** (`===` false right
after the set), returns **one `NSCGImageSnapshotRep`** at 2× pixels whatever
reps were assigned (16² + 32² reps at size 32 read back as one 64×64
snapshot, size 32×32), and after assigning `nil` returns the **generic
icon** (size 128×128), never `nil`. So the spec's A4 ("`applicationIconImage`'s
reps match; `[]` → `nil`") could not pass against a correct implementation,
and A2's "a rep's `CGImage`" could read an AppKit snapshot rather than the
bytes MetalUI wrapped.
1. `AppKitIcon.cgImage(from:) -> CGImage?` (internal) is the pixel pin's
   subject (A2); `image(from:)` wraps one rep per texture around it (A1).
2. `AppKitPlatform` keeps the image it last assigned in an internal
   `private(set) var iconImage: NSImage?` (`nil` after `[]`); A4 reads that,
   plus `applicationIconImage!.size` as the only getter fact that
   discriminates (the largest texture's size after a set, the pre-test size
   after `[]`).

## AI-J — windows opened later are the platform's job; S5 runs on `SDLPlatform` (critic round)

**Ruling.** `App` calls `setApplicationIcon` only on assignment (`AI-C`) and
never again from `openWindow`; a platform whose icon is per window (SDL)
applies its stored icon to each window it opens (`AI-F` item 4). Pinned on
both sides: 1.2 asserts a window opened after the assignment adds no second
call (mutation M1m), S5 asserts a window `SDLPlatform` opens after
`setApplicationIcon` carries the icon (MS8).

**Rejected**: running S5 through `App(platform:)`, as the spec first said —
`MetalUISDLTests` depends on `MetalUISDL`, `SDLReplay`, `MetalUIScene` and
`MetalUIPortableText`, not `MetalUI`; adding `MetalUI` to it for one test
widens the test target's graph for a fact `App` does not participate in.

## AI-K — `run()`'s re-assignment stays, declared unpinned (critic round)

**Ruling.** `AI-E` item 4 (re-assign the stored image in `run()` after
`setActivationPolicy(.regular)`) is kept but is **pinned by no test**: a
headless test cannot call `AppKitPlatform.run()`, so the mutation that
deletes it reddens nothing. The lane's mutation table lists it as unpinned,
its only check human check O1. **Rejected**: dropping it as untestable — the
cost of a missing icon on launch (the one case the feature exists for) is
higher than one idempotent assignment, and O1 observes it.

## AI-L — lane 1's measurements: an empty `NSImage` crashes AppKit; the mutation table (lane 1)

**Ruling.** Recorded from lane 1 (commits `39d18a9` red, `45f3e75` green);
no design change.
1. **`AppKitIcon.image(from: [])` must answer `nil`, not an empty image —
   measured, not only stylistic.** Under mutation MA6 (return `NSImage()`)
   `AppKitPlatform.setApplicationIcon([])` assigns a zero-size, rep-less image
   to `applicationIconImage`, and AppKit raises
   `NSImageCacheException` ("Cannot lock focus on image … Size={0, 0}") inside
   A4: the unfiltered run terminates with no summary line. A4 is therefore
   MA6's reddening in the full suite; A5 (`anEmptyTextureListMakesNoIconImage`),
   the test named for it, never ran in that process, and a **filtered**
   supplementary run of A5 alone under MA6 reddens it (line 136) — recorded as
   filtered, not as the suite's answer.
2. **A3's drawn texels equal the stored bytes exactly** (the whole 3×2
   texture, not only the half-alpha texel), so a premultiplied-RGBA8 sRGB
   destination with `interpolationQuality = .none` adds no rounding.
3. **Mutation table**, each applied to the green tree from a copy, the full
   unfiltered native suite (2041 tests in 3 suites), restored, `git status`
   clean after every one:

| Mutation | Reddened |
|---|---|
| M1a `App.init(platform:)` calls `setApplicationIcon([])` | 1.1, 1.2, 1.3, 1.5 |
| M1b `didSet` empty | 1.2, 1.3, 1.5 |
| M1c textures copied from the same pixels | 1.2, 1.3, 1.5 |
| M1d no sort (input order) | 1.3 |
| M1e no dedupe | 1.3 |
| M1f dedupe keeps the last (iterate reversed) | 1.3 |
| M1g `icon` rewritten to the normalized list | 1.4 |
| M1h call only when the count changes | 1.5 |
| M1i skip the call for `[]` | 1.5 |
| M1j drop the 512 | 1.6, 1.7 |
| M1k disc radius 0.30 s | 1.7 |
| M1l corner radius 0.18 s | 1.7 |
| M1m `App.openWindow` re-sends `icon` | 1.1, 1.2 |
| MA1 only the first texture becomes a rep | A1, A4 |
| MA2 un-premultiply before wrapping | A2, A3 |
| MA3 `.last` instead of `.premultipliedLast` | A2, A3 |
| MA4 `setApplicationIcon` body empty | A4 |
| MA5 `[]` returns early, keeping the old image | A4 |
| MA6 `image(from: [])` returns `NSImage()` | A4 by crash (item 1); A5 filtered |
| MG1.1 a protocol-extension default | G1.1 (`without succeeded=true`) |
| `AI-K` delete `run()`'s re-assignment | **none — unpinned by design** (`AI-K`; human check O1) |

Test names: 1.1 `anAppThatNeverSetsAnIconNeverCallsThePlatform`, 1.2
`settingTheAppIconReachesThePlatformOnceWithTheBitmapsOwnTextures`, 1.3
`theAppIconReachesThePlatformSmallestFirstWithoutRepeatedSizes`, 1.4
`theAppIconReadsBackExactlyAsAssigned`, 1.5
`settingTheAppIconAgainReplacesItAndClearingPassesAnEmptyList`, 1.6
`theDemoIconIsSixSquareBitmapsFrom16To512`, 1.7
`theDemoIconsPixelsAreTheSpecifiedShape`, A1
`anIconImageHoldsOneRepresentationPerTextureSmallestFirst`, A2
`anIconCGImageCarriesTheTexturesPremultipliedBytesUnchanged`, A3
`anIconRepresentationDrawsWithoutASecondPremultiply`, A4
`settingTheIconOnTheAppKitPlatformSetsTheApplicationIconImage`, A5
`anEmptyTextureListMakesNoIconImage`, G1.1
`aPlatformWithoutSetApplicationIconDoesNotCompile`.

4. **Census.** `Platform.setApplicationIcon` is a protocol requirement and
   the census counts only `public`/`open` declarations, so the public census
   moves 1940 → **1943** (`App.icon`, `AppKitPlatform.setApplicationIcon`,
   `demoIcon`) in **100** families; the map's `Platform.swift` row for the
   requirement claims no census row today and is kept so a future
   `public` spelling there maps to `app-icon`.

## AI-M — lane 2's measurements: the SDL mutation table, a `NULL` counter, packaging's resource-bundle rule (lane 2)

**Ruling.** Recorded from lane 2 (commits `c5aa5b4` red, `b1f4116` green,
and the docs commit carrying this ruling); no change to `AI-F`'s design.
1. **One instrument beyond the spec's bridge**: `mui_window_set_icon` refuses
   a `NULL` surface itself (returns `false` through `SDL_SetError`, never
   calling SDL) and counts it in `mui_window_set_icon_null_calls()`. S6 reads
   the counter before and after `[]`, so `AI-F` item 5's "`NULL` is never
   passed" is pinned by a reading, not by inspection (MS10 below).
2. **Red**, over a skeleton (`straightRGBA` identity, `makeSurface` `nil`,
   `setApplicationIcon` empty, `iconResult` never set): `Backends/SDL`
   **22 + 47**, 6 issues, one per test — S1 `SDLIconTests.swift:59`
   (`straightRGBA`), S2 `:79` and S3 `:101` (`makeSurface` `nil`), S4 `:129`,
   S5 `:146`, S6 `:164` (`iconResult` `nil`). **Green**: 22 + 47 passed on
   macOS; the `swift:6.4-noble` `metalui-portable-ax` container **22 + 45**
   (the two macOS-only run-loop tests absent, as before: 39 + 6).
3. **Mutation table**, each applied to the green tree from a copy, the whole
   `Backends/SDL` suite (`PKG_CONFIG_PATH=.accesskit swift test --no-parallel`,
   unfiltered), restored; `git status` showed no tracked change after every
   one:

| Mutation | Reddened (line) |
|---|---|
| MS1 `straightRGBA` returns the premultiplied bytes | S1 (`:59`), S2 (`:91`) |
| MS2 no `min(255, …)` clamp | S1 by trap (`Fatal error: Not enough bits to represent the passed value`); the run truncates with no second summary line |
| MS3 `a == 0` keeps its colours | S1 (`:59`) |
| MS4 `w`/`h` swapped at `mui_icon_surface_create` | S2 (`:84`, size 2 × 3) |
| MS5 surface created from the premultiplied bytes | S2 (`:91`, `:92`) |
| MS6 `mui_icon_surface_add_alternate` skipped | S3 (`:107`, image count 1) |
| MS7 applied to the first open window only | S4 (`:129`) |
| MS8 `openSDLWindow` skips the stored icon | S5 (`:146`) |
| MS9 `[]` keeps the last non-empty icon for new windows | S6 (`:170`) |
| MS10 `[]` passes `NULL` to every open window | S6 (`:171`, the `NULL` counter) |

Test names: S1 `unpremultiplyingRestoresStraightAlpha`, S2
`anIconSurfaceIsRGBA32HoldingTheStraightBytesRowByRow`, S3
`anIconSurfaceCarriesEveryLargerTextureAsAnAlternate`, S4
`settingTheIconAppliesItToEveryOpenWindow`, S5
`aWindowOpenedAfterTheIconIsSetGetsIt`, S6
`clearingTheIconLeavesOpenWindowsAndGivesNewOnesNone`.

4. **`applied` off macOS is not asserted**: S4/S5 expect `applied == true`
   only under `#if os(macOS)`; in the Linux container they pass on the
   textures alone. Whether a real X11/Wayland/Windows shell shows the icon is
   human checks O3/O4.
5. **Packaging (`AI-H`) found a build-system difference, measured**: under
   Swift 6.4's **default** build system the generated `Bundle.module`
   accessor searches `Bundle.main.resourceURL` (`Contents/Resources`) first
   and, in release, no build directory — so `docs/packaging.md` puts
   `MetalUI_MetalUIRender.bundle` in `Contents/Resources`; an ad-hoc signed
   `.app` of `MetalUIDemo` laid out that way verifies and stays running, and
   the same bundle without the resource bundle exits at once (`unable to find
   bundle named MetalUI_MetalUIRender`, status 133). Under `--build-system
   native` the accessor searches only the `.app`'s root and the absolute build
   directory; a resource bundle at the root makes `codesign --sign` refuse
   (`unsealed contents present in the bundle root`). The document says to
   package with the default build system. Windows' link step and every look
   stay **unverified** there.

