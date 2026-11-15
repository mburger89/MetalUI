# Getting Started

Create a MetalUI app with the `metalui` scaffolder and run it.

## Overview

`metalui new` writes a SwiftPM package with an executable that opens a MetalUI window. See the [website](https://mburger89.github.io/MetalUI/) for the install step and the platform notes.

```sh
git clone https://github.com/mburger89/MetalUI.git
swift run --package-path MetalUI metalui new MyApp
cd MyApp
swift run MyApp
```

`swift run --package-path` leaves the current directory where it is, so `MyApp/` is created beside the clone.

### What you get

```
MyApp/
  Package.swift                  depends on MetalUI (git URL, pinned to one commit)
  Sources/MyApp/main.swift       App(), one window, app.run()
  Sources/MyApp/ContentView.swift  a Component with @State and a Button
  Tests/MyAppTests/MyAppTests.swift  presses the Button headless (`swift test`)
  Packaging/macOS/Info.plist     identifier com.example.MyApp
  scripts/bundle-macos.sh        builds build/MyApp.app
```

### Testing the interface

`swift test` runs `Tests/MyAppTests`. It opens the root view in a headless window through MetalUI's test harness, clicks the button by its accessibility label and reads the text it changes. No screen is needed, so it runs in CI.

### A bigger example

[`Examples/Jotter`](https://github.com/mburger89/MetalUI/tree/master/Examples/Jotter) is a finished notes app with a sidebar list, text editing, a toolbar, menus, dialogs, drag-to-reorder and tests.

### Which MetalUI the app gets

The generated `Package.swift` pins MetalUI to one commit, so nothing that changes on `master` reaches the app until you move the pin. The full guide is [docs/getting-started.md](https://github.com/mburger89/MetalUI/blob/master/docs/getting-started.md).
