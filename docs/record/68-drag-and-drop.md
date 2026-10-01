# 68 — Drag and drop

Branch `feat/drag-and-drop` from `053a3b3` (master: plan task 15 merged, PR
#35). **Not a plan task**: the SwiftUI-alignment plan is agent-complete and
tasks 12 and 15 wait on human checks; this is new feature work, requested by
the user on 2026-10-01. Spec
`docs/superpowers/specs/2026-10-01-drag-and-drop-design.md`; rulings
`DN-A`…`DN-Z` in the new decisions doc
`docs/superpowers/2026-10-01-drag-and-drop-decisions.md` (next unused
`DN-AA`); probe `docs/probes/swiftui-drag-and-drop.swift` (groups `T`, `R`,
`A`, `P`).

**Status: LANDED — every agent-doable clause is built; the looks are owed to a
human** (`docs/verification/human-checks.md` group N, §7). Three lanes, each
red first, all verified `ok: true`; the Record phase's close (§9) re-took the
suite, the counts, the guard and golden counts, the inventory check and the
lock probe.

## §0 Baseline, design session and critic round (2026-10-01)

- **Baseline** at `053a3b3`, re-taken by the design session after a clean
  build: **1976 tests in 3 suites**, 0 `error:`, the one native deprecation
  `warning:`; 121 typecheck guards, 0 goldens, 66 live divergences (next
  label 100). No decisions doc's "Carried…" section addresses drag and drop;
  `specs/2026-09-23-text-input-design.md:262` lists "drag and drop of text"
  among `TextField`'s non-goals, unchanged (`DN-D` item 6).
- **Probe** `swiftui-drag-and-drop.swift`: `T` (Transferable encoding), `R`
  (callback sequencing through a fake `NSDraggingInfo`), `A` (accessibility),
  `P` (real pointer drags posted at the HID tap, a human's session). Groups
  `T`, `R`, `A` re-run from a fresh compile at the critic round, 72 lines
  byte-identical to the header; group `P` stands on the design session's two
  byte-identical runs (it moves the real pointer for minutes).
- **Critic round** (`DN-S`, `DN-T`, `DN-U`): `T7e` contradicted the spec's
  `Data` import (`DN-S`); the `Transferable` members were properties where
  CoreTransferable's call sites are functions, and SwiftUI's conformer
  spelling needed a ruling (`DN-S`); lane 1 carried 31 of 42 additions, so
  the preview moved to lane 2 (`DN-T`); a held long press, `P13c`'s timing,
  the custom preview's state on session end, SDL's C-enum spelling in tests,
  the no-target arena's multi-click path and the per-site capture hazard
  were pinned or ruled (`DN-U`).

## §1 What landed

- **`Transferable`/`ContentType`** (`Sources/MetalUI/Transferable.swift`,
  `DN-B`, `DN-S`): MetalUI's own synchronous, `Data`-based protocol with
  CoreTransferable's call-site spellings; `String`, `URL` and `Data` conform;
  conformance-carrying content types; `transferRepresentation` and
  `visibility:` are not offered. Portable (runs in Linux/Windows CI).
- **`.draggable(_:)`, `.draggable(_:preview:)`,
  `.dropDestination(for:action:isTargeted:)`**
  (`Sources/MetalUI/DragAndDrop.swift`, `DN-A`, `DN-P`) on every
  `StyledElement` (returning `Self`, no id moves) and every
  `ProposalElementGroup` (`DraggableModifier`, `DropDestinationModifier`,
  `DraggablePreviewModifier`, each one identity level). `.onDrag`/`.onDrop`,
  `DropDelegate` and the `DropSession` family are ruled out (`DN-A` item 2).
- **The arena member and the session** (`Gesture.swift`, `DragSession.swift`,
  `Window.swift`, `DN-D`…`DN-I`): a drag begins on the first pointer move
  from a draggable, outranks taps, long presses and clicks, yields to a
  `DragGesture` that outranks it; a draggable adds no opaque hit target (a
  non-opaque region joining the arena by identity, `DN-E`); the destination
  is the topmost one by the one `(layer, index)` ranking, generalized to
  `topmostHitbox(in:at:where:)` — `topmostOpaqueHitbox` is a specialization,
  never a second ranking (`DN-F`); a covering view does not block a drop, a
  presentation on a higher layer does; a disabled source does not drag and a
  disabled destination refuses (divergence 100, `DN-G`); `isTargeted` turns
  `false` before the next `true` and before the action; Escape cancels
  (`DN-I`).
- **The preview** (`Frame.swift`, `AnimatedColor.swift`, `DragSession.swift`,
  `DN-J`, `DN-X`, `DN-Y`): the source's own primitives captured once inside
  `paintDecoration` (and in `DraggableModifier.paint` on the proposal side),
  replayed above everything at 70% opacity, translated by the pointer; a
  `preview:` closure is a presentation root laid out against the window, with
  no hitbox and nothing published to accessibility; a clip pushed inside the
  source is kept in the replay.
- **The seam** (`MetalUIPlatform`, `DN-C`): `InputEvent.drop(DropEvent)`
  (`DropItem`, `PasteboardType`) and a defaultless
  `PlatformWindow.beginExternalDrag(_:at:)` (`DragRepresentation`) with honest
  implementations on `AppKitWindow`, `SDLWindow` and the test fakes.
- **AppKit** (`Sources/MetalUIAppKit/AppKitDragAndDrop.swift`, `DN-K`,
  `DN-L`): the host view registers for dragged types once and maps
  `NSDraggingDestination` onto `InputEvent.drop` (files, text, URLs; only the
  imported type is read from the pasteboard); a MetalUI drag that leaves the
  window becomes an `NSDraggingSession` (`NSDraggingSource`, copy in both
  contexts) when the platform answers (divergence 101).
- **SDL** (`SDLBridge.c`, `SDLPlatform.swift`, `DN-M`, `DN-Z`): the five
  `SDL_EVENT_DROP_*` events become one drop session; types are unknown until
  the drop (divergence 102); outgoing drags ruled unsupported (SDL3 has no
  outgoing-drag API, `SDLWindow.beginExternalDrag` answers `false`).
- **Accessibility** (`DN-N`): SwiftUI publishes nothing for a draggable or a
  drop destination (probe `A0`–`A4`), so neither does MetalUI; parity pinned
  on the neutral tree, the AppKit bridge and AccessKit.
- **Demo** (`Sources/MetalUIDemoContent/DragAndDropDemo.swift`,
  `METALUI_DND_DEMO=1`, both `MetalUIDemo` and `MetalUISDLDemo`, `DN-Q`,
  `DN-Z` item 2): four chips (Apple, example.com, Custom preview, Hold-then-
  drag), a `List` of draggable rows, four wells (Text, Links and files,
  Anything, Disabled). Human checks N1–N8.
- **Docs**: divergences 100–102 and three "Not offered" rows
  (`docs/divergences.md`), the API overview's drag-and-drop section,
  human checks N1–N8, two inventory families (`transferable`,
  `drag-and-drop`).

## §2 Tests and guards, per file

Root suite **1976 → 2028** (+52; 0 removed). `Backends/SDL`
`MetalUISDLTests` **33 → 41** (+8), `ReplayFixtureTests` 22. Guards **121 →
125**. Goldens 0. `@Test` counts by `grep -c '@Test'`:

| file | tests | note |
|---|---|---|
| `Tests/MetalUITests/DragAndDropTests.swift` | 24 | lane 1: 1.5–1.19, 1.22–1.29, plus its review round's 1.23b (`anExternalExitUnTargetsAndAnExternalDropDeliversItsLocalLocation`); 1.7 gained an eighth arm (the inner-draggable long press, `DN-W` item 2) |
| `Tests/MetalUITests/DragPreviewTests.swift` | 8 | lane 2: 2.10–2.14 plus its review round's 2.11b, 2.11c, 2.12b |
| `Tests/MetalUITests/AppKitDragAndDropTests.swift` | 9 | lane 2: 2.1–2.9, a real `AppKitWindow` driven by a fake `NSDraggingInfo` |
| `Tests/MetalUITests/DragAndDropAccessibilityTests.swift` | 2 | lane 3: 3.8, 3.11 |
| `Tests/MetalUICrossPlatformTests/TransferableTests.swift` | 4 | lane 1: 1.1–1.4, portable (Linux/Windows CI) |
| `Tests/MetalUITests/DragAndDropCompileGuards.swift` | 3 | G1.1–G1.3, all whole-file `typecheckFile` |
| `Tests/MetalUITests/DragPreviewCompileGuards.swift` | 1 | G2.1, whole-file |
| `Tests/MetalUITests/ModifierTests.swift` | 1 | `aDropDestinationAndADraggableSurviveEveryLaterHandlerModifierAndAWrapper` (`DN-W` item 3); the file's modifier table gained two rows (52 → 54) |
| `Backends/SDL/Tests/MetalUISDLTests/SDLDropTests.swift` | 7 | lane 3: 3.1–3.7 |
| `Backends/SDL/Tests/MetalUISDLTests/AccessKitDragAndDropTests.swift` | 1 | lane 3: 3.9 |

**52 = 24 + 8 + 9 + 2 + 4 + 3 + 1 + 1** in the root package (lane 1 +30 and
its review round +2, lane 2 +15 and its review round +3, lane 3 +2), the
SDL tests (+8) outside it. **T rows** (retained tests whose fixture or
literal changes, answers unchanged): `theNewDeclarationsCostHandlersAtMostOnePointer`'s
bound 440 + 8 → 440 + 8 + 8; `HandlerShape` (`ModifierTests`) and
`HandlerFingerprint` (`OuterModifierMatrixTests`) each gain
`dropDestination` and `draggableCount`, the matrix two rows;
`ControlStateCompileGuards`' and `TransactionCompileGuards`' `Conformer`
fixtures and `Fakes.swift`'s `FakePlatformWindow` gain `beginExternalDrag`;
`AccessibilityModifierTests` (one literal); `DemoStackBudgetTests`'s builder
list gains `dragAndDropDemoContent()` (3.10). Guard count by the file's own
method: raw `grep -c canTypecheck` over the four root test targets reads 127,
two of them comments (`UnitSafetyTests`, `CloseoutCompileGuards`), as at
`053a3b3` (123 raw, 121). Helpers: 40 `typecheck` and **84** `typecheckFile`
guards (80 before; all four new ones are whole-file).

## §3 Probes

`docs/probes/swiftui-drag-and-drop.swift`, header carrying the recorded
output. Groups `T`, `R`, `A` re-run by the critic round, lane 1's reviewer
and lane 3's verifier from fresh compiles: byte-identical to the header
**except `R3f`'s order**, which is nondeterministic (the reviewer read
`["two", "one"]` in 2 of 6 runs and `["one", "two"]` in 4; the count is
stable). The probe's header carries the erratum and `DN-H` item 2 is amended:
offering several items in offered order is **MetalUI's own choice**, not a
SwiftUI fact (`DN-W` item 1). Group `P` (real pointer) was run by the design
session twice, byte-identical; no later lane re-ran it. **Unmeasured, ruled
as MetalUI's choice** (spec §1): the preview's exact opacity, shadow and
anchor; a presentation blocking a drop beneath it; a draggable that is not
itself hit-testable; the long press written after an inner draggable (SwiftUI
moves at once, `P2f`; MetalUI's arena rule holds the long press off until the
release, pinned, `DN-V` item 6, `DN-W` item 2); drops in a `.sheet`.

## §4 Red runs

Each lane committed its tests red first against a stub, then green.

- **Lane 1** (`a5a1e83`, `8866c94`): 1.1–1.19, 1.22–1.29 and G1.1–G1.3
  failed to compile or asserted against a stub that did nothing; the
  harness fix (`8866c94`) kept each test's `Window` alive for its scope — a
  `Window` is held weakly by its platform window, and thirteen arms read
  every event `false` on a deallocated one (`DN-V` item 4).
- **Lane 2** (`7a86c1b`): 2.1–2.14 and G2.1 against a stub surface; the
  review round's 2.11b, 2.11c and 2.12b were committed red first
  (`1268365`), 2.12b red before the fix (`9ae15d3`).
- **Lane 3** (`eab49a7`, re-checked by its verifier in a temporary worktree):
  3.1, 3.2, 3.3, 3.4, 3.6, 3.7 and 3.11 red; **3.5, 3.8, 3.9 and the 1 MB-
  thread arm green on arrival**, as designed (`DN-Z` item 3: lane 1 wrote
  `SDLWindow.beginExternalDrag`'s final `false`; lanes 1 and 2 added no
  accessibility path). Their mutations are the instrument.

## §5 Mutation tables

Each applied to the named spelling only on a committed tree, restored from a
copy, the full unfiltered suite of the package named, `git status --short`
clean after each.

**Lane 1** (spec §6.2's M1a–M1ae; spellings changed by `DN-V` item 2:
M1g′, M1i, M1ab, M1ae). The mutations the lane's verifier took after the
review round, tree `2321315`, **2008 tests each**:

| mutation | spelling | reddened |
|---|---|---|
| I | `Box.swift`'s `onKey` also sets `dropDestination = nil` | `aDropDestinationAndADraggableSurviveEveryLaterHandlerModifierAndAWrapper` (3 issues: the onKey loop arm, the layered arm, the rewrapped inner arm) |
| B2 | `dispatchExternalDrop` `.exited` sets `dropTarget = nil` in place of `untarget()` | `anExternalExitUnTargetsAndAnExternalDropDeliversItsLocalLocation` (2) |
| F2 | `.performed` retargets and delivers at a fixed `Point(201, 1)` | the same test (1) |
| LP | `isBlocked`'s non-draggable branch: an undecided member ahead whose possible leaves are all draggables no longer blocks | `aDraggableBeatsATapAClickAndALongPressOnItsElementAndItsChildren` (1, the eighth arm's "waits" expectation) |

