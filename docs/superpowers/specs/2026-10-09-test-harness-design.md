# Test harness — design

Item 8 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**): a public test harness — a headless window over a public headless
platform in a test-support product, input injection, layout / accessibility /
presentation / menu inspection, and a warm headless frame for benchmarks.
Requested by MetalCreator (`docs/metalui-gaps.md` **M6-e**, **M7-b**, **TH-a**)
and the SMK configurator port (`2026-10-06-metalui-gaps.md` **MG-17**,
**MG-12**). Branch `feat/test-harness` from `70e9389`. Rulings:
[`../2026-10-09-test-harness-decisions.md`](../2026-10-09-test-harness-decisions.md)
(`HT-A`…`HT-S`). Record: `docs/record/91-test-harness.md`.

**Status: designed, critic-revised (2026-10-09, HT-R); lane 1 measured corrections HT-S (2026-10-10).**

## §0 Baseline and constraints

- At `70e9389`: **3069 tests in 3 suites** (native, unfiltered,
  `--no-parallel`), the `FR-J no-argument frame: succeeded=` line present,
  0 `error:`, the only `warning:` SwiftPM's deprecation notice; `swift build
  --build-tests` 0 warnings. Each lane re-measures before it starts.
- Parallel branches: **C9** `feat/key-focus` (record §88; `Window.swift` key
  dispatch), **C12** `fix/smk-port-gaps` (§89; menus, shortcuts, fonts, menu bar
  on SDL), **C13** `perf/shadow-cache` (§90; `RasterCache`, shadows, blur). This
  design edits **none** of `Window.swift`, `RasterCache.swift`, the menu files
  or `Backends/SDL` (HT-C). Merge debts named in §9.
- MUST NOT MOVE: identity and retention (`theSevenRetentionSlotsAreMutuallyDistinct`,
  MC-A/MC-C/MC-P, `.id()` outermost), hit testing, accessibility, animation,
  focus, `List` windowing and TB-AH, `Deferred`, text input; 0 px in the
  fourteen offscreen images against `70e9389`; `Expected.swift` unedited;
  `MetalUILayout` imports only `MetalUICore`; `MetalUIScene` only
  `MetalUIShaderTypes`; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
  green. **Nothing here changes behaviour**: every production path is reached
  through its existing public seam; the only `Sources/` edits outside the new
  target are `package` read-back hooks in new files and two `package`
  widenings in `MetalUILayout`.
- No `PlatformWindow`/`Platform`/`WindowRenderer` requirement is added. No
  shader, renderer or pixel change. No new divergence: the harness has no
  SwiftUI counterpart (HT-B, probe E1), so the reserved labels **215–224 stay
  unused**.

## §1 What SwiftUI and gpui answer (probed / read)

- **SwiftUI** (probe `docs/probes/swiftui-xcuitest-test-surface.sh`, recorded in
  its header): no in-process input injection or element query in SwiftUI's or
  SwiftUICore's interface (S1: 0 matches each for `func simulate`, `Simulat`,
  `TestHost`, `func inject`, `ViewInspect`; S0 control finds `class
  ImageRenderer` 2×, `onGeometryChange` 10×). Its headless surfaces are
  `ImageRenderer` (R1, a `CGImage` with no window) and a hosting view's
  `fittingSize` (R2); a per-view frame is readable only inside the view (R3).
  UI tests go out of process through **XCUITest**, whose actions typecheck as
  X1 (`click`, `doubleClick`, `rightClick`, `hover`, `typeText`,
  `typeKey(_:modifierFlags:)`, `scroll(byDeltaX:deltaY:)`,
  `click(forDuration:thenDragTo:)`, identifier/label queries) and whose
  separating arm X2 (`rightTap()`) does not.
- **gpui** (read, not probed — a precedent, HT-B): `TestAppContext` /
  `VisualTestContext` with `simulate_keystrokes`, `simulate_input`,
  `simulate_mouse_move/down/up`, `simulate_click`, `simulate_event`,
  `run_until_parked`, `simulate_resize`, `simulate_window_scale_factor_change`,
  `simulate_prompt_answer`, `simulate_path_prompt_response`,
  `debug_bounds(selector)`.
- **Answer**: MetalUI-only API (inventory class `M`), gpui's structure, XCUITest's
  action names, XCUITest's query model on MetalUI's published accessibility
  tree, gpui's `debug_bounds` as `frame(ofID:)` over `.id`.

## §2 Public API (final spellings; `MetalUITesting`)

Every declaration below is `public`, `@MainActor` unless a value type, and
doc-commented; every one gets an inventory row of class **M**. `Size`,
`Point`, `Bounds`, `Pixels` are MetalUICore's; units are logical points,
window content space, top-left origin (as `AccessibilityGeometry`).

### §2.1 Errors

```swift
public enum TestHarnessError: Error, CustomStringConvertible, Equatable {
    case textSystemRequired                 // HT-J: off Apple, nil text system
    case noElement(String)                  // the query, described
    case ambiguous(String, count: Int)
    case notHittable(String)                // zero-area visible frame
    case notRecorded(String)                // recordsLayout / accessibility off
    case nothingPresented(String)           // no alert / dialog / menu / toolbar item
    case noMenuItem([String])               // the path
    case disabledMenuItem([String])
    case notIdle(rounds: Int)               // runUntilIdle bound
    public var description: String { get }
}
```

### §2.2 The platform (HT-D)

```swift
public final class HeadlessPlatform: Platform {
    public init()
    public var nextWindowOptions: HeadlessPlatformWindow.Options       // used by openWindow
    public private(set) var openedWindows: [HeadlessPlatformWindow]
    public private(set) var applicationIcons: [[ImageTexture]]
    public private(set) var menuBar: PlatformMenuBar?
    public private(set) var terminateReplies: [Bool]
    public private(set) var terminateCalls: Int
    public func simulateTerminateRequest() -> CloseRequestReply
    public func simulateOpenURLs(_ urls: [String])                    // parked until a handler, as platforms do
    // + every Platform requirement; run() returns at once (no run loop, HT-R item 6)
}

