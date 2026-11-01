# 190 - app-shell extras (`AE-A`..`AE-F`)

2026-11-01, branch `feat/app-shell-extras` from master `5f347c1a`; round-3 item R3-10 part 3. Rulings:
`docs/superpowers/2026-11-01-app-shell-extras-decisions.md`. Probe: `docs/probes/swiftui-app-shell.swift`, new arms `N6`-`N13` and `D2`-`D6` (output below
and in the probe's header). Rule: `docs/rules/app-shell.md` ("App-shell extras"). Divergences 1035, 1036 (1037-1044 unused). Human check group `AE`.

## 1. What was there

Two "Not offered"/"not built" rows of `docs/divergences.md`: `navigationTitle` took only a `StringProtocol` (`.navigationTitle(Text("x"))` did not compile and a
guard pinned that), and "`windowDismissBehavior(_:)`, `WindowDragGesture`, `windowBackgroundDragBehavior(_:)` not built". **Two of the three were built long ago**
and the row was stale: `WindowDragGesture` is `WD-A`...`WD-J` (record 97; divergences 275, 276, 425, 426) and the background drag is
`Window.backgroundDragBehavior` (`BG-G`...`BG-J`, record 144; divergence 736; `WindowInteractionBehavior` exists). Only `windowDismissBehavior` and the title
overloads were missing; nothing was rebuilt for the other two.

## 2. SDK signatures (macOS 27.2 SDK, `SwiftUICore.swiftinterface` / `SwiftUI.swiftinterface`)

```
View.navigationTitle(_ title: Text)                                   // macOS 11
View.navigationTitle(_ titleKey: LocalizedStringKey)                  // macOS 11
@_disfavoredOverload View.navigationTitle<S: StringProtocol>(_ title: S)
View.navigationTitle(_ title: Binding<String>)                        // macOS 13
View.navigationTitle<V: View>(@ContentBuilder _ title: () -> V)       // @available(macOS, unavailable)
View.navigationSubtitle(_ subtitle: Text) / (_ subtitleKey: LocalizedStringKey) / @_disfavoredOverload <S: StringProtocol>(_:)   // macOS
View.windowDismissBehavior(_ behavior: WindowInteractionBehavior)     // macOS 15, a View modifier (also windowMinimizeBehavior, windowResizeBehavior)
Scene.windowBackgroundDragBehavior(_ behavior: WindowInteractionBehavior)   // macOS 15, a Scene modifier
struct WindowDragGesture: Gesture                                     // macOS 15
```

## 3. The probe, verbatim (macOS 27.0.1 session, screen unlocked, one run each from cleared defaults, exit 0; lines trimmed to the fields that differ)

```
=== N6 .navigationTitle(Text("Plain **bold** `code`").bold().foregroundStyle(.red))   title="Plain bold code"
=== N7 .navigationTitle(string literal with Markdown)                                 title="Lit bold code link"
=== N8 .navigationTitle("Title").navigationSubtitle("Sub")                            title="Title" subtitle="Sub"
=== N9 nested .navigationSubtitle: Inner inside Outer                                  title="T" subtitle="Outer sub"
=== N10 .navigationTitle(Binding<String>), then the model writes it                    title="Doc A" -> after write title="Edited by app"
=== N11 .navigationSubtitle(Text with Markdown)                                        subtitle="Sub b"
=== N12 sibling .navigationSubtitle: Left then Right in one HStack                     subtitle="Left"
=== N13 .navigationSubtitle("Inner") inside a VStack with .navigationSubtitle("Outer") subtitle="Outer"
=== D0 .windowDismissBehavior(.disabled)       closable=false closeButton enabled:false ; after performClose: visible windows=1
=== D2 nested: inner .enabled inside outer .disabled   closable=true  ; after performClose: visible windows=0
=== D3 nested: inner .disabled inside outer .enabled   closable=false closeButton enabled:false ; visible windows=1
=== D4 siblings: .disabled then .enabled       closable=false ; visible windows=1
=== D5 .windowDismissBehavior(.automatic)      closable=true  ; visible windows=0
=== D6 .disabled with an onTapGesture content  closable=false ; visible windows=1
(delegate windowShouldClose -> true in every D arm: a static switch, not a veto)
```

Reading: a `Text` title and a literal title both reach `NSWindow.title` as plain text (Markdown parsed by the `Text`/key init, then shown without styles). The title's
precedence is post-order (inner, first sibling; `N2`, `N5`), **the subtitle's is pre-order** (outer beats inner, first sibling), and the dismiss behavior's is
post-order (`D2`-`D4`). A `Binding` title is followed (`N10`); the rename-from-the-title-bar half is not observable headless and is carried.

## 4. What was built, per platform

- **API** (`WindowPreferences.swift`): `navigationTitle(Text)`, `navigationTitle(LocalizedStringKey)` (the `StringProtocol` one now `@_disfavoredOverload`), `navigationSubtitle` in the same
  three spellings, `windowDismissBehavior(_:)` (an `EnvironmentScope` write each; `EnvironmentWrite` gained `.navigationSubtitle` and `.windowDismissBehavior`).
- **Core**: `Frame.collectedNavigationSubtitle` (set before the scope's content builds) and `collectedDismissBehavior` (after), `BuildAudit.navigation` counts both,
  `WindowShellState.treeSubtitle/treeDismiss/sentSubtitle/sentDismissEnabled`, `reconcileTitleAndDocument` sends on change, `answerCloseRequest(userInitiated:)`
  refuses a user's close while disabled; `AppShell.walkWindows` asks with `false`.
- **Seam**: `PlatformWindow.setSubtitle(_:)` and `setDismissEnabled(_:)`, defaultless; added to CLAUDE.md's list, `migration.md`, the seam guard's `windowMembers`.
- **AppKit**: `NSWindow.subtitle`; `.closable` inserted/removed from the style mask (the close button greys, ⌘W's item disables, `performClose` closes nothing; `close()` unaffected).
  Not run on a real window here (human check `AE1`-`AE3`).
- **SDL**: records both calls (`subtitleCalls`, `dismissEnabledCalls`); the OS close request and the drawn buttons' close go through `Window.answerCloseRequest`, which refuses (divergences 1035, 1036).
- **Headless** (`HeadlessPlatformWindow`: `subtitleWrites`, `dismissEnabledCalls`) and the test fakes (`FakePlatformWindow` records, the nine compile-guard conformers and `PortableFakeWindow` no-op).

## 5. Counts and verification

Mutation table (each applied to the named declaration in `Sources/MetalUI`, `swift test --build-system native --no-parallel --filter 'AppShellExtrasTests|performCloseAsksAndCloseDoesNot|aQuitWithNoHandlers'`, source restored after; every mutant red):

| mutation (declaration, spelling) | reddened |
|---|---|
| `navigationTitle(_ title: Text)` forwards `"Text"` for `title.string` (`WindowPreferences.swift`) | `aTextOrKeyTitleIsItsPlainString` |
| `navigationTitle(_ titleKey:)` forwards `String(describing: titleKey.segments)` for `Text(titleKey).string` | `aTextOrKeyTitleIsItsPlainString` |
| `.navigationSubtitle` reported after its content builds (`EnvironmentScope.reportingPreference`, post-order) | `theSubtitleIsPreOrderAndSentOnChangeOnly` (nesting arm) |
| `.navigationSubtitle` last report wins (the `== nil` guard dropped) | `theSubtitleIsPreOrderAndSentOnChangeOnly` (siblings arm) |
| `.windowDismissBehavior` reported before its content (pre-order) | `dismissDisabledRefusesTheUsersCloseAndFollowsPostOrderPrecedence` (`D2`/`D3` arms) |
| `reconcileTitleAndDocument` sends the dismiss flag on every build (`if true`) | `dismissDisabledRefusesTheUsersCloseAndFollowsPostOrderPrecedence` (call list) |
| `answerCloseRequest` never refuses a disabled dismiss (the guard line removed) | `dismissDisabledRefusesTheUsersCloseAndFollowsPostOrderPrecedence` |
| `answerCloseRequest` gates the quit walk too (`userInitiated` dropped from the guard) | `aDisabledWindowStillClosesForQuitAndForClose` |
| `reconcileTitleAndDocument` sends the subtitle on every build (`if true`) | `theSubtitleIsPreOrderAndSentOnChangeOnly` (call list) |

Not mutated (named limits): `BuildAudit.navigation`'s two new terms (no retained-graft test reports a subtitle; carried), the AppKit bodies (`NSWindow.subtitle`, `.closable`; human checks `AE1`-`AE3`,
and the SDL package's records are not asserted by a test), the `StringProtocol` overloads (unchanged spelling, exercised by the existing title tests). The plain-import guard
`anOutsideModuleCanSpellTheAppShellAPI` now spells `Text`, `LocalizedStringKey`, subtitle and dismiss forms positively and refuses `Binding` and builder titles; the seam guard
`aPlatformWindowWithoutEachAppShellRequirementDoesNotCompile` gained `setSubtitle` and `setDismissEnabled` arms (both green, the table is one list).


Full suite, `swift build --build-system native --build-tests && swift test --build-system native --no-parallel`, unfiltered, on this branch (log kept in the session scratchpad):

`✘ Test run with 4830 tests in 13 suites failed after 595.321 seconds with 1 issue.`

The one failure is `anOutsideSwitchOverPlatformPointerStyleOwesTheImageCase` (`ImageCursorCompileGuards.swift:49`): its fixture's `oldCases` list names twelve `PlatformPointerStyle` cases, but the type has since gained
`columnResizeOneWay`, `rowResizeOneWay` and `hidden`, so the control arm's `default:`/`.image` switch is not exhaustive. It reads no file this branch touches (`PointerStyle.swift` is unchanged) and is
carried as a stale guard, not fixed here. The four new tests and both app-shell guards pass;. Quoted guard line: `AS-B spellings: succeeded=true`. `swift build` and, from
`Backends/SDL`, `swift build $(python3 scripts/fetch-accesskit.py --print-flags)` build clean (the SDL package's tests were not run here).

## 6. Carried

`navigationTitle(Binding<String>)` (the rename field); `windowMinimizeBehavior`, `windowResizeBehavior`; what a quit does with a disabled window in SwiftUI (the probe cannot
quit); a retained-graft test that an `.equatable()` occurrence reporting a subtitle or a dismiss behavior refuses by `windowMetadata` (the audit counts them, no test mutates that line);
`Window.subtitle` (SwiftUI has none); the stale `ImageCursorCompileGuards` fixture (above). Human check group `AE` (unrun).
