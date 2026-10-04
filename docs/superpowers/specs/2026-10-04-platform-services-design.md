# Platform services — dialogs, alerts, window sizing, hover, Divider, menu Picker — design

**Status: DESIGNED (2026-10-03) — not yet implemented.** User request
2026-10-02, an item of the gpui-gap priority list (the SMK configurator port's
gaps 4, 5, 7, 8, 9, 10 and 12); **not a plan task**. Rulings `SV-A`…`SV-W` in
[`../2026-10-04-platform-services-decisions.md`](../2026-10-04-platform-services-decisions.md).
Record: `docs/record/77-platform-services.md` (Record phase). Probes (new,
outputs and readings in their headers): `docs/probes/swiftui-platform-services.swift`
(SwiftUI: `D` importer, `X` exporter, `A`/`C1` alerts, `H` hover — a broken
instrument, `V` Divider, `P` menu picker; run twice, byte-identical),
`docs/probes/swiftui-window-sizing.swift` (SwiftUI scenes, `W0`–`W5`) and
`docs/probes/swift-main-queue-drain-nested.swift` (runtime, `J0`–`J3`, macOS
and `swift:6.4-noble`). Branch `feat/platform-services` from `c2b8f48`.

**Motivation.** The configurator (SwiftCrossUI, ~8,500 lines, one window,
macOS first) needs: ~10 JSON import/export sites (keymaps, themes, macros), 4
alerts (one a confirm-delete), a 1440-wide minimum window with a computed
height, one hover highlight, 13 `Divider`s, key and step choosers over
hundreds of options, and main-actor async work on Linux/Windows (its device
monitor's `Task.sleep` loop, its USB transport resuming on the main actor).

## 0. Baseline (re-taken by the design session at `c2b8f48`)

`swift build --build-system native --build-tests`: **0 `error:`**, the one
`warning:` SwiftPM's deprecation notice. `swift test --build-system native
--no-parallel`: **`Test run with 2430 tests in 3 suites passed after 127.067
seconds`**, the `FR-J no-argument frame: succeeded=true` line present. 150
`canTypecheck`-gated test declarations (`grep -rh "enabled(if: canTypecheck"
Tests | wc -l`), 0 goldens, **92 live divergences, next label 126**
(`docs/divergences.md` lines 4 and 12). Screen **locked** throughout (lock
probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`): no real-window
capture in the design session. OrbStack was running and was left running.

## 1. What MetalUI has, and what SwiftUI does

### 1.1 Inventory

| Area | Today | File |
|---|---|---|
| Platform seam | `PlatformWindow`: defaultless `setPreferredColorScheme`, control-state pair, reduce-motion pair, `onAccessibilityRequest`/`publishAccessibilityTree`, `setTextInputArea`, `readClipboard`/`writeClipboard` (text only), `beginExternalDrag`, `presentMenu`; `Platform`: `openWindow(title:size:)`, `run`, `setApplicationIcon`, `setMenuBar`. No dialog, alert or size-limit call. | `Sources/MetalUIPlatform/Platform.swift` |
| Conformers | `AppKitWindow` (`AppKitPlatform.swift`), `SDLWindow` (`SDLPlatform.swift`), `FakePlatformWindow`/`FakePlatform` (`Tests/MetalUITests/Fakes.swift:108, 406`), `SDLLifecycleTests`' fake, and conformer fixtures in seven compile-guard files (`AppIcon`, `ColorScheme`, `Commands`, `ControlState`, `DragAndDrop`, `Menu`, `Transaction` `CompileGuards.swift`), each with a positive control that must compile. | — |
| Input | `InputEvent`: mouse down/up/moved/dragged, wheel, keys, modifiers, text input/composition, `.drop`, right down/up, `.menuAction`. **No pointer-left-window case**; AppKit's tracking area already declares `.mouseEnteredAndExited` and consumes nothing. | `InputEvent.swift:122`, `AppKitPlatform.swift:80–110` |
| Hover | Paint-only: `Frame.resolveHover(at:)` once per frame (topmost **opaque** hitbox) → `PaintPass.isHovered`. `Window.lastMousePosition` is **deliberately sticky** (nothing clears it when the pointer leaves). No hover callback. | `Frame.swift:1998–2045`, `Window.swift:415–445`, `Passes.swift:779–810` |
| One ranking | `topmostHitbox(in:at:where:)`; `topmostOpaqueHitbox` its specialization; the arena's ancestors by `id.parent` chain, same layer, `contains`. Non-opaque regions: draggable, drop destination, contextual. | `Hitbox.swift:236–250`, `Window.swift:2044–2080`, `Frame.swift:1390–1440` |
| Menus | `MenuContent` (closed), `Divider` **menu-only** (`MN-H` item 3), `Menu` pull-down via `Window.openPullDownMenu`, native `NSMenu` or the drawn `MenuPanel` (no scrolling: a 300-row level overflows the window). | `MenuContent.swift:102–115`, `PullDownMenu.swift`, `MenuPanel.swift`, `MenuSession.swift` |
| Picker | `PickerStyle` `.automatic` = `.segmented`, `.radioGroup`; options found through `PickerScope` during layout, each `TaggedElement` building chrome; `.menu` not offered (divergence 81, guard `aMenuPickerStyleIsNotOffered`). | `Picker.swift`, `ControlsCompileGuards.swift:75` |
| Button role | `ButtonRole` stored, "read by nothing" (record §05). | `Button.swift:54`, `ButtonStyle.swift:3–30` |
| ContentType | Identifier + transitive conformance; `item`, `data`, `text`, `plainText`, `utf8PlainText`, `url`, `fileURL`. No filename extensions, no `.json`. | `Transferable.swift` |
| Windows | `App.openWindow(title:size:startsDisplayLink:content:)`; windows resizable with no limits. Root laid out by `computeNativeLayout(root:proposal:centredIn:)`; a measure-only entry `measureNativeLayout(root:proposal:)` exists, internal. | `App.swift:96–140`, `LayoutTree.swift:530–600`, `Frame.swift:2324–2345` |
| Frame loop | `drawFrameIfNeeded`: build → `CR-Q` second build → `drainLifecycle` (actions after the build, one settle build) → accessibility → `finishFrame`. | `Window.swift:1109–1340` |
| Input order | pointer state, tooltip, external drop, drag session, menu session / popovers / context menu, wheel, text input, value track, gestures, keymap, text keys, `onKey`, context-menu key, shortcuts, commands, Tab, `onInput`. | `Window.swift:736–890` |
| SDL loop | `run(maxIterations:)`: pump + tick, or `mui_wait_event(250)`; never enters `RunLoop` (main-actor tasks starve, `LC-L` `B1`). Thread-safe wake precedent: `mui_wake_for_accessibility`. SDL 3.4.18 (brew) has `SDL_ShowOpenFileDialog`/`SaveFileDialog`, `SDL_SetWindowMinimumSize`/`MaximumSize`, `SDL_EVENT_WINDOW_MOUSE_LEAVE`. | `SDLPlatform.swift:85–106`, `SDLBridge.h` |
| Accessibility roles | group … `menu`, `menuItem`, `menuItemCheckBox`, `menuButton`, `popover`. No pop-up button, no alert. | `AccessibilityTree.swift:31–68` |
| Demo flags | `METALUI_{TEXT_INPUT,CONTROLS,LOOKS,DND,METALVIEW,MENUS}_DEMO`; the SDL demo reads the same names. | `Sources/MetalUIDemo/main.swift:26–45`, `Backends/SDL/Sources/MetalUISDLDemo/main.swift:40–70` |