The lane's own table of M1a–M1ae was run by the implementer; the decisions
doc records what differed from the spec's spellings (`DN-V`): **M1g′** is two
sites (the `ended` clause of `isBlocked`'s draggable branch and an exemption
in `cancelBehindEndedMembers` — the second alone enforces the rule), and its
first spelling (skipping them in the final `fail` loop) **hung the suite**
(killed after 66 minutes: `cancelled` non-empty, nothing failed, `resolve()`'s
`while changed` loop never settled) — detected, by a hang rather than a named
red test; **M1i** is spelled "an activated simultaneous `DragGesture` is
ended instead of failed" (the session claims every event after the begin, so
"keep receiving" is unreachable); **M1ab** is spelled "register the
destination region under a derived child id" (the spelling returns `Self`,
the spec's does not compile); **M1ae** is `ContentType(offered.identifier)`
and reddens 1.29 and thirteen other drop tests, not 1.29 alone. The full
M1a–M1ae result lines are not carried in any document the Record phase had;
the four above and `DN-V`'s are the figures it can state.

**Lane 2** (`DN-X`, tree `b216ac9`, 2023 tests each; `DN-Y`, tree `9ae15d3`,
2026 tests each). The verifier re-took V1, V2, V11 at `b86760d`, 2026 tests:

