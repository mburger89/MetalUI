# Tooling, tests, guides, sample app

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Scaffolding** (`SC-`, record §72, `docs/getting-started.md`): `metalui new`
is the `MetalUICLI` executable over `MetalUIScaffold` — Foundation only, every
declaration `package` (a tool, not API: no inventory row). `--cross-platform`
works from any source, `--local` or the URL (the SDL backend is a root-package product behind traits, `PX-J`, which supersedes `SC-C`). **A change to
`docs/packaging.md`'s recipe, `App`'s initialisers or the starter's API
changes the generated text too** — re-run
`METALUI_RUN_SCAFFOLD_BUILD_TEST=1 swift test --filter aGeneratedPackageBuildsAgainstThisCheckout`.
The default dependency is **pinned** (`SC-I`): `revision:` the merge base of
HEAD and `origin/master` in the checkout `#filePath` names, falling back to
`branch: "master"` with a note; the lookup is injected, so a test never runs
git on the checkout's history. **A refused name is a measured build failure**
(`SC-H`): add one only after generating and building a package with it.

**Sample app (`EX-`, record §136, `Examples/Jotter/README.md`).** `Examples/Jotter` is the repo's one real app: a notes app in **its own SwiftPM
package** (library `JotterKit`, executable, `JotterTests`) depending on the checkout by path with the scaffold's products and traits (`EX-A`, `EX-B`;
not a root target, so no PC-A list, census or CI build of the root grows), built and tested on macOS and in the Linux image with the SDL trait. It uses
only existing API: no `Sources/` change, no divergence, no public declaration. Its tests run over `MetalUITesting` the way `docs/testing.md` tells an
author (21, 20 off Darwin). **A change to `docs/packaging.md`'s recipe, `App`'s initialisers, the scaffold's manifest or an API the app uses can break
it**: run `METALUI_RUN_SAMPLE_APP_TEST=1 swift test --filter aSampleAppBuildsAndItsTestsPassAgainstThisCheckout` (the root's two manifest/docs tests run always,
CI runs `swift test --package-path Examples/Jotter` on macOS and in the Linux image). Every section is its own `Component` (1 MB stacks); a `List` row is one
`Element` (a `Column` around an `.equatable()` component); `.focused($flag)` goes on the control before any wrapper (`EX-N`). Rough edges are findings in
record §136 §2, not fixes.

**Test harness (`HT-`, record §91, `docs/testing.md`).** `MetalUITesting` is a portable library
product for test targets only (`MetalUI` never links it): `TestApp`/`TestWindow` run the **real**
`App.openWindow` and `Window` over `HeadlessPlatform`/`HeadlessPlatformWindow`/
`HeadlessWindowRenderer`, which implement every platform requirement honestly (options default to
AppKit's answers). Input is XCUITest's names with AppKit's key routing; a **simulated clock**
(`tick`, `advance(by:)`, `runUntilIdle()` — four quiet yields, bounded at 64 rounds, a closed window counting as clean, and work only the clock can finish (a fade, an animation, a held long press, a tooltip's delay) never dirtying it, `HT-Z`; `runUntil(timeout:_:)` waits for work off the main actor by its effect, the real-time bound only a failure bound, `HT-Y`); **an action
draws one frame, `tick` draws the next**, and a test's model is a plain class plus
`setNeedsRedraw()` or `@Observable` with `runUntilIdle()` (the observation hop is asynchronous off
macOS); queries read the accessibility tree (`element(label:)` also matches a static text's string)
and `frame(ofID:)` is the laid-out rect before scroll and effects; presentations are read and
answered at the seam, or driven through the tree where the option makes the window draw them
(`presentsAlertsNatively`, `presentsMenusNatively`, `showsToolbarNatively`,
`HeadlessPlatform.showsMenuBarNatively`); `FrameWork` counts a frame's work (benchmarks count work,
never time). `frame(ofID:)` finds an `.id` on proposal content too: an `IdentifiedGroup` records the union of its nodes' rects in a recording frame only and is never a `scrollTo` target (`TW-A`…`TW-C`, record §108). `MetalUI` gains only `package` read-back hooks in `TestingHooks.swift` and
`TestingMenuHooks.swift` (plain-import guards 3.1–3.4 pin them unreachable); no pixels, no GPU
surface draws. `metalui new` generates a test target over it, and `Testing` is a refused name
(`HT-V`). MetalUI-only by class `M`: SwiftUI tests out of process.

**Developer guides (`DG-`, record §103, `docs/guides/README.md`).** Six task-led guides (layout, state
and identity, input, presentations and the app shell, drawing and GPU, cross-platform) for an author
coming from SwiftUI. **Every `swift` block is compiled**: copied by hand, byte for byte, into a
`// guide: <file> #<n>` region of `Tests/MetalUITestingTests/GuideMirrors*.swift` (an ordinary
target, so no build system skips it, `DG-C`), and `GuideDocCheck.swift` fails on a differing byte,
an unmirrored block, a fence other than `swift`/`text`/`sh`, a dead pin, divergence label or link,
an unmerged-API name and a behaviour word with no `(pin: \`test\`)`. **A new block is written in the
guide, then copied by hand** (no generator, `DG-D`); SDL snippets are `text` fences (`DG-L`); a
mirror test settles with `setNeedsRedraw()` and `tick()`, never `runUntilIdle()` after a click
(`DG-P`). The C23/C24/C27/C28 sections are in (record §107): `frame(ofID:)` does not see a proposal
element's `.id`, so a guide test reads an accessibility frame (`DG-T`). No public API.

**Small items carried (`SM-`, record §147).** No code, no public API, no divergence (765-774 untouched). **`IH-K` image decode cancellation stays carried** (stb's callback EOF saves nothing on a PNG, about two thirds of a JPEG decode on an early cancel, and a JPEG returns a zero-filled full-size image, never `nil`, so a wrapper must discard: `SM-A`); **`SN-L` stays carried**: an activation token cannot be forwarded because SDL's raise ignores the environment (`SM-B`) and D-Bus activation does not fit the pure-C transport (`SM-C`); **`P3c` R8 coverage with a shader tint stays carried** on `PN-D`'s reading and the absent shader toolchain (`SM-D`; critic review `SM-E`). Re-open each only on the evidence its ruling names.

**`metalui bundle` (`BU-`, record §165).** The command is a pure planner (`parseBundleCommand`, `bundlePlan`, tested as text) over a thin executor (`performBundle`) with every process behind `BundleProcessRunner`, so a unit test never runs `swift build`; the `.app` is ad-hoc signed, not notarized, and the end-to-end test is env-gated (`METALUI_RUN_BUNDLE_TEST=1`).

**Harness timeline clock (`DX-A`, record §166).** A `TestWindow`'s `TimelineView` clock is simulated from the window's first build, so `advance(by:)` alone re-evaluates a periodic timeline; a new timeline-wake path must go through `TimelineStore.scheduler` so the harness can hold it.
