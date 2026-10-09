# Key and focus scoping — design

Item C9 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**), requested by MetalCreator (gaps M4-a, M4-b, M5-b, M5-g, M5-h, and
M6's `Panel`/`!Panel` vetoes in `MetalCreator/docs/metalui-gaps.md`). Branch
`feat/key-focus` from `c62d6ba`. Rulings:
[`../2026-10-08-key-focus-decisions.md`](../2026-10-08-key-focus-decisions.md)
(`KF-A`…`KF-W`, next unused `KF-X`; the critic's amendments `KF-P`…`KF-W` of
2026-10-09 are folded in below and win over any earlier sentence). Record: `docs/record/88-key-focus.md`
(Record phase). Probes: `docs/probes/swiftui-key-focus.swift` (K, FC, RS, G, T
arms) and `docs/probes/swift-builder-for-opaque.sh` (A arms).

**Status: designed (2026-10-08); critic-revised (2026-10-09, `KF-P`).** Baseline at `c62d6ba`: 2873 tests in 3
suites, 0 goldens; the `FR-J no-argument frame: succeeded=true` line present.

## 1. Scope

| # | Ask | Answer | Rulings |
|---|---|---|---|
| 1 | `onKeyPress` on focusable elements and on a region; ↑/↓ reach a palette over a focused field; Keymap contexts for `Panel`/`!Panel` | SwiftUI's `onKeyPress` family (focus-scoped, outermost first, after the Keymap and before field editing keys) + MetalUI-only `.hoverKeyRegion()`; one key chain feeds the Keymap's contexts | `KF-B`…`KF-E`, `KF-H`, `KF-I` |
| 2 | Focus on click for a surface | `.focusable(interactions: .edit)`; divergence 94 narrowed to `.automatic` | `KF-F` |
| 3 | A press elsewhere resigns text focus | SwiftUI does **not** (RS1–RS5): no default change; remedies via 2 and a key-region press | `KF-G`, `KF-E` 5 |
| 4 | `onGeometryChange(for:of:action:)` | Built; actions in the lifecycle drain (first frame, same frame as a resize) | `KF-J` |
| 5 | `for` over an opaque helper in a builder | Swift 6.4 compiler defect, refuted as library-fixable (A4); pinned by a guard; remedies documented | `KF-M` |
| 6 | `TimelineView(.animation)` (+ periodic) | Built: `.animation`, `.animation(minimumInterval:paused:)`, `.periodic`, `.everyMinute`, `.explicit`, custom | `KF-K`, `KF-L` |

**Not touched** (MUST NOT MOVE): identity and state retention (the seven
slots, `MC-A`/`MC-C`/`MC-P`, `.id()` outermost), the hit-test ranking (one
`topmostHitbox`; new regions are non-opaque and inert to every existing stage),
accessibility, animation, focus itself (`focusedElement`, `isFocused`,
`@FocusState`, Tab order — the hover chain focuses nothing; only the two
opt-ins move focus on a press), `List` windowing and `TB-AH`, `Deferred`,
text input (the field's editing table is unchanged; it simply runs after
`onKeyPress`). No `PlatformWindow`/`Platform`/`WindowRenderer` requirement, no
shader, no renderer change. Pixels: 0 px in the fourteen offscreen images
(the demo section is opt-in, §6).

## 2. SwiftUI's answers (probed)

`docs/probes/swiftui-key-focus.swift`, macOS 27.0.1 (26A434), Swift 6.4,
screen unlocked, runs 10 and 11 byte-identical (69 lines). Summary — the
header has every line:

- **Keys need focus** (K1s, K1u, K1v, K2s); a window's first focusable view
  gets default focus (K1, K1t; MetalUI does not — divergence 186).
- **Outermost first** (K2t, K2v, K2w), a handled ancestor shadows the child
  (K2, K3), a handler inside `.focusable()` never hears (K12).
- **Before the field editor** (K4a–K4h), **before `keyboardShortcut`** (K10,
  K11). Phases default down + repeat (K5a, K9). Key filters ignore modifiers
  but compare the character (K8); `characters:` by `CharacterSet` (K7).
- **Click focus**: `.focusable()` (FC1), `.edit` (FC3), effect-disabled (FC4)
  yes; `.activate` (FC2, FC7), `false` (FC5) no; focus + tap together (FC6).
- **No resign** on a press elsewhere (RS1–RS3, RS5); a click-focusable press
  moves focus (RS4).
- **Geometry**: initial before `onAppear` (G1), per change (G5), not
  unchanged (G3), union over a group (G6), initial again on re-insertion (G7),
  offset included (G4a).
- **Timeline**: every frame (T1), paused once (T2), stepped (T3), schedule
  entries not the clock (T4), cadence `live` (T5).

`docs/probes/swift-builder-for-opaque.sh`: A1 fails, A2/A3 compile, A4/A5
fail, A6 compiles (erasure), A7 SwiftUI has no `for`, A8 `ForEach` compiles.
The critic (2026-10-09, `KF-P`) re-ran it byte-identical and added A9–A13 (all
fail as A1). The SwiftUI probe could **not** be re-run (screen locked); lane A
re-runs K2t, K2v, K4c, K4a first and runs the new gated KX arms (`KF-R`).
Spellings were checked against the MacOSX27.0 SDK's `SwiftUI.swiftinterface`.

## 3. Public API

Every new public declaration owes a doc comment and an inventory map row
(lane C records the census; lanes A and B write the doc comments).

### 3.1 Keys (lane A)

```swift
public struct KeyPress: Sendable {                      // A — SwiftUI's
    public struct Phases: OptionSet, Sendable { .down, .repeat, .up, .all }
    public enum Result: Sendable { case handled, ignored }
    public let phase: Phases
    public let key: KeyEquivalent
    public let characters: String
    public let modifiers: EventModifiers
}                                                       // init internal

extension StyledElement {                               // each returns Self
    func onKeyPress(_ key: KeyEquivalent, action: @escaping @MainActor () -> KeyPress.Result) -> Self
    func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases,
                    action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self
    func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                    action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self
    func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                    action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self
    func onKeyPress(phases: KeyPress.Phases = [.down, .repeat],
                    action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> Self
    func focusable(_ isFocusable: Bool = true) -> Self                     // replaces focusable()
    func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> Self
    func hoverKeyRegion(_ isEnabled: Bool = true) -> Self                 // M — MetalUI-only
}

public struct FocusInteractions: OptionSet, Sendable { .activate, .edit, .automatic }   // A (D: .automatic, 94)

extension ProposalElementGroup {                        // each returns KeyboardModifier<Self>
    // the five onKeyPress, focusable(_:), focusable(_:interactions:),
    // keyContext(_:_:), focused(_:), focused(_:equals:), hoverKeyRegion(_:)
}
public struct KeyboardModifier<Content: ProposalElementGroup>: Element   // M — the one layer (lane C, KF-W)
extension KeyboardModifier { /* the same names, returning Self (KF-H item 2) */ }

extension KeyEquivalent: Hashable {}
```

`CharacterSet` comes from Foundation (already imported by `MetalUI` on every
platform). The `@MainActor` on closures matches `onKey`'s `KeyHandler`; SwiftUI's
closures are main-actor by `View`'s isolation — the same effect.

### 3.2 Geometry (lane B)

Wider than SwiftUI's on purpose (`KF-S`): no `@Sendable` on `transform`, no
`Sendable` on `T`; every SwiftUI spelling compiles.

```swift
public struct GeometryProxy: Sendable {                 // A (MetalUI geometry types)
    public let size: Size<Pixels>
    public func frame(in space: CoordinateSpace) -> Bounds<Pixels>
}
extension ElementGroup {
    func onGeometryChange<T: Equatable>(for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (_ newValue: T) -> Void) -> GeometryChangeScope<Self>
    func onGeometryChange<T: Equatable>(for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> GeometryChangeScope<Self>
}
public struct GeometryChangeScope<Content: ElementGroup>: ElementGroup   // + ProposalElementGroup where Content is
```

### 3.3 Timeline (lane B)

```swift
public protocol TimelineSchedule {
    typealias Mode = TimelineScheduleMode                    // KF-T
    associatedtype Entries: Sequence where Entries.Element == Date
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries
}
public enum TimelineScheduleMode: Sendable { case normal, lowFrequency }
public struct AnimationTimelineSchedule: TimelineSchedule     // .animation, .animation(minimumInterval:paused:)
public struct PeriodicTimelineSchedule: TimelineSchedule      // .periodic(from:by:)
public struct EveryMinuteTimelineSchedule: TimelineSchedule   // .everyMinute
public struct ExplicitTimelineSchedule<Entries: Sequence>: TimelineSchedule where Entries.Element == Date  // .explicit(_:)
public struct TimelineViewDefaultContext {
    public enum Cadence: Comparable, Sendable { case live, seconds, minutes }
    public let date: Date
    public let cadence: Cadence
}
public struct TimelineView<Schedule: TimelineSchedule, Content: ProposalElementGroup>: ProposalElementGroup {
    public typealias Context = TimelineViewDefaultContext     // KF-T: SwiftUI's nested name
    public init(_ schedule: Schedule,
                @ProposalContentBuilder content: @escaping (TimelineViewDefaultContext) -> Content)
}
```

`TimelineView` is an `ElementGroup` (every `ProposalElementGroup` is) and so
sits in either vocabulary; `LegacyContent` makes any legacy content proposal.

### 3.4 Not added

`.focusEffectDisabled()`, `.focusSection()`, proposal `.onKey`/`.onAction`,
`GeometryReader`, `GeometryProxy.safeAreaInsets`/anchors/named spaces,
`onKeyPress` with a `KeyboardShortcut`. Each is an inventory **R** row only if
the census already lists the SwiftUI name; otherwise nothing.

## 4. Semantics and implementation

### 4.1 The pipeline (lane A, `Window.swift`)

At `c62d6ba` the key stages are `dispatchAction` → `dispatchTextKey` →
`dispatchKey` → `dispatchContextMenuKey` → `dispatchShortcut` →
`dispatchCommandShortcut` → `dispatchFocusTraversal` → `onInput`. Lane A
inserts **`dispatchKeyPress(event)`** between `dispatchAction` and
`dispatchTextKey`, with the existing comment block's form (why here, which
test pins it). It handles `.keyDown` (phase `.repeat` when `isRepeat`, else
`.down`) and `.keyUp` (phase `.up`); everything else returns `false`.

