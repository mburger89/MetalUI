# Record 240: the environment clipboard and the Markdown fence copy button (Alloy gap G2b)

Branch `feat/env-clipboard` (master `dfc21168`). Rulings `CB-S` in `docs/superpowers/2026-10-14-clipboard-types-decisions.md` (next `CB-T`) and `BM-K` in `docs/superpowers/2026-11-07-block-markdown-decisions.md` (next `BM-L`). Class `M`; no divergence added or retired (labels untouched). Number 239 is held by the tooltip branch (`feat/help-provider`); re-check `README.md` at merge.

## 1. What was asked and built

A "Copy" button on a Markdown code fence had no way to write the clipboard: `Window.clipboard` is reachable only outside the view tree and `.copyable` answers a key on a focused element.

- **`EnvironmentValues.clipboard`** (`Sources/MetalUI/Clipboard.swift`, `CB-S`): a get-only `Clipboard`, read with `@Environment(\.clipboard)` and written from an action. SwiftUI has no such value (the doc comment says so; `CP-A` had ruled it not built for that reason, and is marked superseded). The window stamps a `ClipboardSource` (a class holding its `PlatformWindow` weakly) at the root beside `URLOpener` (`LI-D`), as an identity reading through `setCustom`, so `EnvironmentValues` gains no stored property and `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` is unchanged. `Clipboard` now has two forms: `Window.clipboard` holds the platform strongly; the environment's reaches it through the source, so a stored value retains nothing, and outside a window (or after it closes) it is a no-op clipboard (`write` false, reads `nil`, `itemCount` 0, `contentTypes` empty). `Clipboard` is now `Equatable` by the window it reaches (public conformance, nonisolated `==`).
- **`MarkdownTheme.showsCodeCopyButton`** (default `false`, `BM-K`): each fence, nested or not, gets an `Image(systemName: "doc.on.doc")` overlay at its top trailing corner, label "Copy code", `isButton` trait and an accessibility action; a press writes the fence's whole `code` through `\.clipboard`. The fence reads the clipboard as an `@Environment` and stays `.equatable()` on its stored values. `BM-J`'s carried "copy accessory" item is amended: a closure accessory stays carried, the built-in button is `BM-K`. The Markdown demo turns it on (human check BM6).

## 2. Findings along the way

