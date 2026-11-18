# MetalUI

A GPU-accelerated UI framework for Swift, modeled on
[gpui](https://github.com/zed-industries/zed) and following SwiftUI's
semantics. It runs on macOS (AppKit and Metal, the default) and on Linux and
Windows (SDL3 backend, portable text system). iOS, iPadOS, tvOS, watchOS and
visionOS are an explicit non-goal, not a gap.

> **Status: experimental.** The API still changes.

Website: <https://mburger89.github.io/MetalUI/> · [API reference](https://mburger89.github.io/MetalUI/api/documentation/metalui/)

## Requirements

- Swift 6.4 (`swift-tools-version: 6.4`; CI builds with Swift 6.4)
- macOS 14 or later with Metal, or Linux or Windows with the SDL backend
  ([cross-platform guide](docs/guides/cross-platform.md))

## Quick start

```sh
git clone https://github.com/mburger89/MetalUI.git
swift run --package-path MetalUI metalui new MyApp
cd MyApp && swift run MyApp
```

Add `--cross-platform` to `metalui new` for a package that also runs on Linux
and Windows. The generated app (`Sources/MyApp`) looks like this:

```swift
import MetalUI

@MainActor
func rootView() -> some Element {
    Column(gap: Pixels(16)) {
        ContentView()
    }
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity))
    .background(.surface)
}

struct ContentView: Component {
    @State var presses = 0

    var content: some ElementGroup {
        Text("Hello from MyApp").font(size: 24)
        Row(gap: Pixels(12)) {
            Button("Press me") { presses += 1 }
            Text("pressed \(presses) times")
        }
    }
}

// main.swift
let app = try App()
try app.openWindow(title: "MyApp",
                   size: Size(width: Pixels(640), height: Pixels(400)),
                   content: rootView)
app.run()
```

The package also gets a test target, a README and a macOS bundling script. For
a complete sample app, see [`Examples/Jotter`](Examples/Jotter/README.md).

## What is included

Products to depend on:

| Product | Contents |
| --- | --- |
| `MetalUI` | The framework: elements, layout, controls, state, animation, gestures, presentations, app shell, `CodeView`, `MarkdownView` |
| `MetalUICodeBuffer` | The text buffer behind a code view: rope, snapshots, edits, undo, find. No UI |
| `MetalUIMarkdown` | Block-level Markdown parser (CommonMark and GFM tables) with streaming append. No UI |
| `MetalUITerminal` | Terminal emulator: parser, grid and snapshots. No UI |
| `MetalUITerminalUI` | `TerminalView`, the terminal's UI half |
| `MetalUITesting` | Headless test windows: input injection, inspection, accessibility tree. For test targets only ([testing](docs/testing.md)) |
| `MetalUISDL`, `MetalUISDLGPU` | The SDL3 backend for Linux and Windows, and SDL_GPU access for app code. Behind the `SDL` and `AccessKit` package traits |
| `metalui` | The command-line tool behind `metalui new` |

The remaining products (scene, text and font building blocks, the shader
compiler) are infrastructure. On Linux and Windows an app passes the backend to
`App(platform:textSystem:)`; see the [cross-platform guide](docs/guides/cross-platform.md).

## Demos

```sh
swift run -c release MetalUIDemo
METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo
```

`MetalUIDemo` runs the main demo. These environment variables, each set to
exactly `1`, select another:

`METALUI_TEXT_INPUT_DEMO`, `METALUI_CONTROLS_DEMO`, `METALUI_DND_DEMO`,
`METALUI_LOOKS_DEMO`, `METALUI_GLASS_DEMO`, `METALUI_METALVIEW_DEMO`,
`METALUI_MENUS_DEMO`, `METALUI_SERVICES_DEMO`, `METALUI_LIST_DEMO`,
`METALUI_OUTLINE_DEMO`, `METALUI_LAZY_DEMO`, `METALUI_RICH_TEXT_DEMO`,
`METALUI_CANVAS_DEMO`, `METALUI_APP_SHELL_DEMO`, `METALUI_SELECTION_DEMO`,
`METALUI_INVALIDATION_DEMO`, `METALUI_RETAINED_DEMO`, `METALUI_CHROME_DEMO`,
`METALUI_CLIPBOARD_DEMO`, `METALUI_CODE_DEMO`, `METALUI_MARKDOWN_DEMO`,
`METALUI_TABS_DEMO`, `METALUI_OVERLAYS_DEMO`, `METALUI_KEY_FOCUS_DEMO`,
`METALUI_ACCESSIBILITY_DEMO` and `METALUI_TERMINAL_DEMO` (macOS only).

## Build and test

```sh
swift build
swift test --no-parallel
# the full run, including the architecture guards
swift build --build-system native --build-tests && swift test --build-system native --no-parallel
```

The SDL backend's tools and tests are a separate package in
[`Backends/SDL`](Backends/SDL/README.md), which needs SDL3 3.4 or later and
lists the build flags per platform.

## Documentation

- [Getting started](docs/getting-started.md)
- [Guides](docs/guides/README.md)
- [API overview](docs/api-overview.md)
- [Differences from SwiftUI](docs/divergences.md)
- [Testing](docs/testing.md)
- [Packaging](docs/packaging.md)
- [Migration](docs/migration.md)

Contributors should read [`CLAUDE.md`](CLAUDE.md) (`AGENTS.md` is a copy of it
for Codex).

## License

MIT, see [`LICENSE`](LICENSE). Licences for the bundled third-party code are
in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