public final class HeadlessPlatformWindow: PlatformWindow {
    public struct Options: Sendable, Equatable {
        public var appearance: Appearance = .light
        public var scaleFactor: Float = 1
        public var presentsMenusNatively = true        // AppKit's answer; false = SDL's (drawn)
        public var presentsAlertsNatively = true
        public var presentsFileDialogs = true
        public var showsToolbarNatively = true
        public var appliesTitleBarStyle = true
        public var externalDragResult = false
        public var accessibilityClientActive = true    // .activate when Window installs the handler
        public init(...)                               // every field, defaulted
    }
    public init(title: String, size: Size<Pixels>, options: Options = Options())
    public let headlessRenderer: HeadlessWindowRenderer
    // Recorded requests (each in call order):
    public private(set) var titleWrites: [String]
    public private(set) var preferredColorSchemeRequests: [ColorScheme?]
    public private(set) var pointerStyles: [PlatformPointerStyle]
    public private(set) var textInputAreas: [Bounds<Pixels>?]
    public private(set) var contentSizeLimits: [(minimum: Size<Pixels>?, maximum: Size<Pixels>?)]
    public private(set) var documentEditedCalls: [Bool]
    public private(set) var representedPaths: [String?]
    public private(set) var titleBarStyles: [PlatformTitleBarStyle]
    public private(set) var externalDrags: [([DragRepresentation], Point<Pixels>)]
    public private(set) var presentedMenus: [(menu: PlatformMenu, at: Point<Pixels>)]
    public private(set) var presentedAlerts: [PlatformAlert]
    public private(set) var presentedFileDialogs: [PlatformFileDialog]
    public private(set) var dismissedPresentations: [Int]
    public private(set) var toolbars: [PlatformToolbar?]
    public private(set) var publishedAccessibilityTrees: [AccessibilityTree]  // keeps the last 1 by default
    public private(set) var displayLinkPauses: [Bool]
    public var clipboard: String?
    public private(set) var isClosed: Bool
    public var titleBarInsets: Edges<Pixels>
    // Simulated platform events:
    @discardableResult public func simulateInput(_ event: InputEvent) -> Bool
    public func simulateTick(timestamp: Double)
    public func simulateResize(to size: Size<Pixels>)
    public func simulateScaleFactorChange(to scale: Float)
    public func simulateAppearanceChange(to appearance: Appearance)
    public func simulateControlActiveStateChange(to state: ControlActiveState)
    public func simulateReduceMotionChange(to value: Bool)
    @discardableResult public func simulateCloseRequest() -> Bool
    @discardableResult public func simulateAccessibilityRequest(_ request: AccessibilityRequest) -> Bool
    // + every PlatformWindow requirement
}

public final class HeadlessWindowRenderer: WindowRenderer {
    public var failsNextFrame: Bool                       // next beginFrame() answers nil, once
    public private(set) var lastScene: Scene
    public private(set) var framesPresented: Int
    public private(set) var lastSurfaceRequests: [SurfaceDrawRequest]   // recorded, never run (HT-Q 2)
    public private(set) var lastAtlasUploadPixels: Int    // dirty-rect area, then clearDirtyRect()
    public private(set) var lastNewTextures: Int          // textures absent from the previous frame
    public private(set) var lastNewTexturePixels: Int
    // internal: var onFirstBeginFrame: (@MainActor () -> Void)?  (one-shot, §3.1 item 3)
    // + WindowRenderer requirements
}
```

`publishedAccessibilityTrees` keeps only the latest tree unless
`keepsAccessibilityHistory = true` (a benchmark must not grow an array per
frame). The fake `FakePlatformWindow` in `Tests/MetalUITests` is untouched.

### §2.3 The app and the window (HT-C, HT-E, HT-J, HT-K)

```swift
public final class TestApp {
    public init(textSystem: (@MainActor () -> any TextSystem)? = nil) throws  // HT-J
    public let app: App                         // the real one: commands, themes, icon
    public let platform: HeadlessPlatform
    public var windows: [TestWindow] { get }               // weak: a TestWindow keeps its app (HT-S 10)
    public func openWindow<Root: Element>(
        title: String = "Test",
        size: Size<Pixels> = Size(width: Pixels(800), height: Pixels(600)),
        minSize: Size<Pixels>? = nil, maxSize: Size<Pixels>? = nil,
        windowResizability: WindowResizability = .automatic,
        windowStyle: WindowStyle = .automatic,
        colorScheme: ColorScheme = .light, scaleFactor: Float = 1,
        options: HeadlessPlatformWindow.Options? = nil,     // nil: platform.nextWindowOptions + the two above
        recordsLayout: Bool = true,
        content: @escaping @MainActor () -> Root) throws -> TestWindow
    // Menu bar (HT-H 3, TH-a):
    public var menuBar: [PlatformMenu] { get }               // PlatformMenuBar.content(), evaluated now
    public func performMenuBarItem(_ path: String...) throws // then ticks every window
}

public final class TestWindow {
    /// A window in its own TestApp.
    public convenience init<Root: Element>(
        size: Size<Pixels> = Size(width: Pixels(800), height: Pixels(600)),
        colorScheme: ColorScheme = .light, scaleFactor: Float = 1,
        options: HeadlessPlatformWindow.Options = .init(),
        recordsLayout: Bool = true,
        textSystem: (@MainActor () -> any TextSystem)? = nil,
        content: @escaping @MainActor () -> Root) throws
    public let testApp: TestApp
    public let window: Window                         // the real Window
    public let platformWindow: HeadlessPlatformWindow
    // Clock and frames (HT-E):
    public private(set) var now: Double                // starts at 0
    public var framesDrawn: Int { get }                // window.framesDrawn
    public var scene: Scene { get }                    // last presented
    public func tick()
    public func advance(by seconds: Double)
    public func advanceFrames(_ count: Int = 1)        // 1/60 s apart
    public func runUntilIdle() async throws           // 4 quiet yields in a row, ≤ 64 rounds (HT-S 1)
    @discardableResult public func send(_ event: InputEvent) -> Bool   // raw, no frame
    // Platform simulation (HT-K):
    public func resize(to size: Size<Pixels>)
    public func setScaleFactor(_ scale: Float)
    public func setAppearance(_ appearance: Appearance)
    public func setControlActiveState(_ state: ControlActiveState)
    public func setReduceMotion(_ value: Bool)
    public func close()                                // platform close: onDisappear runs (LC-J)
    @discardableResult public func requestClose() -> Bool   // asks onCloseRequest
    // Layout (HT-G 2):
    public func frame(ofID name: String) throws -> Bounds<Pixels>   // laid out, before scroll offsets (HT-S 4)
    public func frames(ofID name: String) throws -> [Bounds<Pixels>]
    // Work (HT-I):
    public private(set) var lastFrameWork: FrameWork
    public private(set) var frameWork: [FrameWork]
    public func resetFrameWork()
}

