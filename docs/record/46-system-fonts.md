# 46 — System font discovery, 2026-09-23

Branch `feat/system-fonts`, from `feat/text-input` (PR #26, record §45).
Spec: `docs/superpowers/specs/2026-09-23-system-fonts-design.md`, rulings
`SF-A`…`SF-D` (next `SF-E`). Roadmap item 8b, the last unticked item.

## What changed

- `MetalUIFreeType`: `FreeTypeFaceNames.read(path:)` returns every face of a
  file with its PostScript, family, full and style names, through
  `FT_New_Face`. The name-table decoder `FreeTypeFont.name(id:)` became a
  static over an `FT_Face` so both paths share it.
- `MetalUIPortableText`: `PortableFontResolver`'s faces are lazy.
  - There is a new `register(_:inCascade:load:)` and a new
    `init(defaultFont:load:)`.
  - The cascade skips faces registered with `inCascade: false`.
  - The byte-registering API and its behaviour are unchanged.
- `MetalUISystemFonts` is a new portable target and library product:
  `SystemFonts.directories`, `defaultFamilies`, `fallbackFamilies`,
  `scan(_:)`, `resolver(…)` and `NoFontsFound`.
- `Backends/SDL`'s `MetalUISDLDemo` takes `METALUI_SYSTEM_FONTS=1`.

## Measured

- **macOS:** `SystemFonts.resolver()` over this machine's
  `/System/Library/Fonts`, `/Library/Fonts` and `~/Library/Fonts` resolves
  `family: nil` to Helvetica's regular face (`Helvetica`). `Helvetica.ttc`
  reads as more than one face, including a Bold, in face order. The whole
  system test runs in well under a second.
- **Laziness (SF-B):** a resolver reads no file until one is resolved. The
  first `resolve(nil)` reads exactly the default face and the one installed
  fallback family. A face resolved by name is read once, whatever the size.
- **Linux aarch64** (`swift:6.4-noble`, which carries
  `/usr/share/fonts/truetype`): the 6 `SystemFontsTests` pass, the system arm
  among them. The root's other portable suites read 486 + 3 + 22, unchanged.

## Counts

1752 tests, 97 goldens, 78 guards; 0 `error:` and 0 `warning:` on both build
systems after `swift package clean` (`Test run with 1752 tests in 3 suites
passed`; the guards ran). 1752 = 1746 + 6.

## Mutations (`--filter SystemFontsTests`)

| # | Mutant | Reddens |
|---|---|---|
| F1 | the cascade ignores `inCascade` (`FB-B` for every face) | `theResolverDefaultsCascadesAndLoadsLazily` |
| F2 | bytes loaded at registration | `theResolverDefaultsCascadesAndLoadsLazily` |
| F3 | regular faces not registered first | `aFamilysRegularFaceIsRegisteredBeforeItsOtherStyles` |
| F4 | the default is the first face, whatever the families | `theResolverDefaultsCascadesAndLoadsLazily`, `thePlatformsOwnFontsResolve` |
| F5 | bytes re-read per size | `theResolverDefaultsCascadesAndLoadsLazily` |
| F6 | only the first face of a collection read | **green at first**: the test fonts are all single-face files. The macOS arm now reads `Helvetica.ttc` and it reddens `thePlatformsOwnFontsResolve` |

## Open

- **Not pinned on Linux or Windows CI:** the fallback lists' coverage (which
  families a stock Ubuntu or Windows image has), and fontconfig's answer. The
  Windows arm asserts only that Segoe UI is the default.
- **A human look:** `METALUI_SYSTEM_FONTS=1 swift run MetalUISDLDemo` on a
  desktop Linux and on Windows.
- The fallback lists are fixed; fontconfig's configured substitutions are not
  consulted beyond the default family (spec, "not measured").