**Typed characters (`KF-Q`).** A focused field's printable keystrokes arrive
as `.textInput`, never `.keyDown` (AppKit's input context, SDL's dropped
text-producing keys), and `dispatchTextInput` runs long before the key stages.
So `dispatchKeyPress` also has a `.textInput` arm, called in its own line
**immediately before `dispatchTextInput`**: when a text field is focused, it
holds no marked text, and the text is one grapheme, the walk below runs with
`KeyPress(phase: .down, key: KeyEquivalent(text), characters: text,
modifiers: [])`; `.handled` drops the text, `.ignored` passes it on unchanged.
Compositions and multi-grapheme commits are never offered. Divergence 187.

**⌘/⌃-keys (`KF-R`).** Before placing the stage, lane A runs probe arms
KX1–KX3 (`KF_PROBE_KX=1`, lock probe first) and builds by `KF-R` item 3's
table: if SwiftUI runs a menu command or a ⌘-key `Button` shortcut first,
`dispatchKeyPress` declines a keystroke the command table (or a modified
shortcut) matches. **Measured (`KF-X`)**: KX2/KX3 read `menu` — the command
table is declined; KX1 reads `view:` — a `Button`'s ⌘-key shortcut is not.

`dispatchKeyPress` walks `keyChain.reversed()` (root → innermost); at each id
it asks `lastFocusRegistry.keyPresses(for:)` (registered in prepaint like
`keyHandlers`, `FocusRegistry.register`) and runs, last-written first, every
handler whose phases contain the event's phase and whose filter matches,
under `StateDispatch.dispatching(to: id)`; the first `.handled` claims the
event (`setNeedsRedraw`, return `true`).