public struct FrameWork: Sendable, Equatable {
    public var builds, layoutMeasureCalls, layoutCacheHits, layoutCacheMisses: Int
    public var rasterizedPixels, blurredPixels: Int
    public var atlasUploadPixels, newTextures, newTexturePixels: Int
    public var rects, glyphs, images: Int
    public static func + (l: FrameWork, r: FrameWork) -> FrameWork
}
```

### §2.4 Input (HT-F; lane 1 points, lane 2 elements)

```swift
extension TestWindow {
    // By point (lane 1):
    public func click(at point: Point<Pixels>, modifierFlags: EventModifiers = [])
    public func doubleClick(at point: Point<Pixels>, modifierFlags: EventModifiers = [])
    public func rightClick(at point: Point<Pixels>, modifierFlags: EventModifiers = [])
    public func otherClick(at point: Point<Pixels>, button: MouseButton = .middle, modifierFlags: EventModifiers = [])
    public func hover(at point: Point<Pixels>)
    public func exitPointer()
    public func scroll(at point: Point<Pixels>, byDeltaX dx: Float, deltaY dy: Float,
                       modifierFlags: EventModifiers = [])
    public func click(at point: Point<Pixels>, forDuration seconds: Double, thenDragTo end: Point<Pixels>)
    public func drag(from start: Point<Pixels>, to end: Point<Pixels>, steps: Int = 8,
                     button: MouseButton = .primary, modifierFlags: EventModifiers = [])
    public func magnify(at point: Point<Pixels>, by magnification: Double, steps: Int = 4)
    public func rotate(at point: Point<Pixels>, byDegrees degrees: Double, steps: Int = 4)
    public func typeText(_ text: String)
    public func typeKey(_ key: KeyEquivalent, modifierFlags: EventModifiers = [])
    public func pressModifiers(_ modifiers: EventModifiers)       // .modifiersChanged; sticky until changed
    public func drop(_ items: [DropItem], at point: Point<Pixels>)  // entered, moved, performed
    // By element (lane 2): the same verbs taking a TestElement, aimed at the
    // centre of its visibleFrame:
    public func click(_ element: TestElement, modifierFlags: EventModifiers = []) throws
    public func doubleClick(_ element: TestElement, …) throws
    public func rightClick(_ element: TestElement, …) throws
    public func hover(_ element: TestElement) throws
    public func scroll(_ element: TestElement, byDeltaX: Float, deltaY: Float) throws
    public func click(_ element: TestElement, forDuration: Double, thenDragTo target: TestElement) throws
    public func typeText(_ text: String, into element: TestElement) throws  // clicks it first
}
```

`MouseButton` is MetalUI's existing public type (`SpatialGestures.swift`,
`CI-F` item 2: `.primary`, `.secondary`, `.middle`, `.other(n)`); `drag`
sends `.mouseDown/Dragged/Up` for `.primary`, `.rightMouse…` for `.secondary`
and `.otherMouse…` (with `MouseEvent`'s button number) otherwise. `otherClick`
takes `button: MouseButton = .middle`.

### §2.5 Inspection (HT-G, HT-H; lane 2)

```swift
public struct TestElement: Equatable {   // a snapshot of one node; not Sendable (HT-R item 2)
    public var id: AccessibilityNodeID
    public var role: AccessibilityRole
    public var label: String?, value: String?, identifier: String?, hint: String?
    public var frame: Bounds<Pixels>, visibleFrame: Bounds<Pixels>
    public var isEnabled: Bool, isSelected: Bool, isFocused: Bool
    public var children: [AccessibilityNodeID]
}
extension TestWindow {
    public var accessibilityTree: AccessibilityTree { get throws }   // .notRecorded when inactive
    public func element(identifier: String) throws -> TestElement
    public func element(label: String) throws -> TestElement
    public func elements(role: AccessibilityRole) throws -> [TestElement]   // tree order
    public func elements(where predicate: (TestElement) -> Bool) throws -> [TestElement]
    public var focusedElement: TestElement? { get throws }
    @discardableResult
    public func performAccessibilityAction(_ action: AccessibilityActions, on element: TestElement) throws -> Bool
    public func focus(_ element: TestElement) throws
    // Presentations (latest unanswered):
    public var presentedAlert: PlatformAlert? { get }
    public var presentedFileDialog: PlatformFileDialog? { get }
    public var presentedMenu: PlatformMenu? { get }
    public var toolbar: PlatformToolbar? { get }
    public var pointerStyle: PlatformPointerStyle? { get }
    public var title: String { get }
    public func respondToAlert(button title: String) throws
    public func respondToAlert(buttonAt index: Int?) throws          // nil: dismissed without a button
    public func respondToFileDialog(choosing paths: [String]) throws
    public func cancelFileDialog() throws
    public func chooseMenuItem(_ path: String...) throws
    public func dismissMenu() throws
    public func performToolbarItem(_ id: String, action: ToolbarActionEvent.Action = .press) throws
}

