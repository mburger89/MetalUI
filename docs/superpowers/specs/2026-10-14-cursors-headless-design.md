# Image cursors and a headless SDL launch - design

Items S4 and S8 (MetalCreator's SDL-port gap 8 and XP-G9; user request 2026-10-02; not a plan task).
Rulings: [`../2026-10-14-cursors-headless-decisions.md`](../2026-10-14-cursors-headless-decisions.md) (`IC-A`...`IC-N`).
Record: `../../record/116-cursors-headless.md`. Probe: `docs/probes/swiftui-image-cursor.swift`.

**Status: LANDED (2026-10-14, record §116).** Lane A (S8) and lane B (S4) built, each red first and verified; see the decisions doc (`IC-R` for lane B's spellings). Owed to a human or CI: group IC and the Windows run.

## 1 Goal

- S4: `PointerStyle.image(_:hotSpot:)` on AppKit and SDL, SwiftUI's spelling; the headless platform records it.
- S8: a public, documented way for an app's smoke test to open the real SDL window with no display and no
  SPI import.

SwiftUI claims rest on the probe (`I0`-`I7`, header output). gpui is not consulted: it has no image-cursor API
of this shape (`CursorStyle` is a system enum), so SwiftUI is the authority throughout.

## 2 Public API

```swift
// MetalUI
extension PointerStyle {
    public static func image(_ image: Image, hotSpot: UnitPoint) -> PointerStyle      // IC-B
}
// MetalUIPlatform
extension PlatformPointerStyle { case image(PlatformCursorImage) }                      // IC-A
public struct PlatformCursorImage: Sendable, Hashable {                                 // IC-A
    public init(texture: ImageTexture, scale: Float, hotSpot: (x: Float, y: Float))
    public var texture: ImageTexture { get }; public var scale: Float { get }
    public var hotSpotX: Float { get }; public var hotSpotY: Float { get }               // points, top-left
    public var pixelWidth: Int { get }; public var pixelHeight: Int { get }
    public var pointWidth: Float { get }; public var pointHeight: Float { get }
}
// MetalUISDL
extension SDLPlatform {
    public struct Options: Sendable, Hashable {                                          // IC-J
        public var hidesWindows: Bool; public var rendersOffscreen: Bool
        public init(hidesWindows: Bool = false, rendersOffscreen: Bool = false)
        public static let `default`: Options; public static let headless: Options
        public static func headlessIfRequested(environment: [String: String] = ...) -> Options   // IC-K
    }
    public convenience init(options: Options) throws
}
```

Census rows: `PointerStyle.image`, `PlatformPointerStyle.image`, `PlatformCursorImage` and its 9 members,
`SDLPlatform.Options` and its 6 members, `init(options:)` (class A for `image`, M for the rest).
`closeout-inventory-check.sh` and `closeout-undocumented.sh` must print nothing; the census is re-recorded.
Divergence **465** (hot spot clamp, `IC-C`). `docs/migration.md`: the `CI-AC` switch note;
`docs/api-overview.md`: both features. Doc comments: `PointerStyle`'s "SDL has no hand or zoom cursor" sentence
gains the `IC-H` recipe and drops `image` from the not-offered list (`shape` stays); `PlatformPointerStyle`'s
`CI-AC` paragraph becomes the note that the case exists.

## 3 Files and lanes (two, sequential, disjoint hunks)

**Lane A - S8 headless launch** (small; run first).
- `Backends/SDL/Sources/MetalUISDL/SDLPlatformOptions.swift` (new): `Options`.
- `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`: **only** the init region (lines ~50-75: public
  `init(options:)`, `init(hiddenWindows:)` forwards, the SPI init forwards) and the trait-off stub (~1207).
- `Backends/SDL/Package.swift` + `Package.swift` root (`HeadlessLaunchCheck` executable, `SDL` trait list):
  the new check target next to `MainQueueDrainCheck`; `Backends/SDL/Sources/HeadlessLaunchCheck/main.swift`
  (plain `import MetalUISDL`).
- Tests: `Backends/SDL/Tests/MetalUISDLTests/SDLHeadlessLaunchTests.swift`.
- Docs: `docs/testing.md` (recipe), `docs/packaging.md` (CI link), `docs/guides/cross-platform.md` + the text fence
  (`DG-L`), `docs/api-overview.md`, `docs/migration.md` (none needed: additive), inventory map rows for A.

**Lane B - S4 image cursors.**
- `Sources/MetalUIPlatform/PointerStyle.swift` (case, `PlatformCursorImage`), `Sources/MetalUI/PointerStyle.swift`
  (`Kind.image`, the static, `platformStyle`), `Sources/MetalUIAppKit/AppKitCursor.swift` (+ the cache in
  `AppKitPlatform.swift`'s `setPointerStyle`, ~line 990).
- `Backends/SDL/Sources/SDLBridge/SDLBridge.c` + `include` header (create/destroy/recorders, `IC-E`),
  `Backends/SDL/Sources/MetalUISDL/SDLCursor.swift` (new: surface build, the bounded table),
  `SDLInputMapping.swift` (`.image` arm in `systemCursor(for:)`'s callers), and **only** the pointer-style region
  of `SDLPlatform.swift` (~505-525) plus window-close/deinit destroy.
- `Sources/MetalUITesting/HeadlessPlatformWindow.swift`: nothing but a doc line (`IC-I`); every test fake
  `switch` over `PlatformPointerStyle` (`Tests/MetalUITests/Fakes.swift`, `PortableFakeWindow.swift`) gains the case.
- Demo: `Sources/MetalUIDemoContent/CanvasDemo.swift` (opt-in `METALUI_CANVAS_DEMO=1`, the pointer strip):
  one new cell showing a generated 24 px "ring" `ImageBitmap` cursor, in **its own function** (1 MB stack,
  `everyProductionTreeBuildsOnAOneMegabyteThread`). The default demo and the fourteen images do not change
  (0 px: `docs/probes/demo-pixels/compare.sh <scratch> fb9a7e42 HEAD`).
- Docs: `docs/guides/input.md` (compiled block + mirror `GuideMirrors*.swift`), `docs/api-overview.md`,
  `docs/migration.md`, `docs/divergences.md` (465), `docs/verification/human-checks.md` (group **IC**),
  inventory rows, and `docs/probes/closeout-public-api.sh` re-record.

Both lanes: unfiltered root suite, `Backends/SDL` suite, the Linux image. No other file moves; the five
must-not-move areas are untouched (pointer style is outside hit testing, identity, state and animation).

## 4 Implementation notes

- `Window.sendPointerStyle` is unchanged; only `PointerStyle.platformStyle` gains the arm that resolves
  `UnitPoint * pointSize`, clamped (`IC-C`).
- `PlatformCursorImage ==`/`hash` use `ObjectIdentifier(texture)`, `scale`, hot spot bits (`IC-A` 2).
- AppKit `NSBitmapImageRep` from `texture.pixels` exactly as `AppKitIcon` wraps them (`AI-E`); no copy of the
  conversion.
- SDL surfaces: RGBA32 from `SDLIcon.straightRGBA`; integer scale >= 2 builds a box-downsampled primary and the
  bitmap as alternate; creation failure leaves the cursor and the recorder counts the attempt.
- Every SDL enum constant used (`SDL_PIXELFORMAT_RGBA32`, cursor/format values) is converted explicitly
  through a C-exported constant or `Int32(truncatingIfNeeded:)`/`UInt32(...)` (Windows `Int32` rawValue).
- `Options`: `init(options:)` is the old init body; the stored `hidden`/`offscreenRenderers` come from it.

## 5 Tests (every one named, with its red-before and the mutation that must redden it)

Red-before means the test fails to compile or fails on `fb9a7e42`. Every mutation: commit, mutate, full
unfiltered suite (or the named package's), name the reddened tests, restore from a copy, `git status --short`.

**Lane B, root (`Tests/MetalUITests/ImageCursorTests.swift`, over `MetalUITesting`)**
1. `anImageCursorSendsItsPointSizeAndHotSpot` - a 32 px, scale 2 image, hot spot `.center`, hovered: the
   window's last style is `.image` with `pointWidth` 16 and hot spot (8, 8). *Mutations:* lower with pixel size
   instead of `pixels/scale`; multiply the hot spot by pixels. Both redden it.
2. `aHotSpotOutsideTheUnitSquareClampsToTheImage` (divergence 465) - `(2, -1)` gives (16, 0) of 16 pt.
   *Mutation:* remove the clamp.
3. `aBitmapRebuiltEveryFrameSendsOneCursor` - hover, 3 `tick`s with a fresh `Image(...)` each build:
   `pointerStyles.count` is 1 (`IC-F`). *Mutation:* key equality on a fresh id per `Image`.
4. `twoBitmapsWithEqualBytesAreTwoCursors` - identity, not bytes (`IC-A` 2). *Mutation:* hash the pixels.
5. `aNilStyleOutsideAnImageCursorKeepsItAndAnInnerStyleBeatsAnOuterImage` (built as one test) - the ranking (probe `I7`, `P11`).
   *Mutation:* resolve outermost first.
6. `anImageIgnoresResizableAndInterpolation` (`IC-B`, probe `I5`). *Mutation:* read `isResizable` into the size.

**Lane B, AppKit (`Tests/MetalUITests/AppKitImageCursorTests.swift`; unfiltered full run, `CLAUDE.md`)**
7. `appKitImageCursorHasTheImagesPointSizeHotSpotAndStoredPixels` - `cursor.image.size`, `hotSpot`, the rep's
   pixel bytes equal the texture's premultiplied bytes (`AI-E`). *Mutations:* flip y; un-premultiply.
8. `appKitCachesAnImageCursorPerImageAndBoundsTheCache` - same style twice gives the same `NSCursor`; 17
   distinct images keep 16. *Mutations:* remove the cache; remove the bound.

**Lane B, typecheck guards** (new; each mutated red once)
9. `anOutsideSwitchOverPlatformPointerStyleOwesTheImageCase` (`typecheckFile`, plain import): a `switch`
   naming the twelve old cases without `default:` fails to compile (separating arm: the same switch with
   `default:` compiles). *Mutation:* delete the new case.
10. `aPlatformCursorImageCanBeBuiltFromAPlainImport` - the public init is spellable outside (the SDL package
    needs it). *Mutation:* make it `package`.

**Lane B, SDL (`Backends/SDL/Tests/MetalUISDLTests/SDLImageCursorTests.swift`; `armMainRunLoopExitCheck()`;
the offscreen driver may not create a cursor. Per `IC-O` the bounded table is a pure `SDLCursorTable<Handle>`
with injected create/destroy, so tests 13-15 run on every driver, in the Linux image included, over a fake
handle; only 11, 12 and 17 read the C recorder, which counts even a refused create, and any assertion that
needs a real created cursor is `.enabled(if:)` on a driver that makes one. Tests 13-15 are ungated.)**
11. `anSDLImageCursorIsCreatedFromStraightAlphaPixels` - `mui_cursor_last_pixel` of (100, 50, 25, 128)
    premultiplied reads (199, 100, 50, 128) (`AI-F`). *Mutation:* pass premultiplied bytes.
12. `anSDLImageCursorGetsItsHotSpotInSurfacePixels` - `.center` on 16 pt scale 1: (8, 8); scale 2 (32 px
    surface via alternate): primary hot (8, 8), `mui_cursor_last_alternate_count` 1. *Mutations:* hot spot in
    points for the alternate; drop the alternate.
13. `aReturnedImageReusesItsCursor` - A, B, A: `created` 2. *Mutation:* no table.
14. `theNinthImageEvictsTheLeastRecentlyUsedAndNeverTheCurrent` - 9 images: `destroyed` 1, `live` 8; the
    current one is not the destroyed. *Mutations:* no bound; evict the current.
15. `closingTheLastWindowDestroysEveryImageCursor` - `live` 0 after; and a still-open second window keeps them.
    *Mutation:* destroy on any window close / never.
16. `grabAndZoomStayOnSystemCursors` (CI-H 8, `IC-H`) - the table is unchanged for the old styles.
    *Mutation:* map `.zoomIn` through the image path.
17. `anImageCursorIsNotSetTwiceForTheSameStyle` - `SDL_SetCursor` counter (`mui_cursor_set_count`) 1.
    *Mutation:* drop the skip.

**Lane A (`SDLHeadlessLaunchTests.swift`, `HeadlessLaunchCheck`)**
18. `headlessOptionsHideWindowsAndRenderOffscreen` - `Options.headless` platform: the injected `showWindow`
    never runs (`WS-D`) and `rendersOffscreen` is true. *Mutation:* `.headless` with `rendersOffscreen` false.
19. `theEnvironmentConvenienceReadsOnlyTheValueOne` - `"1"` headless; `"0"`, `"true"`, `""`, absent default.
    *Mutation:* accept any non-empty value.
20. `aHeadlessAppRunsItsTaskAndExits` - (`IC-P`: the check bounds itself by loop iterations, never time, and the
    test kills only its own child process at a generous deadline and fails on it) launches `HeadlessLaunchCheck` (plain import of `MetalUISDL`, recipe
    verbatim) in a process; reads `task ran=true` and exit 0 under `SDL_VIDEO_DRIVER=offscreen`; **ungated, in
    the Linux image**. *Mutation:* `.headless` without offscreen renderers: the check ends at its iteration
    bound with `task ran=false` (red). The plain import is itself the guard that `Options` needs no SPI.
21. `theSPIInitialiserStillForwards` - `MainQueueDrainCheck`'s existing `task-modifier-offscreen` test stays
    green through the SPI spelling. *Mutation:* make the SPI init ignore `offscreenRenderers`.
22. `anSDLPlatformWithoutTheSDLTraitNamesTheTraitForItsOptionsInitialiser` - extends guard 1.6 (trait off): `SDLPlatform(options:)`
    reports the trait message. *Mutation:* delete the stub's init.

Counts (a plan, re-measured, never trusted): root = items 1-8 as tests (6 + 2 AppKit; some are parameterised,
count by `@Test` function) + items 9-10 as 2 guards; `Backends/SDL` = items 11-22 (12 tests, counting 13-15 once
in the pure table and once through the platform where it differs).

## 6 Demo expectation

`METALUI_CANVAS_DEMO=1`: the pointer strip gains a "ring" cell (generated bitmap, hot spot at the ring's
centre); on macOS the ring follows the pointer exactly; on SDL it does too. No default tree changes.

## 7 Human checks (group IC, `docs/verification/human-checks.md`)

- **IC1** SDL on Linux and Windows: the hand/zoom recipe cell (`IC-H`) shows the supplied images, not the move
  cursor, hot spot on the click point.
- **IC2** macOS on a 2x and a 1x display: the cursor is crisp and the same point size on both.
- **IC3** every platform: the hot spot lands on the clicked pixel at the four corners of the image.
- **IC4** Windows (UTM or CI) and Linux: a `HeadlessLaunchCheck`-shaped app exits 0 in CI with no display.

## 8 Verification plan

Root suite unfiltered under `--build-system native` (read the one summary line, `FR-J` line, 0 `error:`);
`swift build --build-tests` 0 warnings; `Backends/SDL` suite; the Linux image (`metalui-sdl-build-cursors-headless`
volume); the fourteen images 0 px; Windows via CI. A real-window look only when the lock probe allows
(it read LOCKED at design time, so IC checks wait).

## 9 Deferred (named, with an owner)

| Item | Why | Owner |
|---|---|---|
| `PointerStyle.shape(_:eoFill:size:)` | `size:`, colour and hot spot unprobed (`IC-G`) | a follow-up item when an app asks; the recipe is rasterize-then-`.image` |
| Bundled hand/zoom art for SDL | design asset + notices (`IC-H`) | none; the recipe |
| `columnResize(directions:)`/`rowResize(directions:)` | still `CI-A` | none |
| A cursor bitmap SDL/OS refuses (size limits) | platform-specific; leaves the current cursor (`IC-C` 3) | human check IC1 reports sizes |
| Wayland/X11 colour-cursor behaviour | not machine-testable here | CI Linux + IC1 |
