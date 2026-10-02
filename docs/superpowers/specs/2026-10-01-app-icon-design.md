# App icon — design

User request 2026-10-01; **not a plan task**. Rulings `AI-A`…`AI-H` in
[`../2026-10-01-app-icon-decisions.md`](../2026-10-01-app-icon-decisions.md)
(binding; this spec is the implementation plan). Record:
`docs/record/70-app-icon.md` (Record phase). Branch `feat/app-icon` from
`330f02b`; baseline **2028 / 0 / 125** tests/goldens/guards, `Backends/SDL`
22 + 41.

## 1. What exists today

- No icon API anywhere: 0 hits for `applicationIconImage`/`SDL_SetWindowIcon`
  in `Sources`/`Backends`. `swift run MetalUIDemo` shows the generic
  executable icon in the Dock.
- `ImageBitmap` (`Sources/MetalUI/ImageBitmap.swift`): straight-alpha RGBA8 in,
  stored as an `ImageTexture` (`Sources/MetalUIScene/ImageTexture.swift`:
  premultiplied RGBA8, sRGB, immutable class, `pixels` public). Invalid sizes
  trap at construction (exit test `anImageBitmapOfTheWrongByteCountOrAZeroSideTraps`).
- `Platform` (`Sources/MetalUIPlatform/Platform.swift`): `openWindow`, `run`.
  Conformers: `AppKitPlatform` (`Sources/MetalUIAppKit/AppKitPlatform.swift`),
  `SDLPlatform` (`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`). **No
  test fake conforms to `Platform` today** (tests build `App(device:)` or a
  `Window` over `FakePlatformWindow`).
- `PlatformWindow` conformers (untouched by this feature, `AI-B`):
  `AppKitWindow`, `SDLWindow`, `FakePlatformWindow`, and the private
  `Conformer`s in `TransactionCompileGuards`, `ControlStateCompileGuards`,
  `DragAndDropCompileGuards`.
- SDL calls go through `Backends/SDL/Sources/SDLBridge/SDLBridge.c` +
  `include/SDLBridge.h` (`mui_*` functions); SDL 3.4.16 locally has
  `SDL_SetWindowIcon`, `SDL_AddSurfaceAlternateImage`, `SDL_GetSurfaceImages`.

## 2. API (ruled)

```swift
// MetalUI — AI-A, AI-C
@MainActor public final class App {
    /// doc: application-wide; [] = the platform's own; SwiftUI has no runtime
    /// icon API (bundle asset catalog / CFBundleIconFile); AppKit's override is
    /// NSApplication.applicationIconImage; SDL applies it to every window.
    public var icon: [ImageBitmap] = [] { didSet { platform.setApplicationIcon(normalized(icon)) } }
}

// MetalUIPlatform — AI-B (no default implementation)
public protocol Platform: AnyObject {
    func setApplicationIcon(_ images: [ImageTexture])
}

// MetalUIAppKit — AI-E
public final class AppKitPlatform { public func setApplicationIcon(_ images: [ImageTexture]) }
enum AppKitIcon { static func image(from textures: [ImageTexture]) -> NSImage? }   // internal; nil for []

// MetalUISDL — AI-F
public final class SDLPlatform { public func setApplicationIcon(_ images: [ImageTexture]) }
enum SDLIcon {                                                   // internal
    static func straightRGBA(_ texture: ImageTexture) -> [UInt8]
    static func makeSurface(_ textures: [ImageTexture]) -> UnsafeMutableRawPointer?  // caller destroys
}
// SDLWindow: internal `private(set) var iconResult: (textures: [ObjectIdentifier], applied: Bool)?`

// MetalUIDemoContent — AI-G
public func demoIcon() -> [ImageBitmap]
```

`normalized` (internal, `App.swift`): stable sort by `width × height`
ascending, drop a later bitmap repeating an earlier `(width, height)` pair,
map to `.texture`. `App`'s didSet is the **only** caller of
`setApplicationIcon` in `MetalUI`; no initialiser calls it (`AI-C` item 1).

C bridge (`SDLBridge.h`/`.c`, `AI-F` item 2):

