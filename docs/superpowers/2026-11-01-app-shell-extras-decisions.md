# App-shell extras (round 3 item R3-10 part 3) - decisions

Prefix `AE-`. **Next unused: `AE-G`.** Record: `../record/190-app-shell-extras.md`. Branch `feat/app-shell-extras` from master `5f347c1a`.
Divergence labels 1035-1044 reserved: **1035, 1036 used**, 1037-1044 unused. Probe: `docs/probes/swiftui-app-shell.swift`, new arms `N6`-`N13`
and `D2`-`D6` (recorded in its header). Closes the two rows of `docs/divergences.md` that read "not offered"/"not built" for the title and the
window interaction behaviors (`AS-D` item 7, `AS-F` item 3). Code: `WindowPreferences.swift`, `EnvironmentScope.swift`, `Frame.swift`,
`WindowShell.swift`, `RetainedGraft.swift`, `AppShell.swift`, `Platform.swift`, `AppKitPlatform.swift`, `HeadlessPlatformWindow.swift`,
`SDLPlatform.swift`. Tests: `AppShellExtrasTests.swift`, `AppShellCompileGuards.swift` (`anOutsideModuleCanSpellTheAppShellAPI`),
`AppShellSeamCompileGuards.swift`.

## AE-A: `navigationTitle` over a `Text` and a `LocalizedStringKey`

1. SDK (macOS 27.2 SDK `SwiftUICore.swiftinterface`): `navigationTitle(_ title: Text)`, `navigationTitle(_ titleKey: LocalizedStringKey)`,
   `@_disfavoredOverload navigationTitle<S: StringProtocol>(_:)`, `navigationTitle(_ title: Binding<String>)` (macOS 13), and a
   `navigationTitle(@ContentBuilder _:)` that is **`@available(macOS, unavailable)`**.
2. Probe: a `Text` title reaches `NSWindow.title` as its **plain string** (`N6`: `Text("Plain **bold** `code`").bold().foregroundStyle(.red)` reads
   `Plain bold code`; the `Text` init parsed the Markdown, the title bar then shows text only, so every font, weight, colour and run attribute
   is dropped). A string literal is a `LocalizedStringKey` whose Markdown is parsed the same way (`N7`: `Lit bold code link`).
3. MetalUI's `LocalizedStringKey` is a Markdown-and-interpolation carrier with no lookup (`RT-C` item 5, unchanged). The overload is offered on that
   basis: the title is `Text(key).string`. No localization story is invented; a key is never looked up. A literal now lands on the key overload
   (the `StringProtocol` one is `@_disfavoredOverload`, as SwiftUI's), so `navigationTitle("a_b *c*")` parses Markdown where it used not to; a
   `String` value is shown as written. The existing tests and demo (`navigationTitle(model.name)`, a `String`) are unaffected.
4. **The builder overload is ruled out: unavailable on macOS in SwiftUI**, so its absence is no divergence. **`Binding<String>` (an editable title) is
   carried**: probe `N10` shows SwiftUI follows the binding's value into `NSWindow.title`; the part MetalUI lacks is the title bar's rename
   field (written back through the binding), which needs a rename UI that AppKit shows only for document windows. Offering the read half would
   compile code that silently never writes back, so the overload is not offered.

## AE-B: `navigationSubtitle`

1. SDK: `navigationSubtitle(_ subtitle: Text)`, `(_ subtitleKey: LocalizedStringKey)`, disfavored `<S: StringProtocol>(_:)` (all macOS). Offered in the
   same three spellings as the title, with `AE-A`'s plain-string rule (`N11`: `Sub b`).
2. **Precedence is pre-order, the opposite of the title's** (probe `N9`, `N13`: an outer subtitle beats an inner one; `N12`: the first sibling beats
   the second). The scope therefore reports **before** its content builds; the title and the dismiss behavior report after. A pre-order rule is
   what `NSWindow.subtitle` read in SwiftUI's own window; no mutation of the title's rule is implied.
