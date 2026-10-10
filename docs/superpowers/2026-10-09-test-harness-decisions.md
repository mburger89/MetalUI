# Test harness — decisions (`HT-`)

Item 8 of the gpui-gap list (user request 2026-10-02; not a plan task): a
public test harness. Requested by MetalCreator (`metalui-gaps.md` M6-e, M7-b,
TH-a) and the SMK configurator port (`2026-10-06-metalui-gaps.md` MG-17,
MG-12). Spec: `docs/superpowers/specs/2026-10-09-test-harness-design.md`.
Record: `docs/record/91-test-harness.md`. Branch `feat/test-harness` from
`70e9389`.

**Next unused id: `HT-U`.** (Read the last `## HT-` heading, not this line,
if they disagree.)

Evidence:

- **E1** — `docs/probes/swiftui-xcuitest-test-surface.sh`, run 2026-10-09
  (Xcode-beta, Swift 6.4 `swiftlang-6.4.0.33.1`, macOS 27). X1 (XCUITest's
  element actions) typechecks; X2 (`rightTap()`, separating) does not; S0 finds
  `class ImageRenderer` (2) and `onGeometryChange` (10) in the SwiftUI and
  SwiftUICore interfaces; S1 finds `func simulate`, `Simulat`, `TestHost`,
  `func inject`, `ViewInspect` **0** times each; R1–R3 run ImageRenderer,
  `NSHostingView.fittingSize` and an in-view `onGeometryChange` headless.
- **E2** — gpui's `crates/gpui/src/app/test_context.rs` (zed `main`, read
  2026-10-09 through the web, **not probed**: gpui is a precedent, not an
  authority): `TestAppContext` (`simulate_keystrokes`, `simulate_input`,
  `dispatch_action`, `run_until_parked`, `simulate_window_resize`,
  `simulate_window_scale_factor_change`, `simulate_prompt_answer`,
  `simulate_path_prompt_response`, `pending_prompt`) and `VisualTestContext`
  (`simulate_mouse_move/down/up`, `simulate_click`, `simulate_event`,
  `simulate_modifiers_change`, `simulate_resize`, `debug_bounds(selector)`).
- **E3** — the source at `70e9389`: `App(platform:textSystem:)` and
  `App.openWindow` are public; every `PlatformWindow`/`Platform` requirement,
  `InputEvent` and its payloads, `AccessibilityTree`/`AccessibilityRequest`,
  `PlatformMenu`/`PlatformMenuBar`/`PlatformAlert`/`PlatformFileDialog`/
  `PlatformToolbar`, `Scene` and `GlyphAtlas.dirtyRect`/`clearDirtyRect()` are
  public. `Window.init`, `recordsElementBounds`/`lastElementBounds`,
  `onFrameAdopted`, `animationStore.rasters`, `MenuSession.number` and
  `LayoutTree.lastNativeLayoutWork` are not. The SMK port's
  `PlatformChromeTests` already drives a real `Window` through a hand-written
  `Platform` (MG-17 status at `70ed000`, ~80 lines per app, broken by every new
  defaultless requirement).

---

## HT-A — One library product, `MetalUITesting`, portable, linked by test targets only

**Ruling.**
1. A new target and library product **`MetalUITesting`** (`Sources/MetalUITesting`),
   declared in the manifest's **portable** list (`PC-A`): it depends on
   `MetalUI` and `MetalUIScene` only and imports nothing else — **no AppKit,
   Metal, CoreText or Foundation** (the Linux and Windows root jobs build it;
   macOS cannot see a violation).
2. `MetalUI` does **not** depend on or re-export it. An app adds it to its
   **test target's** dependencies (`.product(name: "MetalUITesting", package: …)`),
   so a production executable never links it.
3. It works from swift-testing and XCTest alike: every API is `@MainActor`
   and synchronous except `runUntilIdle()` (async); errors are thrown
   (`TestHarnessError`), never trapped, so a failing query fails one test.
4. `Tests/MetalUITestSupport` (the typecheck helpers, in no product) and
   `Tests/MetalUITests/Fakes.swift` stay as they are (`CI-N` unchanged):
   `FakePlatformWindow` renders through Metal into a readable texture, which
   the pixel-readback tests need and a portable harness cannot offer.

**Reasoning.** M6-e asks for "a public headless `Window` … in a test-support
product"; MG-17 names the cost of each app writing its own fake. A separate
product keeps the test surface out of `MetalUI`'s census of app API and out of
shipped binaries. Portability is the SMK port's requirement (its tests run on
all three platforms).