public struct MenuEvaluation {                        // TH-a outside any window
    public init(isEnabled: Bool = true, @MenuContentBuilder content: () -> some MenuContent)
    public let items: [PlatformMenuItem]
    public func item(_ path: String...) throws -> PlatformMenuItem
    public func perform(_ path: String...) throws
}
```

(`ToolbarActionEvent.Action` is the seam's: `.press`, `.toggle(Bool)`,
`.select(Int)`, `.text(String)`.)

### §2.6 What an app writes (the `docs/testing.md` opening example)

```swift
import Testing
import MetalUI
import MetalUITesting
@testable import MyApp

@MainActor @Test func pressingTheButtonCountsIt() throws {
    let window = try TestWindow(size: Size(width: Pixels(640), height: Pixels(400))) { rootView() }
    try window.click(window.element(label: "Press me"))
    #expect(try window.element(label: "pressed 1 times").role == .staticText)
}
```

## §3 Implementation

### §3.1 Lane 1 — the host (M6-e, MG-17, MG-12, M7-b)

1. **Manifest.** Portable list: `.library(name: "MetalUITesting", targets:
   ["MetalUITesting"])`; `.target(name: "MetalUITesting", dependencies:
   ["MetalUI", "MetalUIScene"])`; `.testTarget(name: "MetalUITestingTests",
   dependencies: ["MetalUITesting", "MetalUI", "MetalUIPortableText"],
   exclude: [])` (fonts read by `#filePath` from `Tests/Fonts`). macOS list:
   `MetalUITests` gains `"MetalUITesting"` (for lane 3's guards, HT-M — added
   here because `Package.swift` is lane 1's file). Comment block per the
   manifest's style. `docs/probes/closeout-public-api.sh`'s `TARGETS` gains
   `MetalUITesting`.
2. **`HeadlessPlatform`, `HeadlessPlatformWindow`, `HeadlessWindowRenderer`**
   (§2.2) in three files. `openWindow` builds a window from
   `nextWindowOptions` (TestApp sets it per open). The accessibility-at-open
   behaviour (HT-D 4) is `onAccessibilityRequest`'s `didSet`: when
   `options.accessibilityClientActive` and the new value is non-nil and not yet
   activated, call it with `.activate` once. `startDisplayLink` stores the
   closure; `simulateTick` calls it. `setContentSizeLimits` clamps the content
   size and reports through `onResize`, as `FakePlatformWindow` does (`SV-M`).
   `close()` fires `onClose` once. Renderer per §2.2.
3. **`TestApp`/`TestWindow`** (§2.3). `TestApp.init` throws
   `.textSystemRequired` when `textSystem` is `nil` and
   `App.hasDefaultTextSystem` (a `package static` hook answering
   `canImport(MetalUIText)`) is `false`, then builds
   `App(platform: platform, textSystem:)`. `openWindow` sets
   `platform.nextWindowOptions` (appearance from `colorScheme`, `scaleFactor`)
   and calls `app.openWindow(…, startsDisplayLink: true, …)`.
   **The harness's per-window setup must precede the first frame**, which
   `App.openWindow` draws before it returns. Mechanism (no `App.swift` or
   `Window.swift` edit): the harness gives the new platform window's renderer
   a one-shot `onFirstBeginFrame` closure; `beginFrame()` runs it inside
   `drawFrameIfNeeded`, before the build. The closure finds the `Window` by
   its platform window through the package hook `App.testingWindow(for:)` — a
   scan of the internal `App.windows` by `platformWindow` identity:
   `openWindow` appends the window (`App.swift`, `windows.append(window)`)
   **before** its `window.drawFrameIfNeeded()`. (Not `Window.liveWindows`:
   it is `private static`, unreadable from a new file without editing
   `Window.swift` — HT-R item 1.) It sets
   `testingRecordsElementBounds` and the frame-work observer
   (`testingOnFrameAdopted`). Lane 1 pins this with 1.25 asserting a frame
   right after open; **if the lookup fails, the fallback is recorded**: the
   flag is set after `openWindow` returns and one more frame is drawn, and
   tests count `framesDrawn` by deltas.
   The frame-work observer accumulates a `FrameWork` across a frame's builds;
   the renderer's `finishFrame` closes the frame (appends to `frameWork`, sets
   `lastFrameWork`).
4. **Input by point** (§2.4) in `TestWindowInput.swift`, routing per HT-F 3:
   `isTextInputActive` = the platform window's last `textInputAreas` entry is
   non-nil. Text-producing key: a `KeyEquivalent` whose character is not a
   control character and not in the `\u{f700}`…`\u{f8ff}` function-key range.
   Shift: letters uppercased in both `characters` and
   `charactersIgnoringModifiers`. Timestamps `now`. Mouse events carry
   `pressModifiers` ∪ `modifierFlags`; `clickCount` 1 (`doubleClick`: a full
   click with 1 then one with 2). Scroll: `ScrollEvent(position:delta:modifiers:)`
   with `location = position`, `timestamp = now` (both platforms do,
   `CI-J` item 4). `click(forDuration:thenDragTo:)`: down,
   `advance(by: seconds)`, drags in 8 steps (`advanceFrames(1)` each), up, tick.
   Magnify/rotate: `.began`, `steps` `.changed`, `.ended`, each with a frame.
5. **Clock** (HT-E) in `TestWindow.swift`; `runUntilIdle` per HT-E 3,
   reading `window.needsRedraw`, `window.hasActiveAnimations` and
   `framesDrawn`.
6. **Hooks** in `Sources/MetalUI/TestingHooks.swift` (new; `package` only):
   `Window.testingRecordsElementBounds` (get/set `recordsElementBounds`),
   `Window.testingElementBounds` (`lastElementBounds`),
   `Window.testingOnFrameAdopted` (set `onFrameAdopted` with a closure handed
   a `package struct BuildWork` — measure calls, hits, misses, rasterized,
   blurred — so `Frame` stays internal), `App.testingWindow(for:)` (over
   `App.windows`, HT-R item 1), `App.hasDefaultTextSystem`. `MetalUILayout`: `NativeLayoutWork` and its
   three fields and `LayoutTree.lastNativeLayoutWork`'s getter become
   `package` (no other change).