| mutation | spelling | reddened (issues) |
|---|---|---|
| M2a | `registeredTypes = []` | `theHostViewRegistersForDraggedTypes` (1) |
| M2b | `dropPosition` reads `draggingLocation` unconverted | `aFinderFileDropReachesAURLDestination` (1), `onlyTheImportedTypeIsReadFromThePasteboard` (1) |
| M2c | `operation(accepting:)` always `.copy` | `aStringDropOnAURLDestinationAnswersNoOperation` (2) |
| M2d | `draggingExited` does nothing | `draggingExitedUnTargets` (1) |
| M2e | `dropItems` reads every type eagerly | `onlyTheImportedTypeIsReadFromThePasteboard` (2) |
| M2f | `pasteboardType` with empty `conformsTo` | `pasteboardTypesCarryTheirUTTypeSupertypes` (3) |
| M2g | `draggingItem` writes `representations.prefix(1)` | `anExternalDragItemCarriesEveryRepresentationAndAnImage` (1) |
| M2h | no drag event → `true` | `beginExternalDragNeedsADragEvent` (1) |
| M2i | source mask `.move` | `theSourceOffersCopyInBothContexts` (2) |
| M2j | replay alpha 1 | `theDefaultPreviewReplaysTheSourceAboveEverythingAtSeventyPercent` (1), `everyDraggableStyledSiteCapturesItsPreview` (38), `aVanishedSourceKeepsItsLastSnapshot` (1) |
| M2k | replay untranslated | `theDefaultPreview…` (1), `everyDraggableStyledSiteCapturesItsPreview` (40) |
| M2l | custom preview's wrapper also captures its content | `aCustomPreviewReplacesTheSnapshot` (1) |
| M2m | preview slot skipped when not the source | `aCustomPreviewReplacesTheSnapshot` (1) |
| M2n | no push in `paintDecoration` | `theDefaultPreview…` (1), `everyDraggableStyledSiteCapturesItsPreview` (9, every styled arm), `aVanishedSourceKeepsItsLastSnapshot` (1) |
| M2o | no push in `DraggableModifier.paint` | `everyDraggableStyledSiteCapturesItsPreview` (1, the proposal arm) |
| M2p | replay `dragSnapshot ?? []` | `aVanishedSourceKeepsItsLastSnapshot` (2) |
| M2q | `capturingDragSnapshot` pushes for every id | `aFrameWithoutASessionCapturesNothing` (1), `aCustomPreviewReplacesTheSnapshot` (1), `aVanishedSourceKeepsItsLastSnapshot` (2) |
| MG2.1 | the `StyledElement` overload made `internal` | `theDraggablePreviewSpellingCompilesFromAPlainImport` (1) |
| V1 | `pass.allowsHitTesting(false) { … }` around the custom preview's prepaint → `do { … }` | `aClickableCustomPreviewNeverCoversTheDestination` (2) |
| V2 | the accessibility suppression around it → `do { … }` | `aCustomPreviewPublishesNothingToAccessibility` (3) |
| V11 | `paintDragPreview` back to `apply(to: primitive.withInnerMask(false))` | `aClipInsideTheSourceIsKeptInTheReplay` (2) |
| V11′ | the verifier's own spelling: all three `if !inner { ` in `CapturedPrimitive.replayed` → `if true { ` | `aClipInsideTheSourceIsKeptInTheReplay` (2) |

