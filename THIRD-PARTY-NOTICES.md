# Third-party notices

MetalUI itself is MIT-licensed (`LICENSE`). It vendors the C and C++ libraries
below and, for the SDL backend, links two libraries it does not vendor. An
application that ships a MetalUI binary must carry the notices for what that
binary contains. This file says which products contain what, and where each
licence text is. Facts were read from `Package.swift`, each target's
`VENDORED.md` and the licence files in the tree.

## Vendored code

| Component | Version | Licence (as used) | Licence text in the repo | Linked by |
|---|---|---|---|---|
| stb_image (`CStbImage`) | 2.30 | MIT or public domain (Unlicense), dual | `Sources/CStbImage/LICENSE` | **Every `MetalUI` product on every platform** (macOS included): `MetalUI` depends on `CStbImage` unconditionally. Not behind any trait. |
| FreeType (`CFreeType`) | 2.14.3 | FreeType License (FTL), chosen over GPLv2 (`VENDORED.md`: "used under the FTL") | `Sources/CFreeType/FTL.TXT`, with the dual-licence statement in `Sources/CFreeType/LICENSE.TXT` | `MetalUIFreeType`, so `MetalUIPortableText` and `MetalUISystemFonts`. Not linked by `MetalUI` on macOS (CoreText). Linked by any app that uses the portable text system: the Linux and Windows (SDL) starter, or macOS `App(platform:textSystem:)` with `MetalUIPortableText`. |
| HarfBuzz (`CHarfBuzz`) | 14.5.0 | "Old MIT" | `Sources/CHarfBuzz/COPYING` | `MetalUIHarfBuzz`, so `MetalUIPortableText`. Same products as FreeType. |
| libunibreak (`CUnibreak`) | 8.0 | zlib | `Sources/CUnibreak/LICENCE` | `MetalUIPortableText`. Same products as FreeType. |
| SheenBidi (`CSheenBidi`) | 3.0.0 | Apache-2.0 | `Sources/CSheenBidi/LICENSE` | `MetalUIPortableText`. Same products as FreeType. |

Every vendored directory has its licence file; there is no vendored code without
one. `Sources/CHarfBuzz/COPYING` says that subdirectories may carry their own
`COPYING`; the vendored tree has none (checked: the only `COPYING` is the top
one). FreeType's own `LICENSE.TXT` names further licences for parts of FreeType
(BDF/PCF drivers, `fthash`, the zlib-based gzip module, HarfBuzz-derived autofit
files, public-domain MD5); none of those sources is in the vendored subset
(`VENDORED.md` lists what is kept: `base`, `sfnt`, `truetype`, `cff`, `psaux`,
`psnames`, `smooth`, with gzip off).

The Adobe CFF engine files carry "Copyright Adobe Systems Incorporated" headers
under the FTL; they are covered by `FTL.TXT` as part of FreeType.

### What each product contains

| Product / configuration | stb_image | FreeType | HarfBuzz | libunibreak | SheenBidi | SDL3 | AccessKit |
|---|---|---|---|---|---|---|---|
| `MetalUI` on macOS (CoreText text system, default) | yes | no | no | no | no | no | no |
| `MetalUI` on macOS plus `MetalUIPortableText` / `MetalUISystemFonts` | yes | yes | yes | yes | yes | no | no |
| `MetalUI` + `MetalUIPortableText` + `MetalUISDL`, trait `SDL`, Linux / Windows | yes | yes | yes | yes | yes | yes (dynamic) | no |
| Same with trait `AccessKit` | yes | yes | yes | yes | yes | yes (dynamic) | yes (static) |
| `MetalUICore`, `MetalUILayout`, `MetalUIScene`, `MetalUIPlatform`, `MetalUIPath`, `MetalUITextSystem` alone | no | no | no | no | no | no | no |

Measured on macOS: `swift build -c release --product MetalUIDemo` (9,619,400
bytes), then `nm .build/release/MetalUIDemo`: 92 lines mention `stbi_` (89 begin
`_stbi_`; 5 are global `T` symbols and 62 are local or static text symbols); 0
`_FT_`, 0 `_hb_`, 0 `_ub_`, 0 `linebreak`, 0 SheenBidi `SB*` symbols;
`otool -L` lists CoreText, ImageIO, AppKit, Metal and QuartzCore and no
third-party dylib. The rows that include FreeType, HarfBuzz, libunibreak,
SheenBidi, SDL3 and AccessKit follow from the target graph and are not measured
here.

## Libraries that are not vendored (SDL backend only)

These are linked only when a dependent enables the `SDL` trait (SDL3) and the
`AccessKit` trait (AccessKit); neither is on by default.

| Component | Licence | Where it comes from | How it ships |
|---|---|---|---|
| SDL3 | zlib | The system or a package: `libSDL3` on Linux, `SDL3.dll` from SDL3's VC package on Windows (`lib\x64` or `lib\arm64`). Not in this repo. | Dynamic library beside the executable or a system dependency. Its zlib licence text comes with the SDL3 release (`LICENSE.txt`); copy it. |
| AccessKit (`accesskit-c` 0.23.0 and the Rust AccessKit it wraps) | MIT or Apache-2.0 (the AccessKit project's published licence; the text is in the downloaded archive, not in this repo) | `python3 Backends/SDL/scripts/fetch-accesskit.py` downloads `accesskit-c-0.23.0.zip` from the AccessKit GitHub release (SHA-256 checked) and builds or unpacks the static library. Not vendored. | Static, inside the executable. Take the licence files from the fetched archive, and those of the Rust crates it was built from if you build it yourself. |

Gap: neither SDL3's nor AccessKit's licence text is in this repo; take them
from the SDL3 release and the fetched `accesskit-c-0.23.0` directory.

## What the repository does not ship

`Tests/Fonts/` (Noto Sans, Noto Sans Arabic, Source Sans 3) are test inputs
(`FT-G`), loaded by `#filePath`, never a resource of a product. If you copy them
into an app, add their OFL notices, which are not in this repo.

## Licence texts

The full text is in the file named in the first table; each must travel with a
binary that contains the component. Short forms follow for the notices that
require reproducing a text.

### stb_image (MIT or public domain)

Text: `Sources/CStbImage/LICENSE` (MIT alternative: Copyright (c) 2017 Sean
Barrett; public domain alternative: Unlicense). Either alternative satisfies
the licence; shipping the MIT text is the conservative choice.

### FreeType (FTL)

Text: `Sources/CFreeType/FTL.TXT`. The FTL requires crediting the FreeType project
in the documentation of a product that includes it. Suggested line:

> Portions of this software are copyright (c) 1996-2026 The FreeType Project
> (www.freetype.org). All rights reserved.

(The vendored sources carry "Copyright (C) 1996-2026" headers.)

### HarfBuzz (Old MIT)

Text: `Sources/CHarfBuzz/COPYING`. The permission notice requires the copyright
list and the two disclaimer paragraphs to appear in all copies.

### libunibreak (zlib)

Text: `Sources/CUnibreak/LICENCE`. Attribution is appreciated, not required;
the notice must not be removed from source distributions.

### SheenBidi (Apache-2.0)

Text: `Sources/CSheenBidi/LICENSE` (Apache License 2.0). No NOTICE file is in the
vendored subset.
