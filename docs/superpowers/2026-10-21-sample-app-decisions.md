# Sample app - decisions

Rulings for item E1 (user request 2026-10-21). Spec: [`specs/2026-10-21-sample-app-design.md`](specs/2026-10-21-sample-app-design.md).
Record: `../record/136-sample-app.md` (Record phase). Branch `feat/sample-app` from `1bdead8d`. Divergence labels 655-664 reserved:
**none taken** (no SwiftUI-facing claim is made: the app uses existing API only; no probe is owed; SwiftUI's own sample shape is the model
for the subject, gpui's `examples/` for "an example is a program, not a test").

Prefix **`EX-`**, lettered. **Next unused: `EX-T`.** (Moves in the commit that appends a ruling.)

**Carried.** `SC-A`/`SC-I` and `Scaffold.swift`'s `manifest` (the package shape), `PX-J` (traits), `SG-D` (unconditional portable-text
products), `HT-O`/`HT-V` (test target, refused names), `PE-K`/`CI-AI` (1 MB stacks), divergence 125 (never-written `@State`), `DG-C`
(mirrored guide blocks).

## EX-A - It lives in `Examples/Jotter/`, a separate package, not a root target

**Ruling.** Its own package depending on the checkout by path. **Reasoning.** It must build the way a user's app does (a manifest an
author copies), and a root executable target would join the root manifest's two lists (PC-A), every platform's CI build, the census and
`Sources`-adjacent counts for no framework benefit. `Experiments/SDLGPU` is the precedent. **Cost if wrong:** the example drifts from
master's API unnoticed; mitigated by EX-C (env-gated root build test) and EX-E (a CI step).

## EX-B - Manifest copies the cross-platform scaffold; the dependency is named explicitly (amended by the critic)

**Ruling.** Same traits block, products and `SG-D` shape as `metalui new --cross-platform`, but the dependency is
`.package(name: "MetalUI", path: "../..", traits: metalUITraits)` and every `.product(..., package: "MetalUI")`, as `Experiments/SDLGPU`
does, so the example builds in any checkout directory name. The first draft omitted `package:`; the scaffold (`Scaffold.swift`, `SC-C`)
always writes it, so that was a drift. **Evidence owed at implementation:** `swift build` in `sample-app` and in a copy named otherwise,
and `name:` together with `traits:` accepted by the tools version in use; if refused, `package:` = the checkout directory's name and a README
note. The EX-D manifest test compares product names and the traits block, not the identity. **Cost if wrong:** a one-line manifest change.

## EX-C - A library target holds the app; the executable is `main.swift` only

**Ruling.** `JotterKit` (library) plus `Jotter` (executable); tests import the library plainly. **Reasoning.** The starter's test is
`@testable` over an executable (SwiftPM renames its entry point); an app author is better served by the split that keeps `main.swift`
trivial and lets tests and a future second front end share the code. **Cost if wrong:** one more target in the manifest.

## EX-D - Env-gated root build test plus a manifest-shape test, no guard

**Ruling.** `aSampleAppBuildsAndItsTestsPassAgainstThisCheckout` (`METALUI_RUN_SAMPLE_APP_TEST=1`, macOS/Linux, counts while skipped,
like `aGeneratedPackageBuildsAgainstThisCheckout`) and an always-on text test that the example's manifest still carries every dependency
line of the scaffold's cross-platform manifest. **Cost if wrong:** the manifest test is brittle to scaffold edits; that is its job (the
failure message says to update both).

## EX-E - CI: one macOS step, the Linux run stays a recipe unless the SDL image job already builds the image

**Ruling.** Add `swift test --package-path Examples/Jotter` to the macOS job after the root tests; leave `scene-linux` alone (portable targets
only). Linux with the `SDL` trait runs in the `metalui-portable` image locally and in CI only if an existing SDL job builds that image
(decided from the workflow at implementation, said in the PR). **Cost if wrong:** about five more CI minutes on macOS; a red macOS job on
unrelated API churn is the signal the example is for.

## EX-F - No hidden state file; persistence only through the file dialogs

**Ruling.** Save and load are `.fileExporter`/`.fileImporter` on versioned JSON; nothing is written on launch or quit. **Reasoning.** One
behaviour on AppKit and SDL, nothing to sandbox or clean in tests, and the presentation seam is what the tests drive. **Cost if wrong:** a
real notes app would autosave; named in the README as the next step, not built.

## EX-G - No guide snippet, no DG-C mirror

**Ruling.** The README links files rather than quoting blocks. **Reasoning.** `GuideDocCheck` would require byte copies in
`MetalUITestingTests`; the example's own tests already compile and drive the files. **Cost if wrong:** none; a snippet added later takes the
DG-C path.

## EX-H - Reorder is tested by in-app drag, not `drop(_:at:)`

**Ruling.** Test 10 drives `TestWindow.drag(from:to:)` over the sidebar (draggable payload: the note id, dropped on a row); `drop(_:at:)` carries
external `DropItem`s and would test a different path (`DN-F`). **Reasoning.** Found by reading `TestWindowInput.swift`. **Cost if wrong:** if the
in-app drag cannot reach the destination in the harness, that is a finding in record 136 and the test falls back to calling the destination action.

## EX-I - Autosave and launch-time file reads are out of the design

**Ruling.** The first spec table listed a `.task(id:)` autosave debounce and an `.onAppear` last-file load, contradicting `EX-F` (no hidden state
file). Both are removed: `.task(id:)` recomputes a word count and `.onAppear` selects the first note. **Cost if wrong:** none.

## EX-J - The reorder payload is the note's id as a `String`, not a `Transferable` `Note`

