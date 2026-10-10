# 91 — Test harness (`HT-`)

Branch `feat/test-harness` from `70e9389`. Spec
`docs/superpowers/specs/2026-10-09-test-harness-design.md`; rulings
`docs/superpowers/2026-10-09-test-harness-decisions.md`. The Record phase
writes the full record; this file starts with the measurements the lanes
carry to it.

## Lane 2 fix round (2026-10-10, `HT-U`)

The lane 2 verifier ran the root package in `swift:6.4-noble` at `c366644`:
`MetalUITestingTests` 63 tests, failed with 3 issues — 2.25 (⌘C is not copy
off macOS) and 2.18 (a menu-bar action's model write reached the window only
through the asynchronous observation hop; no frame drawn).

- **Red first** (`d978e2b`, filtered `MetalUITestingTests`, native): 67
  tests, only `aMenuBarCommandDrawsWithNoObservationHop` (2.27) red.
- **Fix** (`96c443d`): `performMenuBarItem` calls `setNeedsRedraw()` on each
  window before its tick (`HT-U` item 1); 2.25 sends the platform's shortcut
  modifier (item 2).
- **macOS, native, unfiltered**: 3136 tests in 3 suites passed (3132 + 4);
  the `FR-J no-argument frame: succeeded=` line present; the only `warning:`
  SwiftPM's deprecation notice; `swift build --build-tests` (default build
  system) 0 `warning:`.
- **`swift:6.4-noble`, root package** (`--scratch-path /tmp/build` on the
  branch's volume): `MetalUITestingTests` 67 passed, then 6 + 35 + 18 + 199 +
  67 + 22 — all passed, 0 `warning:`.
- **Mutations** (full native unfiltered suite each, `git status --short`
  clean after each restore):

| Mutation | Reddened |
|---|---|
| `setNeedsRedraw` dropped from `performMenuBarItem` | `aMenuBarCommandDrawsWithNoObservationHop` (2.27) only |
| `standardAction` guard dropped | `aStandardMenuBarItemIsNotPerformed` (2.28) only |
| `presentedAlert`'s `dismissedPresentations` check dropped | `anAlertTheWindowDismissesIsNoLongerPresented` (2.29) only |
| `respondToAlert(button:)`'s `matches.count == 1` guard dropped | `anAlertButtonTitleTwoButtonsShareIsAmbiguous` (2.30) only |

- **2.23** (`HT-U` item 3), the verifier's measurements at `c366644`: "the
  query walk visits only `roots.first`" reddened seven other tests but not
  `aPopoverAppearsInTheTreeInsideTheWindow`; "only the last root" (2.23c)
  left it green too — the popover's node is not another root. "Skip the
  children of a `.popover`" (2.23b) reddened exactly
  `aPopoverAppearsInTheTreeInsideTheWindow`, and is now 2.23's named
  mutation.
