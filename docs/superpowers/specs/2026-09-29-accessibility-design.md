# Accessibility — design (plan task 12, part 2)

Branch `feat/accessibility-bridge` from `31d3565` (master, plan task 12 part 1
landed, record §62). Rulings **`IX-U`…`IX-AE`** appended to the existing
part-1 decisions doc,
[`../2026-09-29-interaction-decisions.md`](../2026-09-29-interaction-decisions.md),
plus the critic round's **`IX-AF`**, which amends `IX-Y`, `IX-AB`, `IX-AD` and
`IX-AE` (next unused **`IX-AG`**). Evidence: `docs/probes/swiftui-accessibility-part2.swift`
(**new**, arm ids `C…` controls, `E…` `accessibilityElement(children:)`, `H…`
hidden, `T…` traits, `M…` modal isolation, `N…` hint and identifier, `A…`
declared actions, `B…` buttons, `G…` gestures, `X…` truncation, `F…` focus, `L…`
the `List`'s rows, `I…` images, `P…` proposal-shaped containers; its header
carries the recorded output and the reading) and one existing probe **re-run
this session**, compiled (`xcrun swiftc … -o`; the `/usr/bin/swift` JIT form
now fails to link on macOS 27 with `Symbols not found: ___isPlatformVersionAtLeast`),
reading its recorded values: `swiftui-controls-and-selection.swift` (LA0–LB3,
byte-identical to its header). Record: `docs/record/63-accessibility.md` (the
Record phase writes it).

**Status: DESIGNED.** This is the plan's task 12 **second sentence** —
"Deliver the missing native accessibility bridge and validate it with
VoiceOver; until then MetalUI cannot claim complete SwiftUI-level application
behaviour." Part 2 closes every accessibility row part 1's audit assigned it
(spec `2026-09-29-interaction-design.md` §2 rows 27–37) and **prepares** the
VoiceOver validation: a written script with expected output and a place for
the human's result. **An agent cannot run VoiceOver or claim the
validation. Task 12's box stays UNticked until a human runs the script**
(`IX-AE`), and the record and the plan note say exactly that.

## 1. Baseline

