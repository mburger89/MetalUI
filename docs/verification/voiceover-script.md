# VoiceOver validation script — plan task 12

**Status: NOT RUN.** This script is written by an agent and **cannot be
completed by one**: an agent cannot run VoiceOver, hear it, or claim the
validation. Every **Observed (human)** cell below is empty on purpose. **Plan
task 12 is ticked only after a human has run every step, recorded every
observed result and signed off below, and the Record phase has re-read this
file** (ruling `IX-AE` item 3). Until then MetalUI does not claim
SwiftUI-level application behaviour for VoiceOver.

## What this validates

The **bridge end to end**: that what MetalUI publishes to an accessibility
client (the tree the tests pin) is what VoiceOver on macOS actually reads,
navigates and operates. It does **not** validate SwiftUI parity — that is the
probes' job (`docs/probes/swiftui-accessibility-part2.swift`,
`swiftui-controls-and-selection.swift`), each stated in the spec
`docs/superpowers/specs/2026-09-29-accessibility-design.md` and ruled in
`docs/superpowers/2026-09-29-interaction-decisions.md` (`IX-U`…).

**Where each expectation comes from.** Every step carries one or more
machine-checked markers — HTML comments (invisible when rendered; read the
source) whose body is `ax: step=… tree=… role=… label="…" value="…" …` or
`ax-absent: step=… tree=… label="…"`. Test 3.10,
`theVoiceOverScriptQuotesThePublishedTree`
(`Tests/MetalUITests/AccessibilityAuditTests.swift`), parses every marker and
checks it against the trees tests 3.8 (the demo), 3.9 (the controls demo) and
3.11 (the preview and the text-input demo) pin, built at the demo's own
920 × 560 window. A marker names one published node by its role, label,
value or row index, and every other field it carries — `selected`,
`enabled`, `focused`, `root`, `actions`, `custom`, `rows` (a table's logical
row count), `realized` (its realized rows), `children` — must equal that
node's. An `ax-absent` marker asserts no published node carries the label.

**The spoken phrasing is an expectation, not a measurement.** It follows
VoiceOver's usual order — label, value, role (AppKit's role description) —
and is what a tester should expect to hear, derived from the markers. Anything
the published tree cannot carry — an announcement on a value change, what
VoiceOver does at the last realized row, the effect of a VO key — is labelled
**(VoiceOver behaviour, not pinned)** and is never presented as derived; 3.10
counts those labels.

A step that fails is the script's purpose: record what was heard, and the
Record phase decides whether the expectation or MetalUI is wrong.

## Tester

| Field | Value |
|---|---|
| Tester | |
| Date | |
| macOS version | |
| VoiceOver version (VoiceOver Utility → About) | |
| MetalUI commit (`git rev-parse HEAD`) | |
| Hardware / display | |

## Setup

1. Build release: `swift build -c release` from the repository root.
2. VoiceOver: **⌘F5** toggles it. **VO** below is **⌃⌥** (Control-Option).
   Leave verbosity at its default (VoiceOver Utility → Verbosity → Default).
3. Full Keyboard Access (System Settings → Keyboard → Keyboard navigation):
   **off** for sections 1–3a, **on** for section 4.
4. In VoiceOver Utility → Navigation, "Keyboard focus follows VoiceOver
   cursor" **on** (section 4 relies on it).
5. Launch each window from a terminal, one at a time; each opens at
   920 × 560 — **do not resize** it before the steps that name a row count
   (the realized rows depend on the height):
   - demo: `swift run -c release MetalUIDemo`
   - controls: `METALUI_CONTROLS_DEMO=1 swift run -c release MetalUIDemo`
   - preview: `METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run -c release MetalUIDemo`
   - text input: `METALUI_TEXT_INPUT_DEMO=1 swift run -c release MetalUIDemo`
6. Click once in the window's content so it is key, then start VoiceOver
   (or start VoiceOver first — both orders activate the bridge, `AB-AB`).