3. The platform seam is `PlatformWindow.setSubtitle(_:)` (`AE-D`). `Window` sends it when the effective subtitle changes; a tree with none sends `""`.
   AppKit sets `NSWindow.subtitle`. **SDL3 has no subtitle: it records the call and shows nothing** (divergence 1035), the edited marker's rule
   (`AS-D` item 5): the title is never altered behind the app's back (no append).
4. There is no `Window.subtitle` property (SwiftUI has none; `Window.title` is MetalUI-only for `openWindow(title:)`).

## AE-C: where the preferences are collected

`.navigationSubtitle` and `.windowDismissBehavior` are two more transparent `EnvironmentWrite` cases (no node, no id level, no value changed), reported to
`Frame` (`collectedNavigationSubtitle`, `collectedDismissBehavior`), read by `Window.adoptShellPreferences` after the build and applied by
`reconcileTitleAndDocument` on change only - written from the build's result at the end of a frame, the title's route, never from a phase of a
retained subtree. Both count into `BuildAudit.navigation`, so a retained occurrence that reports either refuses to graft by the channel's name
`windowMetadata` (`RK-F`), like the title.

## AE-D: `windowDismissBehavior`

1. SDK: `View.windowDismissBehavior(_ behavior: WindowInteractionBehavior)`, macOS 15 (a **view** modifier, unlike `windowBackgroundDragBehavior`,
   which is a `Scene` one). `WindowInteractionBehavior` already exists (`BG-G`). `windowMinimizeBehavior(_:)` and `windowResizeBehavior(_:)` are its
   siblings in the SDK and are not offered (carried).
2. Probe `D0`-`D6`: `.disabled` removes `.closable` from the style mask and disables the close button; `performClose(_:)` then closes nothing; the
   delegate's `windowShouldClose` is **not** a veto (it answers true). `.enabled` and `.automatic` leave the window closable (`D5`). **Precedence is
   post-order, the title's**: an inner `.enabled` beats an outer `.disabled` (`D2`) and the reverse (`D3`); the first sibling wins (`D4`). Gestures
   in the content change nothing (`D6`).
3. Seam: `PlatformWindow.setDismissEnabled(_:)` and `setSubtitle(_:)`, **defaultless** (`HT-X` 1). AppKit adds or removes `.closable`; the close
   button greys and ⌘W's Close item disables. `Window` sends it on change only (initially allowed) and **also refuses the user's close itself**:
   `answerCloseRequest(userInitiated:)` answers `false` without asking `onCloseRequest` while the tree's behavior is `.disabled` - the platform's
   request, `performClose()` and the drawn buttons' close all go through it. So SDL (whose system title bar's button cannot be disabled through
   SDL3 and records the call) refuses the request instead (divergence 1036). The headless window and the test fakes record the calls.
4. **A dismissal is not a quit and `close()` is not a dismissal**: the termination walk asks `answerCloseRequest(userInitiated: false)`; `Window.close()`
   and the platform's `close()` never ask. A disabled window therefore closes when the app quits (pinned by `aDisabledWindowStillClosesForQuitAndForClose`;
   SwiftUI's quit behavior with a disabled window is unmeasured, the probe's instrument cannot quit - carried).

## AE-E: `WindowDragGesture` and `windowBackgroundDragBehavior` were already built

The row "`windowDismissBehavior(_:)`, `WindowDragGesture`, `windowBackgroundDragBehavior(_:)` | not built" was stale for two of its three: `WindowDragGesture`
is `WD-A`...`WD-J` (record 97, `WindowDragGesture.swift`, an arena leaf, `PlatformWindow.performWindowDrag()`, divergences 275, 276, 425, 426) and the
background drag is `Window.backgroundDragBehavior` (`BG-G`...`BG-J`, divergence 736). Nothing was rebuilt; divergences 275, 425 and 426 stay as
written (their pinning tests are unchanged and green). The row is rewritten to name only `windowMinimizeBehavior`, `windowResizeBehavior` and
what `AE-A` and `AE-D` leave out.

## AE-F: tests and mutations

See record 190: `AppShellExtrasTests.swift` (four tests), the plain-import guard `anOutsideModuleCanSpellTheAppShellAPI` (new positive spellings, the
`Text` negative replaced by `Binding` and builder negatives) and the seam guard (two new members of `windowMembers`).
