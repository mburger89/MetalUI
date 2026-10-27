# MetalUI

A GPU-accelerated UI framework for Swift, modeled on
[gpui](https://github.com/zed-industries/zed) and following SwiftUI's
semantics. It runs on macOS (AppKit and Metal) and on Linux and Windows (SDL3).

> **Status: experimental.** The API still changes.

## Requirements

- Swift 6.4
- macOS 14 or later with Metal, or Linux or Windows with the SDL backend
  ([cross-platform guide](docs/guides/cross-platform.md))

## Quick start

```sh
git clone https://github.com/mburger89/MetalUI.git
swift run --package-path MetalUI metalui new MyApp
cd MyApp && swift run MyApp
```

The generated app looks like this:

```swift
import MetalUI

struct ContentView: Component {
    @State var presses = 0

    var content: some ElementGroup {
        Text("Hello").font(size: 24)
        Row(gap: Pixels(12)) {
            Button("Press me") { presses += 1 }
            Text("pressed \(presses) times")
        }
    }
}

@MainActor
func rootView() -> some Element {
    Column(gap: Pixels(16)) { ContentView() }.padding(Pixels(24))
}

let app = try App()
try app.openWindow(title: "MyApp",
                   size: Size(width: Pixels(640), height: Pixels(400)),
                   content: rootView)
app.run()
```

Run the demo with `swift run -c release MetalUIDemo`. For a complete sample
app, see [`Examples/Jotter`](Examples/Jotter/README.md).

## Build and test

```sh
swift build
swift test --no-parallel
```

## Documentation

- [Getting started](docs/getting-started.md)
- [Guides](docs/guides/README.md)
- [API overview](docs/api-overview.md)
- [Differences from SwiftUI](docs/divergences.md)
- [Testing](docs/testing.md)
- [Packaging](docs/packaging.md)
- [Migration](docs/migration.md)

Contributors should read [`CLAUDE.md`](CLAUDE.md).

## License

MIT, see [`LICENSE`](LICENSE). Licences for the bundled third-party code are
in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