### 1.2 SwiftUI's answers (summary; the probes' READING blocks are the authority)

- **Importer/exporter** — sheets on the window (`D1`, `X1`); cancel: importer
  calls nothing, exporter calls `onCancellation`, both write `isPresented =
  false` (`D2`, `X3`); `isPresented = false` dismisses silently (`D3`); a `nil`
  item still presents (`X5`); save panel named `defaultFilename`, extension
  hidden, "Export" (`X1`). Completion content is unmeasured (out-of-process
  panel).
- **Alerts/confirmation dialogs** — `NSAlert` sheets; two buttons side by side
  with Cancel left, three or more stacked in declaration order with Cancel
  last; Escape → cancel; Return → first plain button; none with only
  destructive + cancel; synthesized Cancel beside a lone destructive; "OK"
  for no actions (`A1`–`A9`, `C1`).
- **Window sizing** — `.automatic` = `.contentMinSize` on macOS; `.contentSize`
  adds the content's maximum; the minimum follows the content; a default below
  the minimum opens at it; limits include the 32-pt title-bar inset
  (`W0`–`W5`).
- **Divider** — 1 pt along the nearest stack's cross axis, horizontal with no
  stack; length `proposal ?? 10`; separator colour (black/white α 0.098); no
  accessibility node (`V1`–`V15`).
- **Menu picker** — the automatic macOS picker; `AXPopUpButton`, value the
  selected title; as wide as its widest option; menu of every option with the
  selection checked (`P0`–`P5`).
- **Hover** — unmeasured (broken instrument, `H1`–`H11`).
- **Main queue** — a drain per loop iteration works from top-level code (`B2`),
  never inside a main-actor job (`J1`; nor the AppKit shape, `J3`).

## 2. Public API

```swift
// File dialogs (SV-C, SV-D) — Sources/MetalUI/FileDialogs.swift (lane 2)
extension ElementGroup {
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [ContentType],
                             allowsMultipleSelection: Bool,
                             onCompletion: @escaping (Result<[URL], Error>) -> Void) -> PresentationScope<Self>
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [ContentType],
                             onCompletion: @escaping (Result<URL, Error>) -> Void) -> PresentationScope<Self>
    public func fileExporter<T: Transferable>(isPresented: Binding<Bool>, item: T?, contentTypes: [ContentType] = [],
                                              defaultFilename: String? = nil,
                                              onCompletion: @escaping (Result<URL, Error>) -> Void,
                                              onCancellation: @escaping () -> Void = {}) -> PresentationScope<Self>
}
public struct FileDialogs {
    public func openFiles(allowedContentTypes: [ContentType], allowsMultipleSelection: Bool = false) async throws -> [URL]
    public func saveFile(contentTypes: [ContentType] = [], defaultFilename: String? = nil) async throws -> URL?
}
public enum FileDialogError: Error, Equatable { case noWindow, unavailable, busy, platform(String) }
public enum FileExportError: Error, Equatable { case noItem }
extension EnvironmentValues { public internal(set) var fileDialogs: FileDialogs }
extension Window { public var fileDialogs: FileDialogs { get } }
extension ContentType {                                   // SV-E — Transferable.swift (lane 2)
    public init(_ identifier: String, conformingTo parents: [ContentType] = [.data], filenameExtensions: [String] = [])
    public var preferredFilenameExtension: String? { get }
    public static let json: ContentType                  // public.json, conforms to .text, ["json"]
}

// Alerts (SV-I) — Sources/MetalUI/Alert.swift (lane 2)
public protocol AlertActions { /* one SPI requirement */ }
@resultBuilder public enum AlertActionsBuilder { /* block, if, if-else, for over Button<Text> */ }
extension Button: AlertActions where Label == Text {}
extension ElementGroup {
    public func alert<A: AlertActions>(_ title: String, isPresented: Binding<Bool>,
                                       @AlertActionsBuilder actions: () -> A) -> PresentationScope<Self>
    public func alert<A: AlertActions>(_ title: String, isPresented: Binding<Bool>,
                                       @AlertActionsBuilder actions: () -> A, message: () -> Text) -> PresentationScope<Self>
    public func alert<A: AlertActions, T>(_ title: String, isPresented: Binding<Bool>, presenting data: T?,
                                          @AlertActionsBuilder actions: @escaping (T) -> A) -> PresentationScope<Self>
    public func alert<A: AlertActions, T>(_ title: String, isPresented: Binding<Bool>, presenting data: T?,
                                          @AlertActionsBuilder actions: @escaping (T) -> A,
                                          message: @escaping (T) -> Text) -> PresentationScope<Self>
    public func confirmationDialog<A: AlertActions>(_ title: String, isPresented: Binding<Bool>,
                                                    @AlertActionsBuilder actions: () -> A) -> PresentationScope<Self>
    public func confirmationDialog<A: AlertActions>(_ title: String, isPresented: Binding<Bool>,
                                                    @AlertActionsBuilder actions: () -> A,
                                                    message: () -> Text) -> PresentationScope<Self>
}
public struct PresentationScope<Content: ElementGroup>: ElementGroup { /* transparent, SV-K */ }
extension PresentationScope: ProposalElementGroup where Content: ProposalElementGroup {}

// Window sizing (SV-L) — Window.swift, App.swift (lane 2)
public struct WindowResizability: Sendable, Equatable {
    public static let automatic: WindowResizability
    public static let contentSize: WindowResizability
    public static let contentMinSize: WindowResizability
}
extension Window {
    public var minSize: Size<Pixels>? { get set }
    public var maxSize: Size<Pixels>? { get set }
    public var windowResizability: WindowResizability { get set }
}
// App.openWindow(title:size:minSize: = nil, maxSize: = nil, windowResizability: = .automatic,
//                startsDisplayLink: = true, content:)

// Hover (SV-N) — Sources/MetalUI/Hover.swift (lane 2)
public enum HoverPhase: Equatable, Sendable { case active(Point<Pixels>), ended }
extension StyledElement {                      // MN-Q's shape: a Handlers member, no identity level
    public func onHover(perform action: @escaping (Bool) -> Void) -> Self
    public func onContinuousHover(perform action: @escaping (HoverPhase) -> Void) -> Self
}
extension ProposalElementGroup {               // ... and one proposal wrapper (ContextualModifier's recipe)
    public func onHover(perform action: @escaping (Bool) -> Void) -> HoverModifier<Self>
    public func onContinuousHover(perform action: @escaping (HoverPhase) -> Void) -> HoverModifier<Self>
}
public struct HoverModifier<Content: ProposalElementGroup>: Element { /* no node; one identity level */ }

// Divider (SV-O) — MenuContent.swift + Sources/MetalUI/DividerView.swift (lane 3)
extension Divider: Element, ProposalElement {}

// Menu picker (SV-P) — Picker.swift (lane 3)
extension PickerStyle { public static let menu: PickerStyle }
```

`onHover`/`onContinuousHover` return what `.contextMenu`/`.help` return on
each vocabulary (`MN-Q`): `Self` on a `StyledElement` (no identity level,
composing with the other decorations in any order) and a `HoverModifier` on
the typed path (no layout node, its child numbered from 0 under its id, one
identity level for its caller only, registering the hover region at its own
bounds — `ContextualModifier`'s recipe; a hover modifier and a contextual one
on the same element are two wrappers). Every new public declaration gets a doc
comment and an inventory row (`A` for a SwiftUI spelling, `M` for
`FileDialogs`, `FileDialogError`, `FileExportError`, `Window.minSize`/
`maxSize`/`windowResizability`, `EnvironmentValues.fileDialogs`, the seam
types; `D` for `ContentType.json` and the importer/exporter — `ContentType`
in place of `UTType`, divergences 128/129 where they apply).

