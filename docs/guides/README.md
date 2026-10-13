# Developer guides

Task-led guides for an app author coming from SwiftUI. Each answers a handful of "how do I…"
questions, links to the reference ([`api-overview.md`](../api-overview.md)), the divergence table
([`divergences.md`](../divergences.md)) and the test harness ([`testing.md`](../testing.md))
rather than repeating them, and closes with the divergences a reader will hit, by number.
Starting a project is [`getting-started.md`](../getting-started.md); moving a legacy layout is
[`migration.md`](../migration.md).

| Guide | You will learn |
| --- | --- |
| [Layout](layout.md) | stacks and frames, `Row`/`Column`/`Box` against `HStack`/`VStack`, modifier order, where `.id()` goes, `Grid` |
| [State and identity](state-and-identity.md) | `@State`, `Binding`, `@Observable`, `@Environment`, `ForEach` identity, what loses state, `List` windowing and selection |
| [Input](input.md) | buttons and what a click does to focus, gestures and the one arena, `onCancelled`, `WindowDragGesture`, `onKeyPress` and key regions, text fields and `TextSelection` |
| [Presentations and the app shell](presentations-and-app-shell.md) | popovers, menus and commands, alerts and file dialogs, the toolbar, windows, close and terminate |
| [Drawing and GPU](drawing-and-gpu.md) | shapes, paths, gradients, shadows, materials, `Canvas`, `GPUSurface` and `MetalView` |
| [Cross-platform](cross-platform.md) | what differs on Linux and Windows, images, fonts, packaging |

## How the code blocks are checked

Every `swift` block in a guide is a complete file-scope fragment: imports, types and functions,
no top-level statements. Each block is copied, byte for byte, into a file of the
`MetalUITestingTests` target between `// guide: <name> #<n>` and `// end guide`
(`Tests/MetalUITestingTests/GuideMirrors*.swift`), so the ordinary build compiles it on
macOS, Linux and Windows, and a test in the same target drives the block through a headless
window ([`testing.md`](../testing.md)) to prove the claims the guide makes.
`GuideDocCheck.swift` fails when a guide's block and its copy differ by a byte (line endings
aside), when a swift block is not copied, when a fence carries any info string but `swift`,
`text` or `sh`, when a cited pin (a test name after the word pin and a colon) names no test, when a
`divergence N` has no row, when a relative link is dead, when a guide names an API that is not
yet on `master`, and when a sentence names a behaviour (its verb list is in `DG-E`) and cites no pin. Rulings: [`DG-A`…`DG-M`](../superpowers/2026-10-12-guides-decisions.md).

Not every block is a `swift` block. A snippet that cannot build in that target (an SDL platform,
which lives in a package behind a trait) is a `text` or `sh` fence, and says so.

To add a block to a guide, write it in the guide, copy it into the mirror file by hand, and run
`swift test --filter everyGuideBlockIsCompiledVerbatim`. A mirror made by a generator would
compare a file with itself, so there is none.