V10 (the placeholder-consume loop → `_ = nodes`) had no site left: the loop
was deleted (`DN-Y` item 2), it did nothing.

**Lane 3** (`DN-Z`, tree `982745f`, root **2028**, `Backends/SDL` **22 + 41**):

| mutation | spelling | package | reddened (issues) |
|---|---|---|---|
| M3a | `.performed(… items: [])` | SDL | `sdlDropEventsBecomeOneDropSession`, `droppedTextIsUTF8PlainText` (4) |
| M3b | an empty drop performed | SDL | `aCompleteWithNoItemsIsAnExit` (1) |
| M3c | the path encoder percent-encodes nothing | SDL | `aDroppedPathBecomesAFileURLString` (4) |
| M3d | text typed `public.text` | SDL | `droppedTextIsUTF8PlainText` (2) |
| M3e | `SDLWindow.beginExternalDrag` returns `true` | SDL | `anSDLWindowCannotBeginAnExternalDrag` (1) |
| M3f | `endDropSessionOnMotion()` returns at once | SDL | `ordinaryPointerMotionEndsAnOpenDropSession` (1) |
| M3g | `case SDL_EVENT_DROP_POSITION:` removed from `translate`'s label | SDL | `theBridgeTranslatesEverySDLDropEvent`, `sdlDropEventsBecomeOneDropSession`, `aCompleteWithNoItemsIsAnExit`, `ordinaryPointerMotionEndsAnOpenDropSession` (4) |
| M3h | `AccessibilityTreeBuilder` gains `["Drop"]` for a destination | root | `aDraggableAndADropDestinationPublishNothingNew` (3) |
| M3h′ | `AccessKitSnapshot.translate`'s `customActions + ["Drop"]` | SDL | `accessKitPublishesADraggableAndADropDestinationUnchanged`, `aMetalUITreeTranslatesToAccessKitsVocabulary`, `everyAccessibilityNodeFieldHasAnAccessKitArm`, `theAccessKitSnapshotCarriesHintIdentifierHeadingLinkAndCustomActions` (13) |
| M3i | `dragAndDropDemoContent()` inlined into one builder | root | **none — green** (§6) |
| M3j | `DropWell`'s `last = describe(items)` → `_ = describe(items)` | root | `theDragAndDropDemoDropsAChipOnTheTextWell` (2) |