7. **Doc comments and inventory rows** for lane 1's declarations; census
   re-recorded.

### §3.2 Lane 2 — inspection (M6-e, TH-a)

1. `TestElement.swift`, `TestWindowQueries.swift` (§2.5 queries; the tree is
   `platformWindow.publishedAccessibilityTrees.last`; `isFocused` from
   `tree.focused`; tree order = pre-order from `roots`).
2. `TestWindowElementInput.swift` (the element verbs; `visibleFrame` centre;
   zero area → `.notHittable`; `typeText(_:into:)` clicks then types).
3. `TestWindowPresentations.swift`: "latest unanswered" — a request is
   answered when the harness sends its result or the window dismisses its
   token (`dismissedPresentations`); `respondToAlert(button:)` resolves the
   title to its index (several equal titles → `.ambiguous`); `chooseMenuItem`
   walks titles through `.submenu`, refuses a disabled item, sends
   `.menuAction(MenuActionEvent(menu: token, item: id))`, ticks;
   `dismissMenu` sends `item: nil`; `performToolbarItem` sends
   `.toolbarAction(ToolbarActionEvent(item:action:))`.
4. `TestAppMenuBar.swift`: `menuBar`/`performMenuBarItem` over
   `platform.menuBar` (lane 1 declared the stored property; this file adds
   only the extension's computed members — **`TestApp.menuBar` is declared
   here, not in lane 1**).
5. `MenuEvaluation.swift` over `Sources/MetalUI/TestingMenuHooks.swift` (new,
   `package`): `package func testingEvaluateMenu(isEnabled:) -> (items:
   [PlatformMenuItem], actions: [Int: @MainActor () -> Void])` on
   `MenuContent`, numbering through `MenuSession.number` with a synthetic root
   `GlobalElementID` and `next = 1`.
6. Doc comments, inventory rows, census.

### §3.3 Lane 3 — proof and documentation

1. Guards (HT-M) in `Tests/MetalUITests/TestHarnessCompileGuards.swift`.
2. Migrations (HT-N): the four tests move to
   `Tests/MetalUITestingTests/MigratedHarnessTests.swift`; their old bodies are
   deleted from `InputDispatchTests.swift`, `LifecycleTests.swift`,
   `AlertTests.swift`, `ContextMenuTests.swift` (a comment at each old site
   names the new file).
3. Scaffold (HT-O): `Sources/MetalUIScaffold/Scaffold.swift` (test target,
   test file, README "Testing" section; refused name `MetalUITesting` after a
   measured failure), `Tests/MetalUIScaffoldTests/ScaffoldTests.swift`;
   re-run `METALUI_RUN_SCAFFOLD_BUILD_TEST=1 swift test --filter
   aGeneratedPackageBuildsAgainstThisCheckout` (extended to `swift build
   --build-tests` and `swift test` in the generated package).
