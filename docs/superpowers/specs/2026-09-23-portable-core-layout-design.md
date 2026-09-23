# Core and layout off macOS — design

**Status: implemented** on `feat/portable-core-layout` (record §34);
roadmap item 5 of `plans/2026-09-23-cross-platform-roadmap.md`. **Ruling
prefix:** `PC-` (`PC-A`…`PC-C`, next `PC-D`; rulings here).

## Rulings

### PC-A — The manifest declares Apple-bound targets on macOS only

`Package.swift` builds two lists. **Declared everywhere:** `MetalUICore`,
`MetalUILayout`, `MetalUIScene`, `MetalUIShaderTypes`, `CHarfBuzz`,
`CUnibreak`, `CFreeType`, `MetalUIHarfBuzz`, `MetalUIFreeType`,
`MetalUIPortableText`, `MetalUITestSupport`, `MetalUICoreTests`,
`MetalUILayoutTests`, and the four portable library products. **Declared
under `#if os(macOS)`:** everything that imports AppKit, CoreText, Metal or
WebKit — `MetalUIText`, `MetalUIRender`, `MetalUIPlatform`, `MetalUI`, the
demo, their tests, and the three portable oracles (`MetalUIPortableTextTests`,
`MetalUIHarfBuzzTests`, `MetalUIFreeTypeTests`), which compare against
CoreText. So `swift build --build-tests` and `swift test` work on Linux and
Windows as they are, with no filter. On macOS nothing changes.

`#if os(macOS)` in a manifest is the **host** that evaluates it; a
cross-compile from macOS to Linux would declare the Apple targets. Nothing
cross-compiles today.

### PC-B — The Core and Layout suites run off macOS, guarded where they cannot

Measured in `swift:6.4-noble` (the CI image) on aarch64: **486
`MetalUILayoutTests` and 22 `MetalUICoreTests` pass**, the goldens'
replay against WebKit's recorded boxes included, with no warning. What
cannot run off macOS is compiled out by `#if canImport(…)`, per declaration,
not per file:

- `canImport(WebKit)`: `LayoutOracle`, `generateGolden` and the four tests
  that drive WebKit (`oracleMeasuresFlexboxFromAFixtureFile`,
  `oracleReportsSubPixelQuantization`, `generatorProducesRawAndRoundedForAFixture`,
  `generatorRoundsWhenTheBrowserQuantizes`, `regenerateAllGoldens`,
  `committedGoldensMatchTheBrowser`) — the goldens are regenerated on macOS
  only, as before.
- `canImport(Darwin)`: the `malloc_logger` instrument and
  `freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine`; its sibling
  `freezeLoopMatchesItsAllocatingReferenceBitForBit` runs everywhere.

One portable test needed a Foundation difference fixed:
`everyFixtureFileIsListedInTheCorpus` lists `Fixtures/` with `FileManager`,
because Foundation on Linux types `Bundle.urls(forResourcesWithExtension:)`
as `[NSURL]?`.

### PC-C — Typecheck guards use this platform's build only

`modulesDirectory(containing:)` accepts a `.build/…/debug/Modules` only if
its resolved path names this platform's triple (`apple-macosx`, `linux`,
`windows`). Measured: a Linux container over a macOS working tree found the
macOS modules and **failed** `UnitSafetyTests`' two guards with "module
'MetalUICore' was created for incompatible target"; with the filter they
skip, as every guard does under a layout it does not know. Off macOS the
default build system's layout is not the one the helper reads, so the
guards skip there in CI too — they remain a macOS instrument.

## CI

`swift.yml`'s `scene-linux` job (kept under that id; now named "Root
package (Linux)") runs `swift build --build-tests` and `swift test
--skip-build` on the root package; a new `root-windows` job does the same on
Windows. An Apple import in any portable target fails both (measured
locally: `import CoreText` in `MetalUILayout` → `no such module 'CoreText'`).