`31d3565`, this worktree with its own `.build`: `swift build --build-system
native --build-tests` (0 `error:`, the one `warning:` SwiftPM's deprecation
notice) then unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1837 tests in 3 suites passed after 113.321 seconds`**
(re-taken by this design session; the log carries `FR-J no-argument frame:
succeeded=true`, so the guards ran); **113** typecheck guards, 0 goldens,
**69** live divergences, next label **95** (record §62 §11). `Backends/SDL`
**22 + 27** on macOS (`31d3565`'s own commit). AccessKit fetched with
`Backends/SDL/scripts/fetch-accesskit.py` (0.23.0, checksum matched) so the
design could read `accesskit.h`.

The probe ran with the screen **locked** (`CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1`), twice, byte-identical (308 filtered lines), exit 0.
Every read is in-process KVC on `NSHostingView`'s published tree after
`AXEnhancedUserInterface` — headless, as the three accessibility-bridge probes
were; no arm needs an unlocked screen except `F4`, recorded as non-separating
(no ruling rests on it). The real-window capture is **not taken** (screen
locked).

## 2. The audit — part 2's rows and every accessibility item owned by task 12 (`IX-U`)

Collected from record §62 §7 (rows 27–37), the part-1 spec §2, the plan's
2026-09-29 progress note, and `grep -rn -i "task 12"` over every decisions
doc's carried table (`AB-Q`, `DD-U`/`DD-Z`/`DD-AB`/`DD-AD`/`DD-AE`, `TE-O`/
`TE-AL`, `GR-` §564/§670, `EV-AE`) and `Sources/` doc comments, 2026-09-29.

| # | item (source) | SwiftUI arm | MetalUI at `31d3565` | verdict | where |
|---|---|---|---|---|---|
| 27 | the VoiceOver script (plan text; record §12) | human | written 2026-09-15, never run | **rewritten** against the demo and the controls demo, expected output from pinned trees; **run by a human** | lane 3, `IX-AE` |
| 28 | settable `AXSelected`/`AXSelectedRows`, divergence 83 (`DD-Z` 8) | LA2–LA4, LB2, LB3 (re-run) | press only; set is refused | **built** (AppKit); AccessKit selects by `Click` (no select action in 0.23) — **83 retires** | lanes 1–2, `IX-AA` |
| 29a | `accessibilityElement(children:)` `.ignore`/`.combine`/`.contain` (`AB-Q`) | E1–E14 | — | **built** | lane 2, `IX-V` |
| 29b | `accessibilityHidden` (`AB-Q` "hidden") | H1–H5 | only `hidden()` suppresses | **built** | lane 2, `IX-W` |
| 29c | extra traits (`AB-Q`) | T1–T11, T3p | `AXTrait` `selected`/`disabled`/`updatesFrequently` only | **built**: `.isButton`, `.isHeader`, `.isSelected`, `.isLink`, `.isImage`, `.isStaticText`, `.isModal`, `.updatesFrequently` | lane 2, `IX-X` |
| 29d | custom and declared actions (`AB-Q`) | A1–A7, G6 | derived only (`AB-H`) | **built**: `accessibilityAction(_:)`, `accessibilityAction(named:_:)` | lane 2, `IX-Y` |
| 29e | a non-button click absorber (`AB-Q`; the demo modal's panel) | T3, T3p | an `onClick {}` is a button | **ruled**: `.accessibilityRemoveTraits(.isButton)` changes the role only (T3p); the demo's panel uses it | lanes 2, 3, `IX-X` |
| 29f | hint, identifier (SwiftUI surface beside the label) | N1–N6 | — | **built** | lane 2, `IX-W` |
| 30 | `AB-H`'s press question, divergence 28; whether a press focuses (`DD-AE` 2) | B6, B7 (P1/P2 re-run) | refused under `allowsHitTesting(false)` | **28 retires**: the press is advertised and runs; the press keeps `runClick`'s focus request (one path, `DD-AE` 2) | lane 1 (press-only), lane 2 (press order), `IX-Z` |
| 31 | modal isolation and press occlusion (`AB-Q`; `AB-H` "not checked") | M0–M5 | everything published | **built**: `.isModal` isolates the tree; an isolated-out request is refused — **divergence 95 added** (SwiftUI's held element still presses, M5) | lane 2, `IX-X`, `IX-Z` |
| 32 | divergence 32; scrolling to unrealised rows (`DD-AB` 4, `AB-L`) | L1 (R16 re-run): AXOutline, 500 rows reachable | `AXTable` of realized rows | **amended**: AppKit role `AXOutline`/`AXOutlineRow`; unrealised rows stay unreachable (kept, owner none; the script records what VoiceOver does at the edge) | lanes 1–2, `IX-AA` |
| 33 | divergence 82 (`DD-U` 3, 9) | — (controls probe PA/STA/SA arms) | partial fold labels the control | **kept**, owner the human VoiceOver run (the script has a step for each) | lane 3, `IX-AE` |
| 34 | `AB-Q` proposal-path accessibility, grids included (`GR-` doc §564, §670) | P1–P5 | **nothing** on the proposal path publishes | **built**: `ProposalText` records its string; proposal accessibility modifiers; grids flatten (P2) | lane 2, `IX-AB` |
| 35 | an `onTap` control's and an image's VoiceOver presence (`TE-O`, `Image.swift` doc, `TE-AL`) | G1–G7, I1–I5 | nothing for either | **ruled**: a tap/gesture publishes no press, as SwiftUI (G1–G7; divergence 27 amended); `accessibilityAction` is the remedy (G6); a decorative image publishes nothing (I2, I4, I5), and `Image(_:scale:label:)` (SwiftUI's labelled init) publishes an image (I3) | lane 2, `IX-Y`, `IX-AB` |
| 36 | `AXNode.actions`' inert row (`AB-` doc) | A1 | declared, never read | **deprecated** toward `accessibilityAction`/`accessibilityAdjustableAction` (no in-repo caller); row amended | lane 2, `IX-Y` |
| 37 | the `DD-` rulings' "if task 12's VoiceOver validation prefers…" costs (`DD-U`, `DD-AD` 1, `DD-AE` 2) | — | — | **routed to the script** (one step each); no code | lane 3, `IX-AE` |
| 38 | `Button(role:)`, `.keyboardShortcut`, `.buttonStyle` as accessibility (brief) | B1–B5, C2 | plain `AXButton` | **pinned as SwiftUI's**: none publishes anything; AppKit's own `NSButton` publishes no shortcut either (C2) | lane 3, `IX-AC` |
| 39 | gestures' accessibility actions (brief) | G1–G7 | none (`AB-Y`) | **pinned as SwiftUI's** | lane 2, `IX-Y` |
| 40 | what a truncated `Text` publishes (task 11's check) | X1–X4 | the whole string (unpinned) | **pinned**: the whole string, as SwiftUI | lane 3, `IX-AC` |
| 41 | the part-1 controls on both bridges, parity (brief) | — | AppKit role table; AccessKit role table | **pinned**: every `AccessibilityNode` field has an arm in both bridges' tables (a `Mirror` count), and the controls demo translates on both | lanes 1, 3, `IX-AD` |
| 42 | focus/accessibility after `IX-I` (brief) | F1, F2 (arm 13 re-run) | `.focus` request moves focus; untested against `@FocusState` | **pinned**: an accessibility focus request writes a `@FocusState`; a `@FocusState` write is the tree's focus; focus leaves the tree with its identity | lane 3, `IX-AC` |
| 43 | divergence 31 (nothing focused reports the host) | F3, F4 | host | **untouched**: F4 answered the host where arm 13 answered its first focusable node (screen state differs) — not separating | — |
| 44 | `Stack` order (divergence 34, `AB-P`), row indices for third-party containers, system settings (task 13), iOS (task 14) | — | — | not task 12's by their own tables; unchanged | — |

Nothing on this list is left unclassified.

## 3. What the probe measured (the short form)

The probe header's "WHAT THE ARMS SETTLE" is the full reading. The facts this
design builds on:

- **`.ignore`** (the default of `accessibilityElement()`): one node, no role
  (`AXUnknown`), no label unless declared, **children dropped and not merged**
  (E1, E2, E12).
- **`.combine`**: one node. Its label/value text is every non-interactive
  descendant's text **plus the first interactive descendant's label**, joined
  with `", "`, resolved as a static text's would be (value for a plain text,
  label when a descendant carries a value — E3, E10, E11); a declared label
  replaces the join (E8). Over interactive descendants it takes the **first**
  one's role and press (E6, E7, E14 runs `A`) and publishes **every**
  interactive descendant as a custom action named by its label, tree order
  (E6 `["B"]`, E14 `["A", "B"]`). **Amended by `IX-AI`** (probe revision 2,
  E15–E21, E18p): "the first one's" holds only for children of one kind.
  Children of different kinds **merge** — the role is the highest-ranked
  (slider over checkbox over button over text field, whatever the order), the
  value the **last** child's that carries one, the label and press the first
  child that **presses** (a slider or a text field is skipped for both), a
  slider's increment is added and reaches it, and only a child that presses
  is a custom action.
- **`.contain`**: a real group, labelled if declared, keeping its children —
  the label is **not** distributed (E5) — and a group even over a leaf text
  (E9).
- **Hidden**: `accessibilityHidden(true)` removes the subtree; an inner
  `(false)` cannot un-hide it (H5); the outer modifier wins on one view (H4);
  a hidden child contributes nothing to a button's label (H3).
- **Traits**: `.isHeader` → `AXHeading` whose text is the **label** (T1),
  distributed from a container (T9), not on a `Button` (T11); `.isButton` →
  `AXButton`, **no press** (T2); removing `.isButton` → the role only, the
  press and the folded label stay (T3, T3p); `.isSelected` on any role (T4,
  T7); `.isImage` → `AXImage` (T5); `.isLink` → `AXLink` (T6);
  `.updatesFrequently` invisible (T10).
- **Modal**: `.isModal` publishes **only** its subtree (M1, M3, over an
  overlay's primary M2); the hit test outside it answers the host (M4); an
  element a client already holds still presses (M5).
- **Hint/identifier**: `AXHelp` and `AXIdentifier`, distributed like a label
  (N1–N5); `.help(_:)` publishes `AXHelp` too (N6, not offered here).
- **Actions**: `accessibilityAction {}` makes a node a pressable `AXButton`
  (A1), distributed (A5), **replacing a `Button`'s own press** (A4); named
  actions are custom actions that run, later-written first (A2, A3, A6); a
  `Button`'s press survives a named action (A3); disabled refuses (A7).
- **Buttons**: role, `.defaultAction`, `.keyboardShortcut`, `.plain` publish
  nothing different (B1–B5, C2). Under `allowsHitTesting(false)` a `Button`
  **still presses** (B6); disabled refuses (B7).
- **Gestures**: no gesture publishes a press (G1–G5, G7); `accessibilityAction`
  on a tapped text runs the action, not the tap (G6).
- **Truncation**: the whole string, whatever is drawn (X1–X4).
- **Focus**: the `@FocusState`-focused field is the focused element (F1); an
  `AXFocused` write reaches `@FocusState` (F2).
- **List**: `AXOutline` with 500 `AXRow`/`AXOutlineRow` rows, indices 0…499,
  8 visible (L1). Selection by `setAccessibilitySelected`/`…SelectedRows`
  (LA2–LB3, re-run).
- **Images**: `Image(nsImage:)` is `AXImage`, labelled when declared (I1, I3);
  a decorative image publishes nothing, even labelled or tapped (I2, I4, I5).
- **Proposal containers**: stacks and grids publish no node of their own; their
  texts flatten into reading order, a grid row by row (P1, P2); a label on an
  `HStack` distributes (P3).

## 4. Public API (spelling ruled against SwiftUI)

All new spellings are SwiftUI's own names and argument labels. Offered on
**`StyledElement`** (returning `Self`, through `handling`, as
`accessibilityLabel` already is — no new layer, no id path moves) and, new,
on **`ProposalElementGroup`** (through a new wrapper
`AccessibilityModifier<Content>`, `GestureModifier`'s shape: one cursor
index, its one child numbered from 0 under it — additive, only a caller who
writes it gains the level). **Not offered on `Component`** (`CO-U`, as the
existing three).

```swift
public enum AccessibilityChildBehavior: Sendable, Hashable {  // SwiftUI's is a struct with static members;
    case ignore, combine, contain                               // a closed enum is PickerStyle's precedent (IX-V)
}
public struct AccessibilityTraits: OptionSet, Sendable, Hashable {
    public static let isButton, isHeader, isSelected, isLink, isImage,
                      isStaticText, isModal, updatesFrequently
}   // not offered (guard G2.3): .isSearchField, .playsSound, .isKeyboardKey,
    // .isSummaryElement, .startsMediaSession, .allowsDirectInteraction,
    // .causesPageTurn, .isTabBar, .isToggle

extension StyledElement {           // and the same seven on ProposalElementGroup
    func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> Self
    func accessibilityHidden(_ hidden: Bool) -> Self
    func accessibilityHint(_ hint: String) -> Self
    func accessibilityIdentifier(_ identifier: String) -> Self
    func accessibilityAddTraits(_ traits: AccessibilityTraits) -> Self
    func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> Self
    func accessibilityAction(_ handler: @escaping @MainActor () -> Void) -> Self
    func accessibilityAction(named name: String, _ handler: @escaping @MainActor () -> Void) -> Self
}
extension ProposalElementGroup {    // new: the three that existed only on StyledElement
    func accessibilityLabel(_:), accessibilityValue(_:), accessibilityAdjustableAction(_:)
}                                    // each returns AccessibilityModifier<Self>