4. Docs: new `docs/testing.md` (how an app tests its UI: setup per platform,
   the example, input, queries, presentations, menus, clock and
   `runUntilIdle`, warm frames and benchmarks, what it cannot do — HT-Q;
   adding `.id` changes identity); links from `docs/getting-started.md` and
   `docs/api-overview.md`; `docs/migration.md` note ("an app's own headless
   `Platform` fake can be replaced by `HeadlessPlatform`; MetalUI now
   implements new platform requirements there"); `THIRD-PARTY-NOTICES.md`
   unchanged (no vendored code).

## §4 Tests (by name; red-before; the mutation that must redden it)

"Red before" for new API: each lane first lands its public declarations as
**compiling stubs** (empty bodies, `fatalError`-free defaults: `frame(ofID:)`
throws `.notRecorded`, actions do nothing) and runs its new tests red, then
implements. Every mutation is applied after the lane's commit, restored from a
copy, the whole suite run unfiltered, and the reddened tests named. Text
literals use `PortableTextSystem` over Noto Sans (HT-J); layout literals use
fixed-size frames.

### §4.1 Lane 1 (`Tests/MetalUITestingTests/`, portable, runs on all three platforms)

| # | Test | Red before (stub) | Mutation that must redden it |
|---|---|---|---|
| 1.1 | `aTestWindowOpensAndPresentsItsFirstFrameHeadless` — `framesDrawn` ≥ 1, `scene` holds the root's background rect at the window's size | stub draws nothing | `HeadlessWindowRenderer.beginFrame` returns `nil` |
| 1.2 | `anAccessibilityClientActiveAtOpenHasTheTreeInTheFirstFrame` — tree non-empty after open, `framesDrawn` unchanged from 1.1's open count | no `.activate` | drop the `didSet` activation |
| 1.3 | `aRendererThatFailsAFrameLeavesTheWindowDirtyAndTheNextTickDraws` | — | `failsNextFrame` ignored |
| 1.4 | `aClickAtAPointRunsAnOnClickAndTheNextFrameShowsIt` — `@State` count text changes (scene glyph run differs; label read through the tree in lane 2's later re-pin) | stub click | `click` sends only `.mouseDown` |
| 1.5 | `aClickMovesThePointerFirstSoHoverSeesIt` — `.onHover` fires `true` before the click's action | — | omit the leading `.mouseMoved` |
| 1.6 | `aDoubleClickDeliversClickCountTwo` — `TapGesture(count: 2)` fires once | — | second click's `clickCount` 1 |
| 1.7 | `aRightClickNeverRunsOnClick` (MN-B through the harness) | — | `rightClick` sends `.mouseDown` |
| 1.8 | `typeTextIntoAFocusedFieldEditsItsBinding` — click a `TextField`, `typeText("abc")`, binding `"abc"` | stub | `typeText` ignores the caret (always keyDown) — **if green, record that keyDown also edits and lean on 1.9** |
| 1.9 | `aPlainLetterKeymapBindingIsSilentWhileAFieldIsFocused` — keymap `k` fires unfocused, not while a field has the caret | — | routing ignores `textInputAreas` |
| 1.10 | `typeKeyWithCommandFiresAKeyboardShortcut` — `.keyboardShortcut("s")` runs on `typeKey("s", modifierFlags: .command)`, not on plain `s` | — | modifiers dropped |
| 1.11 | `aShiftedShortcutMatchesAsAppKitDeliversIt` — `[.command, .shift]` `"s"` shortcut fires | — | shift not applied to characters |
| 1.12 | `scrollMovesAScrollViewsContent` — every row's presented rect moves up by the delta; `frame(ofID:)` (laid out) does not (HT-S 4) | — | `location` not set to `position` |
| 1.13 | `aDragDeliversStepsDraggedEventsEachWithAFrame` — `DragGesture` `onChanged` count == steps, final translation == end − start, `framesDrawn` +steps+1 | — | steps collapsed to 1 |
| 1.14 | `aLongPressRunsOnlyAfterItsDurationUnderAdvance` — 0.5 s press: not at `advance(by: 0.4)`, yes after `+0.2` | — | `advance` does not fire a tick |
| 1.15 | `clickForDurationThenDragToHoldsThenDrags` — a `DragGesture` and a simultaneous `LongPressGesture` on one box: the press is held, the drag ends at end − start (no `sequenced(before:)`, HT-S 2) | — | no hold before the drags |
| 1.16 | `magnifyAndRotateReachTheirGestures` — `MagnifyGesture` value 1.5, `RotateGesture` 30° | — | `.ended` only |
| 1.17 | `aRawSendDrawsNoFrameUntilATick` | stub `send` draws | `send` ticks |
| 1.18 | `anOnAppearWriteIsInTheFirstFrame` (MG-12 item 2) | — | `Window.drainLifecycle` returns at once (in `Window.swift`, restored) — shows the harness runs the real drain |
| 1.19 | `onChangeRunsAfterAClickChangesItsValue` | — | as 1.18 |
| 1.20 | `aTaskCompletesUnderRunUntilIdle` — `.task { value = await model.load() }` (main-actor, timer-free) visible after `await runUntilIdle()` | stub returns at once | `runUntilIdle` without `Task.yield()` |
| 1.21 | `runUntilIdleThrowsNotIdleForAWindowThatRedrawsForever` — a phase-time `@State` write (CLAUDE.md's documented hazard: the window never goes clean) throws `.notIdle(rounds: 64)` | stub returns | the bound changed 64 → 65 (the literal reddens; never an unbounded loop) |
| 1.22 | `aDarkWindowResolvesItsFirstFrameDark` (MG-12 item 1) — a `Color(light:dark:)` background equals the dark resolution in frame 1; palette key too | — | `openWindow` ignores `colorScheme` |
| 1.23 | `setAppearanceSwitchesTheSchemeLikeTheSystem` | — | `simulateAppearanceChange` skips the callback |
| 1.24 | `aPreferredColorSchemeReachesThePlatformRecord` — `.preferredColorScheme(.dark)` in the tree → `preferredColorSchemeRequests == [.dark]` | — | record not appended |
| 1.25 | `frameOfIDReadsLaidOutRects` (MG-12 item 3) — `HStack(spacing: 0)` of `.frame(width: 120)` / `.frame(width: 80)` ids `a`/`b` in a 400×300 window: literals derived from the stack rule (centred root) | stub throws | `testingRecordsElementBounds` not set |
| 1.26 | `frameOfAnAmbiguousIDThrowsAndFramesOfIDListsBoth` | — | `frames(ofID:)` returns first only |
| 1.27 | `aWindowNotRecordingLayoutThrowsNotRecorded` | — | always record |
| 1.28 | `resizeReflowsTheRoot` — a greedy `.id("fill")` root's frame equals the new size | — | `resize` skips `onResize` |
| 1.29 | `scaleFactorTwoDoublesTheScenesDeviceRects` | — | renderer `beginFrame` returns 1 |
| 1.30 | `closeRunsEveryOnDisappearOnce` (LC-J) | — | `close()` does not fire `onClose` |
| 1.31 | `aVetoedCloseRequestKeepsTheWindowOpen` (AS-B) | — | `simulateCloseRequest` ignores the answer |
| 1.32 | `theLastWindowsCloseTerminatesTheTestApp` — `platform.terminateCalls == 1` | — | `terminate()` not counted |
| 1.33 | `theSecondUnchangedFrameUploadsNothing` (M7-b) — frame 1 `atlasUploadPixels > 0`, `newTextures` for an image > 0; a forced redraw (`window.setNeedsRedraw(); tick()`) reports 0 and 0 | — | renderer skips `clearDirtyRect()` |
| 1.34 | `frameWorkSumsEveryBuildOfAFrame` — an `onAppear` write: `lastFrameWork.builds == 2` at open (LC-E) | — | accumulator reset per build |
| 1.35 | `aWarmDragLoopCountsLayoutWorkPerFrame` — a branching tree (2 stacks × 3 fixed leaves, one leaf `.offset` by the drag): each drag frame `layoutMeasureCalls`, `layoutCacheHits`, `layoutCacheMisses` equal literals the lane derives **before** the run from the stack algorithm (`CN-B`…, probe `swiftui-stack-algorithms.swift`: a stack proposes each child more than once, so the count is not the leaf count — HT-R item 3), equal on all 10 frames, and the sum is 10 × the per-frame literal | — | the frame accumulator not reset at `finishFrame` (frame 2 reads twice frame 1's work); second mutation: the hook reads the previous build's `lastNativeLayoutWork` |
| 1.36 | `anUnchangedPathIsRasterizedOnceAcrossFrames` — a `Path` fill: frame 1 `rasterizedPixels > 0`, frame 2 `== 0` | — | hook reads the counters before the build |
| 1.37 | `theDefaultTextSystemIsCoreTextOnApple` (`#if canImport(Darwin)`) / `aMissingTextSystemThrowsOffApple` (`#else`) — one test name, two arms | stub | `hasDefaultTextSystem` answers the other value |
| 1.38 | `XCTestHarnessTests.testAClickRunsAnOnClickFromXCTest` — XCTest, `@MainActor func … async throws` | — | as 1.4 |

### §4.2 Lane 2

| # | Test | Red before | Mutation |
|---|---|---|---|
| 2.1 | `elementByIdentifierReturnsItsFrame` — `.accessibilityIdentifier("save")` `Button`: role `.button`, frame literal | stub throws | activation off by default |
| 2.2 | `elementByLabelFindsAStaticText` | stub | match on `identifier` instead |
| 2.3 | `elementsByRoleAreInTreeOrder` — three buttons in a `VStack`, labels in order | — | dictionary order (`nodes.values`) |
| 2.4 | `aMissingAndAnAmbiguousElementThrowNamingTheQuery` | — | ambiguous returns first |
| 2.5 | `clickOnAnElementAimsAtItsVisibleFrame` — a button half scrolled out of a `ScrollView`: the click lands (its `frame` centre is outside the viewport) | — | aim at `frame` centre |
| 2.6 | `aZeroAreaElementIsNotHittable` — fully scrolled out | — | no zero check |
| 2.7 | `anAccessibilityPressRunsAButton` | — | `.increment` sent |
| 2.8 | `tabMovesFocusAndFocusedElementFollows` | — | `isFocused` from `isFocusable` |
| 2.9 | `anAlertIsReadAndAnsweredByButtonTitle` — title, message, buttons; `respondToAlert(button: "Delete")` runs the action, `presentedAlert == nil` after | stub | token off by one |
| 2.10 | `aDeclinedAlertIsDrawnAndPressedThroughTheTree` — options `presentsAlertsNatively: false`: role `.alert` node, its button pressed by `click` | — | option ignored |
| 2.11 | `aFileImporterIsAnsweredWithPaths` — `.fileImporter`: `presentedFileDialog?.kind == .open(false)`; `respondToFileDialog(choosing: ["/tmp/a.json"])` → handler `.success` with that path | — | outcome `.cancelled` |
| 2.12 | `aCancelledFileDialogReachesTheHandler` | — | — (control for 2.11's arm) |
| 2.13 | `aContextMenuIsReadAndAnItemChosenByTitle` — `rightClick(element)`; titles, `isOn`, shortcut; `chooseMenuItem("Dark")` runs | stub | `item: nil` sent |
| 2.14 | `aSubmenuItemIsChosenByPath` | — | path walk stops at depth 1 |
| 2.15 | `aDrawnMenuIsDrivenThroughTheTree` — `presentsMenusNatively: false`: `.menuItem` nodes, click one | — | `presentMenu` answers `true` regardless of the option |
| 2.16 | `aDisabledMenuItemThrows` | — | no enabled check |
| 2.17 | `aPullDownMenuIsReadTheSameWay` — `Menu("Options") { … }` clicked; `presentedMenu == nil` after the choice | — | a token answered by `.menuAction` still counts as unanswered |
| 2.18 | `theMenuBarListsCommandsAndPerformsOne` (TH-a) — `app.commands { CommandMenu("Theme") { Toggle("Dark", isOn: …) } }`; `performMenuBarItem("Theme", "Dark")` flips the model | stub | `perform(id + 1)` |
| 2.19 | `theMenuBarIsReEvaluatedAtEachRead` — `isOn` true after 2.18's perform | — | cached content |
| 2.20 | `menuEvaluationReadsContentOutsideAnyWindow` (TH-a) — `Button`, `Divider`, `Toggle` with shortcut: kinds, titles, `isOn`, shortcut; `perform("Save")` runs | stub | `isEnabled: false` passed |
| 2.21 | `theToolbarIsReadAndAnItemTriggered` | stub | `.toolbarAction` with wrong item |
| 2.22 | `aDeclinedToolbarIsDrawnAndItsButtonClickable` — `showsToolbarNatively: false`: `$toolbar` strip (MD-K), its button by label | — | `setToolbar` answers `true` regardless of the option |
| 2.23 | `aPopoverAppearsInTheTreeInsideTheWindow` — role `.popover`, its frame inside the window bounds | — | the query walk visits only `roots.first` (a presentation root's node is another root, or the test records that it is not and swaps the mutation for "skip children of a `.popover`") |
| 2.24 | `pointerStyleFollowsHover` — `.pointerStyle(.link)` → `pointerStyle` | — | last style not read |
| 2.25 | `copyInAFieldReachesTheWindowsClipboard` — ⌘A ⌘C | — | `writeClipboard` drops the write |
| 2.26 | `aClickByElementReRunsLane1sClickTestThroughTheTree` — 1.4 re-pinned by label | — | as 1.4 |

### §4.3 Lane 3

| # | Test | Red before | Mutation |
|---|---|---|---|
| 3.1 | `anOutsideTestFileCanDriveATestWindowWithAPlainImport` (`typecheckFile`, imports `MetalUI` and `MetalUITesting` only: open, click by label, `frame(ofID:)`, `respondToAlert`, `MenuEvaluation`, `menuBar`) — must typecheck | — | `TestWindow.click(_:modifierFlags:)` made `internal` → red |
| 3.2 | `anOutsideFileCannotReachTheTestingHooks` — `window.testingElementBounds` must fail | — | hook made `public` → red |
| 3.3 | `anOutsideFileStillCannotConstructAWindow` — `Window(platformWindow:…)` must fail | — | `Window.init` made `public` → red |
| 3.5 | `aClickInsideTheBoundsRunsTheHandler` (moved from `InputDispatchTests`) | — | as its original mutation (recorded there) |
| 3.6 | `anIfThatInsertsContentRunsItsOnAppearOnce` (moved from `LifecycleTests`) | — | as its original |
| 3.7 | `anAlertResultWritesIsPresentedFalseThenRunsTheAction` (moved from `AlertTests`) | — | as its original |
| 3.8 | `aChosenItemRunsItsActionFromInputUnderStateDispatch` (moved from `ContextMenuTests`) | — | as its original |
| 3.9 | `aGeneratedPackageHasATestTargetOverTheHarness` (`ScaffoldTests`) — manifest has the `.testTarget` with `MetalUITesting`; the test file exists | — | drop the file |
| 3.10 | `metalUITestingIsARefusedName` — only after the measured build failure (SC-H) | — | remove the refusal |
| 3.11 | `aGeneratedPackageBuildsAgainstThisCheckout` (env-gated, extended: builds and runs the generated test) | — | — (run, not mutated) |

Count expectation: lane 1 +38 (37 swift-testing + 1 XCTest; the XCTest
counts in the summary only if the native summary includes XCTest — lane 1
reads both summary lines), lane 2 +26, lane 3 +5 (3.1–3.3, 3.9, 3.10; 3.11
modified; 3.5–3.8 moved, net 0; 3.4 dropped, HT-R item 5). Guards +3
(3.1–3.3, HT-M). Re-measured, never trusted.

## §5 Platforms

- macOS: everything; CoreText default.
- Linux (`swift:6.4-noble`) and Windows: `MetalUITesting` and
  `MetalUITestingTests` build and run (the root jobs run every portable test
  target). Lane 1 and lane 2 each run the root package in the container:
  `docker run --rm -v "$PWD":/work -v metalui-root-test-harness:/tmp/build -w
  /work swift:6.4-noble bash -c 'swift build --build-tests --scratch-path
  /tmp/build && swift test --skip-build --scratch-path /tmp/build'`. `.task`
  and `runUntilIdle` on Linux are measured there (the main queue is drained by
  the test runner's main actor; if not, the record says what is gated).
  Windows is CI's (or the UTM VM's) — the 1 MB stack does not apply to
  `@MainActor` tests on the main thread.
- `Backends/SDL` is untouched; its build is re-run once by lane 3 to show it
  still builds (it shares `MetalUIPlatform`).

## §6 Files and lanes (HT-P; disjoint)

| Lane | Files |
|---|---|
| 1 | `Package.swift`; `Sources/MetalUITesting/{TestHarnessError,HeadlessPlatform,HeadlessPlatformWindow,HeadlessWindowRenderer,TestApp,TestWindow,TestWindowInput,FrameWork}.swift`; `Sources/MetalUI/TestingHooks.swift`; `Sources/MetalUILayout/{LayoutTree,NativeLayoutRun}.swift` (access only); `Tests/MetalUITestingTests/{HarnessSupport,HarnessWindowTests,HarnessInputTests,HarnessClockTests,HarnessLifecycleTests,HarnessLayoutTests,HarnessWorkTests,XCTestHarnessTests}.swift`; `docs/probes/closeout-public-api.sh` (TARGETS), its `.tsv`, `closeout-inventory-map.tsv` (lane 1 rows) |
| 2 | `Sources/MetalUITesting/{TestElement,TestWindowQueries,TestWindowElementInput,TestWindowPresentations,TestAppMenuBar,MenuEvaluation}.swift`; `Sources/MetalUI/TestingMenuHooks.swift`; `Tests/MetalUITestingTests/{HarnessQueryTests,HarnessPresentationTests,HarnessMenuTests}.swift`; census `.tsv` and map rows (lane 2's) |
| 3 | `Tests/MetalUITests/TestHarnessCompileGuards.swift`; `Tests/MetalUITests/{InputDispatchTests,LifecycleTests,AlertTests,ContextMenuTests}.swift` (deletions); `Tests/MetalUITestingTests/MigratedHarnessTests.swift`; `Sources/MetalUIScaffold/Scaffold.swift`; `Tests/MetalUIScaffoldTests/ScaffoldTests.swift`; `docs/{testing,getting-started,api-overview,migration}.md` |

Lane order 1 → 2 → 3. The Record phase (after lane 3) edits CLAUDE.md,
AGENTS.md, `docs/record/README.md`, `docs/record/91-test-harness.md`.

## §6a Rules for CLAUDE.md (Record phase, one or two sentences each)

1. `MetalUITesting` (product, portable list) imports only `MetalUI` and
   `MetalUIScene`; production targets never depend on it (HT-A).
2. **A new defaultless `PlatformWindow`/`Platform`/`WindowRenderer` requirement
   is implemented in `HeadlessPlatformWindow`/`HeadlessPlatform`/
   `HeadlessWindowRenderer` too** (HT-D 5).
3. Harness read-back goes through `package` hooks in `Sources/MetalUI/Testing*Hooks.swift`,
   never a `public` widening of `Window` (HT-C); `onFrameAdopted` belongs to
   the harness for its windows.

## §7 Demo expectation

No demo change, no new demo section. The fourteen offscreen images compare
**0 px** against `70e9389` (`docs/probes/demo-pixels/compare.sh <scratch>
70e9389 HEAD`, run by lane 3); `DemoFrameDeterminismTests`' `Expected.swift`
unedited.

## §8 Human checks

**None added.** The harness is headless by construction; nothing it does is a
look. Its XCTest path is run by test 1.38 rather than by hand.

## §9 Merge debts and what this design did not measure

1. **C9/C12** may add a defaultless platform requirement; the merge adds it to
   the headless conformers (HT-D 5). C9 changes key dispatch: tests 1.8–1.11
   are the merge's first look.
2. **C13** may rename `RasterCache.lastRasterizedPixels`/`lastBlurredPixels`;
   `TestingHooks.swift` is the only reader.
2a. **C12** (menus on SDL) may change `MenuSession.number`'s signature or
   `MenuContent`'s SPI; `TestingMenuHooks.swift` is the only reader, re-pointed
   at merge, and tests 2.13–2.20 are the merge's first look (HT-R item 7).
3. Not measured by the designer (each lane measures and records): the
   accessibility-at-open path (HT-D 4) and its fallback; whether
   `testingRecordsElementBounds` can be set before `App.openWindow`'s first
   draw (§3.1 item 3) or needs the second frame; `runUntilIdle` on Linux;
   testable executables on Windows for the scaffold (HT-O); whether 1.8's
   mutation is green (keyDown may also edit a field).