**Cost if wrong.** If an app wanted the harness in production code (a
headless renderer for thumbnails), it can still link the product; nothing
stops it. If `MetalUITesting` ever needs Foundation, the rule is relaxed by a
ruling, not silently.

## HT-B — The shape is gpui's TestAppContext/VisualTestContext; SwiftUI has no in-process harness

**Ruling.**
1. **SwiftUI offers no in-process input injection or element query** (E1, S1
   all 0 with S0 found): its headless surfaces are `ImageRenderer` (pixels) and
   a hosting view's size; a SwiftUI app tests its UI **out of process through
   XCUITest**. There is no SwiftUI spelling to align with, so the harness is
   **MetalUI-only** (inventory class `M` for every declaration).
2. Its **structure** follows gpui's test contexts (E2), the framework MetalUI
   is modelled on: an application-level `TestApp` (gpui `TestAppContext`) that
   opens `TestWindow`s (gpui `VisualTestContext`), each a real window over a
   test platform, with simulated input, a simulated clock, `runUntilIdle()`
   (gpui `run_until_parked`), resize and scale simulation, prompt answers
   (`simulate_prompt_answer`, `simulate_path_prompt_response`) and a bounds
   query by a name the element carries (`debug_bounds(selector)` ↔ `.id`, HT-G).
3. Its **action names** are XCUITest's (HT-F), since that is what a SwiftUI
   developer already writes for the same act.
4. **ViewInspector is rejected** as the precedent: it reflects over a SwiftUI
   view value's structure. MetalUI rebuilds the tree every frame and layout,
   hit testing and accessibility exist only in the built frame, so a reflected
   element value answers none of M6-e's questions (routing, layout, menus).

**Cost if wrong.** Names are the only SwiftUI-facing surface; a later Apple
in-process harness would get a re-spelling ruling with deprecations.

## HT-C — Built on the public seams; the only `MetalUI` additions are `package` read-back hooks in new files

**Ruling.**
1. `TestApp` wraps a real `App(platform: HeadlessPlatform)`; `TestWindow`
   wraps the real `Window` that `App.openWindow` returns. **Every injected
   event goes through `PlatformWindow.onInput`** — the closure `Window.init`
   installed, the one a platform calls — and every tick through the closure
   `Window` handed `startDisplayLink`. Commands, the menu bar, the app shell's
   close and terminate, the lifecycle drain and the colour scheme all run as
   in a shipped app.
2. **`Window.swift` is not edited.** Read-back that has no public spelling is
   added as `package` members in **new files** in `Sources/MetalUI`
   (`TestingHooks.swift`: element bounds, frame work; `TestingMenuHooks.swift`:
   menu evaluation) reading internal state from the same module; and two
   `package` widenings in `MetalUILayout` (`NativeLayoutWork`,
   `LayoutTree.lastNativeLayoutWork`). `package` is unspellable outside this
   package, so an app sees only `MetalUITesting`'s public API (guard 3.2).
3. `Window.init` stays internal (guard 3.3): an app opens a window through
   `TestApp`/`TestWindow`, which go through `App.openWindow`.
4. `Window.onFrameAdopted` (internal, one slot, test-only) is **owned by the
   harness** for windows it opens; nothing else in `Sources/` sets it.

**Reasoning.** Driving the real seams is what makes a harness test mean
something about the shipped app (the SMK port's `PlatformChromeTests` reached
the same conclusion by hand). Parallel branches C9 (key dispatch in
`Window.swift`), C12 (menus on SDL) and C13 (`RasterCache`) are live; new files
keep the merge additive.

**Cost if wrong.** If a hook needs a value `Window` does not keep, the lane
adds one internal stored property with a migration-free one-line capture and
says so in the record — not a rewrite.

## HT-D — `HeadlessPlatform`, `HeadlessPlatformWindow`, `HeadlessWindowRenderer` are public and honest

**Ruling.**
1. Three public final classes in `MetalUITesting`, each implementing **every**
   requirement of `Platform`, `PlatformWindow` and `WindowRenderer` with no
   stub: what the window asks is recorded (titles, preferred schemes, pointer
   styles, text input areas, size limits, document-edited, represented paths,
   title-bar styles, drags out, menus, alerts, file dialogs, dismissals,
   toolbars, published accessibility trees, clipboard, icons, menu bar,
   terminate replies), and the platform's events can be simulated (input,
   ticks, resize, scale, appearance, key state, Reduce Motion, close request,
   terminate request, open-URLs).