extension Image {
    public init(_ bitmap: ImageBitmap, scale: Float, label: Text)   // SwiftUI's Image(_:scale:label:)
}
```

`SwiftUI.accessibilityAction(.default) {}` and `accessibilityAction(_ kind:)`
with `.escape`/`.magicTap` are **not offered** (owner none): `.default` is the
unlabelled form above; the other kinds have no macOS client in the probe.
`AccessibilityChildBehavior`'s `.ignore` default matches SwiftUI's
`accessibilityElement(children: = .ignore)`. `label: Text` reads the text's
string (a `Text` built from a string literal; lane 2 checks `Text` exposes it
internally).

**`AXNode.actions` and `AXActionKind` are deprecated** (`@available(*,
deprecated, message: "declare an action with accessibilityAction(_:) or
accessibilityAdjustableAction(_:); AXNode's actions are never read (AB-H)")`);
`AXNode.init`'s `actions:` parameter moves to a deprecated overload so an
existing spelling still compiles. No in-repo caller writes either (grep of
2026-09-29: the `actions: [.press]` hits are `AccessibilityNode`'s, the
platform type), so the 0-`warning:` baseline holds (`IX-Y`). **Three
mechanics the baseline depends on** (`IX-AF` item 2): the deprecated
overload's `actions:` has **no default** (with one, `AXNode(role:label:)`
would be ambiguous between the two initialisers — G2.2's control arm is the
pin); the stored property keeps its `= []` default so the undeprecated
initialiser never names it; and `isEmpty`'s `self == AXNode()` and the
synthesized `==` must build with 0 `warning:` on both build systems — the
lane records that build, and if the synthesized conformance warns, `==` is
written by hand inside a `@available(*, deprecated)` helper rather than the
deprecation being dropped.