```c
extern const uint32_t MUI_PIXELFORMAT_RGBA32;            // = SDL_PIXELFORMAT_RGBA32
void *mui_icon_surface_create(int32_t w, int32_t h, const uint8_t *straight_rgba); // NULL on failure
bool  mui_icon_surface_add_alternate(void *primary, void *image);
bool  mui_window_set_icon(void *window, void *surface);
void  mui_surface_destroy(void *surface);
// test readback:
uint32_t mui_surface_format(void *surface);
void  mui_surface_size(void *surface, int32_t *w, int32_t *h);
bool  mui_surface_read_rgba(void *surface, uint8_t *out, int32_t capacity); // row by row via pitch
int32_t mui_surface_image_count(void *surface);           // SDL_GetSurfaceImages count
void  mui_surface_image_size(void *surface, int32_t index, int32_t *w, int32_t *h);
```

## 3. Demo icon (`AI-G`)

`demoIcon()` returns sizes `[16, 32, 64, 128, 256, 512]`, in that order, each
square. For size `s`, the pixel at column `x`, row `y` (top-left origin) is
classified by its **centre** `(x + 0.5, y + 0.5)` — binary coverage, no
anti-aliasing (deterministic and trivially pinned, `AI-G`):

- outside the rounded square `[0, s] × [0, s]` with corner radius `0.22 s` →
  `(0, 0, 0, 0)`;
- inside the disc centred `(s/2, s/2)` with radius `0.28 s` → `(255, 255, 255, 255)`;
- else (inside the square) → `(47, 111, 235, 255)` (`#2F6FEB`).

Pinned values at `s = 16` (disc radius 4.48 about (8, 8); corner radius
3.52 about (3.52, 3.52)): `(0,0)` → `(0,0,0,0)`; `(15,15)` → `(0,0,0,0)`;
`(8,8)` → white; `(1,8)` → `(47,111,235,255)`; **boundary pins**: `(3,8)`
→ accent (centre distance √(4.5² + 0.5²) = 4.528 > 4.48; at radius 0.30 s =
4.8 it would be white); `(4,8)` → white (3.536); `(0,1)` → `(0,0,0,0)`
(distance to the corner centre √(3.02² + 2.02²) = 3.63 > 3.52); `(1,1)` →
accent (2.857). Built in its own function (no
builder), outside every element tree.

## 4. Lanes

Two lanes, **run in order** (agents run one at a time here). Lane 1's
requirement makes `Backends/SDL` fail to compile until lane 2's first commit —
by construction of `AI-B` (no default). Lane 1 must not add a stub to
`Backends/SDL`.

### Lane 1 — portable API, AppKit, fakes, demo, inventory (Opus)

Files: `Sources/MetalUIPlatform/Platform.swift`, `Sources/MetalUI/App.swift`,
`Sources/MetalUIAppKit/AppKitPlatform.swift` and new
`Sources/MetalUIAppKit/AppKitIcon.swift`, new
`Sources/MetalUIDemoContent/DemoIcon.swift`, `Sources/MetalUIDemo/main.swift`,
`Tests/MetalUITests/Fakes.swift` (`FakePlatform`: records `iconCalls:
[[ImageTexture]]`, `openWindow` returns a `FakePlatformWindow` over the system
device, `run()` no-op), new `Tests/MetalUITests/AppIconTests.swift`,
`AppKitIconTests.swift`, `AppIconCompileGuards.swift`;
`docs/probes/closeout-inventory-map.tsv` (a family `app-icon`, class M,
ruling `AI-A`, plus mapping rows for `App.icon`,
`Platform.setApplicationIcon`, `AppKitPlatform.setApplicationIcon`,
`demoIcon`) and the recorded census `docs/probes/closeout-public-api.tsv` if
the check reads it. Every new public declaration gets a doc comment.

### Lane 2 — SDL, packaging, human checks (Opus; docs may be the same agent)

Files: `Backends/SDL/Sources/SDLBridge/SDLBridge.c`,
`include/SDLBridge.h`, `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`
and new `SDLIcon.swift`, `Backends/SDL/Sources/MetalUISDLDemo/main.swift`,
new `Backends/SDL/Tests/MetalUISDLTests/SDLIconTests.swift`, new
`docs/packaging.md`, `docs/verification/human-checks.md` (group **O**, after
N, before Sign-off). Also: the `swift:6.4-noble` container builds MetalUI
and `Backends/SDL` (OrbStack; start if stopped, stop after).