### 4.2 The key chain (lane A, `Window.swift`, `Focus.swift`)

`var keyChain: [GlobalElementID]` (innermost first): `focusChain` when
`focusedElement != nil`, else `focusChain(from: hoveredKeyRegion())`, where
`hoveredKeyRegion()` is the `KF-E` item 3 lookup against `lastHitboxes` at
`lastMousePosition` (`nil` when the pointer left the window, when no key
region was registered — `lastKeyRegionCount == 0` costs no ranking — or while
`hoverIsSuppressed`). `dispatchAction` builds `contextsByLevel` from
`keyChain` (was `focusChain`) and dispatches the action along it;
`dispatchKeyPress` as §4.1. **`dispatchKey` (the `onKey` bubble, where every
control's `ControlKeys` live) keeps `focusChain`** (`KF-U`): with nothing
focused `onKey` and the controls' keys still see nothing. `matchKeymap`,
`contextDepth` and the predicate language are unchanged (a doc paragraph in
`Keymap.swift` says where the chain comes from).

Counter: `Window.keyRegionLookups` (internal, test observability) — one per
lookup, so a pointer move costs 0 and a key event at most 1.

### 4.3 Key regions and focus on press (lane A)

`Handlers.keyboard: KeyboardAttachment?` (`KF-I`) carries `keyPresses`,
`focusInteractions` and `isKeyRegion`. `Frame.registerHandlers` (the
5-argument implementation, the one gate) registers a **non-opaque** hitbox
when `keyboard?.isKeyRegion == true || keyboard?.focusesOnPress == true` (by
its own condition, as `hasDraggable`'s non-opaque box), inside the disabled,
hidden and `allowsHitTesting` gates; no other stage reads these fields, so
every existing ranking (`topmostOpaqueHitbox`, the arena, hover's
`opaque || hover`, wheel routing, drop destinations) is unchanged — pinned by
A32. `lastKeyRegionCount`/`lastFocusOnPressCount` are adopted with the frame
like `lastHoverRegionCount`.

`focusOnPress(_ event:)` — a non-claiming stage on primary `.mouseDown`
only, placed after the hover update and the modal/menu/popover stages and
**before `dispatchTextInput`**: with the cover `topmostHitbox(in:
lastHitboxes, at:, where: { $0.opaque || $0.handlers.keyboard?.isKeyRegion ==
true || $0.handlers.keyboard?.focusesOnPress == true || $0.handlers.hover !=
nil })`, it finds on the cover's layer the innermost click-focusable `F` and
the innermost key region `R` that contain the point and from which the cover
descends (`isOrDescends(from:)`), then:

1. the cover is a text field (`handlers.textInput != nil`) → nothing (the
   text stage focuses it);
2. `F` exists and (`R` is nil or `F` is or descends from `R`) → `focus(F)`;
3. else `R` exists → `focus(nil)` (no-op when nothing is focused);
4. else nothing (`KF-G`: no resign).

It returns `false` (the press continues to the text stage, the arena and
click dispatch: FC6). A selectable `List` inside a key region focuses itself at
the release (`DD-Z` item 9), so there the press clears and the release focuses
— two events, two changes (`KF-U` item 4).

### 4.4 Proposal `KeyboardModifier` (lane C, new `KeyboardModifier.swift`; `KF-W`)

`HoverModifier`'s recipe (`Hover.swift`): stores `content` and a `Handlers`
value holding only keyboard fields (`isFocusable`, `keyContext`,
`focusBinding`, `keyboard`); `requestProposalLayout` lays the content out
under its id from cursor 0 and requires one native child (precondition with
the hover modifier's message shape); `prepaint` registers through
`frame.sharingRegistrationsWithEffects` + `pass.registerHandlers(…,
synthesizesAccessibility: false)`; `paint` forwards. A `.focused` on it
records the focus binding at its id (`registerFocusBinding`). On
`KeyboardModifier` itself every keyboard modifier returns `Self` (§3.1). The
dual declaration — `StyledElement` returning `Self`, `ProposalElementGroup`
returning the wrapper — is the one `onHover`/`onContinuousHover` already use
(`Hover.swift`); G1 covers a type reachable through both.

### 4.5 Geometry (lane B, new `GeometryChange.swift`, `Lifecycle.swift`)

`GeometryChangeScope` copies `LifecycleScope`'s two entries (typed and
untyped — each pinned on its own, spec test B14, as `LC` test 1.10 does):
reserve nothing, forward `parent`/`cursor`, build content, and when it
registered nodes store in its layout the key (`.child(of:
.child(of: parent, at: start), at: 0, name: "$geometry<depth>")`, depth =
geometry scopes enclosing it, a store key, never `noteNamed`) and the nodes.
`prepaintGroup` computes the proxy (§`KF-J` item 3: union of
`pass.bounds(of:)`, `Frame.activeOffset`, `prepaintEffects.last?.composed`),
calls `transform`, and notes `(key, owner, value, isEqual, action)` into
`animationStore.lifecycle.noteGeometry(…)`. `LifecycleStore.endFrame`
compares each noted key with the previous build's value — new key: initial
event; changed: change event; untouched: entry dropped silently (no SwiftUI
callback) — and `takeEvents()` returns this build's geometry events **before**
its lifecycle events. `Window.drainLifecycle` is unchanged.

### 4.6 Timeline (lane B, new `TimelineView.swift`, `TimelineSchedule.swift`, `TimelineStore.swift`, `AnimationStore.swift`)

`AnimationStore` gains `let timeline = TimelineStore()` and its `endFrame`
calls `timeline.endFrame(stateTable:)`. `TimelineView.requestGroupLayout` (and
the typed entry, each pinned) computes its key (`$timeline<depth>` under its
position), asks `pass.frame.animationStore.timeline.context(for: key,
schedule:, timestamp: pass.frame.timestamp)` for the context (and whether it
is live), calls `pass.frame.noteActiveAnimation()` when it is, builds
`content(context)` with the caller's parent and cursor, and returns its nodes.
`TimelineStore`:

- `clock` (internal, injectable): timestamp → `Date`, default one offset taken
  at first use;
- per key: first appearance date, an iterator over `entries(from:)`, the
  current and next entries (a non-animation schedule), the stepped date
  (`minimumInterval`), touched-this-build;
- `endFrame(stateTable:)`: drops untouched keys, computes the earliest next
  entry, and (re)schedules the one wake through `scheduler` (internal,
  injectable; default a `@MainActor Task` that sleeps until the entry's
  timestamp and calls `stateTable.onWrite?()` once — the `@State` write path);
  no timeline → the wake is cancelled.
- `AnimationTimelineSchedule` is recognized by type (`as?`), never through its
  `entries` (which return a per-frame sequence for custom callers, SwiftUI's
  shape).

## 5. Tests

Each test is named with its **red-before** (what it reads on `c62d6ba`, or
"does not compile" for new API — then the red is taken against a stub that
compiles and does nothing, committed first, per
`docs/practices/verifying-tests-can-fail.md`) and **the mutation that must
redden it** (applied on the lane's branch, full unfiltered suite, the reddened
tests named in the lane's commit). Literals are derived before the run.
**No test sleeps** (`simulateTick(timestamp:)`, `simulateResize(to:)`,
`simulateInput(_:)`, injected scheduler and clock); performance tests count
work. Files: lane A `Tests/MetalUITests/KeyPressTests.swift`,
`FocusOnPressTests.swift`, `HoverKeyRegionTests.swift`,
`KeyFocusCompileGuards.swift`, `Tests/MetalUICrossPlatformTests/KeyPressPortableTests.swift`;
lane B `Tests/MetalUITests/GeometryChangeTests.swift`, `TimelineViewTests.swift`,
`Tests/MetalUICrossPlatformTests/GeometryTimelinePortableTests.swift`;
lane C `Tests/MetalUITests/BuilderForLoopCompileGuards.swift`, the demo's arm
in `DemoStackBudgetTests`.

### 5.1 Lane A — keys

| # | Test | Red before | Mutation that must redden it |
|---|---|---|---|
| A1 | `aFocusedElementsOnKeyPressHearsAKeyDown` | stub: never called | delete the `dispatchKeyPress` call in the pipeline |
| A2 | `anUnfocusedElementsOnKeyPressHearsNothing` (K1s) | — (green by construction against the stub; red against M) | walk every registered handler instead of the chain |
| A3 | `onKeyPressRunsOutermostFirstAlongTheFocusChain` (K2v: `root,mid,inner`) | stub: `""` | iterate `keyChain` innermost first |
| A4 | `aHandledKeyPressStopsTheWalk` (K2) | stub | ignore the result (continue after `.handled`) |
| A5 | `theLaterOnKeyPressOnOneElementRunsFirst` (K2w; `StyledElement` and `KeyboardModifier` arms) | stub | run one element's handlers in written order |
| A6 | `onKeyPressOnAFocusedTextFieldClaimsUpArrowAheadOfTheField` (K4c: selection unchanged, then `z` replaces all) | at `c62d6ba` ↑ moves the caret | move `dispatchKeyPress` after `dispatchTextKey` |
| A7 | `anIgnoredKeyPressLetsTheFieldEdit` (K4b, K4d: `zabc`) | stub | treat `.ignored` as claimed |
| A8 | `aHandledReturnDoesNotSubmitTheField` (K4g) | stub: submits | the A6 mutation |
| A9 | `aBoundKeymapActionRunsBeforeOnKeyPress` | stub | swap `dispatchAction` and `dispatchKeyPress` |
| A10 | `onKeyPressRunsBeforeAButtonShortcutAndAnIgnoredKeyReachesIt` (K10, K11) | stub | move `dispatchKeyPress` after `dispatchShortcut` |
| A11 | `defaultPhasesAreDownAndRepeat` (K5a), `phasesAllAddsTheRelease` (K5b), `aReleaseOnlyHandlerHearsOnlyTheRelease` (K5c) | stub | map every key event to `.down` (ignore `isRepeat`/`keyUp`) |
| A12 | `anUnclaimedKeyUpStillReachesOnInput` | — | claim every `keyUp` in the stage |
| A13 | `aKeyFilterIgnoresModifiersButComparesTheCharacter` (K8: `a`, cmd-a fire; shift-A not) | stub | compare `key` case-insensitively (shift-A fires) / compare modifiers (cmd-a silent) — two mutations |
| A14 | `aCharacterSetFilterTestsTheProducedCharacters` (K7) | stub | test `charactersIgnoringModifiers` with an option-modified fixture whose two spellings differ |
| A15 | `aKeysSetFilterHearsOnlyItsKeys` (K6) | stub | ignore the set |
| A16 | `onKeyPressWritesStateOnItsOwnElement` (ID-F: the same element placed twice, the pressed occurrence's `@State` changes) | stub | drop `StateDispatch.dispatching(to:)` |
| A17 | `aDisabledOrHiddenElementsOnKeyPressIsSilent` | stub | register `keyPresses` outside the gate |
| A18 | `withNothingFocusedTheHoveredKeyRegionReceivesKeys` | `c62d6ba`: chain empty | `keyChain` = `focusChain` always |
| A19 | `aFocusedElementOutsideTheRegionKeepsTheKeys` (`KF-D` 2) | — | prefer the hover chain when one exists |
| A20 | `theInnermostHoveredKeyRegionWins` | — | take the outermost member |
| A21 | `aKeyRegionUnderAnOpaqueSiblingOrAPresentationIsNotHovered` (opaque-sibling arm; presentation arm: a popover declared inside the region, added after the lane A review) | — | drop the cover/`isOrDescends` test (first arm); V1: drop `box.layer == cover.layer` in `hoveredKeyRegion` (second arm, `KF-X` item 10) |
| A22 | `keymapContextsReadTheHoveredRegionsChain` (`Graph` binding beats `!Panel` by depth; `!Panel` vetoed under a `Panel` region; a focused field inside `Panel` keeps the keys) | `c62d6ba`: contexts from the focus chain only | build `contextsByLevel` from `focusChain` |
| A23 | `aPressInAKeyRegionClearsFocus`, `aPressOnAFieldInsideAKeyRegionFocusesItWithOneFocusStateChange` | `c62d6ba`: focus kept | delete step 3 / delete step 1 of §4.3 (the second reads `false,true` on the `@FocusState`) |
| A24 | `aKeyRegionCostsNoLookupWhileThePointerMoves` (`keyRegionLookups` 0 over 50 moves, 1 per key; 0 with no region) | — | compute the hovered region in `updateHover` |
| A25 | `aPressFocusesAnEditInteractionFocusable` (FC3) | `c62d6ba`: does not compile → stub: not focused | delete the `focusOnPress` call |
| A26 | `aPressDoesNotFocusPlainOrActivateFocusables` (FC1 → divergence 94 pin, FC2) | — | treat `.automatic` as `.edit` |
| A27 | `aPressFocusesAndStillTaps` (FC6) | stub | make `focusOnPress` claim the event |
| A28 | `theInnermostClickFocusableWinsAndAFieldInsideTakesFocus` | — | outermost member / skip step 1 |
| A29 | `aSecondaryPressFocusesNothing` | — | run the stage on `.rightMouseDown` |
| A30 | `aPressElsewhereDoesNotResignAFocusedField` (RS1, RS2, RS3, RS5: plain, tap, `Button`, drag) | green at `c62d6ba` (SwiftUI-aligned pin) | `focus(nil)` on every press outside a field |
| A31 | `aClickFocusablePressMovesFocusFromAField` (RS4) | stub | delete step 2 |
| A31b | `aPressOnAnOpaqueSiblingAboveAKeyRegionChangesNoFocus` (`KF-G`, `KF-E` 5; review fix) | — (green against `4b80b9d`; red under V4) | V4: drop `cover.id.isOrDescends(from: box.id)` in `focusOnPress` |
| A31c | `aPressOnAKeyRegionsOwnPopoverChangesNoFocus` (`KF-E` 3, 5; review fix) | — (green against `4b80b9d`; red under V1′) | V1′: drop `box.layer == cover.layer` in `focusOnPress` |
| A26b | `focusableFalseRegistersNoFocusableAndALaterCallReplacesAnEarlierOne` (review fix) | — (green against `4b80b9d`; red under V9) | V9: `isFocusable = true` regardless of the argument, in `focusable(_:)` and separately in `focusable(_:interactions:)` |
| A32 | `pressAndKeyRegionsChangeNoOtherPointerOutcome` (the same tree with and without `.focusable(interactions: .edit).hoverKeyRegion()`: click, hover set, tap arena, wheel scroller, drop destination identical) | — | register the region hitbox `opaque: true` |
| A33 | `disabledHiddenAndAllowsHitTestingWithdrawThePressAndKeyRegions` | — | register outside the gates |
| A34–A35 | moved to lane C as C4, C5 (`KF-W`) | | |
| A36 | `HandlerShape`/`HandlerFingerprint` gain `keyboard` (the `KeyboardModifier` arms of the three `everyHandlerRegisteringSite…` guards move to lane C as C6) | — | drop the field from `Handlers`' equality the fingerprint reads |
| A37 | portable copies of A1, A3, A6, A18, A42 in `KeyPressPortableTests` (Linux/Windows CI) | as above | as above |
| A38 | `aHandledKeyPressSwallowsATypedCharacterInAFocusedField` (K4a, `KF-Q`) | stub: `z` typed | delete the `.textInput` arm |
| A39 | `anIgnoredKeyPressLetsATypedCharacterIn` (K4b) | stub | treat `.ignored` as claimed on that arm |
| A40 | `anAncestorsKeyPressHearsTypedCharactersBeforeTheFieldsOwn` (K2x) | stub | walk innermost first on that arm |
| A41 | `aCompositionAndAMultiGraphemeCommitAreNeverOffered` (+ divergence 187: repeats read `.down`, no `.up` when the platform drops it) | stub | offer every `.textInput` |
| A42 | `aDigitFilterOnAFieldKeepsOnlyDigits` (`a1b2` → `12`) | stub: `a1b2` | the A38 mutation |
| A43 | `aCommandsKeystrokeRunsTheCommandNotOnKeyPress` (KX2/KX3 read `menu`, `KF-X`: the handler never hears ⌘J; ⌘K, unbound, reaches a catch-all) | `7d00e5b`: `["all-j", "all-j"]` | drop the command-table decline |
| A44 | `aModifiedButtonShortcutReachesOnKeyPressBeforeTheButton` (KX1 reads `view:`, `KF-X`) | stub | decline a keystroke `dispatchShortcut`'s table matches |
| A45 | `aHoveredRegionDrivesNoControlKeysAndNoOnKey` (`KF-U`) | — (green against the stub; red against M) | `dispatchKey` walks `keyChain` |

Typecheck guards (`KeyFocusCompileGuards.swift`, `typecheckFile` with a plain
`import MetalUI`, `SA-P`); each mutated red once:

| # | Guard | Separating arm |
|---|---|---|
| G1 | `theOnKeyPressFamilyCompilesOnBothVocabularies` | an action returning `Bool` does not compile |
| G2 | `focusableWithNoArgumentsStillResolvesAndInteractionsCompile` | `.focusable(interactions: .bogus)` does not compile |
| G3 | moved to lane C as C8 (`KF-W`) | |
| G4 | `keyPressHasNoPublicInitializer` (`KeyPress(phase:…)` must not compile from outside; a `@testable` test cannot see it) | positive control (`KF-W` item 2): reading `press.key`, `.characters`, `.modifiers`, `.phase` inside an `onKeyPress` closure compiles |

### 5.2 Lane B — geometry and timeline

| # | Test | Red before | Mutation that must redden it |
|---|---|---|---|
| B1 | `theInitialValueIsReportedOnceBeforeOnAppear` (G1: `g,appear`) | stub: `appear` only | hand lifecycle events before geometry events in `takeEvents` |
| B2 | `theTwoArgumentFormPassesOldEqualNewInitially` | stub | pass a default `old` |
| B3 | `aResizeIsReportedInTheFramePresentingIt` (the action writes `@State`; the presented scene carries the written label after one `simulateResize` + one `drawFrameIfNeeded`) | stub | run geometry events after `finishFrame` (next frame) |
| B4 | `eachResizeStepIsReportedOnce` (G5: five steps, five calls) | stub | report only the last |
| B5 | `anUnchangedValueIsNotReported` (G3) | stub | compare nothing (report every build) |
| B6 | `aGroupReportsTheUnionOnce` (G6) | stub | report the first node |
| B7 | `reinsertionReportsTheInitialValueAgain` (G7) | stub | keep a dropped key's last value |
| B8 | `frameInGlobalIncludesAnEnclosingOffsetAndScroll` (G4a) | stub | drop the composed affine / drop `activeOffset` (two mutations) |
| B9 | `sizeIgnoresAScaleEffect` | — | take `size` from the transformed box |
| B10 | `aGeometryWriteLetsTheDisplayLinkPause` (two frames after the settle, `pausesEntered` advances: no phase write) | — | run the action inside `prepaintGroup` |
| B11 | `aSteadyFrameRunsKTransformsAndNoAction` (K = 3 scopes: 3 transform calls, 0 actions) | — | call the action on every build |
| B12 | `geometryActionsRunUnderStateDispatch` | stub | drop `StateDispatch` in the drain path |
| B13 | `aViewportKnowsItsSizeInTheFirstPresentedFrame` (M4-a end to end: a `MetalView` whose overlay label reads the size the action stored) | `c62d6ba`: does not compile → stub: label missing | B3's mutation |
| B14 | `theTypedAndUntypedEntriesAreEachPinned` (the scope in a legacy `Column` and in an `HStack`) | stub | break one entry's key computation |
| T1 | `anAnimationTimelineRebuildsEveryTickWithTheFrameDate` (ticks 0, 1/60, 2/60: dates equal under the zero-offset clock) | stub: one evaluation | drop `noteActiveAnimation()` (the link pauses: `pausesEntered`) |
| T2 | `aPausedAnimationTimelineEvaluatesOnceAndAsksNoFrame` (T2) | — | ignore `paused` |
| T3 | `minimumIntervalStepsTheDateInWholeIntervals` (T3) | stub | pass the frame date unstepped |
| T4 | `aPeriodicTimelineReportsTheEntryNotTheClock` (T4: tick 0.37 → date 0.30) | stub | report the clock |
| T5 | `aPeriodicTimelineSchedulesOneWakeAtTheNextEntry` (recording scheduler: one wake at 0.4) | stub | schedule no wake |
| T6 | `theWakeDirtiesTheWindowThroughTheStateWritePath` (fire the recorded wake: `needsRedraw`, not during a phase) | — | have the wake call nothing |
| T7 | `aTimelineLeavingTheTreeCancelsItsWakeAndStopsTheLink` | — | keep untouched keys |
| T8 | `aTimelineIsIdentityTransparent` (`@State` inside keeps its value when the `TimelineView` is added around it; ids equal with and without) | — | give it a cursor index |
| T9 | `cadenceIsLiveAndModeIsNormal` | — | report `.seconds` (`KF-V` item 4) |
| T10 | `aCustomAndAnExplicitScheduleAreEvaluatedThroughTheirEntries` | stub | special-case only periodic |
| T11 | `anOverlayFollowsAContinuousSurfaceThroughATimeline` (M4-b (2): the label's position moves each tick with a time-driven camera) | `c62d6ba`: does not compile | T1's mutation |
| T12 | `aTimelineNeverRequestsAnotherFrame` (`wantsAnotherFrame` false across ticks) | — | call `requestAnotherFrame()` instead |
| T13 | portable copies of B1, B3, T1, T4 in `GeometryTimelinePortableTests` | as above | as above |
| T14 | `theTimelinesTypedAndUntypedEntriesAreEachPinned` (a legacy `Column` consumes a `.flexGrow(1)` item inside it; an `HStack` keeps proposal nodes; `KF-V` item 2) | stub | route the untyped entry through the typed one |
| T15 | `anEmptyTimelineDoesNotShareItsScheduleWithTheNext` (`KF-V` item 3) | — | drop the occurrence ordinal |

Guards (lane B): `onGeometryChangeAndTimelineViewCompileOnBothVocabularies`
(separating: a non-`Equatable` `T` does not compile; further must-compile arms:
an explicit `@Sendable` transform over a `Sendable` `T` (`KF-S`),
`TimelineView<PeriodicTimelineSchedule, ProposalText>.Context` and a custom
schedule's `mode: Mode` (`KF-T`); a must-not-compile arm:
`Box{}.onGeometryChange(…).padding(4)` against the must-compile
`.padding(4).onGeometryChange(…)` (divergence 120, `KF-V` item 1)), and
`aTimelineViewInsideAnHStackKeepsItsProposalType` (separating: the same
content typed as `LegacyContent<…>` does not compile). Each mutated red once.

### 5.3 Lane C — builder, demo

| # | Test | Red before | Mutation that must redden it |
|---|---|---|---|
| C1 | `aForLoopOverAnOpaqueHelperIsAToolchainLimitation` (`typecheckFile`: the failing arm **must fail** with `underlying type for opaque result type`; arms `ForEach(texts, id: \.self) { label($0) }`, a `-> ProposalText` helper, a `struct Label: Element` helper and the inline chain **must compile**) | green at `c62d6ba` (it pins today's toolchain) | change the failing fixture's helper to `-> ProposalText` (the "must fail" arm reddens); delete `ForEach` from a separating arm's import path (a "must compile" arm reddens) |
| C2 | `everyProductionTreeBuildsOnAOneMegabyteThread` gains the key-focus demo tree | new tree unbuilt | build the section inline in the composer (the tree overflows or the arm is absent) |
| C4 | `aMetalViewTakesFocusOnPressAndHearsKeysThroughOneLayer` (was A34; proposal, end to end) | does not compile | make `KeyboardModifier`'s own methods return a nested wrapper |
| C5 | `aProposalFocusedBindingAndKeyContextSitOnTheFocusTarget` (was A35) | does not compile | register the binding on the content's id |
| C6 | the three `everyHandlerRegisteringSite…` guards gain the `KeyboardModifier` arm (was part of A36) | — | skip the gate in `KeyboardModifier` |
| C7 | A5's `KeyboardModifier` arm (`theLaterOnKeyPressOnOneElementRunsFirst` gains it) | — | run the layer's handlers in written order |
| C8 | guard `keyboardModifiersMergeIntoOneLayer` (was G3: `let x: KeyboardModifier<MetalView> = MetalView…focusable(interactions: .edit).keyContext("V").onKeyPress("f") { .handled }`; separating: the chain typed `KeyboardModifier<KeyboardModifier<MetalView>>` does not compile) | — | mutated red once |
| C3 | the fourteen offscreen images, `docs/probes/demo-pixels/compare.sh <scratch> c62d6ba HEAD`: 0 px each; `DemoFrameDeterminismTests`' `Expected.swift` unedited | — | — (acceptance) |

**Expected count**: 2873 + lane A (≈ 50 incl. 3 guards and 5 portable) + lane
B (≈ 35 incl. 2 guards and 4 portable) + lane C (≈ 5 incl. 2 guards) —
re-measured, never quoted from here. Typecheck guards: 185 at `c62d6ba` + 7.

## 6. Demo

`Sources/MetalUIDemoContent/KeyFocusDemo.swift`, reached with
`METALUI_KEY_FOCUS_DEMO=1 swift run MetalUIDemo` and in `MetalUISDLDemo`
(lane C wires both; the SDL wiring is built and run in the Linux image). Not
in the default tree, so **0 px** in all fourteen images. One section per
function passed to the generic composer (1 MB Windows stack):

1. **Canvas and inspector** — a canvas (`.hoverKeyRegion()`,
   `.keyContext("Canvas")`, `.onKeyPress(.tab)` opens a palette) beside an
   inspector of `TextField`s inside `.keyContext("Panel")`; a status line
   shows who took the last key. A press on the canvas clears the field's
   focus; Tab over the canvas with nothing focused opens the palette; Tab
   from a focused field moves focus.
2. **Palette** — a search field with `.onKeyPress(keys: [.upArrow,
   .downArrow])` moving a highlight; Return picks.
3. **Viewport** — a `GPUSurface(redraw: .continuous)` with
   `.focusable(interactions: .edit)`, `.onGeometryChange` feeding its size
   label, and a `TimelineView(.animation)` overlay whose label orbits with a
   time-driven camera.

Real-window capture only when the lock probe allows; the demo is launched only
then and killed after a few seconds.

## 7. Lanes

Three lanes, disjoint files, run **one at a time** in this worktree in order
A → B → C. Each commits its own tests red-first (stub commit, then the
implementation), runs the full native suite unfiltered, reads the one summary
line and the `FR-J` line, and names every mutation's reddened tests.

| Lane | Owns (edits) | New files |
|---|---|---|
| **A** keys and focus | `Window.swift`, `Focus.swift`, `Handlers.swift`, `Box.swift` (`StyledElement` keyboard modifiers), `FocusState.swift`, `KeyboardShortcut.swift` (`Hashable`), `Keymap.swift` (doc), `Frame.swift` (`registerHandlers`' non-opaque region condition and the counts), `Tests/MetalUITests/ModifierTests.swift`, `OuterModifierMatrixTests.swift`; `docs/probes/swiftui-key-focus.swift` (records K2t/K2v/K4c/K4a re-runs and KX1–KX3, `KF-P`, `KF-R`) | `KeyPress.swift`, `HoverKeyRegion.swift`; tests §5.1 |
| **B** geometry and timeline | `Lifecycle.swift`, `AnimationStore.swift` | `GeometryChange.swift`, `TimelineView.swift`, `TimelineSchedule.swift`, `TimelineStore.swift`; tests §5.2 |
| **C** proposal layer, builder, demo, docs | `DisabledTests.swift`, `HitRegionTests.swift` (the `KeyboardModifier` arms), `ElementBuilder.swift`, `ProposalContentBuilder.swift` (doc comments), `Sources/MetalUIDemo/main.swift`, `Backends/SDL` demo entry, `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift`, `docs/divergences.md`, `docs/api-overview.md`, `docs/migration.md`, `docs/verification/human-checks.md`, `docs/probes/closeout-*` | `KeyboardModifier.swift`, `KeyFocusDemo.swift`, `BuilderForLoopCompileGuards.swift`; tests C4–C8 |

Lane B reads lane A's nothing; lane C's demo uses both. `Frame.swift` is lane
A's (one condition in `registerHandlers`); lane B reads `Frame` internals
(`activeOffset`, `prepaintEffects`, `timestamp`, `noteActiveAnimation`,
`animationStore`) without editing it. If lane B finds it must edit
`Frame.swift` or `Window.swift`, it records a `KF-` amendment first.

## 8. MetalCreator, mapped

| Gap | Stopgap today | With this item |
|---|---|---|
| M4-a size | `MetalDrawContext.pixelSize` in the draw | `.onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { viewport.size = $0 }` — in the first presented frame and during a live resize |
| M4-a focus | window-wide F/+/− (`ViewportKeyBindings`) | `.hoverKeyRegion().keyContext("Viewport")` with bindings on `"Viewport"`, or `.focusable(interactions: .edit)` + `.onKeyPress` |
| M4-b (1) | inline label loops | still the toolchain's limit (`KF-M`): `ForEach(texts, id: \.self) { label($0) }` or a concrete helper type |
| M4-b (2) | labels hidden during an animation | `TimelineView(.animation) { ctx in labels(camera: model.camera(at: ctx.date)) }`, the same camera passed to the `MetalView`'s `value:` |
| M5-b | keymap `GraphTab` reading hover state | the canvas `.hoverKeyRegion().onKeyPress(.tab) { … }`; a focused inspector field keeps Tab (traversal) by `KF-D` 2 |
| M5-g | `releaseTextFocus` at each press | a press in the canvas's key region clears focus (`KF-E` 5), or a click-focusable canvas (RS4) |
| M5-h | keymap `PaletteMove` | `.onKeyPress(keys: [.upArrow, .downArrow])` on the palette's field |
| M6 `Panel`/`!Panel` | `handleAction` vetoes by hover state | region contexts: `"Graph"` bindings beat `!Panel` by depth over the canvas. **Migration**: a `!Panel` binding is vetoed while hovering a region inside a `Panel` contributor (the viewport's `F` over the graph) — bind `F` to `"Viewport"`, or contribute `Panel` on the fields' container |

## 9. Deferred, with reasons and owners

| Item | Reason | Owner |
|---|---|---|
| `.focusEffectDisabled()` | MetalUI draws no generic focus effect; only controls' rings would read it | a controls-looks follow-up |
| `.focusSection()`, default focus on show (divergence 186) | not asked; moving default focus is a focus change | a focus item when requested |
| proposal `.onKey`/`.onAction` | not asked; `KeyboardModifier` takes them additively | the next request |
| `GeometryReader`, named coordinate spaces, `safeAreaInsets` | `onGeometryChange` answers M4-a; `.named` adds an enum case (`CI-AC` migration) | a geometry item |
| `TimelineScheduleMode.lowFrequency` | MetalUI windows never enter it; `mode` is always `.normal` | — |
| `onKeyPress` for an option-modified key | unmeasured (the probe's two spellings were equal) | a probe arm when a request needs it |
| SwiftUI `.automatic` click focus (retiring divergence 94) | would move every `.focusable()` box's click behaviour | a ruling that names it, with a migration note |

## 10. Human checks (group KF, `docs/verification/human-checks.md`, lane C)

- **KF-1** With a real keyboard on AppKit (and SDL on Linux/Windows), in the
  demo's canvas section: an ancestor's `onKeyPress` runs before the focused
  child's (the status line's order), ↑/↓ move the palette's highlight with
  its field focused, Return picks without submitting the field.
- **KF-2** Hover routing: with nothing focused, keys go to the region under the
  pointer; with a field focused, the field keeps them wherever the pointer is.
- **KF-3** A real click on plain content leaves a focused field focused (RS1);
  a click on the canvas region clears it; a click on the viewport focuses it.
- **KF-4** Live-resizing the window: the viewport's size label follows every
  frame with no lag; on launch it is right in the first frame.
- **KF-6** (`KF-X`: the KX arms ran in lane A, so only the look remains) a
  native-only menu item's ⌘-key (⌘Q, ⌘H) under a focused catch-all
  `onKeyPress { .handled }` is swallowed (divergence 188); an app command's
  ⌘-key runs the command.
- **KF-7** Typing into a focused field with a digit filter (`KF-Q`): letters
  never appear, digits do, an input method's composition is unaffected (AppKit
  Japanese IME; SDL on Linux with IBus).
- **KF-5** The timeline overlay moves smoothly with the orbiting camera; with
  the demo idle otherwise, the display link pauses once the timeline leaves.

## 11. Divergences (this branch's range 185–194)

- **185** — `onKeyPress` and `.focusable()` on one keyboard layer (or one
  `StyledElement`) are order-free; SwiftUI's handler inside `.focusable()`
  never hears (K12). Pin: A5's `KeyboardModifier` arm and G3.
- **186** — MetalUI focuses nothing when a window shows; SwiftUI focuses the
  first focusable view (K1, K1t). Pin: an existing-behaviour test in A2's file
  (`noElementHoldsFocusWhenTheWindowFirstDraws`).
- **94 amended** — narrowed to `.focusable()`/`.focusable(interactions:
  .automatic)`; `.edit` now focuses on click as SwiftUI does (FC3). Pin: A26.

- **187** — a typed character reaches `onKeyPress` on a focused field as
  `.down` only (repeats too, modifiers empty); on SDL its release is not
  delivered (`KF-Q` item 4). Pin: A41.
- **188** — used (`KF-X`: KX2 reads menu-first): native-only menu items
  (Quit, Hide, Minimize…) are still offered to `onKeyPress` first. Pin: A43's
  separating arm.
- **120 amended** — `GeometryChangeScope` joins the transparent groups a legacy
  decoration cannot follow (`KF-V` item 1). Pin: lane B's guard arm.

Labels 189–194 stay unused (188 is used, `KF-X`). The header's next-label line is left for the
merge (`docs/divergences.md`, lane C).