## 3. The seam (lane 1, `Sources/MetalUIPlatform/Presentations.swift`, new)

```swift
public struct PlatformFileType: Sendable, Equatable {
    public var identifier: String; public var conformsTo: [String]; public var filenameExtensions: [String]
}
public struct PlatformFileDialog: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case open(allowsMultipleSelection: Bool), save(defaultFilename: String?) }
    public var token: Int; public var kind: Kind; public var allowedTypes: [PlatformFileType]
    public var title: String?; public var prompt: String?
}
public struct FileDialogResultEvent: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable { case chosen([String]), cancelled, failed(String) }  // file-system paths
    public var token: Int; public var outcome: Outcome
}
public struct PlatformAlertButton: Sendable, Equatable {
    public var title: String; public var isDestructive: Bool; public var isDefault: Bool; public var isCancel: Bool
}
public struct PlatformAlert: Sendable, Equatable {
    public var token: Int; public var title: String; public var message: String?; public var buttons: [PlatformAlertButton]
}
public struct AlertResultEvent: Sendable, Equatable { public var token: Int; public var button: Int? }  // nil: dismissed
// PlatformWindow — each defaultless (SV-B):
func presentFileDialog(_ dialog: PlatformFileDialog) -> Bool
func presentAlert(_ alert: PlatformAlert) -> Bool
func dismissPresentation(token: Int)
func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?)
// InputEvent: case pointerExited, case fileDialogResult(FileDialogResultEvent), case alertResult(AlertResultEvent)
// AccessibilityRole (AccessibilityTree.swift): case popUpButton, case alert   (SV-S)
```

Each requirement's doc comment states the contract, "No default
implementation", its pinning guard and the migration stub (`SV-B` item 5).

## 4. Implementation

### 4.1 Lane 1 — the seam on every platform

- **`MetalUIPlatform`**: `Presentations.swift` (new); `Platform.swift` (four
  requirements); `InputEvent.swift` (three cases); `AccessibilityTree.swift`
  (two roles).
- **`MetalUIAppKit`**: new `AppKitPresentations.swift` —
  `presentFileDialog` (`SV-F`: `NSOpenPanel`/`NSSavePanel`,
  `beginSheetModal(for:)`, `false` when a sheet is attached, `UTType`
  mapping of `SV-E`), `presentAlert` (`SV-J` item 1), `dismissPresentation`
  (end the sheet with `.abort`, suppress its answer), every answer queued
  through `RunLoop.main.perform` onto `onInput`; `AppKitPlatform.swift` —
  `setContentSizeLimits` (`SV-M`), `mouseExited(with:)` → `.pointerExited`;
  `AppKitAccessibility.swift` — the two roles (`AXPopUpButton`; `AXGroup`
  subrole `AXDialog`).
- **`Backends/SDL`**: `SDLBridge.c`/`.h` — `MUI_EVENT_DIALOG`,
  `MUI_EVENT_MOUSE_LEAVE` (from `SDL_EVENT_WINDOW_MOUSE_LEAVE`),
  `mui_show_file_dialog(window, token, is_save, allow_many, filters…,
  default_location)` (heap-copied filters freed in the callback), the
  mutex-guarded result queue and `mui_take_dialog_result`,
  `mui_test_complete_dialog`, `mui_window_set_size_limits`,
  `mui_window_size_limits` (read back for tests), `mui_current_video_driver`.
  Every C enum `rawValue` converted explicitly (Windows `Int32`).
  `SDLPlatform.swift` — `presentFileDialog` (`SV-G`), `presentAlert` →
  `false`, `dismissPresentation` (forget only), `setContentSizeLimits`,
  dispatch of the two new event kinds, **the drain** in `run(maxIterations:)`
  (`SV-H` item 1, a doc comment naming `B2`/`J1`); `AccessKitTree.swift` — the
  two roles. New executable target `MainQueueDrainCheck` (`Package.swift`:
  depends on `MetalUISDL`, `MetalUI`, `MetalUIPortableText`; `main.swift`,
  top-level code, modes `task` and `dialog`).
- **Tests**: `Fakes.swift` (four members recording calls; `presentFileDialog`
  settable, default `true`; `presentAlert` settable, default `false`; the size
  clamp), the seven guard fixtures and `SDLLifecycleTests`' fake (four
  members each), new `PlatformServicesCompileGuards.swift`, new
  `AppKitPresentationTests.swift`, new SDL `SDLPresentationTests.swift` and
  `SDLMainQueueDrainTests.swift`.

### 4.2 Lane 2 — `Window`-side presentations, sizing, hover

- **`Presentations.swift`** (new, `MetalUI`): `PresentationScope`, the
  `PresentationRegistry` (records per build keyed per `SV-K` item 2; the
  in-flight token map; one in flight per window), the post-frame
  `reconcilePresentations()` called from `drawFrameIfNeeded` after
  `drainLifecycle`, and outcome dispatch from `onInput` (`.fileDialogResult`,
  `.alertResult`) **first in the input order** after pointer state (a
  result is never claimed by a later stage).
- **`FileDialogs.swift`** (new): the modifiers, `FileDialogs` (weak window,
  `withCheckedThrowingContinuation` + `withTaskCancellationHandler`), errors,
  the exporter's byte rule (`SV-C` item 4), URL ↔ path conversion.
- **`Alert.swift`** (new): `AlertActions`, the builder, the modifiers,
  `AlertButtons.resolve` (`SV-I` item 3, pure). **`AlertPanel.swift`** (new):
  the drawn alert (`SV-J` items 2–4): geometry (pure, unit-tested), paint via
  `Frame`'s rect and glyph primitives (no new drawable primitive; `TE-AD` not
  triggered), modal input stage (first after pointer state), accessibility
  nodes appended like `appendMenuPanel`.
- **`Hover.swift`** (new): `HoverPhase`, `HoverAttachment`, the modifiers, the
  hovered-set function over `lastHitboxes` (`SV-N` item 3) and the reconcile
  (`SV-N` items 4–6). **`Handlers.swift`**: the sixteenth member.
  **`Frame.swift`**: the hover region in `registerHandlers` (`SV-N` item 2);
  the axis stack is lane 3's (§4.3) — lane 2 does not touch it; the stamp of
  `fileDialogs`; content-limit measurement (`SV-L` item 2) before
  `computeRootLayout`. **`Window.swift`**: `.pointerExited` clears
  `lastMousePosition` (and its doc comment is rewritten: `SV-N` item 7);
  hover recompute in `updatePointerState`'s callers; the post-frame hooks;
  `minSize`/`maxSize`/`windowResizability` and the limit reconcile.
  **`App.swift`**: `openWindow`'s three parameters. **`EnvironmentValues.swift`**:
  `fileDialogs`. **`Transferable.swift`**: `SV-E`. **`LayoutTree.swift`**:
  `measureNativeLayout` → `package` (no other change; `MetalUILayout` still
  imports only `MetalUICore`). **`AccessibilityTreeBuilder.swift`**: nothing
  (the panel appends after the build, as the menu panel does).