M3h cannot reach 3.9 (it changes the root builder, which 3.9 never runs;
measured) — hence M3h′. The lane 3 verifier took a second set, each
restored and `git status --short` clean:

| mutation | spelling | reddened |
|---|---|---|
| R1 | the drop target found with a second lookup (`lastHitboxes.indices.first(where: contains && !opaque && dropDestination != nil)`) instead of `topmostHitbox(in:at:where:)` | `theDeepestDestinationTakesTheDropAndCoversDoNotBlockIt`, `aDestinationThatRefusesTheTypeTargetsNothing` |
| R2 | `untarget()` removed from an external `.exited` | `draggingExitedUnTargets`, `anExternalExitUnTargetsAndAnExternalDropDeliversItsLocalLocation` |
| R3 | `enabled,` removed from the destination region's registration | `aDisabledSourceDoesNotDragAndADisabledDestinationRefuses`, `theDragAndDropDemoDropsAChipOnTheTextWell` |
| R4 | `String.init?(importing:)` decodes `data.reversed()` | `aStringExportsAndImportsUTF8PlainTextOnly`, `aDraggableRowsClickStillSelectsAndItsDragDoesNot`, `theDragAndDropDemoDropsAChipOnTheTextWell` |
| R5 | the Escape case returns `false` without `endDragSession()` | `escapeCancelsADragWithNoDropAndNoClick` |
| S1 | `handleDrop`'s position always `(0, 0)` | `sdlDropEventsBecomeOneDropSession`, `aCompleteWithNoItemsIsAnExit`, `droppedTextIsUTF8PlainText`, `ordinaryPointerMotionEndsAnOpenDropSession` |
| S2 | every SDL drop item typed as a file | `droppedTextIsUTF8PlainText` |
| S3 | a later `DROP_POSITION`'s position not stored | `sdlDropEventsBecomeOneDropSession` |
| M3g (re-run) | as above | the same four |

**The guards**: each new guard (G1.1–G1.3, G2.1) was mutated red once by its
lane (`MG2.1` above is lane 2's; lane 1's guard mutations are not carried in any document the Record phase had, like the rest of its table). **The branch check re-ran lane 1's three, as each guard's own doc comment spells them** (§11): MG1.1, MG1.2 and MG1.3 each redden exactly their own guard.

## §6 Green mutations and pins that prove less than they look

