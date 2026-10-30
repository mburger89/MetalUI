# `metalui bundle` decisions (prefix `BU-`)

Rulings for the `bundle` subcommand of `metalui` (`Sources/MetalUIScaffold/Bundle.swift`,
`Tests/MetalUIScaffoldTests/BundleTests.swift`). Next unused id: `BU-F`.
Why it exists: an app (MetalFlow) needs a real `.app` for user notifications; `docs/packaging.md` was manual.

## BU-A: the command, as a planner and an executor

`metalui bundle --product <P> --bundle-id <id> [--icon <png|icns>] [--version <x.y.z>] [--output <dir>] [--package-path <dir>]`.
Pure, tested as text: `parseBundleCommand` (arguments), `minimumMacOSVersion(inManifest:)`, `bundlePlan` (directories,
copies, Info.plist entries, icon conversion invocations, signing invocation). Impure, thin: `performBundle`, with every
process behind `BundleProcessRunner`, so a unit test never runs `swift build`. Same split as `metalui new`. Every
declaration is `package` (a tool, not API: no inventory row). `metalui bundle` is routed from `parseScaffoldCommand`
(`ScaffoldCommand.bundle`/`.bundleHelp`) and `runScaffold` gained a `processRunner:` parameter.

## BU-B: layout and resource bundles

`Contents/MacOS/<P>`, and every `*.bundle` in `swift build -c release --show-bin-path` copied to `Contents/Resources`.
`Contents/Resources` is a directory MetalUI's runtime finds (`ShaderLibrary.candidateDirectories`, `AI-N`: `Bundle.main.resourceURL`
is second), so no runtime change. An existing `<P>.app` is removed first.

## BU-C: Info.plist

Written with `PropertyListSerialization` (XML). Keys: `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`,
`CFBundlePackageType` APPL, `CFBundleShortVersionString` and `CFBundleVersion` (both `--version`, default 1.0),
`LSMinimumSystemVersion`, `NSHighResolutionCapable`, `NSPrincipalClass` NSApplication, `CFBundleIconFile` only with an icon.
`LSMinimumSystemVersion` is read from the package's `Package.swift` (`.macOS(.v14)` reads 14.0, `.v10_15` 10.15,
`.macOS("13.3")` 13.3), falling back to 14.0 (the framework's own platform). The version must be digits, `x`, `x.y` or `x.y.z`.

## BU-D: icons

`.icns` is copied as `<P>.icns`; `.png` is converted with `sips` (ten sizes, `icon_<n>x<n>[@2x].png`) and
`iconutil -c icns`, in a scratch `<output>/<P>.iconset` that is removed afterwards. Any other extension is refused at
parse time; a missing file fails before the build starts.

## BU-E: signing and platform

Ad hoc `codesign --force --sign - --deep <app>`; a Developer ID and notarization stay manual (`docs/packaging.md`). On any
platform but macOS the command prints an error and exits 1 (the code is portable Foundation, so it compiles everywhere and
the manifest needs no change, `PC-A`).

## Carried

- The end-to-end test (`METALUI_RUN_BUNDLE_TEST=1`, `theRealCommandProducesASignedAppThatVerifies`) bundles a tiny package
  without MetalUI; the demo run (shaders found at launch) was a manual check recorded with the change, not a test.
- The `.app` is not notarized, and Finder/Dock showing the icon is a look, not checked.
- `--deep` is deprecated for signing nested code in newer Apple guidance; resource bundles hold no code today. Re-open if an
  app ships frameworks or helper executables.
- A package with several executables still builds only `--product`. Universal (arm64 + x86_64) binaries are not produced.