- **Tests**: new `PresentationTests.swift`, `FileDialogTests.swift`,
  `AlertTests.swift`, `AlertPanelTests.swift`, `WindowSizingTests.swift`,
  `HoverTests.swift`, `PresentationCompileGuards.swift`; one field each in
  `ModifierTests.swift` (`HandlerShape`) and `OuterModifierMatrixTests.swift`
  (`HandlerFingerprint`); one arm each in `DisabledTests.swift`
  (`everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` — the D2 guard)
  and `HitRegionTests.swift` (`everyHandlerRegisteringSiteHonoursAllowsHitTesting`).

### 4.3 Lane 3 — Divider, menu picker, scrolling panel, demo, docs

- **`DividerView.swift`** (new): `Divider: Element, ProposalElement` — a
  native leaf (`requestNativeLeaf`), measure `(proposal ?? 10) × 1` or
  `1 × (proposal ?? 10)` by the axis read at layout, paint one rect of the
  theme's `.separator` (through the paint pass's colour resolution so it
  follows the scheme), no handlers, no accessibility emission.
  **`MenuContent.swift`**: `Divider`'s doc comment (no longer menu-only).
  **`Frame.swift`** — only the internal axis stack (`stackAxis`, push/pop
  helpers); **`NativeElements.swift`** (`HStack`/`VStack` push, `ZStack`
  pushes none), **`Flex.swift`** (`Row`/`Column` push), **`Grid.swift`**
  (pushes none). Each push wraps exactly the children's layout request and
  pops in a `defer`.
