# 113 — Public image decoding and orientation (S2)

Branch `feat/image-decode-api` from `fb9a7e42`. Not a plan task: item S2 of the gpui-gap priority list (user request
2026-10-02), MetalCreator's SDL-port gap 4 (developer-c0, 2026-10-13). Spec
`docs/superpowers/specs/2026-10-13-image-decode-api-design.md`; rulings `IB-A`…`IB-M` in
`docs/superpowers/2026-10-13-image-decode-api-decisions.md` (next unused `IB-N`); probe
`docs/probes/swiftui-image-orientation.swift`. Divergence labels reserved 435–444: **435 taken** (`IB-G`).

**Status: BUILT, both lanes.** No C change, no new target, no shader or renderer change (so no `replay.hlsl`), no
change to `ImageTexture`.

## §1 What shipped

- Lane 1 (decode, EXIF, orientation type): `Image.Orientation` (SwiftUI's eight cases and raw values, plus
  `init?(exifValue:)`, `exifValue`, `swapsAxes`), `ImageEXIF.swift` (bounds-checked JPEG `APP1` and PNG `eXIf`
  readers, Foundation-free), `DecodedImage` (straight RGBA8 or 8-bit grey, `bytesPerRow`, reported orientation,
  `orientedSize`, `applyingOrientation()`), `ImageBitmap(_ decoded:)`, `decodeImage(_:channels:)`; tests 1-15 and guard
  `G-IB1`; rulings `IB-A`…`IB-L`. Its mutation table M1-M18 is in the lane's commits and `IB-L`.
- Lane 2 (drawing, docs, guide): `ImageBitmap.oriented(_:)` over a cached `OrientedVariants` box, the two
  `Image(…orientation:)` overloads (no default, `IB-K`), tests 16-19, the cross-platform guide block #3 and its
  mirror (`GuideMirrorsImage.swift`), divergence 435, the `IB` human-check group, `docs/api-overview.md` and
  `docs/migration.md` notes, inventory rows and the re-recorded census (`IB-M`).

## §2 Lane 2 red lines, mutations, counts

Red (`471d5f21`): `ImageOrientationDrawTests.swift:48:87: error: extra argument 'orientation' in call` (and `cannot
infer contextual base in reference to member 'right'`), `oriented(_:)` absent; the test target did not compile.
Green after the implementation; `GuideDocCheck` green with the new block and its mirror.

Mutations, each applied, built, the five lane-2 tests run (filtered: the full unmutated suite finishes normally, §2.1),
restored, `git status --short` empty:

| id | mutation | reddened |
|---|---|---|
| M1 | `Image(decorative:scale:orientation:)` drops the argument | `anOrientedImageLaysOutAtTheOrientedSize`, `anOrientedBitmapKeepsOneTextureIdentityAcrossBuilds`, `orientedPixelsEqualSwiftUIsForAllEight` |
| M2 | `OrientedVariants` never returns its cached texture | `anOrientedBitmapKeepsOneTextureIdentityAcrossBuilds` |
| M3 | `permuteSamples` `.left` and `.right` exchanged | `orientedPixelsEqualSwiftUIsForAllEight` |
| M4 | `.up` copies (no early return in `oriented(_:)` or `permuteSamples`) | `upOrientedIsTheSameBitmapAndZeroWork` |

§2.1 Unfiltered `swift test --build-system native --no-parallel` after `swift package clean` (a stored property was
added to a public type): **3737 tests in 3 suites passed** (3717 + 20: lane 1's 15, lane 2's 5 including the guide
mirror test), `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice.
The mutation runs were filtered (five tests, seconds each) because a full run is about seven minutes on a shared Mac.
Census and closeout scripts: both print nothing after the re-record.

§2.2 Pixels: `docs/probes/demo-pixels/compare.sh <scratch> fb9a7e42 HEAD` (HEAD `a9725270`): the controls read their recorded
values and all fourteen images are **0 differing pixels, scene identical**. `git diff fb9a7e42 --stat -- Tests/MetalUITests/DemoFrameDeterminismTests*
Tests/**/Expected.swift` is empty. Not run: the Linux image and the Windows VM (lane 2 touches no `Backends/SDL` file;
the portable targets are for CI to confirm), `swift build --build-tests` on the default build system (see the hand-off).

## §3 Deferred

As the spec §7: orientation from HEIC/TIFF/WebP, applying EXIF by default (`IB-G`), colour profiles, 16-bit output,
premultiplied readback of a bitmap.
