# 136 - The sample app (E1: `Examples/Jotter`)

Branch `feat/sample-app` from `1bdead8d`. Not a plan task: item E1 (round 2) of the gpui-gap list, user request 2026-10-21 ("Sample app: `metalui new` gives
a hello-world starter, but no real sample app exists"). Spec `docs/superpowers/specs/2026-10-21-sample-app-design.md`; rulings `EX-A`...`EX-S` in
`docs/superpowers/2026-10-21-sample-app-decisions.md` (next `EX-T`). Divergence labels 655-664 reserved: **none taken** (no `Sources/` change, no public
declaration, no SwiftUI claim, no probe). One lane. Human checks: group `EX` (proposed text in section 7), not yet in `human-checks.md`.

## 1 What landed

`Examples/Jotter/`: a notes app as its own SwiftPM package (library `JotterKit`, executable `Jotter`, `Tests/JotterTests`), depending on the checkout with
`.package(name: "MetalUI", path: "../..", traits: metalUITraits)` and the scaffold's products (`EX-A`, `EX-B`; tools 6.1 accepts `name:` with `traits:`;
built in a checkout directory named `sample-app`, not `MetalUI`). Sources (about 700 lines): `Note`/`NotesModel` (an `@Observable` `@MainActor` model, versioned JSON,
"today" injected), `RootView` (`VStack`, `HStack`, `Divider`, `.toolbar` with six items, `.searchable`), `SidebarView` (`List(_:selection:rowHeight:)` in a
`ScrollView`, an empty state over it), `NoteRow` (`.equatable()`, `.draggable`, `.dropDestination`, `.contextMenu`), `DetailView` (`TextField`, `TextEditor`,
`@FocusState`, `.onChange`, `.task(id:)`, a Markdown literal), `StatsView` (rectangles and a `Shape`), `Presentations` (`.confirmationDialog`, `.alert`,
`.fileExporter`, `.fileImporter`), `JotterApp` (`App.commands`), `Theme` (`ThemeColorKey`, `Color(light:dark:)`, `.preferredColorScheme`). Every section is its own
`Component` (Windows 1 MB stack). The model is created in `main.swift` and passed in (divergence 125).
Root: `Tests/MetalUIScaffoldTests/SampleAppTests.swift` (+2 tests, `EX-S`); CI: a macOS step in `swift.yml` and a Linux-image step in `sdl-gpu-linux.yml`;
`README.md`, `docs/getting-started.md`, `docs/guides/README.md` and `docs/testing.md` link it.

## 2 Findings (API rough edges the app hit; none fixed here)

1. **No `Canvas`/`GraphicsContext`** (known, `drawing-and-gpu.md`): the chart is `Rectangle`s and a `Shape` (`EX-K`).
2. **`.accessibilityIdentifier`/`.accessibilityLabel` on a container reach every child** (as SwiftUI); on a `TextField` placed before `.frame` the node became a plain
   group with no value, after it a `textField` (`EX-N`).
3. **`.focused($flag)` must be applied to the control before any proposal wrapper**; after `.frame`/`.accessibilityIdentifier` it bound a non-focusable wrapper and a
   focus write did nothing, silently (`EX-N`). A focus write from `.onChange` (the lifecycle drain) does apply, in the same frame.
4. **`Toggle` has no `.keyboardShortcut`** (`EX-Q`).
5. **A `List` row must be one `Element`**: an `.equatable()` component needs a `Column { }` around it; the error is a generic-constraint failure naming `EquatableComponent<NoteRow>`.
6. **A `List` created in a frame builds its rows one frame later**, so swapping it for an empty state flashes (`EX-M`).
7. **`Equatable` on a `Component` needs `nonisolated static func ==`** under Swift 6 (main-actor conformance error otherwise).
8. **`.preferredColorScheme` returns an `EnvironmentScope`, not an `Element`**: it cannot end a window's root, only sit inside a container.
9. **`Edges` has `init(all:)` and per-side, no horizontal/vertical**; `.padding` takes `Edges<Length>` on a legacy element (which a legacy `.frame` keeps it) and `Edges<Pixels>` on proposal content, so a modifier order silently changes the type wanted.
10. **A headless platform does not echo `.preferredColorScheme` as the appearance** (`EX-P`); `Text` parses Markdown only in a literal, so there is no live preview.
11. **A main-actor model read through a stdlib closure traps off the main thread**, which bounds a "build on a 1 MB thread" test (`EX-O`).
12. **Delete's ⌘⌫ belongs to a focused text field** (`EX-Q`).