**Ruling.** A row `.draggable(id.uuidString)` and `.dropDestination(for: String.self)` parses it back. **Reasoning.** `String` is
`Transferable` already; a custom conformance (four requirements) would teach nothing about reorder and a `Note` payload would put the
whole note in a drag. The spec's "`Note` ... `Transferable`" is dropped. **Cost if wrong:** a drop from another app of a UUID-shaped
string moves a row; harmless (an unknown id is declined).

## EX-K - The stats chart is shapes, not a `Canvas`

**Ruling.** MetalUI has no `Canvas` (`docs/guides/drawing-and-gpu.md`). The words-per-note bars are `Rectangle`s in an `HStack` and the
per-day line is a `Shape` whose `path(in:)` builds a `Path`, `.stroke`d. Every bar carries `accessibilityLabel` and an identifier, so the
chart is testable; there is no container-level label (it propagates to every child, EX-N). Test 14 keeps its table name
`theStatsCanvasSummaryNamesTheCountsAndFollowsEdits`. **Cost if wrong:** a chart of hundreds of points would want a `Canvas`; a finding.

## EX-L - Toolbar and search are driven through the platform seam, and the drawn strip is the layout test

**Ruling.** Tests press toolbar items by id (`performToolbarItem`) and type into the search field with `.text(_:)` against the native
toolbar (the harness default, AppKit's answer). Test 16 turns `showsToolbarNatively` off (SDL's answer) so every control is in the tree at
the 640 x 400 minimum and clickable by label, which also answers open point 2 of the spec: `.searchable` is drawn by the strip on SDL as
a field labelled with its prompt ("Search notes").

## EX-M - The sidebar's `List` stays in the tree when no note matches

**Ruling.** The empty state is a `Text` over the list in a `ZStack`, not a replacement for it. **Reasoning.** Found by test 4: a `List`
created in a frame builds its rows one frame later (it measures its origin first), so swapping it in as a search is cleared left the
sidebar empty for a frame, a flash on a real display and a stale accessibility tree in a harness that draws one frame per action.

## EX-N - Identifier and label go on the leaf; `.focused` goes on the control before any wrapper

**Ruling.** `.accessibilityIdentifier` and `.accessibilityLabel` on a container stack apply to every text inside it (as SwiftUI does), so a
row's id is on its title `Text` and the app finds rows by it; on a `TextField` the identifier must come **after** `.frame` (before it, the
field's accessibility node became a plain group with no value), and `.focused($flag)` must be applied to the `TextField` **before** `.frame`
(after a proposal wrapper it bound the wrapper, which is not focusable, and the focus write did nothing). Both are recorded as findings.

## EX-O - Test 17 builds the six trees that do not read the model through a stdlib closure; a Darwin arm keeps it not vacuous

**Ruling.** On a secondary thread `SidebarList`, `DetailArea`, `NoteRow`, `StatsView` and `PerDayLine` trap (`SIGTRAP`): they read the model
through a closure given to `first { }`/`flatMap`, whose dynamic isolation check fails off the main actor (the fact of `SV-AK` and `HP-C`;
they run on the main thread in the app). The test builds `rootView`, `JotterScreen`, `SidebarView`, `DetailEditor`, `DetailFooter` and
`WordBars` on a 1 MB thread; a Darwin-only arm shows the same harness fails on a 64 KB thread (measured on macOS arm64, debug: 64 KB
`SIGBUS`, 128 KB passes, so 1 MB is eight times the need). Not red on a mutation (inlining the sections does not come near 1 MB); it is a pin.

## EX-P - A headless platform does not echo `.preferredColorScheme`; the test reports the appearance as AppKit does

**Ruling.** `HeadlessPlatformWindow` records the request; AppKit forces the `NSWindow`'s appearance and reports it back
(`setPreferredColorScheme`). The theme test therefore asserts the request and then calls `setAppearance(_:)` itself. A finding (the
harness could echo it, `HT-` follow-up), not a bug in the framework.

## EX-Q - Two View items have no shortcut; Delete's shortcut yields to a focused field

**Ruling.** `Toggle` has no `.keyboardShortcut` in MetalUI, so "Statistics" and "Dark Appearance" are menu-only toggles (a finding).
Delete is ⌘⌫, which a focused text field keeps for its own editing (delete to the line start): after New the title is focused, so the
command test moves focus to the list by a click first. Documented in the test.

## EX-R - No `Packaging/` directory

**Ruling.** The spec's `Packaging/{macOS,linux}` is not built: the example's README points to `docs/packaging.md` and bundle id
`com.example.Jotter`, which is what a user would copy. The packaging recipe is the scaffold's and is already pinned by its own tests.
**Cost if wrong:** a user must run the recipe by hand; one more directory later.

## EX-S - Root and CI wiring (EX-D, EX-E settled)

**Ruling.** Root suite +3 tests in `Tests/MetalUIScaffoldTests/SampleAppTests.swift`: the always-on manifest-shape test, a files-exist test and the env-gated
`aSampleAppBuildsAndItsTestsPassAgainstThisCheckout` (`METALUI_RUN_SAMPLE_APP_TEST=1`). CI: `swift.yml`'s macOS job gains
`swift test --package-path Examples/Jotter` after the root tests, and `sdl-gpu-linux.yml`'s Linux job, which already builds the
`metalui-portable` image, gains a step running the package there with the SDL trait (`Examples/Jotter/**` joins its path filters).
`scene-linux` is untouched. Said in the PR.

## Critic's rejections

No probe is added: the app uses only existing API with no SwiftUI-behaviour claim (checked: `.searchable`, `.confirmationDialog`,
`.fileExporter`, `.draggable`, `.dropDestination`, `presentedAlert`, `presentedFileDialog`, `chooseMenuItem` exist). No renderer, platform
requirement, C enum or `Sources/` change, so those attack classes do not apply. Test 17 may be an unred pin; the spec already says so honestly.