Either lane appends rulings `AI-I`… to the decisions doc, moving its
"next unused" line in the same commit.

## 5. Tests (every one red before its implementation; mutation that must redden it)

Lane 1 — `AppIconTests.swift` (`FakePlatform`, `App(platform:)` with CoreText):

| # | Test | Mutation that must redden it |
|---|---|---|
| 1.1 | `anAppThatNeverSetsAnIconNeverCallsThePlatform` — build `App`, open a window: `iconCalls.isEmpty` | **M1a** `App.init` calls `setApplicationIcon([])` |
| 1.2 | `settingTheAppIconReachesThePlatformOnceWithTheBitmapsOwnTextures` — one call; `ObjectIdentifier`s equal the bitmaps' `texture`s | **M1b** `didSet` removed; **M1c** passes copies (`ImageTexture(…pixels…)`) |
| 1.3 | `theAppIconReachesThePlatformSmallestFirstWithoutRepeatedSizes` — assign [32², 16², 32²′, 8×64]: call holds 16², 8×64, 32² (first), in that order | **M1d** no sort; **M1e** no dedupe; **M1f** dedupe keeps last |
| 1.4 | `theAppIconReadsBackExactlyAsAssigned` — `icon` returns the four, unsorted, identities equal | **M1g** store the normalized list |
| 1.5 | `settingTheAppIconAgainReplacesItAndClearingPassesAnEmptyList` — three assignments ([a], [b], []) → three calls `[a]`, `[b]`, `[]` | **M1h** short-circuit on equal count; **M1i** skip the call for `[]` |
| 1.6 | `theDemoIconIsSixSquareBitmapsFrom16To512` | **M1j** drop the 512 |
| 1.7 | `theDemoIconsPixelsAreTheSpecifiedShape` — §3's eight pins at 16, and the 512's centre (white) and `(0,0)` (clear) | **M1k** disc radius 0.30 s (moves `(3,8)`); **M1l** corner radius 0.18 s = 2.88 (moves `(0,1)` to accent: distance to (2.88, 2.88) is √(2.38² + 1.38²) = 2.75 < 2.88) |

Lane 1 — `AppKitIconTests.swift` (AppKit; run the whole suite unfiltered):

| # | Test | Mutation |
|---|---|---|
| A1 | `anIconImageHoldsOneRepresentationPerTextureSmallestFirst` — reps' `pixelsWide/High` in input order, every rep's `size` = image `size` = largest | **MA1** only the first texture becomes a rep |
| A2 | `anIconRepresentationCarriesTheTexturesPremultipliedBytesUnchanged` — rep's `CGImage`: `alphaInfo == .premultipliedLast`, colour space sRGB, provider bytes == `texture.pixels` (a 3×2 texture with straight (200,100,50,128) and an opaque and a clear texel) | **MA2** un-premultiply before wrapping |
| A3 | `anIconRepresentationDrawsWithoutASecondPremultiply` — draw the rep into a premultiplied RGBA8 sRGB context: the half-alpha texel reads (100, 50, 25, 128) | **MA3** label `.last` instead of `.premultipliedLast` (expected (50, 25, 13, 128)) |
| A4 | `settingTheIconOnTheAppKitPlatformSetsTheApplicationIconImage` — `applicationIconImage`'s reps match; `[]` → `nil`; restores `nil` in a `defer` | **MA4** method body empty; **MA5** `[]` leaves the old image |
| A5 | `anEmptyTextureListMakesNoIconImage` — `AppKitIcon.image(from: [])` is `nil` | **MA6** returns an empty `NSImage` |

Lane 1 — `AppIconCompileGuards.swift` (**one** new guard, whole-file
`typecheckFile`, `import MetalUIPlatform`; guards 125 → 126):

