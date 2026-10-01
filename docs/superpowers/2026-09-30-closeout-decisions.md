# Replacement closeout — decisions (plan task 15)

Rulings for plan task 15 of
[`plans/2026-09-12-swiftui-alignment.md`](plans/2026-09-12-swiftui-alignment.md),
the replacement closeout: re-run the inventory so no public behaviour is
unclassified, settle tasks 4 and 5, dispose of every item addressed to "plan
task 15", write migration guidance and public API documentation, collect the
human visual checks, and re-confirm that the retired CSS engine has no
production caller and no browser golden remains. Spec:
[`specs/2026-09-30-closeout-design.md`](specs/2026-09-30-closeout-design.md).
Record: [`../record/66-closeout.md`](../record/66-closeout.md).

Prefix **`CX-`**, lettered. **Next unused: `CX-R`.** (This line moves in the
commit that appends a ruling; read the last `## CX-` heading.)

Branch `feat/closeout` from `1b093b8` (master: task 13 merged, task 14's
record). Baseline at `1b093b8`: **1961 tests in 3 suites, 0 goldens, 119
typecheck guards**, 72 live divergences (next label 100).

---

## CX-A — the inventory is a census of every public declaration, mapped to five classes, with a mechanical "unmapped" check

**Ruling.**

1. **The census.** `docs/probes/closeout-public-api.sh` prints one line per
   `public`/`open` declaration in every `Sources/` target that ships in a
   library product or is re-exported by `MetalUI` (fifteen targets; the
   script's header names them). Its committed output,
   `docs/probes/closeout-public-api.tsv`, reads **1871 declarations** at
   `1b093b8` (MetalUI 1258, MetalUILayout 95, MetalUICore 83, MetalUIPlatform
   78, MetalUIScene 77, MetalUIText 62, MetalUIPortableText 50,
   MetalUITextSystem 35, MetalUIRender 35, MetalUIFreeType 29,
   MetalUIHarfBuzz 24, MetalUIDemoContent 24, MetalUISystemFonts 13,
   MetalUIAppKit 5, MetalUIPrimitives 3); 0 rows with an unattributed owner
   (`?`). Re-run at the design session: byte-identical to the committed TSV.
2. **Five classes.** Every census row belongs to exactly one inventory
   **family** (a type with its members, or a modifier group), and every
   family to one class:
   - **A — SwiftUI-aligned**: evidence is a probe arm (file + arm id, output
     in the probe's header) **and** a discriminating MetalUI test (name, which
     must resolve by grep in `Tests/`). A family aligned except for a numbered
     divergence is A with the label listed.
   - **D — documented divergence**: the record §04 label(s) and the live pin.
   - **M — MetalUI-only by design**: a ruling id that says why (no SwiftUI
     counterpart: the three-phase element protocols, the legacy CSS-derived
     vocabulary, the gpui keymap, the theme, every backend/infrastructure
     target).
   - **X — deprecated**: the replacement spelling (from its `@available`
     message).
   - **R — documented absence**: a SwiftUI API MetalUI does not offer, with
     the ruling that says so and its owner (usually none). R rows are not
     census rows — they answer "what about SwiftUI's X?" for a reader, and
     are listed in the same table so the public docs carry them.
3. **The mechanical check.** `docs/probes/closeout-inventory-map.tsv` maps
   census rows to family ids (by target + file, narrowed by owner where one
   file holds two families), and `docs/probes/closeout-inventory-check.sh`
   joins it with the census and prints (a) every census row no family claims,
   (b) every family with no class, (c) every class-A row whose test name does
   not resolve in `Tests/` or whose probe file does not exist. **All three
   must print nothing** at the branch tip. This is what "no public behaviour
   is unclassified" means operationally; the record §66 table is its
   human-readable form.
4. **Behaviour, not only declarations.** A family's row states the
   behaviour it is classified on; where members of one family differ in class
   (e.g. `StyledElement`'s modifier extension: `.padding` A, `.margin` M,
   `.width` X), the family splits into per-modifier rows.

**Evidence.** The census script and its TSV (committed by the interrupted
predecessor session, re-run identical here); the 888 public declarations
without a doc comment counted at the same commit (`CX-K`).

**Cost if wrong.** A family drawn too coarsely can hide one member whose
behaviour differs from the rest; item 4 and the reviewer's spot check of the
largest families (`Box.swift` 84, `NativeElements.swift` 107, `Passes.swift`
49, `Gesture.swift` 43, `ElementGroup.swift` 41) bound it. A check script
that only greps names cannot see a wrong classification — it sees a missing
one.

---

## CX-B — tasks 4 and 5 are settled clause by clause: both ticked, with two new order pins for task 5

**Ruling.**

1. **Task 4 ("Finish frame and sizing semantics") — every clause holds.**
   - *Specify and implement `.frame(width:height:alignment:)`, optional axes,
     min/ideal/max, alignment, chained-frame ordering* — `FR-A`…`FR-V`
     (record §14), four probes, 71 arms; legacy `ideal` traps by design
     (divergence 39, kept, documented).
   - *Move `width`, `height`, min/max sizing … onto that representation;
     deprecate APIs whose observable meaning cannot match SwiftUI* — stage 8
     (`FR-I` amended by `LR-ER`…`LR-FB`, record §50): the eight
     `StyledElement` sizing modifiers deprecated toward `.frame`, every
     in-repo caller converted; `frame()` deprecated (`FR-J`).
     `flexBasis(fraction:)` joins them at this task (`CX-C`).
   - *The single semantic path* — stage 9 deleted the CSS engine (record
     §51); a legacy `.frame` lowers onto the kernel's frame
     (`FrameLayer.swift`), the only layout path; the closing check
     `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` pins it.
   - The progress note's "also open" items: the greedy finite maximum and the
     single-axis infinite maximum on the legacy path are answered by the
     lowering (`CN-Q` → `LR-L`, confirmed by stage 11's branch check,
     `LR-GG` item 5); the release-window captures were taken 2026-09-17.
2. **Task 5 ("Finish outer modifiers and modifier order") — every clause
   holds once two orders are pinned.**
   - *Padding migration* — done 2026-09-16 (`OM-D`, `OM-E`).
   - *Audit background, overlay, border, corner/clip shape, opacity, hit
     testing, focus drawing, content shape* — done (`OM-`), with the gaps
     the note named since filled: legacy `.overlay` (stage 11, `LR-FX`),
     `.background(alignment:content:)` (`ID-J`), clip shapes (task 11 part
     2, `TE-AJ`), `contentShape<S: Shape>` (task 12, `IX-L`).
   - *Pin whether each wraps, distributes through a `Component`, or affects
     only paint* — the proposal column the note called "never collected" is
     collected: `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`
     (`OuterModifierMatrixTests`, stage 7b lane 3, record §49 N3.x).
   - *Test order-sensitive chains* — every order the note listed is pinned
     except `swiftui-border-clip-paint.swift` **C3**
     (`.cornerRadius(12).background(red)`: the background is square) and
     **D1** (`.cornerRadius(12).border(blue, 4)`: a square border over the
     rounded fill). Lane 1 adds both on the proposal path (tests **1.3,
     1.4** — corrected by `CX-P` item 1), where `.cornerRadius` is a clip
     layer (`TE-AJ`), **and** pins the legacy path's answer to the same two
     chains (tests 1.3L, 1.4L, `CX-P` item 2): record §04's row 47 itself
     reads "C3/D1 orders unpinned", so "already documented" was not true of
     the legacy order until those pins land and row 47 is amended to state
     the legacy answer.
   - *The focus ring's look* is a human check (`CX-M`), not a clause of the
     task's text, which asks for an audit and pins — the same reading
     `AN-AG` made for task 13.
3. **Both boxes are ticked by the Record phase**, with a dated note citing
   this ruling, once lane 1's two pins are green and mutated.

**Evidence.** The plan's two progress notes; records §14–§17, §49, §50, §51,
§54; `swiftui-border-clip-paint.swift`'s header (C3, D1 lines).

**Cost if wrong.** A clause read as closed that is not would leave a gap the
definition of done does not allow; every citation is a test name or a record
section the reviewer can open.

---

## CX-C — no deprecated public spelling is removed at closeout; `flexBasis(fraction:)` is deprecated; `ModifiedElement` stays undeprecated

**Ruling.**

1. **Removal is not this task's.** MetalUI has no release cadence and no
   external-caller census; a deprecated spelling that still does what its
   message says costs a warning, and removing it costs every caller a
   compile error for no behaviour gained. So the eight deprecated sizing
   modifiers, `width/height(fraction:)` and the `percent:` renames,
   `frame()`, the `Native…` aliases and `AXNode.actions`/`AXActionKind` all
   **stay deprecated**, each an X row of the inventory with its replacement.
   This disposes `LR-FN` item 5, `LR-FR` F5's "release decision", `IX-Y` item
   4's "until plan task 15 removes the field" and stage 11's §10 row.
2. **`flexBasis(fraction:)` is deprecated** (`flexBasis(percent:)` already is,
   as its rename). Every fraction is a percentage basis, which the lowering
   reports by name and a production frame traps on (`LR-FO` item 1) — the
   same reason `width(fraction:)` was deprecated at stage 8 (`LR-EU`); stage
   8 left it undeprecated only because its spec listed the item modifiers as
   out of scope (`LR-ER` item 2). Message: no SwiftUI counterpart, traps by
   name under the proposal layout, declare a length or a `.frame`. Lane 1
   measures whether `fraction: 0` traps too and words the message by the
   measurement. **T row**: `ContainerCompileGuards`' G4 arm that asserts
   `flexBasis(fraction:)` is *not* deprecated inverts (named for this
   ruling); its two in-repo callers (`ModifierTests`' row,
   `LoweringItemTests`' report arm) move to a `cssFlexBasis(fraction:)`
   helper in `CSSSizing.swift` / the `DeprecatedSpelling` witness, so the
   0-`warning:` baseline holds.
3. **`ModifiedElement` stays an undeprecated typealias** (an M row): it
   names the legacy arm of `ModifiedContent<Content, ModifierLayer>`, has no
   behaviour, and deprecating it warns at every in-repo annotation for a
   spelling choice.

**Evidence.** `Box.swift`'s `@available` attributes at `1b093b8`;
`ContainerCompileGuards.swift` lines 128–155; `LR-ER`, `LR-EU`, `LR-FO`.

**Cost if wrong.** If an external caller relied on `flexBasis(fraction:)`
compiling warning-free, they get a warning pointing at a spelling that traps
in production anyway. If a later release wants the deprecated spellings
gone, removal is a mechanical commit with the X rows as its list.

---

## CX-D — `Box`'s public `style:` parameter is narrowed to `package`

**Ruling.** Since stage 10 every stored `Style` field is `package`, so an
external caller can pass only `Style()` to `Box(style:…)` — a parameter that
configures nothing (`LR-FR` F5; record §05's inert row). The three public
`Box` initialisers split: a **public** `init(decoration:content:)` /
`init(decoration:@ElementBuilder content:)` / `init(decoration:)` with no
`style:` parameter, and a **`package`** `init(style:decoration:…)` (no
default for `style`, so no call is ambiguous) that every in-package caller —
251 `Box(style:`/`Stack(style:` sites at `8095fd9`, the demo's one — keeps
using unchanged. `Stack`'s public initialiser has no `style:` and is
untouched; `public var style` (a `StyledElement` requirement over an opaque
type) is untouched. **New guard** `aPlainImportCannotPassBoxAStyle`
(`CloseoutCompileGuards.swift`, whole-file `typecheckFile`): `Box(style:
Style())` fails to compile from a plain `import MetalUI`; the control,
`Box(decoration: Decoration()) { }` and `Box()`, compiles. Record §05's row
is deleted at the Record phase (fixed, not narrowed). **Migration note**:
`Box(style: Style(), decoration: d)` → `Box(decoration: d)`.

**Evidence.** `Box.swift:45`, `:53`, `:162` at `1b093b8`; `LR-FR` F5.

**Cost if wrong.** An external `Box(style: Style())` stops compiling — the
call meant nothing. If the split makes an in-package call ambiguous, the
build says so at once.

---

## CX-E — divergence 52 (`Row`/`Column` default spacing 0) is kept, owner none

**Ruling.** `Row`/`Column` keep their CSS default gap of 0 where
`HStack`/`VStack` default to SwiftUI's 8 (`CN-P` 1). The legacy containers
are MetalUI's CSS-derived vocabulary by design (`CN-A`: they keep their CSS
algorithms); the SwiftUI-aligned spelling exists and is the migration path.
Changing a public default under every default-gap caller's pixels silently is
worse than documenting it — the reason `LR-EY` moved it here rather than
deciding it inside a 0-px stage. Kept, owner **none**; the migration guide
names it in its `Row {}` → `HStack {}` row ("set `spacing: 0`, or accept 8").

**Evidence.** Probe `swiftui-stack-algorithms.swift` S; live pin
`aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault`
(`LoweringDistributionTests`) — record §04's row still names
`aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`,
which no longer exists in `Tests/` (retired at stage 7b); the Record phase
corrects the row (`CX-P` item 3).

**Cost if wrong.** A reader porting `Row` to `HStack` still sees 8 points
appear; the migration row is where they will look.

---

## CX-F — divergence 85 (an optional `@State` reads `nil` before its first write) is fixed and retires

**Ruling.** `StateTable.peek(_:as:)` returns `storage[id]?.value as? S`; for
an optional `S` and an **absent** entry, `nil as? S` succeeds as
`.some(nil)`, so `State.wrappedValue`'s `?? initialValue` never runs and
`@State var x: Int? = 2` reads `nil` until its first write. SwiftUI reads
`2` — **measured at the critic round** (`docs/probes/swiftui-closeout.swift`
group O, two runs byte-identical, recorded in its header): O0 (a
non-optional `@State var n: Int = 2`, positive control) reads 2, O1n
(`Int? = nil`) reads nil, **O1 (`Int? = 2`) reads 2**, and O2 (O1 after a
write of `nil`) reads nil — the separating arm. **Fix**: `peek` distinguishes absent from stored —
`guard let entry = storage[id] else { return nil }; return entry.value as?
S`. Every other `peek` caller reads a non-optional `S` (`FocusStateValue`,
`ListOrigin`, `AXNode`, `Bool`, the animation states), whose answer cannot
change; lane 1 re-reads each to confirm. Tests 1.1 (red at `1b093b8`) and 1.2
(the separating arm). **Divergence 85 retires** (72 → 71 before `CX-G`).
**Migration note**: an optional `@State` with a non-`nil` default now reads
its default before the first write; code that worked around the bug by
writing the value first is unaffected, and the controls demo's `Set`
workaround stays (it is correct either way, and re-spelling it would move a
look nobody has taken).

**Evidence.** `StateTable.swift:740`, `State.swift:100` at `1b093b8`;
`DD-AG` item 3, `DD-AI` item 2; record §04's 2026-09-28 section.

**Cost if wrong.** A caller who read `nil` on purpose from an
optional-with-default (no reason to) sees the default. `$anim`/`$focus`/
`$ax` slots never store an optional, so retention is untouched —
`theSevenRetentionSlotsAreMutuallyDistinct` stays green unedited.

---

## CX-G — the divergence table is re-read once against one criterion and published as one current list

**Ruling.**

1. **Criterion for retiring a row by re-reading** (no code change): a row
   retires when, in the only engine since stage 9, (a) its live pin asserts
   SwiftUI's answer, (b) the probe arm the row cites agrees with that answer,
   and (c) no reachable public spelling still produces the old answer.
   `LR-GG` item 5 named **35, 53 and 55** as candidates ("SwiftUI's answer …
   already"); lane 2 applies the criterion to them and to every other row,
   recording per row: pin (grep-resolved), probe arm, verdict. A row failing
   (c) — e.g. a legacy spelling that still answers the CSS way — stays, its
   wording narrowed to that spelling.
2. **One public list.** `docs/divergences.md` carries every live divergence
   after this task: label, one-sentence fact, the SwiftUI answer, the
   MetalUI answer, ruling, live pin, owner. Record §04 keeps its dated
   history; the public file is the current state (definition of done:
   "each unsupported or intentional divergence is prominent in the public
   documentation"). Retired labels are listed once at the end, never reused.
3. **Owners re-read.** Every live row whose owner reads "plan task 15" or a
   ticked task is re-owned: 61 and 62 → none (`CX-H`), 85 → retired
   (`CX-F`); any other is named in record §66 with its new owner.

**Evidence.** Record §04's 2026-09-24 (stage 9) and 2026-09-25 (stage 11)
sections; `LR-GG` item 5.

**Cost if wrong.** A row retired on a misread pin hides a live difference;
(a)–(c) and the per-row record make each retirement checkable. Labels are
never reused, so a wrongly retired row can be restored under its own number.

---

## CX-H — the grid model's residual disagreements (divergences 61, 62): the baseline holds; kept, owner none

**Ruling.** `GR-AA` asked task 15 to re-run the GZ table and the divergence
corpus against `GR-B`'s baseline. Re-run at this design session
(`xcrun swiftc -O docs/probes/swiftui-grid.swift`, screen unlocked, macOS 27.0):
the default run's stdout hashes **5d2030386ae93bba614ff68f203e8d56a1bf284bad9912232f261088172f61ba**,
byte-identical to the committed `swiftui-grid-default-run.txt`'s recorded
hash (GZ1 1000/1000, GZ2 988/1000, GZ3 469/500, GZ4 441/500, GZ5 482/500,
GZ6 376/500, GZ7 231/300, GZ8 662/1000, GZ9–GZ12 300/300 each, GZ0 control
212/300); the `divergences` mode prints the committed 65 cases line for line
(the committed file adds only its comment header). The kernel's agreement
with the model is pinned by the corpus tests in the suite (green at
`1b093b8`). **No count fell below the baseline.** Closing the gap means
replacing the reference model with SwiftUI's undocumented span/priority
rules — a layout project of its own, not a closeout edit — so 61 and 62 are
**kept, owner none**, and the GZ table stays the dated baseline any later
change may not lower.

**Evidence.** The two runs (record §66 §2); `GR-AA`, `GR-B`, `GR-N`.

**Cost if wrong.** None new: the honest bound `GR-O` 2 states (a
regression missing every pinned case is caught only at a re-run) stands,
and this ruling dates the latest re-run.

---

## CX-I — every other item addressed to plan task 15, disposed

**Ruling** (the full table with sources is record §66 §3):

1. **The per-entry memory harness and the settled-store allocation count**
   (`AN-AJ`, record §64 §11): taken once, as a gated measurement test
   `measureSettledStoreEntryAllocations` (`METALUI_STORE_ALLOC_MEASURE=1`,
   `malloc_logger`, suite configuration, `--no-parallel`), its output
   recorded in record §66 — a figure, not a gate, like the other `measure…`
   tests. The arithmetic bound already carried in `AnimatedStyle.swift` is
   checked against it and the doc comment's "re-owned to plan task 15"
   replaced by the figure.
2. **`switch` transitions** (record §64 §14, "not pinned"): probe arm SW1
   (a `switch` branch change with `.transition(.move(edge: .leading))` under
   `withAnimation` records an offset; SW1n without animation records
   nothing) and test **1.5** (corrected by `CX-P` item 1).
3. **Documented absences, owner none** (R rows of the inventory and of the
   public docs): Increase Contrast and the other system accessibility
   settings (`colorSchemeContrast`, reduce transparency, differentiate
   without colour); a readable `colorScheme` (`TE-AO` item 1); an animated
   `scrollTo`/scroll offset (SwiftUI unmeasured); two-axis scrolling (`CN-M`)
   and `scrollPosition(id:)` (`DD-AB` items 5–6); `LazyVGrid`/`LazyHGrid`
   (`GR-L`, stage G2 unblocked, unbuilt); `ButtonStyle`/`PrimitiveButtonStyle`
   as open protocols, `.borderedProminent`, `.link`, `.toggleStyle`,
   `.pickerStyle(.menu)` (`IX-E`, `IX-M`); `sequenced`, `@GestureState`,
   `GestureMask` (`IX-B`); `Path`, gradients, `StrokeStyle`, SF Symbols
   (spec `2026-09-28-shapes-and-rendering-design.md` §9); elliptical
   corners (`RoundedRectangle(cornerSize:)`) and `UnevenRoundedRectangle`
   (the same spec's §9 table, "plan task 15's" — found by the critic
   round's grep, `CX-P` item 6). Each is one row,
   none a numbered divergence (nothing exists to diverge).
4. **Guards skipping under the default build system** — `CX-J`.
5. **Missing doc comments** — `CX-K`.
6. **The older milestones' "Carried…" sections** (m0, m1a, box model,
   alignment, flex sizing, wrapping, element pipeline, content sizing,
   frame sizing, animation): lane 2 re-reads each and records per item
   "closed by <evidence>" or an R/D row; none is expected open (every one
   predates the engine replacement that deleted its subject).

**Cost if wrong.** An item missed here is a row the inventory check (`CX-A`)
does not catch, because it is not a declaration; the grep of "task 15"
across `docs/` and `Sources/` (record §66 §3, its command recorded) is the
list, and a re-run of it must find nothing unaddressed.

---

## CX-J — a typecheck guard that would skip fails when guards are required, and macOS CI requires them

**Ruling.** Every guard returns `true` for free when
`.build/<triple>/debug/Modules` is not where `#filePath` expects — under the
default build system, a `--scratch-path` or `-c release` — and the macOS CI
job runs `swift build -v` / `swift test -v` under the default build system,
so **none of the 119 guards has ever run in CI**. Fix in two parts:
(1) `theTypecheckGuardsRanWhereTheyAreRequired`
(`Tests/MetalUITests/CloseoutCompileGuards.swift`): when
`METALUI_REQUIRE_GUARDS=1`, `#expect(canTypecheck)` naming the searched
directory; otherwise it records nothing (the env var is the gate, as the
`measure…` tests' are). (2) `.github/workflows/swift.yml`'s macOS job builds
with `swift build --build-system native --build-tests` and tests with
`METALUI_REQUIRE_GUARDS=1 swift test --build-system native --no-parallel`.
Red-before: `METALUI_REQUIRE_GUARDS=1 swift test --filter
theTypecheckGuardsRan…` under the **default** build system fails; under
native it passes. The `FR-J no-argument frame: succeeded=` grep stays the
local tell. Linux and Windows jobs are untouched (guards skip off macOS by
design, `PC-C`).

**Evidence.** `Tests/MetalUITestSupport/Typecheck.swift` lines 23–90;
`.github/workflows/swift.yml` lines 15–22; record §64 §11.

**Cost if wrong.** The macOS CI job takes about a minute longer (119 ×
≈0.46 s). If the native build system misbehaves on the CI image, the job
fails loudly — the point.

---

## CX-K — every public declaration that is not a protocol-requirement witness carries a doc comment

**Ruling.** At `1b093b8`, **888** of the 1871 census rows have no `///`
directly above them (attributes skipped); **592** remain once
protocol-requirement witnesses are exempted — names that implement a
documented requirement and inherit its documentation:
`requestLayout`, `prepaint`, `paint`, `requestGroupLayout`, `prepaintGroup`,
`paintGroup`, `requestProposalLayout`, `requestProposalGroupLayout`,
`sizeThatFits`, `placeSubviews`, `geometry`, the associated-type witnesses
`Layout`/`GroupLayout`/`Prepaint`/`PrepaintState`/`LayoutState`/
`GroupPrepaint`, the `StyledElement` storage witnesses `style`/
`decoration`/`elementID`/`handlers`, and `description`, `hash`, `==`,
`rawValue`, `body`, `_recognizers`. `docs/probes/closeout-undocumented.sh`
encodes exactly this rule and must print **0** at the branch tip. A doc
comment states what the declaration does and, where it matters, its SwiftUI
counterpart or divergence label — never a restatement of its name. Lane 1
documents the files it edits; lane 3 every other file. **Doc-comment-only
edits move no behaviour**: `git diff` of lane 3's commits filtered to
non-comment lines must be empty.

**Cost if wrong.** A wrong doc comment misleads; each cites a ruling or a
divergence label where it makes a claim, so a reviewer can check it.

---

## CX-L — migration guidance, an API overview and the divergence list are three public documents

**Ruling.** Under `docs/` (none exists at `1b093b8`):

1. **`docs/migration.md`** — (a) legacy → SwiftUI vocabulary: `Box` →
   `VStack`/`ZStack`/`.frame`/`.padding`/`.background`; `Row`/`Column` →
   `HStack`/`VStack` (spacing 0 vs 8, divergence 52; cross-axis centring;
   `flexGrow` → `Spacer`/`.frame(maxWidth: .infinity)`); `Stack` → `ZStack`
   (fit-content vs proposal, divergence 53/its `CX-G` verdict); legacy
   `ScrollView` → `ProposalScrollView`; legacy `.frame` → proposal `.frame`;
   the eight sizing modifiers → `.frame` by `LR-ES`'s recipe R1–R8, with
   `.frame(minHeight: 0, maxHeight: .infinity)` for `LR-ET`; `margin` →
   `.padding` outside; `Text.proposalLayout()`'s drops. (b) **every breaking
   or behaviour change since 2026-09-12**, collected from the rulings'
   migration notes by grep (`migration note`, `**Migration`) and from the
   public-API removals the records list (e.g. `KeyBinding`'s `Binding`
   alias, `EV-N`/`DD-D`; `Rectangle.color` → `ColorToken?`, `TE-AC`; the
   `Style` fields deleted/narrowed, `LR-FM`; the public registrars,
   `LR-FF`; focus leaving with identity, `IX-I`; one structural slot per
   `if`/`for`, `ID-B`; the `VerticalAlignment` cases, `TE-K`; this task's
   `CX-C`, `CX-D`, `CX-F`), each with its old spelling, new spelling and
   ruling.
2. **`docs/api-overview.md`** — a concise map of the public surface by area
   (app and window; elements and builders; the SwiftUI-vocabulary layout
   types; the legacy vocabulary; modifiers; state, binding, environment;
   identity; controls; text; shapes and images; input, gestures, focus;
   accessibility; animation and transitions; backends), each area naming its
   types, its class from the inventory and its pointer into the docs.
3. **`docs/divergences.md`** — `CX-G` item 2, plus the R rows.

README's links to these three (and the human checklist) are added at the
Record phase, which is when README may be edited.

**Cost if wrong.** A migration row missed leaves a caller with a compile
error and no pointer; the grep commands are recorded in record §66 so the
collection can be re-run.

---

## CX-M — the human visual checks are one checklist; the real-window default/preview capture is taken; task 15 is not ticked until the user runs the checklist

**Ruling.**

1. **`docs/verification/human-checks.md`** collects every look owed across
   record §03 and the task records into one runnable list: each check says
   what to run (`swift run MetalUIDemo` with its env var, keys **M**,
   **Space**, **F**/**Esc**, **=**/**-**, **A**, **Q**), what to look at,
   what the expected answer is and where it was pinned headless, and a box
   to tick. Groups: the demo-layout looks stage 6b re-opened (sidebar 196,
   animation panel 320, modal card height, list-row labels centred); the
   paragraph under **A** at 920×560 and `controlSize`'s drawn font (task 11
   part 1); a `displayScale` change across two displays and the
   key/active/inactive looks (task 9, task 12 part 1); the controls demo by
   pointer and keyboard and the five roles under VoiceOver (task 10 part 2);
   wheel under `.disabled` (task 10 part 1); shapes, strokes, clips and
   images through a real renderer (task 11 part 2); gestures on a trackpad,
   the pressed/disabled/inactive looks, the focus ring, a real key window
   (task 12 part 1); the VoiceOver script itself
   (`docs/verification/voiceover-script.md`, task 12 part 2, which the
   checklist links rather than copies); transitions, Reduce Motion's
   cross-fade and `.scale`'s mid-flight glyphs (task 13); a grid on screen
   (`GR-N`); the spring's overshoot and reverse (animation milestone). Lane 3
   builds the list from record §03 by grep and states the source section of
   every item, so none is lost.
2. **The real-window capture, taken at design time.** The lock probe read
   unlocked (2026-09-30 23:41 PDT: no `CGSSessionScreenIsLocked` line,
   `displayAsleep main: 0`). `capture.sh <scratch> 6c961e3 1b093b8` read
   every a-vs-b pair 0, **6c961e3 → 1b093b8 default 0 and preview 0
   differing**, control default-vs-preview 958986 — so plan task 13 and
   task 14 moved no pixel of the real default and preview windows since the
   last unlocked reading. The Record phase re-runs the lock probe and, if
   unlocked, `capture.sh <scratch> 1b093b8 <HEAD>`.
3. **Ticking.** Task 15's box is ticked only when every agent-doable clause
   holds with evidence **and** the user has run the checklist and the Record
   phase has re-read it. Expected outcome of this run: a dated note in the
   plan saying everything agent-doable is closed and naming
   `docs/verification/human-checks.md` as what remains. Task 12's box stays
   open on the same condition (the VoiceOver run, `IX-AE`).

**Cost if wrong.** An item missed in the checklist is a look nobody takes;
the per-item source citation is how a reviewer finds the gap.

---

## CX-N — the retired engine and the goldens, re-verified

**Ruling.** The plan's last two clauses hold and are re-checked at the
Record phase, not re-done: (1) *no production caller of the retired CSS
engine* — the engine files are absent (`git ls-files Sources/MetalUILayout`
lists none of `FlexEngine`, `ResolveFlexibleLengths`, `FlexBaseSize`,
`FlexLines`, `LayoutContext`), `MetalUILayout` imports only `MetalUICore`,
and `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` is green; (2) *remove
or reclassify all browser goldens* — removed at stage 7a (`LR-DS`, record
§48: all 97, each with a retirement row): `find Tests/MetalUILayoutTests
-name "*.json" | wc -l` reads 0 and no test imports WebKit. README's "WebKit
was the oracle for the legacy engine" section is history and is labelled so
at the Record phase ("migration-only historical evidence", the plan's own
words).

**Cost if wrong.** None new; the checks are the stage-9/10 and 7a checks
re-run on this branch.

---

## CX-O — three lanes, run in order, over disjoint files

**Ruling.** Lane 1 (code: every `Sources/`/`Tests/`/CI change and the
closeout probe, and — since `CX-P` item 9 — `docs/verification/human-checks.md`)
→ lane 2 (the inventory map and check, record §66's tables,
tasks 4/5 settlement text, `docs/divergences.md`, `docs/migration.md`,
`docs/api-overview.md`) → lane 3 (doc comments in every `Sources/` file lane
1 does not edit). Lane 2 runs after
lane 1 so 85's retirement and `CX-C`/`CX-D` are in the documents; lane 3
after lane 2 so doc comments can cite the divergence list. Spec §4 lists each
lane's files; no file is in two lanes.

---

## CX-P — critic round: corrections to the committed design

**Ruling.** The critic round (2026-09-30) attacked commit `6e14813` and
corrects it as follows; the spec is amended to match.

1. **Test numbers.** `CX-B` named the C3/D1 pins 1.4/1.5 and `CX-I` the
   `switch` pin 1.6, where the spec numbers them 1.3/1.4 and 1.5 (1.6 is the
   allocation measurement). The spec's numbering stands; both rulings now
   cite it.
2. **The legacy C3/D1 order is pinned too.** Record §04's row 47 reads
   "(C3/D1 orders unpinned)", so task 5's "test order-sensitive chains"
   clause is not closed by proposal-path pins alone. Lane 1 adds **1.3L**
   `aLegacyBackgroundWrittenAfterCornerRadiusIsRoundedOnOneDecoration` and
   **1.4L** `aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc` (names may
   be re-spelled to what they find): `Box` 40×40 with the two chains,
   asserting the answer the legacy path actually gives (expected: one
   `Decoration`, order-insensitive, so the background and the border are
   both rounded — wrong on purpose against probe C3/D1), each with a
   mutation that reddens it (M1cL: make the legacy background's mask
   square; M1dL: square the legacy border band). The Record phase amends
   row 47 to state the legacy answer and drop "unpinned". **If either
   proposal pin (1.3, 1.4) is red on arrival**, lane 1 stops: that is a
   lowering answer differing from SwiftUI's, owed a ruling (fix or a new
   divergence), not a re-spelt test.
3. **Stale pin names in the divergence table.** `CX-E`'s pin
   (`aLegacyRowAndColumnDefault…`) does not exist in `Tests/`; the live pin
   is `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault`. Lane
   2's `CX-G` table resolves **every** row's pin by grep and lists each
   stale name; the Record phase corrects record §04's rows.
4. **Guard count.** CLAUDE.md counts guards by `grep -c canTypecheck`;
   G2 (`theTypecheckGuardsRanWhereTheyAreRequired`) calls `canTypecheck`,
   so it counts. Guards after lane 1: **121** (119 + G1 + G2), not 120.
   Tests after lane 1: **1971** (1961 + 1.1–1.6 + 1.3L + 1.4L + G1 + G2).
5. **`CX-D`'s forwarding.** The new public `Box.init(decoration:…)`
   initialisers forward to the `package` `init(style: Style(), …)` — never
   a second copy of its body — so whatever the package init does to the
   style (`EP-8`'s stretch default) is unchanged for every caller; the
   fourteen in-repo `Box(decoration:` callers resolve to the public init
   with an identical result. `DecorationCompileGuards`' doc comment, which
   says `Decoration` is reachable "through `Box(style:decoration:)`", is
   re-spelled to `Box(decoration:)` by lane 1. No typecheck fixture string
   contains `Box(style:` (grep at `6e14813`), so no guard's fixture breaks;
   lane 1 re-greps at its tip. `Backends/SDL`, `Tests/PortableTests` and
   `Experiments` contain no `Box(style:`/`Stack(style:` call (grep), so the
   `package` narrowing reaches no other package.
6. **The "task 15" sweep had gaps.** The grep finds, beyond §3's table:
   the shapes spec's elliptical-corner/`UnevenRoundedRectangle` row (now in
   `CX-I` item 3); `ModifiedContent.swift`'s `ModifiedElement` doc comment
   ("its fate is plan task 15's" — `CX-C` item 3 disposes it; lane 3
   re-spells the sentence); `NativeGridTests.swift`'s divergence-61/62 doc
   comment ("Owner: plan task 15's closeout" — `CX-H`; lane 1 re-spells
   it). Every `Sources/`/`Tests/` sentence that names plan task 15 as a
   future owner is re-spelled by the lane that owns the file, so a
   post-merge grep of `Sources Tests` finds only past-tense mentions.
7. **`flexBasis(percent:)`.** Its `@available(…, renamed:
   "flexBasis(fraction:)")` would point at a spelling `CX-C` item 2
   deprecates; lane 1 gives it the same `message:` as `flexBasis(fraction:)`
   (not a `renamed:` to a deprecated name).
8. **A second `malloc_logger` installer.** Test 1.6 installs one beside
   `ModifiedElementTests`' own, re-opening the two-installer race CLAUDE.md
   records as moot; it is gated (`METALUI_STORE_ALLOC_MEASURE=1`) and run
   only `--no-parallel`, and its doc comment says so.
9. **Lane balance.** `docs/verification/human-checks.md` moves from lane 3
   to lane 1 (a grep of record §03 and the task records, small beside lane
   3's 592 doc comments and lane 2's inventory). `CX-O` is amended to
   match.
10. **Verified, no change.** `swiftui-border-clip-paint.swift` re-run
    compiled at this round: K0, C3 and D1 byte-identical to its header.
    The census was cross-checked by an independent grep (1871 declarations
    by a looser regex; no `public extension` in `Sources/`, no modifier
    keyword before `public`), so members of a public extension without
    their own `public` cannot hide from it. The tasks 4/5 citation
    `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`
    resolves (`OuterModifierMatrixTests`). The CI job does run the default
    build system today (`swift build -v`), so `CX-J`'s premise holds.

**Cost if wrong.** Items 2 and 4 move the expected counts; a lane that
lands the spec's old figures would read the new ones as a regression.

---

## CX-Q — lane 1's fix round: `CX-F`'s rule reaches the public `withState`; a looks demo is the human checklist's runnable surface

Lane 1's verifier found two majors and two minors (record §66 §4.7).

1. **`CX-F` extends to `StateTable.withState`.** The record's first reading
   called its `(storage[id]?.value as? S) ?? initial()` "latent" because no
   in-package caller passes an optional `S` — but `withState` is public
   through `LayoutPass`/`PrepaintPass`/`PaintPass.withState`, so an external
   element calling `pass.withState(id, initial: Optional(5))` on an absent
   entry received `nil`, divergence 85's own shape on a public path. Fixed
   the same way: the absent case is told apart by the dictionary lookup, a
   stored value cast to `S` is used, anything else takes `initial()` (a stored
   value of another type took `initial()` before too, so no other answer
   moves). Red first: `thePublicWithStateHandsAnOptionalStateItsInitialValueOnFirstAccess`
   read `[nil, nil]`. No in-package caller changes answer (all non-optional).
2. **`Box(decoration:)` gets a painted pin**
   (`thePublicBoxDecorationInitialisersPaintWhatTheStyleInitialiserPaints`,
   both forms, with and without content), and **`flexBasis(percent:)` its own
   class-D row** in `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`
   (51 → 52 cases): a copy of a pinned body is unpinned, and forwarding
   between two deprecated spellings is not what `CX-P` item 7 chose.
3. **The looks demo.** `METALUI_LOOKS_DEMO=1 swift run MetalUIDemo`
   (`Sources/MetalUIDemoContent/LooksDemo.swift`, public
   `looksDemoContent()`) builds the surfaces human checks H1, I1, J1 and
   K1–K3 look at, which no demo tree built: three texts under
   `.controlSize(.mini/.small/.regular)`; an ellipse fill and band, a capsule,
   a rounded clip over a larger rectangle, a resizable image `.fit`/`.fill`,
   a checker at `.interpolation(.none)` and the default; double-tap,
   long-press and drag pads with counters; one button per K1 transition
   toggling a text-bearing tile under `withAnimation(.easeInOut(duration:
   0.8))`. Each section is its own function passed to a generic composer
   (the Windows 1 MB stack rule); it joins
   `everyProductionTreeBuildsOnAOneMegabyteThread` and is smoke-tested by
   `theLooksDemoDrawsEverySurfaceItsHumanChecksName`. It is not in the default
   demo, so the fourteen offscreen images read 0 px. `CX-M` item 1 holds:
   every checklist item names what to run.

**Cost if wrong.** Item 1 changes a public API's answer for an optional
`S` over an absent entry; an external caller that relied on reading `nil`
there now reads its own `initial` — the value it asked for.