- **An `@Environment` of a non-`Equatable` struct is an uncomparable reading and a refusal to replay** (`EE-B`): `EnvironmentReading.of(values[keyPath: kp])` reads the getter's *result*, not the stamped custom reading. The first version (a plain struct) re-evaluated an `.equatable()` component every idle frame (`retainedHits` 0); `Clipboard: Equatable` by window identity fixed it. The stamp's own `.object` reading does not matter to `@Environment`; it matters to the fingerprint. A probe of four components (text or button, reading the clipboard or not) separated it: only the two reading it missed.
- **A `Button` is not proposal content** (its type does not conform to `ProposalElementGroup`), so it cannot be the overlay of the fence (a proposal group). The copy glyph is a drawn tap target (`onTapGesture` plus the button trait and an accessibility action, as the tab strip's close slot is). It has no hover or pressed look, and `contentShape` is not available on a padded `Image` in proposal content, so the hit area is the padded glyph.
- `Clipboard`'s stored platform is `nonisolated(unsafe)` so the weak form can be built in the nonisolated `EnvironmentValues` getter; it is only read on the main actor.
- A fence still streaming copies the code so far.

## 3. Tests

`Tests/MetalUITestingTests/EnvironmentClipboardTests.swift` (9), portable (plain imports, `harnessTextSystem`); a Button action writes the headless window's clipboard; the no-op outside a window; two windows with their own (and unequal clipboards); `.equatable()` replay unchanged (no re-evaluation, `retainedHits > 0`, skipped under `METALUI_VERIFY_RETAINED=1` as the other replay tests); a stored clipboard retains no window; the fence button copies the whole 40-line fence (two chunks); a fence nested in a list and in a quote copies its own code; absent by default; an overlay that moves nothing and whose press shapes nothing.

## 4. Mutations (each alone, in place after the commit, restored with `git checkout`; filtered run `--filter EnvironmentClipboardTests`)

| Mutation | Reddened |
| --- | --- |
| M1 root stamp (`stampClipboardSource`) removed in `Window.swift` | all seven that write through it: `aButtonActionWritesTheWindowsClipboardThroughTheEnvironment`, `twoWindowsEachWriteTheirOwnClipboard`, `theEnvironmentClipboardDoesNotBreakEquatableReplay`, `aStoredEnvironmentClipboardDoesNotRetainItsWindow`, `theCopyButtonCopiesTheWholeFence`, `aNestedFenceHasItsOwnCopyButton`, `theCopyButtonIsAnOverlayAndPressingItDoesNotReshapeTheFence` |
| M2 `Clipboard ==` always false | `theEnvironmentClipboardDoesNotBreakEquatableReplay`, `twoWindowsEachWriteTheirOwnClipboard` |
| M3 `ClipboardSource.platformWindow` strong | `aStoredEnvironmentClipboardDoesNotRetainItsWindow` |
| M4 one shared source (the first window's) for every window | `twoWindowsEachWriteTheirOwnClipboard` and six more that reach a later window's clipboard (the mutant's global outlives the first test) |
| M5 no-op `itemCount` `?? 1` | `outsideAWindowTheEnvironmentClipboardIsANoOp` |
| M6 `showsCodeCopyButton` defaults `true` | `noCopyButtonIsShownByDefault` |
| M7 the action copies the first line only | `theCopyButtonCopiesTheWholeFence`, `theCopyButtonIsAnOverlayAndPressingItDoesNotReshapeTheFence` |
| M8 the button as a row of the fence's column (not an overlay) | `theCopyButtonIsAnOverlayAndPressingItDoesNotReshapeTheFence` (the code moves), `theCopyButtonCopiesTheWholeFence`, `aNestedFenceHasItsOwnCopyButton` (the row has no action) |
| M9 the quote hands its blocks a default theme | `aNestedFenceHasItsOwnCopyButton` |
| M10 the fence's `==` always false | **green**: a press does not dirty the window, so an unequal fence is still not re-evaluated on a frame nothing asked for (the click itself redraws once, and the chunks stay equal). Both the fence's and the chunk's `==` always false: `theCopyButtonIsAnOverlayAndPressingItDoesNotReshapeTheFence` |

The `.equatable()`-replay arm was first red for a real reason (finding 1) before any mutation.

## 5. Counts

Native, unfiltered, `--no-parallel` after `swift package clean`: `Test run with 5684 tests in 26 suites passed after 534.335 seconds` (0 failures; the same count under `METALUI_VERIFY_RETAINED=1`, 465.705 seconds), `FR-J no-argument frame: succeeded=true`; closeout scripts print nothing. A first run read `5562 tests in 25 suites` (a stray second `swift test` shared its log); it was discarded and repeated. The replay arm `theCopyButtonIsAnOverlayAndPressingItDoesNotReshapeTheFence` counts shaping only when not verifying (`rsVerifying`), as the other replay tests do: under verify mode every frame re-evaluates. Portable container `metalui-portable:latest` (`git archive HEAD` over stdin to `docker run --rm -i`): `swift build --build-tests` complete (255.75 s); `Test run with 972 tests in 11 suites passed` (`MetalUITestingTests`, was 961), then 9, 16, 73, 68, 53, 25, 290, 165, 24 and 45, all passed.

## 6. Carried

A hover and pressed look and a larger hit area for the copy glyph; a "Copied" confirmation; a position or glyph other than top trailing (an app wraps the fence); a phase-detecting guard that makes a clipboard write from a phase a no-op (the value cannot tell a phase from an action); `Button` as proposal content.