Result column: **P** pass, **F** fail, **N/A** with a reason.

---

## 1. The demo — window "MetalUI — Milestones 1 to 3"

| Step | Action | Expected (spoken) | Observed (human) | P/F | Notes |
|---|---|---|---|---|---|
| D1 | Focus the window; VO-→ from the start of the content | "Library" (a text) <!-- ax: step=D1 tree=demo role=staticText value="Library" root=true actions=none --> | | | |
| D2 | VO-→ | "3" (the hero badge's text) <!-- ax: step=D2 tree=demo role=staticText value="3" --> | | | |
| D3 | VO-→ | the counter panel: a group, no label; VO-Shift-↓ interacts with it <!-- ax: step=D3 tree=demo role=group label="-" value="-" children=3 --> Interacting is (VoiceOver behaviour, not pinned) | | | |
| D4 | Inside the panel, VO-→ | "Decrement, button" <!-- ax: step=D4 tree=demo role=button label="Decrement" actions=press enabled=true --> | | | |
| D5 | VO-→ | "Count 0" <!-- ax: step=D5 tree=demo role=staticText value="Count 0" --> | | | |
| D6 | VO-→ | "Increment, button" <!-- ax: step=D6 tree=demo role=button label="Increment" actions=press enabled=true --> | | | |
| D7 | VO-Space on `Increment` | the counter reads "Count 1" when you VO-← back to it <!-- ax: step=D7 tree=demo-incremented role=staticText value="Count 1" --> Whether VoiceOver announces the change unprompted is (VoiceOver behaviour, not pinned) | | | |
| D8 | VO-Shift-↑ out of the panel, VO-→ | "Text renders" <!-- ax: step=D8 tree=demo role=staticText value="Text renders" --> then the paragraph "CoreText shapes this paragraph…" | | | |
| D9 | VO-→ to the list | an outline (AppKit publishes the `List` as `AXOutline`, `IX-AA`) with **500 rows** <!-- ax: step=D9 tree=demo role=table rows=500 realized=5 actions=none --> — the exact phrase ("outline, 500 rows" or similar) is (VoiceOver behaviour, not pinned) | | | |
| D10 | VO-Shift-↓ into the list, VO-↓ | "Row 1 of 500 — a scrollable list item", row 1 <!-- ax: step=D10 tree=demo role=row index=0 selected=false selectable=false actions=none --> <!-- ax: step=D10 tree=demo role=staticText value="Row 1 of 500 — a scrollable list item" --> | | | |
| D11 | VO-↓ repeatedly to the last realized row | row 5 ("Row 5 of 500 — …", index 4) is the last realized row at 920 × 560 <!-- ax: step=D11 tree=demo role=row index=4 --> <!-- ax: step=D11 tree=demo role=staticText value="Row 5 of 500 — a scrollable list item" --> <!-- ax-absent: step=D11 tree=demo label="Row 6 of 500 — a scrollable list item" --> **What VoiceOver does past it** — stop, scroll the list, wrap — is divergence 32's recorded edge: unrealised rows are not published (kept, owner none). Record exactly what happens: (VoiceOver behaviour, not pinned) | | | |
| D12 | With VO anywhere in the window, press **M** | the modal opens; VoiceOver's cursor can reach **only** `Close modal` and the modal's text <!-- ax: step=D12 tree=demo-modal role=button label="Close modal" root=true actions=press children=1 --> <!-- ax-absent: step=D12 tree=demo-modal label="Increment" --> <!-- ax-absent: step=D12 tree=demo-modal label="Library" --> <!-- ax-absent: step=D12 tree=demo-modal label="Row 1 of 500 — a scrollable list item" --> Whether VoiceOver moves its cursor into the modal by itself is (VoiceOver behaviour, not pinned) | | | |
| D13 | VO-→ / VO-← inside the modal | "Close modal, button"; then the panel: a group reading "Modal, Declared inside the list, painted over it, and clipped by the window rather than by the scroller." — **not** a button (`.isButton` removed, `IX-X` item 4; its press is kept, T3p) <!-- ax: step=D13 tree=demo-modal role=group label="Modal, Declared inside the list, painted over it, and clipped by the window rather than by the scroller." actions=press root=false --> | | | |
| D14 | Before opening the modal, park VO on `Increment` (D6); press **M**; then VO-Space **without moving VO** | nothing happens — a press on an element the modal isolated out is refused (divergence 95, `IX-Z` item 3; SwiftUI's held element still presses, M5). Pinned by 3.8's refusal arm; what VoiceOver says about the stale element is (VoiceOver behaviour, not pinned) | | | |
| D15 | VO-Space on `Close modal` | the modal closes; `Close modal` is gone and the counter is back <!-- ax-absent: step=D15 tree=demo label="Close modal" --> <!-- ax: step=D15 tree=demo role=button label="Increment" actions=press --> | | | |
| D16 | Press **Space** (theme) with VO off the counter | the theme changes; nothing spoken changes — no marker can carry "nothing new is announced": (VoiceOver behaviour, not pinned) | | | |

## 2. The controls demo — window "MetalUI — Controls"

| Step | Action | Expected (spoken) | Observed (human) | P/F | Notes |
|---|---|---|---|---|---|
| C1 | VO-→ from the start | "Controls" <!-- ax: step=C1 tree=controls role=staticText value="Controls" root=true --> | | | |
| C2 | VO-→ | "Press me, button" <!-- ax: step=C2 tree=controls role=button label="Press me" actions=press enabled=true --> | | | |
| C3 | VO-Space on `Press me`, then VO-→ | "pressed 1 times" <!-- ax: step=C3 tree=controls-pressed role=staticText value="pressed 1 times" --> and the button did **not** take keyboard focus (a button's press requests none, as its click does not) <!-- ax: step=C3 tree=controls-pressed role=button label="Press me" focused=false --> | | | |
| C4 | VO-→ | "Wi-Fi, checked, checkbox" (AppKit value 1) <!-- ax: step=C4 tree=controls role=checkBox label="Wi-Fi" value="1" actions=press --> VoiceOver's word for value 1 ("checked" / "on") is (VoiceOver behaviour, not pinned) | | | |
| C5 | VO-→ to the slider | "0.4, slider" — no label: the demo's slider declares none <!-- ax: step=C5 tree=controls role=slider label="-" value="0.4" actions=increment+decrement --> | | | |
| C6 | VO-↑ (increment) once on the slider | "0.5", and the text beside it reads "volume 5" <!-- ax: step=C6 tree=controls-slider-up role=slider value="0.5" --> <!-- ax: step=C6 tree=controls-slider-up role=staticText value="volume 5" --> That VoiceOver speaks the new value on `.valueChanged` is (VoiceOver behaviour, not pinned) | | | |
| C7 | VO-→ | "volume 4" before C6, "volume 5" after it <!-- ax: step=C7 tree=controls role=staticText value="volume 4" --> | | | |
| C8 | VO-→ to the stepper | "Quantity 2, 2, stepper" — **one** labelled incrementor; the title is folded into it, not a sibling text (divergence 82, kept, `DD-U` item 3 — SwiftUI publishes a sibling title) <!-- ax: step=C8 tree=controls role=incrementor label="Quantity 2" value="2" actions=increment+decrement children=2 --> <!-- ax-absent: step=C8 tree=controls label="Quantity" --> **Contingent cost (`DD-U` item 3):** if you would rather hear SwiftUI's sibling title, say so in Notes. The two arrow buttons inside it are unlabelled; what VoiceOver says for them is (VoiceOver behaviour, not pinned) | | | |
| C9 | VO-→ to the segmented picker | "Flavor, radio group" <!-- ax: step=C9 tree=controls role=radioGroup label="Flavor" children=3 --> | | | |
| C10 | VO-Shift-↓ into it, VO-→ through its options | "Vanilla, radio button", "Chocolate, selected, radio button", "Strawberry, radio button" <!-- ax: step=C10 tree=controls role=radioButton label="Vanilla" value="0" selected=false actions=press --> <!-- ax: step=C10 tree=controls role=radioButton label="Chocolate" value="1" selected=true actions=press --> <!-- ax: step=C10 tree=controls role=radioButton label="Strawberry" value="0" selected=false actions=press --> "n of 3" position phrases are (VoiceOver behaviour, not pinned) | | | |
| C11 | VO-Shift-↑, VO-→ to the radio group | "Size, radio group"; inside: "Small", "Medium, selected", "Large", each a radio button <!-- ax: step=C11 tree=controls role=radioGroup label="Size" children=3 --> <!-- ax: step=C11 tree=controls role=radioButton label="Medium" value="1" selected=true actions=press --> <!-- ax: step=C11 tree=controls role=radioButton label="Small" value="0" selected=false --> <!-- ax: step=C11 tree=controls role=radioButton label="Large" value="0" selected=false --> | | | |
| C12 | VO-→ through the chores | "Water the plants, unchecked, checkbox", "Take out the bins, checked, checkbox", "Call the plumber, unchecked, checkbox" (a `ForEach` over a binding) <!-- ax: step=C12 tree=controls role=checkBox label="Water the plants" value="0" actions=press --> <!-- ax: step=C12 tree=controls role=checkBox label="Take out the bins" value="1" actions=press --> <!-- ax: step=C12 tree=controls role=checkBox label="Call the plumber" value="0" actions=press --> | | | |
| C13 | VO-→ to the list | an outline with **40 rows**; 7 realized in its 120-point frame <!-- ax: step=C13 tree=controls role=table rows=40 realized=7 focused=false --> | | | |
| C14 | VO-Shift-↓ into the list, VO-↓ through the rows | "Row 0", "Row 1", "Row 2, selected", …; each row is selectable <!-- ax: step=C14 tree=controls role=row index=0 selected=false selectable=true actions=press --> <!-- ax: step=C14 tree=controls role=row index=2 selected=true selectable=true actions=press --> <!-- ax: step=C14 tree=controls role=staticText value="Row 2" --> | | | |
| C15 | VO-Space on "Row 4" | row 4 becomes the only selected row, and keyboard focus moves to the list — a press keeps the click's focus request (`DD-AE` item 2) <!-- ax: step=C15 tree=controls-row-pressed role=row index=4 selected=true --> <!-- ax: step=C15 tree=controls-row-pressed role=row index=2 selected=false --> <!-- ax: step=C15 tree=controls-row-pressed role=table focused=true --> **Contingent cost (`DD-AE` item 2):** if you would rather a VoiceOver press not move keyboard focus, say so in Notes | | | |
| C16 | On "Row 5", select it **through selection, not a press**: VO-⌘-Space where VoiceOver offers it (or the Item Chooser / rotor's select) | row 5 becomes the only selected row — AppKit's `setAccessibilitySelected` reaches the list (divergence 83 retires, `IX-AA`) <!-- ax: step=C16 tree=controls-row-selected role=row index=5 selected=true selectable=true --> <!-- ax: step=C16 tree=controls-row-selected role=row index=4 selected=false --> Which VO command VoiceOver maps to a selection on an outline row is (VoiceOver behaviour, not pinned) — note the command you used | | | |
| C17 | Nothing in the controls demo is disabled | **Contingent cost (`DD-AD` item 1):** a disabled picker keeps its options published, disabled, as SwiftUI's PA4 does; no window here shows a disabled control, so this cannot be heard in this run — mark N/A unless a disabled control is added; the fact is pinned by the root suite's 1.24, not by a marker here | | | |

## 3a. The preview — window "MetalUI — Native Layout Preview"

| Step | Action | Expected (spoken) | Observed (human) | P/F | Notes |
|---|---|---|---|---|---|
| P1 | VO-→ from the start | "Native proposal text measures and wraps from the parent width." <!-- ax: step=P1 tree=preview role=staticText value="Native proposal text measures and wraps from the parent width." root=true --> | | | |
| P2 | VO-→ | "Proposal scroll content stays intrinsically tall." <!-- ax: step=P2 tree=preview role=staticText value="Proposal scroll content stays intrinsically tall." --> | | | |
| P3 | VO-→ again | nothing further: the rectangles, the tapped toggle and the grid's tapped cell publish no node (a tap publishes no press, as SwiftUI's G1–G7; the grid's texts would flatten row by row, but it holds none, `IX-AB`). `AB-Q`'s "the preview toggle is silent" is answered as SwiftUI's own silence <!-- ax: step=P3 tree=preview role=staticText value="Proposal scroll content stays intrinsically tall." children=0 --> Whether VoiceOver plays its end-of-content sound here is (VoiceOver behaviour, not pinned) | | | |

## 4. Focus — window "MetalUI — Text Input" (Full Keyboard Access on)

| Step | Action | Expected (spoken) | Observed (human) | P/F | Notes |
|---|---|---|---|---|---|
| F1 | VO-→ from the start | "Text input" <!-- ax: step=F1 tree=textinput role=staticText value="Text input" root=true --> | | | |
| F2 | VO-→ | "Type here: an input method, a selection, copy and paste, text field" (the placeholder is the label; the value is empty) <!-- ax: step=F2 tree=textinput role=textField label="Type here: an input method, a selection, copy and paste" value="" focused=false --> | | | |
| F3 | With "Keyboard focus follows VoiceOver cursor" on, rest VO on the first field | keyboard focus moves to it — VoiceOver's focus request (`AXFocused`) moves window focus, and the tree's focus follows <!-- ax: step=F3 tree=textinput-focused role=textField label="Type here: an input method, a selection, copy and paste" focused=true --> Type a letter: it appears in the field and in the echo text below. The caret announcement is (VoiceOver behaviour, not pinned) | | | |
| F4 | VO-→ | "A second field — Tab does not move here; click it, text field" <!-- ax: step=F4 tree=textinput role=textField label="A second field — Tab does not move here; click it" value="" --> | | | |
| F5 | VO-→ | "(the first field echoes here)" before F3's typing, the typed text after <!-- ax: step=F5 tree=textinput role=staticText value="(the first field echoes here)" --> | | | |
| F6 | VO-→ | "A multi-line editor: return, up and down, the wheel, text area" <!-- ax: step=F6 tree=textinput role=textArea label="A multi-line editor: return, up and down, the wheel" value="" --> | | | |
| F7 | A `@FocusState`-bound field | a `.focus` request writes the `@FocusState` bound to the field and a `@FocusState` write is the tree's focus (`IX-AC` item 3, F1/F2) — no demo window binds a `@FocusState`, so this is pinned by the root suite's 3.3 and 3.4 only; mark N/A | | | |

---

## Sign-off

- [ ] Every step above has an **Observed (human)** entry and a P/F/N/A.
- [ ] Every F is described in Notes precisely enough to reproduce.
- [ ] The contingent-cost steps (C8 `DD-U` item 3, C15 `DD-AE` item 2, C17
      `DD-AD` item 1) record the tester's preference, if any.

Tester's signature and date: ______________________

## Closing

**Plan task 12 is ticked only after every step has an observed result and the
Record phase re-reads this file.** No agent writes an observed result: this
script was prepared by an agent from the trees the tests pin, and it is the
human's run — not the agent's preparation — that validates MetalUI with
VoiceOver. An agent that reads this file with any Observed cell empty must
leave task 12 unticked.