2. **The renderer presents every frame**: `beginFrame()` returns the window's
   scale factor; `finishFrame` keeps the `Scene`, accounts the atlas upload
   (the dirty rect's area, then `clearDirtyRect()` — what both GPU renderers
   do), counts textures not referenced by the previous frame and their texels,
   records the frame's `SurfaceDrawRequest`s **and runs none of them** (there
   is no GPU context to hand a `GPUSurface` draw; deferred, HT-Q), and returns
   `true`. A test can make the next `beginFrame()` answer `nil`
   (`failsNextFrame`), as `FakeRenderSurface` does.
3. **Presentation answers are options** (`HeadlessPlatformWindow.Options`):
   `presentsMenusNatively`, `presentsAlertsNatively`, `presentsFileDialogs`,
   `showsToolbarNatively`, `appliesTitleBarStyle` default **`true`** (AppKit's
   answers: the request is recorded and the test answers it, HT-H);
   `false` gives SDL's answers, so the window draws its menu, alert or toolbar
   strip and the test drives it by input or accessibility.
   `externalDragResult` defaults `false` (SDL's).
4. **Accessibility client at open**: with `Options.accessibilityClientActive`
   (default `true`) the window answers the `onAccessibilityRequest` assignment
   `Window.init` makes by sending `.activate` at once — a screen reader already
   running when the window opens (`WS-` precedent) — so the tree is in the
   first frame and no extra frame is drawn. **Fallback if measured unsafe**:
   activate after `openWindow` returns and draw once; the record says which.
5. **A new defaultless `PlatformWindow`/`Platform`/`WindowRenderer` requirement
   now owes an implementation here too** (CLAUDE.md rule at the Record phase,
   beside "both conformers and every test fake"). A parallel branch adding one
   (C9, C12) breaks this branch's build at merge, not silently: the merge adds
   it. This is the point of MG-17: the cost moves from every app into MetalUI.

**Cost if wrong.** If an option default is the wrong platform's, a test reads
an empty `presentedAlert`; the doc comment and `docs/testing.md` say which
defaults are AppKit's.

## HT-E — A simulated clock; actions draw one frame; `runUntilIdle()`

**Ruling.**
1. A `TestWindow` opens with `startsDisplayLink: true` (the headless window
   keeps the tick closure; nothing fires on its own). The clock `now` starts at
   **0** and moves only by `advance(by:)` (one tick at `now + seconds`) and
   `advanceFrames(_:)` (that many ticks, `1/60` s apart: the display link's
   pacing, M7-b). `tick()` fires one tick at `now`.
2. **Every high-level action** (HT-F) delivers its events stamped `now`, then
   fires one tick at `now` — the frame a display link would draw next. A
   `click` is down + up then one tick (gpui's `simulate_click`); a `drag` is
   down, `steps` dragged events each followed by `advanceFrames(1)`, up, tick.
   `send(_:)` delivers one raw `InputEvent` and draws nothing.
3. `runUntilIdle() async` (gpui `run_until_parked`): repeats `await Task.yield()`
   then `tick()`, **without advancing the clock**, until a round draws no frame
   or the only reason to draw is an active animation (which needs the clock);
   bounded at 64 rounds, then throws `TestHarnessError.notIdle`. A `.task`
   whose work is main-actor and timer-free completes inside it; one awaiting
   real time (`Task.sleep`) does not — a test injects its own clock (deferred,
   HT-Q).
4. Tests never sleep; the harness never reads a wall clock.

**Reasoning.** One frame per action matches the order of real events (input,
then the next tick) and makes "click then assert" one line; the raw `send`
keeps a benchmark's frame count exact. Yield-based settling is the only
in-process way to let main-actor tasks run without a real run loop.

**Cost if wrong.** A test needing a frame between press and release spells it
with `send` + `tick`; nothing is lost.

## HT-F — Action vocabulary: XCUITest's names, AppKit's key routing

**Ruling.**
1. Names from XCUITest (E1, X1), on `TestWindow`, each taking a `TestElement`
   (aimed at the centre of its **visible** frame, the rect its hitbox
   registers at; zero area throws `.notHittable`) or a point:
   `click`, `doubleClick` (clickCount 1 then 2), `rightClick`, `hover`,
   `typeText(_:)`, `typeKey(_:modifierFlags:)` (a `KeyEquivalent` and
   `EventModifiers`), `scroll(byDeltaX:deltaY:)`, `click(forDuration:thenDragTo:)`.
2. MetalUI-only additions where XCUITest has none (gpui's `simulate_*`):
   `drag(from:to:steps:button:modifierFlags:)`, `otherClick`, `magnify`,
   `rotate`, `pressModifiers(_:)` (`.modifiersChanged`), `exitPointer()`,
   `drop(_:at:)`, `send(_:)`.
3. **Key routing mirrors the platforms** (`MetalHostView.keyDown` and SDL's
   `producesText`): while the window has set a text input area (a field is
   focused, `setTextInputArea` non-nil) a key with no ⌘ or ⌃ that produces
   text is delivered as `.textInput`; otherwise `.keyDown` then `.keyUp`.
   `characters` has Shift applied; `charactersIgnoringModifiers` too for a
   letter (AppKit's "ignoring modifiers except Shift"). `typeText` sends one
   such key per `Character`.
4. Every mouse event carries the harness's tracked modifier state (`pressModifiers`)
   unioned with the call's `modifierFlags`, and moves the pointer first with a
   `.mouseMoved` when it is not already at the point (a real pointer travels).

**Cost if wrong.** A routing mismatch shows as a test passing headless and
failing on a platform; pinned by test 1.9 (a plain-letter keymap binding is
silent while a field is focused, CLAUDE.md "Text input").

## HT-G — Queries: the accessibility tree (XCUITest's model) and `.id` frames (gpui's `debug_bounds`)

**Ruling.**
1. **Elements are found through the published `AccessibilityTree`** — the
   model XCUITest queries (identifier, label, role) and the one tree both
   platform bridges publish: `element(identifier:)`, `element(label:)`,
   `elements(role:)`, `elements(where:)`, `focusedElement`. A `TestElement` is
   a value snapshot of one node in the last published tree (`id`, `role`,
   `label`, `value`, `identifier`, `hint`, `frame`, `visibleFrame`,
   `isEnabled`, `isSelected`, `isFocused`, `children`). No match throws
   `.noElement`, several throw `.ambiguous` (listing them) for the singular
   queries.
2. **Layout frames by `.id(name)`**: `frame(ofID:)` / `frames(ofID:)` read the
   window's `Frame.recordElementBounds` record of the last build — every
   element, not only accessible ones — matching ids whose last component is
   `.named(ElementID(name))`. Window content space, logical points. This is
   MG-12's "the inspector is 248 wide".
3. `recordsLayout` (default `true`) turns recording on for the harness's
   windows; `accessibilityClientActive` (default `true`) the tree. A benchmark
   turns both off so a frame does only production work; a query then throws
   `.notRecorded`.
4. `performAccessibilityAction(_:on:)` sends an `AccessibilityRequest`
   (press, increment, decrement, focus, showMenu) as a screen reader would;
   `focus(_:)` is `.focus`.

**Reasoning.** Identifier/label/role queries are what a SwiftUI developer
already knows; using the published tree means a query that works is also a
VoiceOver fact. `.id` gives every element a name without forcing an
accessibility identifier onto layout boxes.

**Cost if wrong.** A layout box with no `.id` and no accessibility node is
unfindable; the test adds `.id` (no state cost beyond what `.id` already
means — a test that adds `.id` changes identity, said in `docs/testing.md`).

## HT-H — Presentations, menus and the menu bar are read at the seam and answered as a platform does

**Ruling.**
1. **No mirror types**: the harness exposes the seam values the window handed
   its platform — `presentedAlert: PlatformAlert?`, `presentedFileDialog:
   PlatformFileDialog?`, `presentedMenu: PlatformMenu?`, `toolbar:
   PlatformToolbar?` — the latest not yet answered or dismissed.
2. Answers are the queued `InputEvent`s a platform sends:
   `respondToAlert(button:)` (title or index) → `.alertResult`;
   `respondToFileDialog(choosing:)`, `cancelFileDialog()` → `.fileDialogResult`;
   `chooseMenuItem(_ path: String...)` (titles, submenus by path) /
   `dismissMenu()` → `.menuAction`; `performToolbarItem(_:action:)` →
   `.toolbarAction`. Each then ticks (HT-E). Choosing a disabled item throws
   `.disabledMenuItem`.
3. **Menu bar (TH-a)**: `TestApp.menuBar` returns `PlatformMenuBar.content()`
   — evaluated afresh, as AppKit does at each open — and
   `performMenuBarItem(_ path: String...)` calls `perform(id)` on that
   evaluation, then ticks every window.
4. **Menu content outside any window (TH-a)**: `MenuEvaluation(@MenuContentBuilder content:)`
   evaluates content into `items: [PlatformMenuItem]` numbered by
   `MenuSession.number` (the window's own numbering; a copy would drift) and
   `perform(_ path:)` runs an item's action directly. No window: no
   `StateDispatch`, so it suits model-driven menus (MetalCreator's View ▸
   Theme), not a `@State` write.

**Cost if wrong.** A menu shown drawn (option off) is driven by clicks on its
accessibility nodes instead; both paths are tested (2.10, 2.15).

## HT-I — Warm frames and work counters (M7-b)

**Ruling.**
1. A `TestWindow` is one `Window` for its life, so its `StateTable`,
   `ShapingCache`, glyph atlas, `AnimationStore` (and its `RasterCache`) and
   texture identities persist across frames: **every frame after the first is
   warm**, by construction, unlike `renderFrame`.
2. `lastFrameWork: FrameWork` (and `frameWork` history, cleared by
   `resetFrameWork()`) per presented frame, summing its builds (a frame may
   build up to three times, `LC-E`, `CR-Q`, `MD-K`): `builds`,
   `layoutMeasureCalls`, `layoutCacheHits`, `layoutCacheMisses` (each build's
   root run, `SA-M`), `rasterizedPixels`, `blurredPixels` (`RasterCache`'s
   per-frame counters), and from the renderer `atlasUploadPixels`,
   `newTextures`, `newTexturePixels`, `rects`, `glyphs`, `images`.
3. **Counted, never timed** by MetalUI. A client's benchmark reads its own
   clock around `advanceFrames`/actions; MetalUI's own tests assert counts.
4. Not counted, deferred (HT-Q): shaping (`ShapingCache` lives in macOS-only
   `MetalUIText`; the portable system has its own caches), GPU time.

**Cost if wrong.** A counter that C13 renames (`RasterCache` is its file) is
re-pointed at merge; the hook file is the only reader.

## HT-J — Text system: CoreText by default on Apple; required elsewhere, thrown not trapped

**Ruling.** `TestApp`/`TestWindow` take `textSystem: (@MainActor () -> any
TextSystem)?`. `nil` is CoreText on Apple platforms (as `App`); off Apple
`nil` throws `TestHarnessError.textSystemRequired` (XP-B: there is no CoreText;
`Window.init`'s trap is never reached). The harness ships no fonts. MetalUI's
own harness tests pass `PortableTextSystem` over `Tests/Fonts/NotoSans-Regular.ttf`
on every platform so their text literals agree on all three.

**Cost if wrong.** An app on Linux writes one more argument.

## HT-K — Colour scheme, scale and environment at open

**Ruling.** `colorScheme:` (default `.light`) is the **platform's** appearance
the window opens with, so a `.dark` window's first frame is dark (palette keys,
`Color(light:dark:)`, the dark theme — MG-12 item 1); `setAppearance(_:)` is a
system switch. `scaleFactor:` (default 1) sets the drawable scale.
`setControlActiveState(_:)`, `setReduceMotion(_:)`, `resize(to:)`,
`setScaleFactor(_:)` simulate the platform. The real `Window` is public as
`window` for `preferredColorScheme`, `keymap`, `environment`, themes.

## HT-L — No pixels

**Ruling.** The harness exposes the last `Scene` (rects, glyphs, images,
transforms, draw list; device pixels) — the observable `DemoFrameDeterminismTests`
already pins across platforms — and **no rendered pixels**: MetalUI has no CPU
rasterizer of a `Scene` (Metal and SDL GPU only). Deferred, owner none; a
pixel test stays a `FakePlatformWindow` test inside MetalUI.

## HT-M — Plain-import guards (`SA-P`)

**Ruling.** Three `typecheckFile` guards with a plain import, each mutated red
once (spec 3.1–3.3): an outside test file can open a `TestWindow`, act, query
and answer (positive); it cannot reach the `package` hooks; it still cannot
construct a `Window`. `MetalUITests` gains a dependency on `MetalUITesting`
so its module is built where `#filePath` expects.

## HT-N — Proof by migration, plain imports

**Ruling.** Four existing tests move, names kept, from `@testable` fakes to the
public harness in the portable target `Tests/MetalUITestingTests` with
**plain** imports (`import MetalUI`, `import MetalUITesting`): a click, a
lifecycle appearance, an alert answer, a context-menu choice (spec 3.5–3.8).
The old copies are deleted, so the count does not move for them. If one's
assertion needs an internal, the lane swaps in another test from the same file
and the record names the swap. Everything else stays on `FakePlatformWindow`.

## HT-O — Scaffold: a generated test target over the harness

**Ruling.** `metalui new` generates `Tests/<Name>Tests/<Name>Tests.swift` and a
`.testTarget` depending on the app's executable target and `MetalUITesting`
(`@testable import <Name>`, one swift-testing test clicking the starter's
button and reading its label). Cross-platform packages pass the system-fonts
`PortableTextSystem` off Apple. `MetalUITesting` joins the refused names
**only after** a generated package of that name is built and fails (`SC-H`).
The env-gated build test builds tests and runs them. **If** a testable
executable cannot be imported on Windows (measured on the VM where one exists,
else stated unmeasured), the generated manifest declares the test target off
Windows only and the record says so.

## HT-P — Lanes: three, sequential, disjoint files

**Ruling.** Lane 1 (host: product, platform, window, input, clock,
lifecycle, layout frames, frame work), lane 2 (inspection: accessibility
queries, element actions, presentations, menus, menu bar, toolbar,
`MenuEvaluation`), lane 3 (proof: guards, migrations, scaffold, docs). Files
in spec §6. Lane 2 extends lane 1's types only through extensions in its own
files.

## HT-Q — Deferred, each with a reason and an owner

1. **Pixels** (HT-L) — no CPU renderer; owner none.
2. **`GPUSurface` draws headless** — no GPU context to hand the closure
   (`MV-`); requests are recorded, not run; owner none.
3. **Shaping counters** — `ShapingCache` is macOS-only `MetalUIText`; owner
   none (a portable counter needs a `TextSystem` hook, a seam change).
4. **Virtual time for `Task.sleep`/clocks in `.task`** — Swift's clocks are not
   MetalUI's; the app injects one; owner none.
5. **IME composition helper** — `send(.textComposition(…))` works; a named
   helper waits for a request; owner none.
6. **Multiple-window key switching** — `setControlActiveState` per window
   covers the observable; a platform-level "key window" model waits for a
   request; owner none.
7. **An in-window menu bar** — SDL draws none (`MN-I` item 3, C12's
   territory); `TestApp.menuBar` reads the seam regardless.

## HT-R — Critic revisions (2026-10-09), each checked against the source at `70e9389`

**Ruling.** The committed design is kept except where named here; the spec
is corrected in the same commit.
1. **The window lookup reads `App.windows`, not `Window.liveWindows`.**
   `liveWindows` is `private static` in `Window.swift` (line 1113), so a
   `package` hook in a new file cannot read it without editing `Window.swift`
   (HT-C 2). `App.windows` is internal and `App.openWindow` appends the window
   (`App.swift` line 148) before its first `drawFrameIfNeeded()` (line 161), so
   `App.testingWindow(for:)` finds it from the renderer's first `beginFrame()`.
2. **`TestElement` is `Equatable`, not `Sendable`.** Its `id` is
   `AccessibilityNodeID`, a public struct wrapping `AnyHashable` and declared
   `Hashable` only; a cross-module public struct is not implicitly `Sendable`,
   so the spelled conformance would not compile under Swift 6. Every harness
   API is `@MainActor`, so nothing needs to send one.
3. **Test 1.35 states no literal.** The design's "6 leaves, one proposal each:
   6" contradicted the stack algorithm (`CN-B`…: a stack measures a child more
   than once, flexibility probes included). The lane derives the per-frame
   measure/hit/miss literals before the run (`SA-M`). Its mutation was
   "`onFrameAdopted` captured only on the first build", which a one-build drag
   frame cannot see; it is now "the frame accumulator not reset at
   `finishFrame`", plus a stale-read arm.
4. **Every lane-2 test names a mutation.** 2.15, 2.17, 2.22, 2.23, 2.25 had
   none; each now names one on the harness declaration it exercises (2.12
   stays the named control for 2.11).
5. **Guard 3.4 is dropped.** `MenuContent`'s requirement is SPI (`MN-D` item 1),
   already pinned by `anOutsideTypeCannotConformToMenuContent`; `MenuEvaluation`
   adds no way to conform, and its proposed mutation ("generic over `Any`")
   would not compile the implementation, so the guard could never be red for a
   real reason. Guards +3, lane 3 +5 tests.
6. **`HeadlessPlatform.run()` returns at once** (said, not implied): a test
   never enters a run loop; the clock is the harness's (HT-E).
7. **Merge debt with C12** named in spec §9: `MenuSession.number` and
   `MenuContent`'s SPI are read by `TestingMenuHooks.swift` alone.

Checked and **kept**: the probe was re-run byte for byte (X1 exit 0, X2 exit 1
with `rightTap`, S0 2/10, S1 all 0, R1–R3 as recorded); every seam type the
spec names (`DropItem`, `AccessibilityActions`, `KeyEquivalent`,
`EventModifiers`, `PlatformMenuBar`, `MouseButton`, `CloseRequestReply`,
`ToolbarActionEvent`, `PlatformPointerStyle`, `SurfaceDrawRequest`,
`Scene.textures`, `Window.setNeedsRedraw`/`needsRedraw`/`hasActiveAnimations`/
`framesDrawn`) exists and is public; `RasterCache.lastRasterizedPixels`/
`lastBlurredPixels` and `NativeLayoutWork` exist (internal, read through
`package` hooks); `MetalUI` re-exports `MetalUIPlatform`, so `MetalUITesting`
conforms to `PlatformWindow` without a direct dependency. No Apple type in the
surface, no platform requirement added, no renderer primitive, no C enum, no
`Window.swift` edit, no pixel change.

**Cost if wrong.** If `App.windows` is ever filled after the first draw, 1.25
reddens and the recorded fallback (set the flag after `openWindow`, draw once)
applies.

## HT-S — Lane 1's measured corrections (2026-10-10)

**Ruling.** Lane 1 (the host) measured these against the source at `70e9389`
plus its own commits; the spec (§2.3, §3.1, §4.1) is corrected in the same
commit.
1. **`runUntilIdle()` returns after four consecutive quiet yields**, not after
   the first round that draws nothing: a `.task`'s continuation and an
   observation hop each need a main-actor turn of their own, so one quiet
   yield can come before the work it waits for. A round is `await
   Task.yield()`, then one tick at `now` when the window is dirty (a window
   dirty only through a running animation counts as quiet: it needs the
   clock). Still bounded at 64 rounds, then `.notIdle(rounds: 64)`. Measured:
   test 1.20's model suspends twice and completes; 1.21's phase-time write
   throws.
2. **`sequenced(before:)` does not exist** in MetalUI (`Gesture.swift` offers
   `exclusively(before:)` and `simultaneously(with:)` only), so test 1.15 puts
   a `DragGesture` and a `.simultaneousGesture(LongPressGesture(…))` on one box.
3. **The gesture arena stamps a press at the first tick after it**
   (`GestureArena.tick`'s `awaitingStamp`: a mouse event carries no
   timestamp). So `click(at:forDuration:thenDragTo:)` delivers the press, draws
   the press's frame at `now`, and only then advances; test 1.14 ticks after
   its raw press. Measured: without that tick 1.14's long press had not run at
   0.6 s (stamped at 0.4) and 1.15's `held` was `false`.
4. **`frame(ofID:)` is the laid-out rect**, in window content space, **before
   any scroll offset or render effect** — what `Frame.recordElementBounds`
   records. Measured (test 1.12): after a −50 wheel delta every row's presented
   rect moved up 50 while `frame(ofID: "row3")` stayed at y 150. The visible
   rect is the accessibility element's (lane 2's `visibleFrame`). Test 1.12 now
   reads the scene's rects for the scroll and pins `frame(ofID:)` unchanged.
   Owner of a scrolled frame query: none (the window keeps scroll offsets per
   scroller, not per element; a `package` hook could compose them later).
5. **Test 1.11's separating half is a raw key reader.** `KeyboardShortcut` and
   `Keystroke` both match case-folded, so "Shift not applied to the
   characters" leaves a ⌘⇧S shortcut firing; 1.11 also reads an unclaimed ⇧A
   at the window's fallback `onInput` (`"A"` in both character fields).
6. **Test 1.13 uses `DragGesture()`** (minimum distance 10):
   `DragGesture(minimumDistance: 0)` reports a change at the press, 9 for 8
   steps (measured).
7. **Test 1.5 separates the leading move at the window's fallback `onInput`**:
   a press recomputes hover too (`Window.swift`'s `.mouseDown` arm), so hover
   alone cannot see the move.
8. **Test 1.37 is two names under `#if canImport(Darwin)`**; off Apple
   `TestApp.init`'s `#else` branch throws whatever `App.hasDefaultTextSystem`
   answers, so the mutation runs on the Apple arm.
9. **A static text's string is its node's `value`**, not its `label` (test 1.2).
10. **`TestApp.windows` holds its windows weakly** and is a computed get-only
    property (spec §2.3 said `private(set) var`): a `TestWindow` keeps its app,
    so a `TestApp` ↔ `TestWindow` cycle would keep a dirty `Window` alive in
    `Window.liveWindows` and make `withAnimation`'s "a frame build is pending"
    answer for later tests in the same process.
11. Small additions: `HeadlessPlatformWindow.options` is a public `var`, it
    records `performTitleBarPress` in `titleBarPresses` (answering `false`),
    and `HeadlessWindowRenderer.scaleFactor` is `public internal(set)`;
    `MetalUITestingTests` also depends on `MetalUIScene` (it reads
    `MUIRect`). `lastFrameWork`/`frameWork` are computed get-only.

**Cost if wrong.** Each item is pinned by the test it names; a later
`sequenced(before:)` or a timestamped mouse event re-spells 1.14/1.15 only.


## HT-T — Lane 2's measured corrections (2026-10-10)

**Ruling.** Lane 2 (inspection) measured these against the source at
`70e9389` plus the branch's commits; the spec (§2.5, §3.2, §4.2) is corrected
in the same commit.
1. **`element(label:)` matches a static text by its string.** A `Text`
   publishes its string as the node's `value` with no `label` (`HT-S` item 9;
   `AccessibilityTreeBuilder`'s `.staticText` node), while XCUITest's `label`
   of a static text is its text. So the label query matches a node's `label`,
   or, for a `.staticText` with no label, its `value`. `TestElement.label`
   stays the node's raw label (a snapshot, not a reinterpretation). Measured:
   tests 2.2 and 2.26 find `Text("Hello")` and `"pressed 1 times"` by label.
2. **A presentation getter answers `nil` when the option makes the window
   draw it.** `presentedAlert`, `presentedMenu`, `presentedFileDialog` and
   `toolbar` read `HeadlessPlatformWindow.options` at the call: with
   `presentsAlertsNatively`/`presentsMenusNatively`/`showsToolbarNatively`
   off the window draws (an `.alert` node, `.menuItem` nodes, the `$toolbar`
   strip) and the test drives it through the tree (2.10, 2.15, 2.22); with
   `presentsFileDialogs` off the window completes the dialog as failed. Only
   the latest request is read (one is in flight per window, `SV-B`); it is
   answered once the harness sends its result or the window dismisses its
   token. The answered tokens live in one internal stored property on
   `TestWindow` (`answered`) — the only lane-1 file lane 2 edits.
3. **A standard menu-bar item is not performed.** `PlatformMenuBar.perform`
   never sees a `standardAction` item (Quit, Copy …: the platform's own
   command), and the headless platform has none to run, so
   `performMenuBarItem` throws `.noMenuItem` for one. Owner: none (a test of
   Quit drives `HeadlessPlatform.simulateTerminateRequest()`).
4. **A popover is in the tree one tick after the frame that opens it.** A
   popover anchors to the last frame's bounds, so the open frame asks for one
   more (`window.needsRedraw` true after `TestWindow.init`) and the next
   display-link tick draws it (test 2.23 pins both halves). The harness keeps
   `HT-E`'s "an action draws one frame"; a test ticks.
5. **A `Button`'s node is its chrome, not its `.frame` wrapper.** The
   accessibility frame of `Button("Save").frame(width: 80, height: 30)` is
   the 52 × 24 bordered button centred in the 80 × 30 frame (Noto Sans
   through the portable text system, so equal on every platform); 2.1's and
   2.5's literals are re-derived from that.
6. **`performAccessibilityAction` takes an `AccessibilityActions` set**:
   each member runs, in the order press, increment, decrement, show-menu, then
   one frame; it answers whether the window handled every one (`false` for an
   empty set). `focus(_:)` is `.focus`, then one frame. Both throw only
   `.notRecorded` (accessibility off).
7. **`MenuEvaluation.perform` runs the action directly** and refuses a
   disabled item (`.disabledMenuItem`) or a non-command item (`.noMenuItem`);
   `item(_:)` returns any item on the path, disabled or a submenu.
   `testingEvaluateMenu` hands back only enabled actions.

**Cost if wrong.** Each item is pinned by the test it names; if `Text` ever
publishes its string as a label, item 1's fallback is dead code and 2.2 stays
green.