| G1.1 | `aPlatformWithoutSetApplicationIconDoesNotCompile` — a `Platform` conformer without the member is refused naming `setApplicationIcon`; with `AI-B`'s migration spelling it compiles (`try #require` both arms disagree) | **MG1.1** a protocol-extension default (the negative compiles) |

Lane 2 — `SDLIconTests.swift` (each test arms `armMainRunLoopExitCheck()`;
hidden windows):

| # | Test | Mutation |
|---|---|---|
| S1 | `unpremultiplyingRestoresStraightAlpha` — (100,50,25,128)→(199,100,50,128); (255,0,0,255) unchanged; (0,0,0,0) and (10,20,30,0)→(0,0,0,0); (200,0,0,100)→(255,0,0,100) | **MS1** identity (no un-premultiply); **MS2** no clamp (traps — record the crash as the reddening); **MS3** `a == 0` keeps colours |
| S2 | `anIconSurfaceIsRGBA32HoldingTheStraightBytesRowByRow` — a 3×2 texture: format == `MUI_PIXELFORMAT_RGBA32`, size 3×2, readback == `straightRGBA` | **MS4** swap `w`/`h` at create; **MS5** create with the premultiplied bytes |
| S3 | `anIconSurfaceCarriesEveryLargerTextureAsAnAlternate` — [16², 32², 64²]: primary 16², image count 3, sizes ascending | **MS6** skip `add_alternate` |
| S4 | `settingTheIconAppliesItToEveryOpenWindow` — two windows: both `iconResult` textures == the set, `applied == true` (on macOS; on a backend that answers `false` the test records it) | **MS7** apply to the first window only |
| S5 | `aWindowOpenedAfterTheIconIsSetGetsIt` — via `App(platform:)`: set `app.icon`, then open a window | **MS8** `openSDLWindow` skips the stored icon |
| S6 | `clearingTheIconLeavesOpenWindowsAndGivesNewOnesNone` — `[]`: open window's `iconResult` unchanged, a new window's `nil`; `mui_window_set_icon` never called with `NULL` | **MS9** a new window gets the last non-empty icon |

Expected counts after both lanes: **2041 tests** (2028 + 7 + 5 + 1: 1.1–1.7,
A1–A5, G1.1 — a guard is also a test), **126 guards**, 0 goldens;
`Backends/SDL` **22 + 47** (S1–S6). Lane 1 re-takes and states the measured
sum; a count is stale the moment a test lands.

## 6. Must not move (checked by each lane before its last commit, and the Record phase)

0 px against `330f02b` in all fourteen offscreen images
(`docs/probes/demo-pixels/compare.sh <scratch> 330f02b HEAD`);
`DemoFrameDeterminismTests`' `Expected.swift` unedited;
`everyProductionTreeBuildsOnAOneMegabyteThread` green; 0 `error:`, the only
`warning:` SwiftPM's deprecation notice under native and 0 under the default
build system; `MetalUIScene`/`MetalUILayout` import rules; identity, hit
testing, accessibility, animation, focus, rendering untouched (no file under
those areas is edited); `zsh docs/probes/closeout-inventory-check.sh` and
`zsh docs/probes/closeout-undocumented.sh` print nothing; `Backends/SDL`
builds and passes on macOS; the noble container builds both packages.

## 7. Notes for the lanes

- 1.7's mutations must each move a pinned pixel; §3 gives the arithmetic;
  copy it into the test's doc comment and re-run the mutation (a green
  mutant is a broken pin).
- AppKit tests touch `NSApplication.shared.applicationIconImage`, a process
  global: restore `nil` in `defer`, and run the suite unfiltered.
- SDL on macOS: `SDL_SetWindowIcon` changes the test process's Dock image;
  harmless, but S4's `applied == true` is the macOS measurement — off macOS
  the backends are only exercised by the human checks (O3, O4).
- Human checks group O: O1 `swift run MetalUIDemo` → Dock shows the blue
  rounded square with a white disc (and after quitting, nothing lingers);
  O2 `swift run --package-path Backends/SDL MetalUISDLDemo` on macOS → Dock
  icon; O3 Linux (X11, and Wayland noting `xdg-toplevel-icon-v1`) window/
  taskbar icon; O4 Windows title bar and taskbar icon. Each with its
  headless pin.