- **M3i is green** and `3.10` (`everyProductionTreeBuildsOnAOneMegabyteThread`
  with `dragAndDropDemoContent()` added) **only proves the demo builds on a 1
  MB thread; nothing pins the per-section builder shape for this tree**
  (`DN-Z` item 6, the lane 3 verifier's minor finding): the smallest thread
  that builds the demo alone on macOS arm64 debug, bisected in 16 KB steps
  through an exit test, is **304 KB** as written and **432 KB** inlined, both
  under 1 MB. The per-section shape is kept for the rule ("a new demo section
  goes in its own function"), not because this tree needs it; the spec's 3.10
  row predicted M3i red and that prediction was wrong.
- **Unpinned by design**: `mui_platform_init`'s explicit
  `SDL_SetEventEnabled(SDL_EVENT_DROP_FILE/TEXT, true)` calls — SDL 3.4.16
  delivers both without them, so 3.7 passes either way, and no SDL build at
  hand disables either event (`DN-Z` item 1).
- **Not separately pinned**: a pointer move during a session calling
  `setNeedsRedraw()` (`DN-X` item 4) — 2.10's `needsRedraw` expectation
  passed against lane 2's red stub; the call stays as the session's own
  statement of need.
- **AppKit's real `NSDraggingSession` hand-off is not testable headless**:
  a session started in a test never returns (`DN-X` item 1, measured: a
  scratch program printed `session: <NSDraggingSession…>` and never reached
  the line after a 2-second run-loop loop; killed at 15 s). 2.8's `true` arm
  is pinned through the injected `AppKitWindow.startDraggingSession`; the
  real hand-off is human check N3. AppKit logs `error in CoreDragDispose:
  -1850` to stderr when 2.9's bare `NSDraggingSession()` is released — a
  system log line, not a diagnostic.

## §7 Demo comparison and looks

- **Offscreen**: `docs/probes/demo-pixels/compare.sh 053a3b3 HEAD` read **0
  differing pixels and identical scenes in all fourteen images, controls
  non-zero**, at lane 3's close (re-taken by its verifier) and at §9.
  `Expected.swift` is unedited; `DemoFrameDeterminismTests` green. The new
  demo (`METALUI_DND_DEMO=1`) renders in none of the fourteen — it is its own
  tree — and is checked by 3.11 and the 1 MB-thread arm.
- **Real-window capture NOT taken.** The lock probe (`xcrun swiftc -O
  docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
  /tmp/lockstate`) read `CGSSessionScreenIsLocked = 1` and `displayAsleep
  main: 1` at lane 3's close and at §9, so `capture.sh` was not run.
- **Owed to a human** (`docs/verification/human-checks.md`, new group **N**):
  N1 in-window drag (preview translucency, anchor, source unchanged), N2
  `isTargeted` highlight on enter/leave/re-enter and Escape, N3 a chip
  dragged out of the window to TextEdit and Finder (the AppKit hand-off and
  its drag image), N4 a file from Finder and text from TextEdit onto the
  wells, N5 the same two drops onto `MetalUISDLDemo` on macOS and, if
  available, Linux and Windows (SDL positions; divergence 102's optimistic
  highlight), N6 a `List` row clicks to select and drags without selecting,
  N7 (optional) VoiceOver reads chips and wells as without drag and drop,
  N8 (optional) a chip held past a long press before moving does not drag.
  An agent cannot perform any of them, and none was performed.

## §8 Hazards

- **A C enum's `rawValue` is `Int32` on Windows and `UInt32` on Apple**
  (CLAUDE.md's CI hazards): lane 3's SDL tests take each `SDL_DropEvent`
  type from C-exported `uint32_t` constants (`mui_sdl_event_window_*`'s
  pattern), never `SDL_EVENT_DROP_*.rawValue` in Swift (`DN-U` item 4, 3.7).
  Only Windows CI can see a miss; it re-confirms on push.
- **The SDL macOS run-loop hazard**: every new SDL test helper creating an
  `SDLPlatform` arms `armMainRunLoopExitCheck()` (3.7). A new SDL entry
  point that initialises video with windows owes the `NSApp.run()` call.
- **`Handlers`** gained its fifteenth member, `dropDestination` (one
  reference); `MemoryLayout<Handlers>.size` **448 → 456**, and the smallest
  thread building every production tree **640 KB → 656 KB** (arm64 debug,
  16 KB bisection, both re-taken by lane 1), inside the Windows 1 MB budget
  (`DN-V` item 5). `HandlerShape` and `HandlerFingerprint` each gain a
  field when `Handlers` does — both did (`DN-W` item 3).
- **A window kept in a global** reddens
  `aDisablingTransactionReachesExactlyOneBuildAndRollsBack` (`withAnimation`
  asks whether any live window is dirty); the test harness keeps each window
  alive for its own scope only (`DN-V` item 4, measured).
- **`swift package clean`** after lane 1: new stored properties on public
  `Handlers` and a new `InputEvent` case crossed module boundaries.
- **A phase-time `@Observable` write** and every drop callback: a drop's
  action and `isTargeted` run under `StateDispatch` from input, never from a
  phase (the existing rule; `DN-H`).
- **Hang risk in mutation work**: a gesture-arena mutation that leaves
  `cancelled` non-empty without failing a leaf hangs `resolve()`'s loop (M1g′'s
  first spelling, 66 minutes); run arena mutations with a timeout.

## §9 The Record phase's own close (2026-10-01)

- **Suite.** After `swift package clean`, `swift build --build-system native
  --build-tests` (0 `error:`, the one SwiftPM deprecation `warning:`) then
  unfiltered `swift test --build-system native --no-parallel`:
  **`Test run with 2028 tests in 3 suites passed after 107.389 seconds`**, the `FR-J no-argument frame: succeeded=true` line present, 0 `error:` in either log. Root counts **2028 tests, 0
  goldens, 125 typecheck guards** (`find Tests/MetalUILayoutTests -name
  "*.json" | wc -l` reads 0).
- **Inventory** (the lane 3 verifier's minor finding, closed here): the
  public-API census read 1872 declarations at `053a3b3` and reads **1940**
  now (+68: 51 in `MetalUI` — `Transferable.swift` 26, `DragAndDrop.swift`
  25 — plus 14 in `MetalUIPlatform`, 2 in `MetalUIScene` and 1 in
  `MetalUIDemoContent`, the last three already claimed by the `platform`,
  `scene` and `demo-content` catch-alls); `docs/probes/closeout-public-api.tsv` is
  re-recorded; `docs/probes/closeout-inventory-map.tsv` gains two class-A
  families, **`transferable`** (probe `swiftui-drag-and-drop.swift` arm `T5`,
  test `aStringExportsAndImportsUTF8PlainTextOnly`) and
  **`drag-and-drop`** (arm `P14`, test
  `isTargetedTurnsFalseBeforeTheNextTrueAndBeforeTheAction`, divergences
  100–102) and two `M` rows (97 → **99** families); `zsh
  docs/probes/closeout-inventory-check.sh` printed 51 `UNMAPPED` lines before
  and **prints nothing** now; `zsh docs/probes/closeout-undocumented.sh`
  prints nothing (every new public declaration carries a doc comment).
  `docs/api-overview.md`'s opening figures read 1940 and 99.
- **Other checks** (lanes' own readings, unmoved by docs): `Backends/SDL`
  (`PKG_CONFIG_PATH=.accesskit`) **22 + 41** on macOS; in the
  `metalui-portable-ax` `swift:6.4-noble` container **22 + 39**; the root
  package in a `swift:6.4-noble` container builds with 0 `error:`/`warning:`
  and runs `MetalUILayoutTests` **199**, `MetalUICoreTests` **22**,
  `MetalUICrossPlatformTests` **14** (10 + the four `TransferableTests`),
  `MetalUISystemFontsTests` 6. `Expected.swift` unedited;
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` green; `MetalUILayout` imports
  only `MetalUICore`, `MetalUIPlatform` only `MetalUICore` and `MetalUIScene`.
- **Divergences**: **100–102 added**, none retired — live **66 → 69**, next
  label **103** (record §04's 2026-10-01 drag-and-drop section). "Not
  offered" gains three rows in `docs/divergences.md`.
- **One migration row, no behaviour change**: `.draggable`/`.dropDestination`
  are new spellings and no id path, retention rule or existing hit test moved
  (1.26, 1.28 count it); the one source break is
  `PlatformWindow.beginExternalDrag`, a new defaultless requirement — an
  **outside** `PlatformWindow` conformer fails to compile until it adds the
  member (pinned by G1.3; both in-repo conformers and the fakes have it), and
  `docs/migration.md`'s `PlatformWindow`-conformer row names it. (This bullet
  read "No migration note: nothing broke" until the branch check, §11, which
  contradicted that migration row.)

## §10 Deferrals, with owners

| item | owner |
|---|---|
| the real-window capture of the demo-layout/preview states, and group N's eight looks (§7) | the user (human checks) |
| a drag leaving the window on SDL (SDL3 has no outgoing-drag API) | none — divergence 101, ruled unsupported |
| types of a hovering external drop on SDL (divergence 102) | none — SDL gives none until the drop |
| `.onDrag`/`.onDrop`, `DropDelegate`, the `DropSession` family, `transferRepresentation`, `visibility:`, async loading | none — documented absences (`DN-A`, `DN-B`) |
| a source half-hidden by a scroller with its own inner clip replays cut where the scroller cut (`DN-Y` item 3's remainder) | none — MetalUI's own choice, the human check's to see (N1) |
| the explicit `SDL_SetEventEnabled(DROP_*)` calls have no pin | none (`DN-Z` item 1) |
| lane 1's full M1a–M1ae result lines are not in any document | none — only the four verifier mutations and `DN-V`'s spelling changes are recorded (§5) |

## §11 The adversarial branch check (2026-10-01)

Re-taken independently on `feat/drag-and-drop` at `113e503`, worktree clean.

- **Suite**: after `swift package clean`, `swift build --build-system native
  --build-tests` (0 `error:`, the one native deprecation `warning:`) then
  unfiltered `swift test --build-system native --no-parallel`: `Test run with
  2028 tests in 3 suites passed after 107.245 seconds`; the `FR-J no-argument
  frame: succeeded=true` line present. `swift build --build-tests` under the
  default build system: 0 `error:`, 0 `warning:`. Named greens in that run:
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` (`Expected.swift` unedited
  against `053a3b3`), `theSevenRetentionSlotsAreMutuallyDistinct`,
  `noConformerEmitsAnAXNodeItDidNotDeclare`,
  `aDeferredPresentationsPressDoesNotJoinItsDeclarersArena`,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  `everyNamingSiteStartsAReturningNameFresh`.
- **Counts**: goldens 0; raw `grep -c canTypecheck` over `Tests` 128 here, 124
  at `053a3b3` (both counting `Typecheck.swift`'s declaration and the two
  comment hits), so guards 121 → **125**. `cmp CLAUDE.md AGENTS.md`
  identical. Every `DN-` id cited in a changed file resolves to a `## DN-`
  heading except `DN-3` (the typo rule) and `DN-AA` (the next-unused line);
  every backticked test-like identifier in the changed docs resolves in the
  sources, bar `accessibilityDragSourceDescriptors` (an AppKit API name, not
  a test).
- **`Backends/SDL`** (`PKG_CONFIG_PATH=.accesskit`), re-run on macOS:
  `ReplayFixtureTests` 22, `MetalUISDLTests` **41**, passed. **No Linux
  container was re-run**: Docker was not reachable from this session; the
  199 + 22 + 14 and 22 + 39 figures in §9 stay the lanes' readings.
- **Offscreen demo comparison** (`docs/probes/demo-pixels/compare.sh`,
  `053a3b3` → `113e503`): every control non-zero where it must be, **0
  differing in all fourteen images, scenes identical**. **Lock probe**:
  `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — the real-window
  capture was not run.
- **Two central mutations of the checker's own design**, each from a clean
  commit, restored from a copy, full unfiltered suite, `git status --short`
  empty after:

  | id | mutation | reddened |
  |---|---|---|
  | BC1 | `DragSession.swift` `dropTarget(at:items:)`: the presentation-cover clause disabled (`…layer > region.layer, false`) — `DN-F` item 4 | `aPresentationAboveADestinationBlocksADropBeneathIt` (1 issue) |
  | BC2 | `Gesture.swift` `yieldsToDraggable`: `.click` answers `false`, so an undecided click holds a draggable off — `DN-D` item 2 | `aDraggableBeatsATapAClickAndALongPressOnItsElementAndItsChildren`, `aDraggableRowsClickStillSelectsAndItsDragDoesNot`, `escapeCancelsADragWithNoDropAndNoClick`, `everyDraggableStyledSiteCapturesItsPreview` (6 issues) |

- **Lane 1's guard mutations, re-run** (the record had none, §5), each as its
  guard's doc comment spells it, same protocol:

  | id | mutation | reddened |
  |---|---|---|
  | MG1.1 | `public extension StyledElement { func onDrag(_ body: () -> Void) -> Self }` | `theDragAndDropSpellingsCompileFromAPlainImport` |
  | MG1.2 | a `public extension Transferable` defaulting all four members | `anOutsideTypeCanConformToTransferable` |
  | MG1.3 | a `public extension PlatformWindow` default for `beginExternalDrag` answering `false` | `aPlatformWindowWithoutBeginExternalDragDoesNotCompile` |

- **Read, not mutated**: with no draggable in a tree, `gestureArenaKey`
  returns `(topmostOpaqueHitbox, nil)` and `GestureArena.init` builds the
  same member list as before; `Handlers.isPointerTarget` differs from
  `053a3b3` only for a gesture list holding a draggable; hover still resolves
  through `topmostOpaqueHitbox` alone, so the new non-opaque regions move no
  hover; the two new hitbox regions are registered only by an element
  carrying a draggable or destination
  (`aFrameWithoutADragOrDestinationAddsNoHitbox`). The pre-existing gesture,
  selection, focus, accessibility and animation suites are green unedited.
- **One doc defect fixed**: §9's "No migration note: nothing broke" bullet
  contradicted `docs/migration.md`'s new `beginExternalDrag` row (above).
- **No code defect found.** No plan box is touched (this is not a plan task);
  `docs/verification/human-checks.md` group N (N1–N8) carries the looks.