- **`Picker.swift`**: `PickerStyle.Kind.menu`, `.menu`; the menu layout
  (`Box` row: title, 8, the pull-down — an internal `Pair(OptionSink,
  PickerMenuLabel)` inside `Menu`'s button chrome, so options are recorded
  before the label reads the selection); `TaggedElement`'s menu-scope branch
  (`SV-P` item 3); the open path through `Window.openPullDownMenu` with the
  options as toggle items; the `.popUpButton` AX node.
  **`PullDownMenu.swift`**: an `initialHighlight` row for a picker's open.
  **`MenuPanel.swift`**/**`MenuSession.swift`**: `SV-Q` (offsets, wheel,
  scroll-into-view, visible-band paint and hit test, edge indicators, initial
  highlight).
- **Demo**: new `Sources/MetalUIDemoContent/ServicesDemo.swift`;
  `Sources/MetalUIDemo/main.swift` and
  `Backends/SDL/Sources/MetalUISDLDemo/main.swift` read
  `METALUI_SERVICES_DEMO`; `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift`
  gains the services tree.
- **Docs**: `docs/api-overview.md`, `docs/migration.md` (the four seam
  members, the three `InputEvent` cases, `aMenuPickerStyleIsNotOffered`'s
  replacement, `.pointerExited` un-sticking hover), `docs/getting-started.md`
  (call `App.run()` from synchronous top-level code, `SV-H` item 2),
  `docs/verification/human-checks.md` (group U).
- **Tests**: new `DividerTests.swift`, `MenuPickerTests.swift`,
  `MenuPanelScrollTests.swift`, `ServicesDemoTests.swift`;
  `ControlsCompileGuards.swift` (the flipped guard).

## 5. Divergences (`docs/divergences.md`, each lane its own rows, `SV-V`)

| # | Lane | SwiftUI | MetalUI | Ruling | Pin |
|---|---|---|---|---|---|
| 126 | 2 | `.automatic` resizability is `.contentMinSize` on macOS (`W0` = `W1`); limits include the 32-pt title-bar inset | `.automatic` asks the content nothing; `.contentMinSize`/`.contentSize` are opt-in and exclude any inset | `SV-L` | `automaticResizabilityAsksTheContentNothing` (2.33) |
| 127 | 3 | `Divider` black/white at α 0.098 (`V12`) | the theme's opaque `.separator` | `SV-O` | `aDividerPaintsTheSeparatorTokenOnePointThick` (4.7) |
| 128 | 3 | a menu picker's menu draws each option's view | an option whose content is not a `Text` is titled by its tag's description | `SV-P` | `aNonTextMenuOptionIsTitledByItsTag` (5.10) |
| 129 | 1 | `allowedContentTypes` match by UTType conformance | off Apple (SDL) by filename extension only; a type without one filters nothing | `SV-E` | `sdlFiltersCarryExtensionsAndATypeWithoutOneFiltersNothing` (1.13) |

Amended rows: **81** (`.menu` offered; the automatic picker still segmented —
lane 3), **120** (a legacy decoration after a presentation modifier does not
compile either — lane 2, pin 2.G8). "Not offered" section rows (lane 2):
`fileExporter(document:)`/`FileDocument`, `confirmationDialog(titleVisibility:)`,
alert text fields, `onContinuousHover(coordinateSpace:)`. Record §05's
`ButtonRole` row is amended in the Record phase (the role is read by alerts).

## 6. Tests

Every test below is **red before by not compiling** (its API is new) unless
it says otherwise; the column "must redden under" names the mutation the lane
applies (commit first, restore from a copy, full unfiltered suite, `git status
--short` after, every reddened test named). Hover, alert and dialog tests drive
a `Window` over `FakePlatformWindow` with `startsDisplayLink: false`; nothing
sleeps; time is `simulateTick`. A test awaiting `FileDialogs` uses the bounded
pattern: start a `Task`, `await Task.yield()` at most N times until the fake has
recorded the call (`try #require`), deliver the result through `onInput`, and on
failure cancel the task (which throws `CancellationError`, `SV-D` item 3) —
never an unbounded await.

### 6.1 Lane 1 — seam and platforms

| # | Test | Asserts | Must redden under |
|---|---|---|---|
| 1.G1 | `aPlatformWindowWithoutPresentFileDialogDoesNotCompile` (guard, `typecheckFile`, plain import) | control compiles; the conformer missing it is refused naming it | a default `presentFileDialog` in a `PlatformWindow` extension |
| 1.G2 | `aPlatformWindowWithoutPresentAlertDoesNotCompile` | likewise | a default `presentAlert` |
| 1.G3 | `aPlatformWindowWithoutDismissPresentationDoesNotCompile` | likewise | a default `dismissPresentation` |
| 1.G4 | `aPlatformWindowWithoutSetContentSizeLimitsDoesNotCompile` | likewise | a default `setContentSizeLimits` |
| 1.1 | `appKitOpenDialogIsASheetWithTheDeclaredTypes` (AppKit, real window) | `attachedSheet` is an `NSOpenPanel`; `allowedContentTypes == [.json]`; multiple selection, files only; `NSApp.modalWindow == nil` | `allowsMultipleSelection` not copied; `runModal` in place of the sheet is not a usable mutation (blocks) — use `canChooseDirectories = true` |
| 1.2 | `appKitSaveDialogCarriesTheNameTypesAndExportPrompt` | `nameFieldStringValue`, `isExtensionHidden`, `prompt`/`title` from the seam | name not copied |
| 1.3 | `appKitCancelledDialogArrivesAsQueuedInput` | `panel.cancel(nil)` → no `onInput` during the call; after a run-loop turn exactly one `.fileDialogResult(token, .cancelled)` | deliver synchronously inside the completion (count during the call ≠ 0) |
| 1.4 | `appKitDismissPresentationEndsTheSheetAndAnswersNothing` | sheet gone; no result event | not suppressing the `.abort` answer |
| 1.5 | `appKitSecondDialogWhileASheetIsUpAnswersFalse` | second `presentFileDialog` → `false` | drop the attached-sheet check |
| 1.6 | `appKitAlertIsASheetWithSwiftUIsKeysAndOrder` | `_NSAlertPanel` attached; buttons by title in the resolved order; `"\r"` only on `isDefault`, `"\u{1b}"` only on `isCancel`; `hasDestructiveAction` | leave NSAlert's own first-button Return (the A1 shape gains `"\r"` on Delete) |
| 1.7 | `appKitAlertButtonReportsItsIndexAfterTheSheetEnds` | `performClick` → one queued `.alertResult(token, index)` | report the response code instead of the index |
| 1.8 | `appKitContentSizeLimitsReachTheWindowAndClampIt` | `contentMinSize`/`contentMaxSize`; a 300 × 200 window given min 400 × 300 is resized to it and `onResize` fires | skip the resize-into-limits |
| 1.9 | `appKitMouseExitedDeliversPointerExited` | a `mouseExited` to the host view → `.pointerExited` | drop the override |
| 1.10 | `sdlDialogResultFromAnotherThreadArrivesAsInput` (SDL, hidden window, `armMainRunLoopExitCheck()`) | `mui_test_complete_dialog` from a new thread; `pumpEvents()` → one `.fileDialogResult(token, .chosen(paths))` with the paths intact | not pushing `MUI_EVENT_DIALOG` (result queued, never dispatched) |
| 1.11 | `sdlCancelledAndFailedDialogsMapTheirOutcomes` | empty list → `.cancelled`; `NULL` → `.failed(message)` | swap the two branches |
| 1.12 | `sdlDialogUnderTheOffscreenDriverFails` (`.enabled(if:)` offscreen) | the real `SDL_ShowOpenFileDialog` → `.failed` within a bounded number of pumps | answer `false` from `presentFileDialog` (no event ever arrives) |
| 1.13 | `sdlFiltersCarryExtensionsAndATypeWithoutOneFiltersNothing` (pure) | `[.json, .plainText]` → `"json"`, `"txt"`; `[.data]` → no filter (`NULL`) | emit `"*"` for a type without extensions |
| 1.14 | `sdlPresentAlertDeclines` | `false`, nothing shown | answer `true` |
| 1.15 | `sdlContentSizeLimitsReachSDLAndClamp` | read back through `mui_window_size_limits`; min rounded up, max down; `nil` → 0 | swap rounding |
| 1.16 | `sdlMouseLeaveDeliversPointerExited` | a pushed raw `SDL_EVENT_WINDOW_MOUSE_LEAVE` → `.pointerExited` | drop the bridge mapping |
| 1.17 | `sdlDismissPresentationForgetsAndALateResultStillArrives` | the late result is delivered as input (the platform cannot close it; `Window` ignores it — 2.4) | — (documents the platform's half; no mutation owed: a contract with no code path to break) |
| 1.18 | `theSDLLoopRunsAMainActorTaskStartedFromTopLevelCode` (`SDLMainQueueDrainTests`, runs `MainQueueDrainCheck task`) | output `task ran=true resumed=true` | delete the drain line — **red in the Linux container**; record whether macOS reddens (SDL's Cocoa pump may drain) |
| 1.19 | `aDialogAnsweredOnAnotherThreadResumesAnAwaitingTask` (runs `MainQueueDrainCheck dialog`) | prints the paths the hook passed | delete the drain line (red on Linux) |
| 1.20 | `theDrainCheckExecutableIsFound` | the product path resolves | — (its failure is the instrument's) |

The AppKit tests (1.1–1.9) open real `NSWindow`s headless; sheets attach on a
locked screen with the app inactive (`D1`, `X1`, `A1` were recorded so), and
each answer is read after a bounded run-loop turn (`RunLoop.main.run(until:)`
of a few ms, repeated at most N times — a turn, not a sleep). Adding AppKit
tests: run the whole suite unfiltered (CLAUDE.md).

Each of the seven existing guard files' positive controls is re-greened by
adding the four members (the check, not a new test). Linux container: lane 1
runs `docker build` + the SDL build/test of the task's recipe; 1.12 runs there.

### 6.2 Lane 2 — presentations, sizing, hover

**Presentations and file dialogs** (`PresentationTests.swift`,
`FileDialogTests.swift`):

| # | Test | Asserts | Must redden under |
|---|---|---|---|
| 2.1 | `anImporterPresentsAfterTheFrameOnceWhileShown` | no call before the first frame; one `.open(true)` call with `[json]`'s `PlatformFileType` after it; none on the next three frames | drop the in-flight check |
| 2.2 | `aChosenImportWritesIsPresentedFalseThenCompletesWithURLs` | order log `["isPresented=false", "completion"]`; URLs = `file://` of the paths; an `@State` write in the completion lands (dispatch) | swap the order; run outside `StateDispatch` (the write misses) |
| 2.3 | `aCancelledImportCallsNothingAndWritesIsPresentedFalse` (`D2`) | no completion; binding `false` | call `onCompletion(.failure)` on cancel |
| 2.4 | `isPresentedFalseDismissesAndALateResultRunsNothing` (`D3`) | `dismissPresentation(token)` recorded; a later result for it runs nothing | not forgetting the token |
| 2.5 | `aFailedOrUnavailableDialogCompletesWithFailure` | `.failed("x")` → `.platform("x")`; fake `false` → `.unavailable`; binding `false` both | swallow the failure |
| 2.6 | `theSingleURLImporterPassesTheFirstURL` | `.open(false)`; `.success(url)` | pass the last |
| 2.7 | `anExporterWritesTheItemsBytesAndCompletesWithTheURL` | `Data` + `.json` into a temp dir: bytes equal, `.success(url)`, binding `false` | write only `exported(as: chosen)` (nil for `Data`/`.json` → failure) |
| 2.8 | `anExporterPrefersAConformingRepresentation` | a two-type custom `Transferable` writes the conforming one | always the first |
| 2.9 | `aCancelledExportCallsOnCancellation` (`X3`) | `onCancellation` once, no completion | call completion |
| 2.10 | `aNilItemExporterPresentsAndFailsOnConfirm` (`X5`) | presented; confirm → `.failure(FileExportError.noItem)` | skip presenting for `nil` |
| 2.11 | `twoPresentationsWaitTheirTurn` | the second presents only after the first's result | present both |
| 2.12 | `fileDialogsOpenFilesReturnsTheURLsAndEmptyOnCancel` (bounded pattern) | `[url]`, then `[]` | throw on cancel |
| 2.13 | `fileDialogsSaveFileReturnsNilOnCancel` | `nil` | — (shares 2.12's mutation site; named for the save half) |
| 2.14 | `cancellingTheAwaitingTaskDismissesAndThrows` | `dismissPresentation` recorded; `CancellationError` | no cancellation handler (the test's bound fails, it does not hang) |
| 2.15 | `fileDialogsWhileBusyThrowsBusy` | second call throws `.busy` | queue it |
| 2.16 | `anUnboundOrDeadWindowThrowsNoWindow` | default `EnvironmentValues().fileDialogs` and a released window → `.noWindow`; the window deinitialises (weak) | hold the window strongly (deinit never runs) |
| 2.17 | `theEnvironmentCarriesTheWindowsFileDialogs` | a `Button` action reading `@Environment(\.fileDialogs)` reaches the fake | stamp nothing |
| 2.18 | `contentTypeJSONConformsToTextAndCarriesItsExtension` | `.json.conforms(to: .text)`, `preferredFilenameExtension == "json"`, `.plainText` `"txt"`, drag-and-drop matching unchanged | drop `.text` from `.json`'s parents |
| 2.19 | `aPlatformFileTypeCarriesIdentifierConformanceAndExtensions` | the seam value for `[json, plainText]` | sort the conformance differently |

**Alerts** (`AlertTests.swift`, `AlertPanelTests.swift`):

| # | Test | Asserts | Must redden under |
|---|---|---|---|
| 2.20 | `alertButtonsResolveSwiftUIsOrderAndKeys` (pure; a table of A1–A5, C1, plus "cancel only" and "two plain") | order, default, cancel, synthesized buttons per row | per row: no synthesized Cancel (A5), destructive eligible for default (A1), cancel kept in place (A4), no OK (A3) — each reddens its row only |
| 2.21 | `anAlertPresentsAfterTheFrameWithItsTitleMessageAndButtons` | fake `presentAlert = true`: one `PlatformAlert` with the resolved buttons | evaluate the message every frame and re-present |
| 2.22 | `anAlertResultWritesIsPresentedFalseThenRunsTheAction` | order, dispatch (an `@State` write lands); a synthesized Cancel runs nothing | swap order |
| 2.23 | `isPresentedFalseDismissesTheAlert` (`A9`) | `dismissPresentation` | — (2.4's site) |
| 2.24 | `alertPresentingShowsOnlyWhileDataIsNonNilAndPassesIt` | `nil` presents nothing; data reaches actions and message | ignore `data == nil` |
| 2.25 | `aConfirmationDialogIsTheSameAlert` | same `PlatformAlert` as the `.alert` spelling | — |
| 2.26 | `aDeclinedAlertIsDrawnAboveEverythingAndOwnsNoState` | scene's last primitives are the panel; `StateTable` entry count and hitbox list unchanged by the panel | paint before the menu panel |
| 2.27 | `theDrawnAlertSwallowsPointerAndKeysBeneath` | a click on a button beneath and a keymap key both do nothing | let unhandled events through |
| 2.28 | `returnPressesTheDefaultAndEscapeTheCancelOnTheDrawnAlert` | A2: Return → "A"; A1: Return nothing, Escape → cancel; A2: Escape nothing | map Return to the first button |
| 2.29 | `tabAndArrowsMoveTheRingAndSpacePressesIt` | ring moves, Space presses | — (shares 2.28's dispatch; mutate the ring step) |
| 2.30 | `aClickOnADrawnAlertButtonPressesIt` | action ran, binding `false`, panel gone | hit-test with the wrong panel origin |
| 2.31 | `theDrawnAlertPublishesAnAlertNodeWithButtonChildren` | `.alert` node, label, value, `.button` children; `press` chooses | omit the panel's append |
| 2.32 | `anAlertDismissesAnOpenInWindowMenu` | menu session closed when the alert presents | keep the menu |
| 2.G5 | `anOutsideTypeCannotConformToAlertActions` (guard) | refused | make the requirement public |
| 2.G6 | `aNonTextButtonIsNotAnAlertAction` (guard) | `Button { Image… }` in `actions` refused | widen the conformance |
| 2.G7 | `thePresentationSpellingsTypecheckFromAnExternalModule` (guard, `typecheckFile`, plain import, `@MainActor` model calls in every closure) | all spellings of §2 compile | — (positive; mutate one spelling's label to prove the fixture fails) |
| 2.G8 | `aLegacyDecorationAfterAPresentationModifierDoesNotCompile` (guard, divergence 120) | refused with "has no member 'onClick'" | a `StyledElement` forwarder on the scope |
| 2.G9 | `fileDialogsIsReadOnlyOutsideMetalUI` (guard, plain import) | `environment.fileDialogs = …` refused | make the setter public |
| 2.G10 | `titleVisibilityIsNotOffered` (guard) | refused | add the parameter |

**Window sizing** (`WindowSizingTests.swift`):

| # | Test | Asserts | Must redden under |
|---|---|---|---|
| 2.33 | `automaticResizabilityAsksTheContentNothing` | no limits call; `lastNativeLayoutWork` equal to a window without sizing (literal) | measure regardless |
| 2.34 | `explicitLimitsReachThePlatformOnlyWhenTheyChange` | one call per distinct pair across five frames and two equal assignments | call every frame |
| 2.35 | `contentMinSizeIsTheRootsAnswerAtAZeroProposal` (`W1`) | `frame(minWidth: 400, maxWidth: 900, minHeight: 300, maxHeight: 600)` root → min 400 × 300, max `nil` | measure at the window's size |
| 2.36 | `contentSizeAddsTheRootsAnswerAtAnInfiniteProposal` (`W2`) | max 900 × 600 | omit the maximum |
| 2.37 | `theContentMinimumFollowsTheContent` (`W5`) | a state write 400 → 700 → a new call with 700 | cache the first answer |
| 2.38 | `explicitAndContentLimitsCombinePerAxis` | max of minima, min of maxima, max raised to min | take the content's alone |
| 2.39 | `limitsAreMeasuredBeforeTheRealLayout` | `lastNativeLayoutWork` after a `.contentSize` frame equals the real run's literal | measure after |
| 2.40 | `openWindowAppliesLimitsBeforeTheFirstFrame` | the fake's first recorded call precedes `framesDrawn == 1` | apply after the first frame |
| 2.41 | `negativeLimitsClampAndInfiniteMaximumMeansNone` | values in the call | pass through |
| 2.42 | `aNaNLimitTraps` (exit test) | process exits | clamp NaN |

**Hover** (`HoverTests.swift`):

| # | Test | Asserts | Must redden under |
|---|---|---|---|
| 2.43 | `onHoverFiresOnEnterAndLeaveFromInput` | moves out/in/out → `[true, false]`; an `@State` write in it lands; nothing on a move within | fire on every move |
| 2.44 | `nestedHoverRegionsAllHoverEnteringOuterFirstLeavingInnerFirst` | `[outer true, inner true, inner false, outer false]` | reverse either order |
| 2.45 | `anOpaqueTargetCoversHoverBeneathAndAPaintedCoverDoesNot` | `onClick` cover → under `false`; plain `Rectangle` cover → under `true` | use every hitbox as a cover (contextual regions too) |
| 2.46 | `aHoverRegionNeverBlocksAClickBeneath` (H8's shape) | the button beneath fires | register the region opaque |
| 2.47 | `allowsHitTestingFalseAndDisabledWithdrawTheRegion` | no callbacks | register outside the gates |
| 2.48 | `hoverFollowsARenderEffect` | a `.offset`/`.rotationEffect` element hovers at its drawn place, not its laid-out one | test `bounds` without the transform |
| 2.49 | `aHigherLayerCoversHoverBeneath` | a `Deferred` presentation over the region → `false` | drop the same-layer clause |
| 2.50 | `pointerExitedClearsHoverAndIsHovered` | `onHover(false)`; next frame `isHovered` false | not clearing `lastMousePosition` |
| 2.51 | `aHoveredElementThatLeavesGetsFalseAfterTheFrame` | removal → `false` once, after the frame | drop departed ids silently |
| 2.52 | `contentMovingUnderAStillPointerUpdatesHoverAfterTheFrame` | a layout change moves a region under the pointer → `true` without an input event | recompute only on input |
| 2.53 | `anOpenInWindowMenuOrDrawnAlertEmptiesTheHoverSet` | `false` while open; `true` again after | ignore the menu |
| 2.54 | `onContinuousHoverReportsLocalPointsAndEnded` | `.active` with local points (an offset element: the offset subtracted); `.ended` on leave | report window points |
| 2.55 | `aTreeWithoutHoverRegistersNoRegionAndDoesNoHoverWork` | hitbox list identical to `c2b8f48`'s for the same tree; hover visits 0 | register a region for every element |
| 2.56 | `hoverRecomputeVisitsEachHitboxOnce` (counted, branching tree) | visits = hitbox count per event (literal) | a nested loop over ancestors × hitboxes |
| 2.G11 | `onHoverTypechecksOnBothVocabularies` (guard, plain import) | legacy and typed content, both modifiers | — (positive; mutate one fixture) |
| — | arms in `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `everyHandlerRegisteringSiteHonoursAllowsHitTesting`; fields in `HandlerShape`, `HandlerFingerprint` | the hover member | dropping the field reddens the matrix |

### 6.3 Lane 3 — Divider, menu picker, scrolling panel, demo

| # | Test | Asserts | Must redden under |
|---|---|---|---|
| 4.1 | `aDividerInAVStackSpansItsWidthOnePointTall` (`V1`) | rect 120 × 1 | swap axes |
| 4.2 | `aDividerInAnHStackSpansItsHeightOnePointWide` (`V2`) | 1 × 40 | — (4.1's site) |
| 4.3 | `aDividerOutsideAnyStackOrInAZStackIsHorizontal` (`V3`, `V4`) | 300 × 1 and 120 × 1 | `ZStack` pushes nothing (inherits an outer `HStack`'s axis — the fixture nests it in one) |
| 4.4 | `theNearestStackDecidesAndWrappersAreTransparent` (`V5`, `V6`, `V8`, `V9`, `V11`) | each literal | not popping (`defer` removed) |
| 4.5 | `aDividerInARowIsVerticalAndInAColumnHorizontal` | legacy rects | `Row` not pushing |
| 4.6 | `anUnconstrainedDividerIsTenLong` | nil proposal → 10 × 1 | `?? 0` |
| 4.7 | `aDividerPaintsTheSeparatorTokenOnePointThick` | scene rect colour = theme `.separator` in light and dark; 2 device px at scale 2 | `.textSecondary` |
| 4.8 | `aDividerPublishesNoAccessibilityNode` (`V15`) | none | emit a node |
| 4.9 | `aDividerInAMenuIsStillASeparator` | the menu's node is `.separator` | — (existing behaviour, pinned) |
| 4.10 | `theAxisDoesNotLeakPastItsStack` | a root `Divider` after an `HStack` sibling is horizontal; one inside a `Button` label inside an `HStack` is vertical | push without pop |
| 4.G12 | `aDividerIsBothAMenuItemAndAnElement` (guard, plain import) | `Row { Divider() }`, `HStack { Divider() }`, `Menu("m") { Divider() }` | — (positive) |
| 5.1 | `aMenuPickerIsATitleAndAPullDownShowingTheSelection` | structure; label text | label from the first option |
| 5.2 | `aMenuPickersButtonIsAsWideAsItsWidestOption` (`P1`, `P3`) | width = widest title's measured width + chrome (literal derived through the test's text system) | the selected title's width |
| 5.3 | `openingAMenuPickerPresentsEveryOptionWithTheSelectionOn` | fake `presentMenu = true`: items = n toggles, `isOn` only on the selected | mark none |
| 5.4 | `choosingAMenuPickerOptionWritesItsTag` (`P1`) | `.menuAction` → binding | run the previous option |
| 5.5 | `aSelectionMatchingNoTagShowsAnEmptyLabel` (`P5`) | label "" | fall back to the first |
| 5.6 | `menuPickerOptionsLayOutNothing` (counted) | 300 options → no node per option; layout work literal = the 3-option picker's | lay the option out |
| 5.7 | `aMenuPickerPublishesAPopUpButtonWithTheSelectedValue` | `.popUpButton`, value, label folded | `.menuButton` |
| 5.8 | `aMenuPickerOpensFromSpaceReturnAndAPressButNotWhenDisabled` | three openers; disabled opens nothing | open regardless |
| 5.9 | `aModifierAfterTagStillYieldsAMenuOption` | recorded; one zero-size node | trap on the single entry |
| 5.10 | `aNonTextMenuOptionIsTitledByItsTag` (divergence 128) | title | empty title |
| 5.11 | `theAutomaticPickerStaysSegmented` | segmented layout | — (pin) |
| 5.G13 | `aMenuPickerStyleCompiles` (replaces `aMenuPickerStyleIsNotOffered`) | compiles | — (the old guard reddens when `.menu` lands: that is its flip) |
| 5.12 | `aTallInWindowMenuIsClampedToTheWindowAndScrolls` | 300 rows: panel height = window − 2 margins; wheel moves the offset; rows painted ≤ visible + 1 (counted) | paint every row |
| 5.13 | `arrowKeysScrollTheHighlightIntoView` | highlight at row 40 → visible | move the highlight only |
| 5.14 | `aPickersMenuOpensWithTheSelectionHighlightedAndVisible` | row 150 selected → highlighted, in band | open at row 0 |
| 5.15 | `hitTestingFollowsTheScrollOffset` | a click at a scrolled row chooses that row | ignore the offset |
| 5.16 | `aShortMenuDoesNotScroll` | offsets 0, no indicators, pre-existing panel tests unchanged | always reserve the band |
| 6.1 | `everyProductionTreeBuildsOnAOneMegabyteThread` gains the services tree | builds | inline a section into the composer (debug build) |
| 6.2 | `servicesDemoHoverTileCountsEnters` | two passes → counter text "2" and an 16-pt bar | — |
| 6.3 | `servicesDemoMenuPickerHasThreeHundredOptions` | presented menu items = 300 | — |
| 6.4 | `servicesDemoOpensWithItsMinimumSize` | the fake's first limits call = 900 × 600 | — |

**Counts owed** (lane 3 re-takes; a count is stale the moment a test lands):
lane 1 ≈ +24 (20 + 4 guards; the SDL ones in `Backends/SDL`, not the root
count), lane 2 ≈ +70 (60 + 10 guards), lane 3 ≈ +33 (31 + 2 guards; one guard
replaced). Root target expected ≈ 2430 + ~100; the measured number is the
record's, never this estimate.

## 7. Demo (lane 3)

`METALUI_SERVICES_DEMO=1 swift run MetalUIDemo` (and `MetalUISDLDemo`):
`servicesDemoContent()` — `servicesDialogsSection()` (Import via
`.fileImporter([.json])`, Export via `.fileExporter(item: Data, [.json],
"keymap")`, "Open… (async)" via `@Environment(\.fileDialogs)`; the last
outcome as text), `servicesAlertSection()` (a "Delete…" button and its
destructive/cancel alert with a message), `servicesHoverSection()` (three
tiles, colour on hover, enter counters as text and an 8-pt-per-count bar),
`servicesDividerSection()` (`Divider` in `VStack`, `HStack`, `Row`, `Column`),
`servicesPickerSection()` (a 300-option `.menu` picker and its value) — each
its own function handed to a generic composer. The window opens with `minSize:
900 × 600`. **Pixels**: the fourteen offscreen images 0 px against `c2b8f48`
(`docs/probes/demo-pixels/compare.sh <scratch> c2b8f48 HEAD`);
`DemoFrameDeterminismTests`' `Expected.swift` unedited. A real-window launch only
when the lock probe allows, killed after a few seconds.

## 8. Docs (lane 3; Record phase for CLAUDE.md, AGENTS.md, README, record)

`api-overview.md` (each new spelling), `migration.md` (`SV-B` item 5's stubs;
the three `InputEvent` cases; `PaintPass.isHovered` no longer sticky after the
pointer leaves; `aMenuPickerStyleIsNotOffered` → `aMenuPickerStyleCompiles`),
`getting-started.md` (`App.run()` from synchronous top-level code),
`divergences.md` (§5), `human-checks.md` (§9). CLAUDE.md's rule lines (Record
phase): the four seam members in "PlatformWindow's defaultless requirements";
"hover is a non-opaque region through the one ranking"; "`Divider` reads the
stack-axis stack: a new linear container pushes"; "SDL drains the main queue
once per iteration — `App.run()` from top-level code".

## 9. Human checks (lane 3, `docs/verification/human-checks.md` group U)

- **U1** AppKit: Import opens an open panel as a sheet on the demo window,
  filtered to `.json`; Cancel and Open both return the sheet; the chosen file's
  name appears.
- **U2** AppKit: Export opens a save panel named "keymap" (extension hidden),
  "Export"; saving writes the file.
- **U3** Linux (X11 and Wayland) and Windows SDL: Import/Export open the
  desktop's dialog (portal, zenity or the Windows dialog); the chosen path
  arrives in the window (the main-queue drain: the async button's result
  appears without moving the pointer).
- **U4** AppKit: the alert is a sheet; Cancel on the left, Delete on the right
  in red; Escape cancels; Return does nothing (A1's shape).
- **U5** SDL: the drawn alert — scrim, panel, the default button accented;
  Return/Escape/Tab/Space; clicks beneath do nothing; Orca/Narrator announce an
  alert.
- **U6** AppKit: the menu picker's button shows the selection, opens a native
  menu of 300 items with a check on the selection, below the button.
- **U7** SDL: the same menu drawn in the window, clamped to the window and
  scrolling by wheel and arrows, opening on the selection.
- **U8** Hover tiles highlight under the pointer and un-highlight when it
  leaves the tile and when it leaves the window (both platforms).
- **U9** Dragging the window edge stops at 900 × 600 (both platforms).
- **U10** `Divider`s: hairline look in light and dark, vertical in the row
  stacks.

## 10. Lanes (`SV-V`)

Three lanes, **in order**, one agent at a time in this worktree; source files
disjoint; registries append-only per lane.

| Lane | Model | Owns |
|---|---|---|
| 1 — seam | Opus | `Sources/MetalUIPlatform/{Presentations.swift (new), Platform.swift, InputEvent.swift, AccessibilityTree.swift}`, `Sources/MetalUIAppKit/{AppKitPresentations.swift (new), AppKitPlatform.swift, AppKitAccessibility.swift}`, `Backends/SDL/**` except `MetalUISDLDemo/main.swift`, `Tests/MetalUITests/{Fakes.swift, PlatformServicesCompileGuards.swift (new), AppKitPresentationTests.swift (new)}` and the seven guard fixtures |
| 2 — window | Opus | `Sources/MetalUI/{Presentations, FileDialogs, Alert, AlertPanel, Hover}.swift (new)`, `Window.swift`, `Handlers.swift`, `App.swift`, `EnvironmentValues.swift`, `Transferable.swift`, `Frame.swift` (hover region, stamp, content limits), `Sources/MetalUILayout/LayoutTree.swift` (one access level), the §6.2 test files, `ModifierTests.swift`, `OuterModifierMatrixTests.swift`, `DisabledTests.swift`, `HitRegionTests.swift` |
| 3 — views, demo, docs | Opus for code; Sonnet for docs | `Sources/MetalUI/{DividerView.swift (new), MenuContent.swift, NativeElements.swift, Flex.swift, Grid.swift, Picker.swift, PullDownMenu.swift, MenuPanel.swift, MenuSession.swift}`, `Frame.swift` (the axis stack only — after lane 2 is committed), `Sources/MetalUIDemoContent/ServicesDemo.swift (new)`, `Sources/MetalUIDemo/main.swift`, `Backends/SDL/Sources/MetalUISDLDemo/main.swift`, the §6.3 test files, `ControlsCompileGuards.swift`, `DemoStackBudgetTests.swift`, the docs of §8 |

Registries each lane appends its own rows to: `docs/divergences.md`,
`docs/probes/closeout-inventory-map.tsv`, `docs/probes/closeout-public-api.tsv`
(re-recorded). Each lane ends with the full gate (§12).

## 11. Deferred (reason, owner)

| Item | Reason | Owner |
|---|---|---|
| Clipboard images / typed data | two more requirements on both platforms for a use the configurator lacks (`SV-R`) | none |
| `.task(perform:)`, `.task(id:)` | its blocker is removed here (`SV-H`), but it is a lifecycle modifier with `K1`/`K2`'s semantics to build and test | none (a lifecycle follow-up) |
| `fileExporter(document:)` / `FileDocument`, `fileMover` | `FileWrapper` configurations; the configurator exports `Data` | none |
| Folder selection (`allowedContentTypes: [.folder]`) | not needed (files only) | none |
| `fileDialogDefaultDirectory`, `fileDialogMessage`, … | customisation modifiers | none |
| Alert `TextField`s, `confirmationDialog(titleVisibility:)` | unmeasured / not needed | none |
| SDL native message box | blocking nested loop (`SV-J` item 2) | none |
| Closing an SDL file dialog from code | SDL3 has no call (`SV-G` item 5) | none |
| Type-select in the drawn menu; pop-up placement of a picker's menu over its button | looks; SwiftUI's placement unmeasured | none |
| `onContinuousHover(coordinateSpace:)` other spaces | MetalUI has local points only | none |
| SwiftUI hover semantics | unmeasurable headless (`H`); re-probe on an unlocked, active session | human check U8 |
| Main-actor tasks under an `async` main | the main queue is not drained inside its own job on either platform (`J1`, `J3`) — documented, not fixable in a loop | none |

## 12. Must not move — the checklist each lane re-measures

- `swift build --build-system native --build-tests` 0 `error:`, only the
  deprecation `warning:`; `swift build --build-tests` 0 warnings; the unfiltered
  `swift test --build-system native --no-parallel` summary line read (not the
  exit status) and the `FR-J` line present. `swift package clean` after the
  public enum cases and stored properties land (lanes 1 and 2).
- Identity and retention: `theSevenRetentionSlotsAreMutuallyDistinct`,
  `MC-A`/`MC-C`/`MC-P` numbering, `.id()` outermost — the scopes are
  transparent and the panels window-owned.
- Hit testing: `topmostHitbox`/`topmostOpaqueHitbox` unchanged; click
  dispatch, the arena and wheel routing unchanged; hover regions non-opaque.
- Accessibility, animation, focus, `List` windowing/`TB-AH`, `Deferred`, text
  input: no ruling moves them (the panels publish beside the tree, as the menu
  panel does).
- Pixels: 0 px in all fourteen offscreen images against `c2b8f48`;
  `Expected.swift` unedited.
- `MetalUILayout` imports only `MetalUICore`; `MetalUIScene` only
  `MetalUIShaderTypes`; `MetalUIPlatform` only `MetalUICore`/`MetalUIScene`.
- `Backends/SDL` builds and tests with `PKG_CONFIG_PATH=$PWD/.accesskit`;
  the `swift:6.4-noble` image (`Backends/SDL/linux/Dockerfile`) builds and runs
  the SDL tests (lane 1 and lane 3, who touch `Backends/SDL`).
- `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green;
  `everyProductionTreeBuildsOnAOneMegabyteThread` green.
- `zsh docs/probes/closeout-inventory-check.sh` and
  `zsh docs/probes/closeout-undocumented.sh` print nothing; the census
  re-recorded.