**No overload ambiguity** (`IX-AF` item 5): no type conforms to both
`StyledElement` and `ProposalElementGroup` (grep of 2026-09-29 —
`ModifiedContent`'s two conformances are disjoint on `Modifier ==
ModifierLayer` / `== LayoutModifier`), so `Box().padding(1).accessibilityLabel(_:)`
still returns `Self` and no existing call site gains `AccessibilityModifier`'s
identity level. G2.1 asserts both results' static types. `AccessibilityModifier`
preconditions **exactly one** child node, as every single-child proposal
wrapper does (`SA-G`), pinned by an exit test in 2.16.

**`AXNode` stores the new declarations in one optional reference box**
(`AXDeclarations`, a final class holding a struct, copied on write), so
`MemoryLayout<AXNode>.size` — and `Handlers`' — grows by **at most one
pointer** (8 bytes; the Windows stack budget, `IX-N`'s rule). Fields: child
behaviour, hidden, hint, identifier, added traits, removed traits, named
actions' names (later-written first). Equality compares the boxed values.

**The neutral tree** (`MetalUIPlatform/AccessibilityTree.swift`):

- `AccessibilityRole` gains `.heading` and `.link`.
- `AccessibilityNode` gains `hint: String?`, `identifier: String?`,
  `customActions: [String]` (names, published order) and `isSelectable: Bool`
  (a row of a `List(selection:)`).
- `AccessibilityRequest` gains `.customAction(AccessibilityNodeID, Int)` (an
  index into `customActions`), `.select(AccessibilityNodeID)` (a row: replace
  the selection with it, LA2/LB3) and `.selectRows(AccessibilityNodeID,
  [AccessibilityNodeID])` (a table: set exactly these, LA3/LB2; a single-
  selection list ignores more than one, LA4).

All three types are public and cross module boundaries: every lane that adds a
stored property takes its counts after `swift package clean`.

## 5. The builder's rules (`AccessibilityTreeBuilder`, lane 2)

In order, extending the existing steps (collect, parent, actions, A
distribution, B text, C combination, emit):

1. **Collect.** Hidden needs no builder step: `accessibilityHidden(true)`
   opens `withAccessibilitySuppressed(except: nil)` around the element's own
   registration **and** its content in `PrepaintPass.registerAndScope` (and
   the proposal wrapper's prepaint), so nothing inside records (H1–H5; the
   innermost `(false)` cannot un-hide, H5, because suppression is a depth).
2. **Modal isolation** (`IX-X`), after parenting: if any kept record declared
   `.isModal`, the one with the greatest `(layer, order)` is the only root; every
   record outside its subtree is dropped (M1, M2, M3). `focused` publishes only
   if inside it (the existing "published only if in `nodes`" rule). The builder
   returns `isolatedOut: Bool` for `Window`'s refusal (lane 2).
3. **Actions.** A press is derived from (a) a hitbox with `onClick` (today),
   (b) **`Frame.accessibilityPressOnly`** — an `onClick` whose hitbox the
   `allowsHitTesting(false)` gate withheld, recorded only while collecting and
   only when enabled (`IX-Z`, B6), and (c) a registered
   `AccessibilityDefaultAction` handler (`accessibilityAction {}`, A1, stored
   through `onAction` in `Handlers.actions`, reached through the focus
   registry exactly as `AccessibilityAdjustment` is — disabled or hidden
   registers none, A7). `customActions` are the node's declared names when a
   registered `AccessibilityNamedAction` handler backs them (A2, A6: later
   written first). **A declared action is a declaration, not a synthesis**
   (`IX-AF` item 3): `registerHandlers`' `hasSomethingToSay` gains "an
   `AccessibilityDefaultAction` or `AccessibilityNamedAction` handler is
   registered" **outside** the `synthesizesAccessibility &&` clause, so
   `HStack{}.accessibilityAction {}` (the wrapper) and G6's action over a
   gesture both record; without it A1/G6 publish nothing through a
   non-synthesizing conformer. When a combined node also declares named
   actions, the declared names come first, then the combined ones — MetalUI's
   choice, no probe arm has both.
   **Which declarations write `$ax`** (`AB-U`, `IX-AF` item 3): every field
   of the `AXDeclarations` box counts toward `AXNode.isEmpty`, so a caller
   who writes any of §4's modifiers on an element declares a node and that
   element writes one `$ax` slot — **with or without a client**, exactly as
   `accessibilityLabel` does today (the emission above the client gate). No
   existing call site writes one of them, so no existing retention moves; the
   demo panel's one slot (§8) is the only production instance.
4. **A. Distribution** (`AB-T`) distributes **label, value, hint, identifier and
   the added `.isHeader`/`.isSelected` traits** (N4, N5, T9; R3/R4/R18 for the
   first two) from a plain generic container or wrapper — unchanged condition
   (not clickable, focusable, adjustable, no count/index) plus "not `.contain`,
   not `.combine`, not `.ignore`, not `.isModal`" (E5: `.contain` keeps its
   label).
5. **`.ignore`**: the node keeps its declared label/value/hint/identifier/
   traits, role `.group` (divergence 33 amended: SwiftUI's `AXUnknown`), and
   **no children** — its whole subtree is dropped (E1, E2, E12).
6. **B. Text** (unchanged) — then the traits: `.isHeader` → `.heading` with the
   text as **label** (T1), unless the node is a button (T11); `.isButton` →
   `.button` (no action added, T2); `.isLink` → `.link`; `.isImage` →
   `.image`; `.isStaticText` → `.text`; a removed `.isButton` on a clickable
   node → `.group` **after** step C's fold ran as a button (T3p: label and
   press stay).
7. **`.combine`** (before C): over the kept subtree in tree order, take every
   non-interactive descendant's text and the **first** interactive
   descendant's label, join with `", "`, resolve as a static text (value, or
   label when a descendant carries a value; a declared label wins, E8). Over an
   interactive descendant: role and actions are the **first** one's, and
   every interactive descendant's label becomes a custom action (E6, E7,
   E14). The builder returns `redirects: [GlobalElementID: [GlobalElementID]]`
   — a press/adjust on the combined id runs `redirects[id][0]`'s; custom
   action `i` runs `redirects[id][i]`'s press (lane 2). Children dropped.
   **Amended by `IX-AI`**: the "first" above is the **lead** — the first
   interactive descendant that presses, else the first that is not
   adjustable; the role is the highest-ranked descendant's, the value the
   last one's that carries one, custom actions only the pressing ones,
   `redirects[id]` lists the lead first, and an adjustment runs the first
   redirect that takes one.
8. **`.contain`**: a `.group` node keeping its declared label and its children;
   over a text leaf it publishes a group at the element's id and the text as
   one synthesized child, `AccessibilityNodeID(ContainedText(id))`, which no
   request resolves (E9).
9. **C. Combination** (`AB-G`, `DD-U`), then emit. `AccessibilityNode.isSelectable`
   is a row's `List(selection:)` hint (lane 2 sets it in `List.swift`).

**The proposal path** (`IX-AB`): `ProposalText.prepaint` records a text leaf
through a new internal `Frame.recordAccessibility(text:declared:at:id:)` —
gated on `collectsAccessibility` alone (no hitbox, no focus entry, no
`StateTable` write), reading `isEnabled` and the suppression exactly as
`registerHandlers`' record does. `AccessibilityModifier` calls
`registerHandlers` with its declared node and actions (so a declared node
writes one `$ax` slot, `AB-U`, as the legacy modifiers do; an action registers
no hitbox and does not make the element focusable, `accessibilityAdjustableAction`'s
contract). `Image(_:scale:label:)` records an `.image` node with the label
through the same internal call; `Image(decorative:scale:)` still records
nothing (I2, I4, I5). A `Grid`/`GridRow`/stack records nothing of its own, so
its texts flatten (P1, P2). **This changes an answer existing trees give
whenever a client is active** (a proposal text that published nothing now
publishes a static text): lane 2 first greps the suite for every test that
builds a `ProposalText`/`.proposalLayout()`/proposal stack with a client
active (or reads `axEmissions`/a published tree over one) and runs it at the
stub commit; any that reddens with the record in is a **T row** named in
lane 2's landing ruling with its old and new answer, never edited silently
(`IX-AF` item 4). The main demo holds no proposal element
(`nativeLayoutPreviewContent()` does), so 3.8's tree is unaffected; the
preview's is 3.11's.

## 6. The bridges (lane 1) and dispatch (lane 2)

**`Window`** (`WindowAccessibility.swift`): keeps the last build's
`redirects`, `isolatedOut` and the frame's `accessibilityPressOnly` beside
`lastHitboxes`. A **press** runs, in order: a registered
`AccessibilityDefaultAction` (A4, G6), the redirect target's press (E6), the
last `onClick` hitbox (today), the press-only handler (B6) — each through
`runClick`, so a press keeps `ClickDispatch`'s `[]` modifiers and its focus
request (`DD-AE` 2, `IX-Z`). **`.customAction(id, i)`** runs the node's
`AccessibilityNamedAction` handler with its `i`-th name, or the redirect
target's press. **`.select(row)`/`.selectRows(table, rows)`** find the row's
table in `lastPublished` and run the list's registered `AccessibilityRowSelection`
handler (lane 2 adds it in `List.swift` beside the click selection it
reuses; a disabled list registers none). **A request whose id the last
published tree does not contain is refused when that tree was built under
modal isolation** (divergence 95: M5's held element presses in SwiftUI).

**AppKit** (`AppKitAccessibility.swift`): `accessibilityHelp` ← `hint`,
`accessibilityIdentifier` ← `identifier`, roles `.heading`/`.link`,
`accessibilityCustomActions` ← one `NSAccessibilityCustomAction(name:handler:)`
per name whose handler sends `.customAction` through `mainActorAnswer`
(`AB-AE`); **a `.table` publishes as `.outline` and its rows with subrole
`.outlineRow`** (L1, R16, LA0); `setAccessibilitySelected(true)` on a
selectable row → `.select`, `setAccessibilitySelectedRows(_:)` on the outline →
`.selectRows`, `accessibilitySelectedRows()` answers the selected rows;
`isAccessibilitySelectorAllowed` allows the two setters only on a selectable
row / an outline with a selectable row. **Every new override answers through
`mainActorAnswer(_:fallback:_:)`** (`AB-AE`) — `accessibilityHelp`,
`accessibilityIdentifier`, `accessibilityCustomActions`, the custom action's
handler, `setAccessibilitySelected`, `setAccessibilitySelectedRows`,
`accessibilitySelectedRows` — and off the main thread answers nothing
without trapping; the existing exit test covers only the label, children,
selector and press, so 1.9 pins the new ones (`IX-AF` item 6).

**AccessKit** (`Backends/SDL/Sources/MetalUISDL/AccessKitTree.swift`,
`AccessKitAdapter.swift`): `hint` → `accesskit_node_set_description`,
`identifier` → `accesskit_node_set_author_id`, `.heading` →
`ACCESSKIT_ROLE_HEADING`, `.link` → `ACCESSKIT_ROLE_LINK`, custom actions →
`accesskit_node_push_custom_action` (id = index, description = name) with
`ACCESSKIT_ACTION_CUSTOM_ACTION` added, and an incoming `CUSTOM_ACTION`
(`data.custom_action`) → `.customAction`; a selectable row sets
`selected` **false** as well as true (AccessKit's "selectable, not selected");
a row is still selected by `Click` (AccessKit 0.23's action enum, header lines
72–146, has no select action). No keyboard shortcut is published on either
bridge (C2, B3: neither SwiftUI nor AppKit's own button publishes one).

**Amended by `IX-AG` (lane 1's landing): the parity tables found two fields
with no arm.** AccessKit translated neither `rowCount` nor `rowIndex` — they
now reach `accesskit_node_set_row_count`/`set_row_index` (a T row in
`aMetalUITreeTranslatesToAccessKitsVocabulary`'s two literals); AppKit read
`isFocusable` nowhere — `isAccessibilitySelectorAllowed(setAccessibilityFocused:)`
now answers it, so `AXFocused` is settable exactly where `Window` would honour
the `.focus` request (AB-J). A row also answers subrole `AXOutlineRow`, and a
node with no identifier answers `""` (the protocol's non-null `NSString`).

## 7. Lanes — AT MOST THREE, run in order 1, 2, 3 (`IX-AE`)

Every lane: tests red first (each lane first lands the public declarations as
stubs that return `Self`/do nothing, so its tests compile and fail on their
assertions — the "red before" column), then green; every **new** typecheck
guard mutated red once; each named mutation applied from a commit, restored
from a copy, the whole suite run unfiltered, `git status --short` clean after,
**every reddened test named**. A lane records its landing in a ruling (`IX-AG`
onward) in the decisions doc; the Record phase writes record §63. No test
sleeps. **No `Handlers` member is added** (the declarations ride `AXNode`'s
box; the actions ride `Handlers.actions`), so `HandlerShape`/
`HandlerFingerprint` gain no field — lane 2 records `MemoryLayout<AXNode>.size`
and `MemoryLayout<Handlers>.size` before and after (440 at `31d3565`, at most
448 after) and the smallest thread building every production tree (624 KB at
`31d3565`); `everyProductionTreeBuildsOnAOneMegabyteThread` green.

**Why this order and this cut** (`IX-AE`, amended by `IX-AF` item 1): the
neutral tree's new cases (roles, fields, request cases) must exist before
anything can publish or send them, and the bridges can be tested on
hand-built trees (as `AppKitAccessibilityTests` and `AccessKitTests` already
are), so they go first — **together with the two requests that need no new
modifier**: the settable selection (`List.swift`'s `AccessibilityRowSelection`,
`isSelectable`, `.select`/`.selectRows` in `WindowAccessibility.swift`) and
the press under `allowsHitTesting(false)` (`Frame.registerHandlers`'
press-only record, the builder's `.press` from it, `Window`'s press-only
arm). The critic round moved these five tests (old 2.13, 2.21, 2.25–2.27)
from lane 2, which held 27 tests and 3 guards over fifteen files, to lane 1,
which held 8: each is the dispatch end of a lane-1 request case and needs
none of lane 2's modifiers. The lanes are **no longer file-disjoint** —
`Frame.swift`, `AccessibilityTreeBuilder.swift`, `Window.swift` and
`WindowAccessibility.swift` are touched by lanes 1 and 2 — so they run
**strictly in order**, lane 2 starting from lane 1's landed commit (never in
parallel), and lane 2 adds the declared-action and redirect arms **ahead of**
lane 1's hitbox and press-only arms in the press order (§6). **One declared
stub remains**: lane 1 adds `case .customAction: return false` to
`Window.handleAccessibilityRequest` (the `switch` is exhaustive), with a
comment naming lane 2, which replaces it. Lane 1 also runs
`python3 Backends/SDL/scripts/fetch-accesskit.py` **in this worktree** (no
`.accesskit` exists here at `50809ed`) before building `Backends/SDL` with
`PKG_CONFIG_PATH=$PWD/.accesskit`.

### Lane 1 — the neutral tree, both bridges, and the two modifier-free requests

**Files.** `Sources/MetalUIPlatform/AccessibilityTree.swift` (§4's neutral
roles, fields and request cases), `Sources/MetalUIAppKit/AppKitAccessibility.swift`,
`Backends/SDL/Sources/MetalUISDL/AccessKitTree.swift`,
`Backends/SDL/Sources/MetalUISDL/AccessKitAdapter.swift`; and, for the two
modifier-free requests (`IX-AF` item 1), `Sources/MetalUI/List.swift`
(`AccessibilityRowSelection`, declared in a new
`Sources/MetalUI/AccessibilityRequests.swift`, and `isSelectable`),
`Sources/MetalUI/Frame.swift` (`registerHandlers`' press-only record only),
`AccessibilityTreeBuilder.swift` (the press from it, `isSelectable`),
`Window.swift` and `WindowAccessibility.swift` (the press-only arm, `.select`/
`.selectRows`, the `.customAction` stub). New root tests go in
`Tests/MetalUITests/AccessibilitySelectionAndPressTests.swift`; the two renamed
pins stay in `AccessibilityTreeTests.swift` and `ListSelectionTests.swift`. Tests: new
`Tests/MetalUIPlatformTests/AppKitAccessibilityPart2Tests.swift` (hand-built
trees, the `AppKitAccessibilityTests` harness), `AppKitAccessibilityTests.swift`
(the role table's `.table` → `.outline` literal — a **T row**, its answer
changed by ruling `IX-AA`, not a retirement), new
`Backends/SDL/Tests/MetalUISDLTests/AccessKitPart2Tests.swift`.

| id | test | red before because | mutation that must redden it |
|---|---|---|---|
| 1.1 | `theAppKitBridgePublishesHintIdentifierHeadingLinkAndOutline` (help, identifier, `AXHeading`, `AXLink`, `AXOutline` with `AXOutlineRow` rows; `accessibilityRows`/`Index`/`RowCount` still answer on the outline) | the fields and roles unmapped | M1a: hint mapped to `accessibilityLabel`; M1a′: `.table` back to `.table` |
| 1.2 | `theAppKitBridgesCustomActionsRequestByIndex` (two names in order; each handler sends `.customAction(id, i)`; a detached element publishes none) | none published | M1b: handlers numbered from 1 |
| 1.3 | `anOutlineRowAcceptsAXSelectedOnlyWhenSelectable` (`setAccessibilitySelected(true)` → `.select`; `(false)` sends nothing; a non-selectable row's setter disallowed and silent; `setAccessibilitySelectedRows` → `.selectRows`; `accessibilitySelectedRows()` answers the selected rows) | the setters are refused | M1c: the setter allowed on every row |
| 1.4 | `everyAccessibilityNodeFieldHasAnAppKitArm` (a `Mirror` of `AccessibilityNode` equals the test's field → attribute table — 14 fields — and each arm is asserted on one element) | 4 new fields unmapped | M1d: drop the `identifier` answer (its arm reddens) |
| 1.5 | SDL `theAccessKitSnapshotCarriesHintIdentifierHeadingLinkAndCustomActions` (description, author id, `HEADING`, `LINK`, custom actions with index ids and `CUSTOM_ACTION` added) | unmapped | M1e: the description not set |
| 1.6 | SDL `aSelectableRowPublishesSelectedFalseToAccessKit` (selectable unselected → `false`, selected → `true`, a non-list row → unset) | only `true` is set | M1f: `false` not set |
| 1.7 | SDL `anAccessKitCustomActionMeansACustomActionRequest` (`CUSTOM_ACTION` with `data.custom_action = 1` → `.customAction(id, 1)`; no data → no request) | no mapping | M1g: the index ignored (always 0) |
| 1.8 | SDL `everyAccessibilityNodeFieldHasAnAccessKitArm` (1.4's table, AccessKit's side) | unmapped | M1h: drop the `customActions` arm |
| 1.9 | `theNewAppKitOverridesAnswerNothingOffTheMainThread` (**exit test**, `anOffMainThreadQueryAnswersNothingAndDoesNotTrap`'s shape: on the main thread help, identifier, two custom actions, the selected setter and `accessibilitySelectedRows` answer — the control; off it each answers nothing and the process survives) | the overrides do not exist | M1i: `accessibilityHelp` answered through a bare `MainActor.assumeIsolated` (the child process traps) |
| 1.10 | `aPressIsAdvertisedWhereHitTestingIsDisabled` (was 2.13; B6: `.press` present, `Frame.accessibilityPressOnly` holds the id; B7 disabled: absent; no client: the map stays empty) | the opposite today (divergence 28) | M1j: the press-only record removed; M1j′: recorded without a client |
| 1.11 | `aPressIsRunWhereHitTestingIsDisabled` — **`aPressIsRefusedWhereHitTestingIsDisabled` renamed, its answer flipped by ruling** (was 2.21; `IX-Z`; B6: the handler runs once; a click at the same point still runs nothing) | refused today | M1k: the press-only map not consulted |
| 1.12 | `settingAXSelectedOnARowReplacesTheSelection` — **`anAccessibilityClientSelectsARowByPressingItAndCannotSetSelectedDirectly` renamed, its AppKit half flipped by ruling** (was 2.25; `IX-AA`; LA2 single → `[3]`; LB3 multi `[0,1]` → `[2]`; its press arm kept) | refused today | M1l: `.select` adds to a multi selection |
| 1.13 | `settingTheOutlinesSelectedRowsSetsThemAndASingleListIgnoresTwo` (was 2.26; LA3, LA4, LB2) | stub | M1m: a single list takes the first of two |
| 1.14 | `aDisabledListRefusesAnAccessibilitySelection` (was 2.27; `.disabled(true)`: `.select` → `false`, nothing written; control enabled) | stub | M1n: the handler registered past the disabled gate |

**Must stay green**: `AppKitAccessibilityTests` but its one T row, every
`AccessKitTests` test, `anNSAccessibilityClientReadsThePublishedTree`, every
root-package test but 1.11's and 1.12's renamed pins (the `.customAction` stub
refuses exactly as an unknown id is refused today; the press-only record is
taken only while collecting, so a window with no client is unchanged),
`noConformerEmitsAnAXNodeItDidNotDeclare`, every `List` click/key selection
test (`DD-Z`'s path is the handler's own).

### Lane 2 — the modifiers, the builder, the proposal path and their dispatch

**Files.** `Sources/MetalUI/AccessibilityModifiers.swift` (the `StyledElement`
modifiers), new `Sources/MetalUI/ProposalAccessibility.swift`
(`AccessibilityModifier`, the `ProposalElementGroup` modifiers), new
`Sources/MetalUI/AccessibilityTraits.swift` (`AccessibilityTraits`,
`AccessibilityChildBehavior`, `AccessibilityDefaultAction`,
`AccessibilityNamedAction`, `AccessibilityRowSelection`), `AXNode.swift` (the
box, the deprecations), `AXEmission.swift`, `AccessibilityTreeBuilder.swift`
(§5; returns a struct carrying the tree, `redirects`, `isolatedOut`),
`Frame.swift` (`recordAccessibility`, `hasSomethingToSay`'s declared-action
term),
`DecorationScope.swift` (the hidden scope), `ProposalText.swift`, `Image.swift`,
`WindowAccessibility.swift` (§6's declared-action and redirect arms ahead of
lane 1's, `customAction` — replacing lane 1's stub arm — and the isolation
refusal), `Window.swift` (the build's `redirects`/`isolatedOut` beside
`lastHitboxes`).
Tests: new `Tests/MetalUITests/AccessibilityModifierTests.swift` (builder level,
the `ControlAccessibilityTests` `tree(_:)` shape), new
`Tests/MetalUITests/ProposalAccessibilityTests.swift`, new
`Tests/MetalUITests/AccessibilityRequestTests.swift` (through a real `Window`
on a `FakePlatformWindow`), new `Tests/MetalUITests/AccessibilityCompileGuards.swift`,
(the two flipped pins are lane 1's).

| id | test | red before because | mutation that must redden it |
|---|---|---|---|
| 2.1 | `anAccessibilityElementIgnoresItsChildrenByDefault` (E1, E2, E12: one `.group`, label only when declared, no children, and the children's text is **not** its label) | stub: children still published | M2a: `.ignore` keeps the subtree |
| 2.2 | `aCombinedElementJoinsItsChildrenIntoOneStaticText` (E3 value `A, B`; E8 declared `L`; E10 nested; E11 `vol, B`/`5`) | stub | M2b: join separator `", "` → `" "`; M2b′: the value-carrying arm resolved as a plain text |
| 2.3 | `aCombinedElementTakesTheFirstInteractiveChildsRoleAndListsEveryOneAsACustomAction` (E6 label `A, B`, role button, press, custom `["B"]`; E7 check box; E14 label `A`, custom `["A","B"]`, redirects `[a, b]`; **`IX-AI`**: E15–E21, E18p, children of different kinds) | stub | M2c: the LAST interactive child's role and label; M2c′: redirects empty — **amended by `IX-AI`**: no single child supplies role, value, label and press any more, so M2c is re-spelled per rule: M2c the lead is the LAST pressing child; M2c-rank no ranking; M2c-value the FIRST valued child; M2c-adjust nothing is adjustable; M2c-custom every interactive child a custom action (the old literal spelling, `interactive.first` → `.last` in the branch head, is equivalent after `IX-AI`: `interactive.first` is only the lead's last fallback, reached when every child is adjustable) |
| 2.4 | `aContainingElementIsAGroupThatKeepsItsLabelAndItsChildren` (E4; E5 label not distributed; E9 a text leaf → group + one synthesized static-text child) | stub | M2d: `.contain` distributes its label |
| 2.5 | `anAccessibilityHiddenSubtreePublishesNothing` (H1; H2 beside a published sibling; H3 a button's label excludes the hidden child; H4 outer `(false)` wins; H5 inner `(false)` cannot un-hide) | stub | M2e: the suppression scope wraps the element's own registration only, not its content |
| 2.6 | `aHintAndAnIdentifierPublishAndDistributeLikeALabel` (N1–N5) | stub | M2f: hint and identifier left out of distribution |
| 2.7 | `aHeaderTraitMakesAHeadingLabelledByItsText` (T1 label `Title`, value nil; T9 two headings; T11 a button stays a button) | stub | M2g: a heading's text goes to its value |
| 2.8 | `theButtonLinkImageAndStaticTextTraitsSetOnlyTheRole` (T2 button with **no** press; T5 image; T6 link; `.isStaticText` on a clickable → text with its press; T3p a clickable with `.isButton` removed → group, folded label, press kept) | stub | M2h: `.isButton` also advertises `.press`; M2h′: the removal applied before step C (the fold lost) |
| 2.9 | `aSelectedTraitPublishesSelectedOnAnyRole` (T4, T7; control without the trait) | stub | M2i: `.isSelected` read only on a generic node |
| 2.10 | `aModalSubtreeIsTheOnlyThingPublished` (M0 control publishes both; M1; M3 a modal sibling; two modals → the higher `(layer, order)`; a focus outside it publishes no `focused`; `isolatedOut == true`) | stub | M2j: isolation skipped; M2j′: the FIRST modal wins |
| 2.11 | `aDeclaredActionMakesAPressableButtonAndADisabledOneNone` (A1 button + press; A5 distributed to each child; A7 disabled: no press) | stub | M2k: the `AccessibilityDefaultAction` handler not counted as a press |
| 2.12 | `aNamedActionPublishesACustomActionLaterWrittenFirst` (A2; A3 a button keeps `.press`; A6 `["Two","One"]`) | stub | M2l: names appended instead of prepended |
| 2.14 | `aGestureOrTapPublishesNoPressAndAnAccessibilityActionAddsOne` (G1, G2, G3, G4, G7: no press; G6 `.accessibilityAction` over a tap: press — **each on both spellings**, `StyledElement.onTapGesture`/`.gesture` returning `Self` and the proposal `GestureModifier`/`OnTapModifier`, a copy of a pinned rule being unpinned) | green for the five today (written first, kept green); G6 red | M2n: `GestureModifier` synthesizes (`synthesizesAccessibility: true`) — **amended by `IX-AI` item 5**: on `GestureModifier` this flip is equivalent (its fresh `Handlers` carry only `gestures` and `contentShape`, and `registerHandlers`' synthesize clause needs an `onClick`, `isFocusable`, an adjustable action or `accessibleText`); the separating site is `OnTapModifier` (`NativeTappable.swift`), whose flip reddens this test; M2n′: the declared-action term moved back inside `synthesizesAccessibility &&` — **amended by `IX-AH` item 1**: `AccessibilityModifier` registers synthesizing, so G6's proposal arm cannot redden; an arm registering an unlabelled declared action with `synthesizesAccessibility: false` does |
| 2.15 | `aProposalTextPublishesItsStringAsAStaticText` (P1 two texts, the spacer nothing; P2 a 2×2 grid flattened row by row; a disabled scope → `isEnabled == false`; a `hidden()` one nothing) | nothing on the proposal path records | M2o: `ProposalText.prepaint` records nothing |
| 2.16 | `aProposalAccessibilityModifierLabelsDistributesAndIsOneIdentityLevel` (P3 over an `HStack`; P5 a labelled `Rectangle` → labelled group; the content's id is `.child(of: wrapper, at: 0)`; an exit test: the wrapper over two nodes traps naming the count) | no API | M2p: the wrapper records nothing; M2p′: content numbered at the wrapper's own id |
| 2.17 | `theProposalModifiersMirrorTheStyledOnes` (on an `HStack`: `.combine`, `.accessibilityHidden(true)`, `.isHeader`, `.accessibilityAction {}` — each 2.x twin's answer) | no API | M2q: the wrapper drops its child behaviour (a copy of a pinned implementation is unpinned) |
| 2.18 | `aLabelledImagePublishesAnImageAndADecorativeOneNothing` (I1/I3 via `Image(_:scale:label:)` → `.image` `Logo`; I2, I4 decorative labelled, I5 decorative tapped: nothing) | no labelled init | M2r: the decorative init records too |
| 2.19 | `theNewDeclarationsCostHandlersAtMostOnePointer` (`MemoryLayout<AXNode>.size` ≤ its `31d3565` value + 8, the literal recorded in the test with the measurement) | fields inline | M2s: the seven fields stored inline |
| 2.20 | `anAccessibilityPressRunsADeclaredActionInsteadOfTheClick` (A4 `["Default"]`; G6) | advertised, not dispatched | M2t: the hitbox tried first |
| 2.22 | `aCombinedElementsPressAndCustomActionsRunItsInteractiveChildren` (E6, E14: press runs `A`; custom action 1 runs `B`; **`IX-AI`**: E17/E18p press the button and increment the slider in either order, E20 presses the button past a text field) | no redirect dispatch | M2v: custom action `i` runs redirect `0`; **`IX-AI`**: M2c-dispatch, an adjustment runs redirect `0` |
| 2.23 | `aCustomActionRequestRunsTheNamedHandlerAndABadIndexNothing` (A2; A3: press `B`, custom 0 `Archive`; index 5 refused) | lane 1's stub refuses | M2w: the index read from the end |
| 2.24 | `aRequestForAnElementOutsideTheModalIsRefused` (M5: a held id's press returns `false` and runs nothing; with the modal gone it presses) | no isolation | M2x: the refusal removed |
| G2.1 | `theAccessibilityModifiersCompileFromAPlainImport` (plain-import `typecheckFile`: every §4 spelling on a `Box`, a `Text` and an `HStack`; `Image(_:scale:label:)`; `let _: ModifiedContent<Box<EmptyGroup>, ModifierLayer> = Box().padding(1).accessibilityLabel("x")` and `let _: AccessibilityModifier<HStack<…>> = HStack { … }.accessibilityLabel("x")` — the overload each resolves to, `IX-AF` item 5) | new guard | mutate red once (make one modifier internal) |
| G2.2 | `anAXNodesActionsAreDeprecatedTowardAccessibilityAction` (plain import: `AXNode.actions` and `AXNode(actions:)` warn, the message names `accessibilityAction`; control: `AXNode(role:label:)` warns nothing) | new guard | mutate red once (drop the attribute) |
| G2.3 | `anUnofferedTraitOrActionKindDoesNotCompile` (`.isSearchField`, `.isToggle`, `.accessibilityAction(.escape) {}`; control: `.isHeader` compiles) | new guard | mutate red once (add `static let isToggle`) |

`noConformerEmitsAnAXNodeItDidNotDeclare` (existing, unedited) is re-run under
every mutation above and stays green (`AB-U`).

**Must stay green, unedited**: every existing accessibility test
(`AccessibilityTreeTests` but lane 1's 1.11 rename, `AccessibilityDefaultsTests`,
`AccessibilityEndToEndTests`, `AXEmitSiteTests`, `AXNodeTests`,
`ControlAccessibilityTests`, the controls' accessibility tests),
`theSevenRetentionSlotsAreMutuallyDistinct`, every `StateTable`/`TB-AH`/focus/
hit-test/`Deferred`/`List`/`TextField`/`TextEditor` test, the `List` selection
tests but lane 1's 1.12 rename (`DD-Z`'s click/key selection is the handler's own
path), `accessKitRequestsReachTheWindowInOrder`,
`theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel`. **No id path moves**:
the `StyledElement` modifiers add no layer; only a caller writing the proposal
wrapper gains its level.

### Lane 3 — the audit, the demo's modal, the VoiceOver script

**Files.** `Sources/MetalUIDemoContent/DemoContent.swift` (**accessibility
modifiers only**: the scrim `Stack` gains `.accessibilityAddTraits(.isModal)`,
the panel `.accessibilityRemoveTraits(.isButton)` — `IX-X`, §8), new
`docs/verification/voiceover-script.md`, new
`Tests/MetalUITests/AccessibilityAuditTests.swift`, new
`Backends/SDL/Tests/MetalUISDLTests/AccessKitControlsParityTests.swift`. If a
test here finds a lane-1 or lane-2 file wrong, the lane **stops on the
finding** (part 1's `IX-S` precedent) and the fix is ruled, not slipped in.

| id | test | red before because | mutation that must redden it |
|---|---|---|---|
| 3.1 | `aButtonsRoleShortcutAndStylePublishOnlyItsLabel` (B1 `.destructive`, B2 `.cancel`, B3 ⌘S, B4 `.defaultAction`, B5 `.plain`: each exactly `role .button, label, no value, no hint, actions [.press]`) | green today: written first and kept green | M3a: the shortcut published as the hint |
| 3.2 | `aTruncatedTextPublishesItsWholeString` (X1 `.lineLimit(1)` at width 60, X2 `.truncationMode(.head)`, X3 two lines, X4 a `Button` label; legacy `Text` and `ProposalText`) | green at lane 3's start (lane 2 built `ProposalText`'s record): **written first and kept green**, reddened only by the mutation | M3b: `Text.prepaint` passes its drawn line |
| 3.3 | `anAccessibilityFocusRequestWritesAFocusStateBinding` (F2, arm 13: `.focus(field B)` → next frame `@FocusState == .b`; a non-focusable id refused, the state unchanged) | green today (written first) | M3c: `reconcileFocusStates` skipped after a request |
| 3.4 | `aFocusStateWriteIsTheTreesFocusedElement` (F1: `focus = .b` from input → the published `focused` is B's id; AppKit's `accessibilityFocusedUIElement` is B's element) | green today | M3d: the builder publishes the frame's handed-in focus |
| 3.5 | `focusLeavesTheTreeWithItsIdentityAfterARename` (`IX-I`: a focused field renamed → `focused == nil`, AppKit posts `.focusedUIElementChanged` on the host) | green today | M3e: `IX-I`'s focus reset removed (restores `ID-R` item 9) |
| 3.6 | `everyPartOneControlPublishesItsRoleLabelValueAndActions` (Button, a `.plain` button, Toggle, Slider, Stepper, both `Picker` styles, TextField, TextEditor, a selectable `List` row, a `TapGesture` target, a `.focused` field: one table of expected neutral nodes) | green at lane 3's start: written first and kept green | M3f: `Toggle`'s value `"1"` → `"true"` |
| 3.7 | SDL `theControlsDemoTranslatesToAccessKitAsToAppKit` (the controls demo's tree through `AccessKitSnapshot.translate`: the same role/label/value/state table 3.6 asserts, AccessKit's vocabulary) | green at lane 3's start: written first and kept green | M3g: `.incrementor` → `.button` in AccessKit |
| 3.8 | `theDemoPublishesTheTreeTheVoiceOverScriptReads` (modal off: the tree's labels in order, as the script lists them; modal on: **only** `Close modal` and its descendants, the panel a `.group` with its folded label and a press, `isolatedOut == true`) | red: no isolation, the panel a button | M3h: the demo's `.isModal` removed |
| 3.9 | `theControlsDemoPublishesTheTreeTheVoiceOverScriptReads` (every control's label, role and value in the order the script walks them) | green at lane 3's start: written first and kept green | M3i: the demo's list built without `selection:` |
| 3.10 | `theVoiceOverScriptQuotesThePublishedTree` (parses every marker in `docs/verification/voiceover-script.md` and checks it against 3.8's, 3.9's or 3.11's tree: `<!-- ax: tree=… role=… label="…" value="…" selected=… enabled=… actions=… custom=[…] rows=… -->` compares **every field the step's spoken expectation names** — role, label, value, selected, enabled, press/increment actions, custom action names, a table's `rowCount` and realized-row count; `<!-- ax-absent: tree=… label="…" -->` asserts no published node carries that label (the modal step); `try #require` on each marker kind's count; a step whose spoken text names a fact no marker carries is labelled **(VoiceOver behaviour, not pinned)** in the script and the test counts those labels too, so an unlabelled unpinned claim is visible in review) | no script | M3j: change one label in the script (the test names the step); M3j′: an `ax-absent` marker naming a label that IS published (`Increment`) |
| 3.11 | `thePreviewAndTextInputDemosPublishTheTreesTheScriptReads` (`nativeLayoutPreviewContent()` with a client: its proposal texts in reading order, the grid row by row — `IX-AB`'s first production reader; the text-input demo: the two fields' roles, labels, values and the focused one) | red for the preview (nothing on the proposal path records until lane 2) — green at lane 3's start: written first and kept green | M3k: `ProposalText.prepaint` records nothing (the preview arm reddens, the text-input arm does not) |

**Must stay green, unedited**: `DemoFrameDeterminismTests` (`Expected.swift`
unedited: accessibility modifiers draw nothing),
`everyProductionTreeBuildsOnAOneMegabyteThread`, the demo modal's hit tests,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`.

## 8. The demo

**The demo's pixels do not move**: lane 3 adds two accessibility modifiers to
`demoModal()` and nothing else — `accessibilityAddTraits(.isModal)` on the
scrim (already declared, `Close modal`, so no new `$ax` slot) and
`accessibilityRemoveTraits(.isButton)` on the panel. **The panel gains one
declared `AXNode`**, so while the modal is up it writes **one more `$ax`
`StateTable` slot** (`AB-U`) — a named, user-invisible change to the state
table's population, ruled in `IX-X`; it moves no id path and no retention
threshold the demo reaches (the modal is up in one of the fourteen captured
states). **0 px against `31d3565` in all fourteen offscreen images**
(`docs/probes/demo-pixels/compare.sh`) at every lane; `Expected.swift`
unedited. The controls demo (not captured) is unchanged.

With a client active the demo's modal now reads, on both bridges, as one
root — the scrim, a button labelled `Close modal` — holding a group whose
label is the modal's two texts; everything behind the scrim is gone from the
tree until the modal closes (`IX-X`).

## 9. The VoiceOver script (lane 3, `IX-AE`)

`docs/verification/voiceover-script.md`, structure:

1. **Preamble**: what it validates (the bridge end to end, not SwiftUI
   parity), the build (`swift run -c release MetalUIDemo`, and
   `METALUI_CONTROLS_DEMO=1`), VoiceOver setup (⌘F5, VO = ⌃⌥, verbosity
   default, Full Keyboard Access off then on for the focus steps), and the
   rule that **the expected output is derived from the trees 3.8/3.9/3.11
   pin** — each step carries machine-checked `ax`/`ax-absent` markers (3.10)
   for every fact its expectation names (role, label, value, selected,
   enabled, actions, custom actions, a table's row counts, absence behind the
   modal); the spoken phrasing beside them is VoiceOver's usual order
   ("label, value, role") stated as an expectation, not a measurement; and
   anything the tree cannot carry — a `.valueChanged` announcement, what
   VoiceOver does at the last realized row, a VO key's effect — is labelled
   **(VoiceOver behaviour, not pinned)**, never presented as derived.
2. **Demo steps** (window "MetalUI — Milestones 1 to 3"): entering the window;
   VO-arrow through the sidebar and panel texts; the counter's `Decrement`/
   `Increment` buttons (VO-Space presses; the readout's new value is announced
   on `.valueChanged`); the focusable counter panel (VO-Shift-↓ interact,
   keyboard focus follows); the `List` (announced as an outline with its row
   count; VO-↓ through realized rows and **what happens at the last realized
   row** — divergence 32's recorded edge); **M** opens the modal — the tree is
   `Close modal` and the modal text only, VO cannot reach behind it; VO-Space
   on `Close modal` dismisses; the theme (Space) changes nothing spoken.
3. **Controls demo steps**: `Press me` (press, the `pressed N times` text
   updates), `Wi-Fi` check box (value), the slider (VO-↑/↓ increments of 0.1,
   spoken value), `Quantity` stepper (divergence 82: spoken as one labelled
   incrementor, not a sibling title), the `Flavor` segmented picker and the
   `Size` radio group (radio buttons, selected state), the chores' check boxes
   (`ForEach` over a binding), the selectable `List`: VO-Space presses a row
   (selects it), **and a selection made through the rotor/`AXSelected`**
   (VO-⌘-Space where offered) — divergence 83's retirement seen by a human.
3a. **Preview steps** (`METALUI_NATIVE_LAYOUT_PREVIEW=1`, `AB-Q`'s "the
   preview toggle is silent", closed by `IX-AB`): VO-arrow through the
   preview's texts, the grid row by row; every expectation from 3.11's tree.
4. **Focus steps** (`IX-AC`): VoiceOver's cursor and keyboard focus with
   "keyboard focus follows VoiceOver cursor" on; a `.focus` request moving the
   `@FocusState`-bound field (the text-input demo, `METALUI_TEXT_INPUT_DEMO=1`).
5. **Each step's result table**: expected, **observed (human)**, pass/fail,
   notes; a header block for the tester's name, date, macOS and VoiceOver
   versions, and a sign-off line. The `DD-U`/`DD-AD`/`DD-AE` contingent costs
   are each one step with the ruling named, so a human preferring SwiftUI's
   shape says so there.
6. **Closing section**: "Plan task 12 is ticked only after every step has an
   observed result and the Record phase re-reads this file" — the script
   itself states it cannot be completed by an agent.

## 10. For the Record phase

- **Divergences** (record §04's own dated section): **28 retires** (B6,
  `IX-Z`); **83 retires** (LA2–LB3 on AppKit, `IX-AA`); **95 added** (an
  isolated-out element a client holds refuses a press; SwiftUI's presses, M5,
  `IX-Z`); **27 amended** (MetalUI's gestures publish no press, as SwiftUI's
  G1–G7; `onClick` stays pressable), **32 amended** (`AXOutline` now; realised
  rows only, kept, owner none), **33 amended** (`.ignore`, a removed
  `.isButton`, a labelled `Rectangle`: `AXGroup` for SwiftUI's `AXUnknown`),
  **82 kept** (owner: the human VoiceOver run). Live **69 → 68**, next label
  **96**.
- **Declared but inert** (record §05): `AXNode.actions`' row **amended**
  (deprecated, still never read); **added**: `AccessibilityTraits.updatesFrequently`
  (published nowhere, as SwiftUI's on macOS, T10); `ButtonRole`'s row gains its
  accessibility evidence (B1, B2 — nothing published, as SwiftUI).
- **Human looks** (record §03): **the VoiceOver script run** (the task's own
  exit), plus the still-owed real-window capture.
- **CLAUDE.md**: "Accessibility" (children behaviour, hidden, traits, modal
  isolation, declared/named actions, press order, the proposal path, the
  neutral tree's new fields), "Hit testing" (a press is not a hitbox query
  under `allowsHitTesting(false)`), the guard list (`AccessibilityCompileGuards`),
  the `IX-` next-unused letter.
- **Plan**: a dated progress note — part 2 delivered, **task 12's box stays
  unticked until a human runs `docs/verification/voiceover-script.md`**.

## 11. Counts (expected, re-measured by each lane)

Baseline **1837** tests / **113** guards / SDL **22 + 27**. After the
critic round (`IX-AF` item 1): lane 1: **+8** root tests (1.1–1.4, 1.9, 1.10,
1.13, 1.14; the role table is a T row, 1.11 and 1.12 are renames) → 1845; SDL
**+4** (1.5–1.8). Lane 2: **+25** (2.1–2.12, 2.14–2.20, 2.22–2.24 = 22, and
G2.1–G2.3) → 1870, guards **+3** → 116. Lane 3: **+10** root tests (3.1–3.6,
3.8–3.11) → 1880; SDL **+1** (3.7). Expected close: **1880 tests, 116 guards,
SDL 22 + 32** — each lane re-takes the count and corrects this line in its
landing ruling.

**Lane 1 measured (`IX-AG`)**: root **1845** (1837 + 8), guards **113**
unmoved, SDL **22 + 31** (22 + 27 + 4) — as designed.

**Lane 2 measured (`IX-AH`)**: root **1870** (1845 + 25), guards **116**
(113 + 3), SDL **22 + 31** unmoved — as designed. `MemoryLayout<AXNode>.size`
113 → 121, `MemoryLayout<Handlers>.size` 440 → 448; smallest thread 624 KB,
unmoved.
