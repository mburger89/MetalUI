# 117 — Header-only image read and bounded decode (S9, `IH-`)

Item S9 of the gpui-gap priority list (user request 2026-10-02), MetalCreator gap XP-G10. Branch `feat/image-info`
from `ceca59f6`. Spec `docs/superpowers/specs/2026-10-14-image-info-design.md`; rulings
`docs/superpowers/2026-10-14-image-info-decisions.md` (`IH-A`…`IH-P`, next `IH-Q`). No divergence label taken
(class `M`, SwiftUI has no such API). No human check added (nothing here is a look).

## 1 What landed

- `ImageInfo(data:)` / `ImageInfo(contentsOfFile:)` (`ImageInfo.swift`): format (png/jpeg), stored size, EXIF
  orientation, bit depth, channel count, `orientedSize`; `nil` for any other format or damaged header; no size limit.
- `ImageHeader.swift`: `HeaderSource` (memory source, and a `FileHeaderSource` behind one 64 KiB window), the IHDR
  (length 13, CRC, legal colour/depth pairs), SOF (13 markers, first wins) and EXIF walks. `ImageEXIF.swift`'s two
  buffer walks are wrappers over the same walks (`IH-H`); S2's `ImageEXIFTests` are unedited and green.
- `DecodedImage.Limits(maxInputBytes:maxSide:maxPixels:)` and the two limited initialisers: input size, header, side,
  pixels, then decode; an overflowing product is a refusal (`IH-N`). The unlimited inits go through the same path.
- `decodeImage(_:channels:expecting:)` refuses a stb size that disagrees with the header (`IH-I`); `crc32` internal.
- Cancellation not built (`IH-K`); `ImageBitmap` untouched (`IH-L`).

## 2 Rulings added during implementation

`IH-O` (regular-file check by path metadata before open, size from the handle; counters are a passed `HeaderTrace`,
never a global) and `IH-P` (a JPEG damaged after its first SOF still answers; a malformed first SOF is `nil`).

## 3 Red lines, then green

Red (tests committed before the sources, build of the test targets): `cannot find 'ImageInfo' in scope`,
`type 'DecodedImage' has no member 'Limits'`, `extra argument 'limits' in call` (ImageInfoTests, the guide mirror).
Green: the 18 `ImageInfoTests` tests, guard `theHeaderSurfaceIsReachableAndTheWalkIsNot` (G-IH1) and the guide mirror
`theCrossPlatformGuideBoundsADecodeFromTheHeader`. Unfiltered native run: **3819 tests in 3 suites** (3799 + 20),
5 issues, exactly the five `AppKitPresentationTests` sheet issues of a locked screen, 0 `error:`, the only `warning:`
SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`.

After merging master `34491ff4` (§114; no record numbered 117 there, no renumbering): `swift package clean`, native build and
unfiltered run re-taken, **3823 tests in 3 suites** (3803 + 20), the same five locked-screen sheet issues, 0 `error:`, guards
238 + 1 = 239, census 3592 unmoved, inventory and undocumented scripts print nothing. The fourteen offscreen images were 0 px
against `ceca59f6` (verifier, before the merge; the merge touches only `Backends/SDL`).

## 4 Mutations (each applied to the spelling named, one at a time, tree restored, `git status` clean after each)

Run on the **filtered family** (`ImageInfoTests|DecodedImageTests|ImageEXIFTests|ImageDecodingTests|theHeaderSurface|
theCrossPlatformGuide|GuideDoc|ImageBitmap`, 63 tests), not the full suite: the mutated code is reached only by that
family, and a full run costs 12 minutes under load. The unmutated tree passed the full suite (section 3).

| Mutation | Reddened |
|---|---|
| palette 3 → 1 channel | `aPNGReportsSizeDepthAndChannelsForEveryColourType` |
| SOF set loses `C2` | `aJPEGReportsSizePrecisionAndComponents`, `everyDimensionBearingSOFMarkerIsRead` |
| `C4` added to the SOF set | `everyDimensionBearingSOFMarkerIsRead` |
| IHDR width/height swapped | 17 tests incl. `theSizeEqualsTheDecodersForEveryFixture`, `everyTruncationOfAPNGIsNilOrAPrefixAnswer` |
| after-IDAT arm dropped | `aPngExifChunkIsRead` (S2), `theFileReaderEqualsTheDataReaderAndReadsNoPixels`, `theOrientationMatchesTheS2WalksOnEveryFixture` |
| IHDR read one byte too long | `everyTruncationOfAPNGIsNilOrAPrefixAnswer` |
| JPEG segment bound dropped | `everyTruncationOfAJPEGIsNilOrAPrefixAnswer` |
| IHDR CRC check dropped | `aHostileHeaderIsNilNotATrap` |
| JPEG `height >= 1` dropped | `aHostileHeaderIsNilNotATrap` |
| GIF arm returning a size | `aFormatOtherThanPNGOrJPEGIsNil` |
| decoder limit inside `ImageInfo` | `aSizeAboveTheDecoderLimitStillReports`, `aHostileHeaderIsNilNotATrap` |
| file reader reads a 64 KiB prefix | `theFileReaderEqualsTheDataReaderAndReadsNoPixels`, `anEXIFPayloadOverOneMebibyteIsDamagedOnBothPaths` |
| EXIF cap off by one / removed | `anEXIFPayloadOverOneMebibyteIsDamagedOnBothPaths` (both) |
| limits checked after the decode | `limitsRefuseBeforeStbSeesTheBytes`, `eachLimitIsInclusiveAtItsBoundaryAndRefusedOneOver` |
| `maxSide`, `maxInputBytes`, `maxPixels` `<=` → `<` | `eachLimitIsInclusiveAtItsBoundaryAndRefusedOneOver` (each; side also `aFileOverTheInputLimit…`, `limitsRefuse…`) |
| overflow not reported | `eachLimitIsInclusiveAtItsBoundaryAndRefusedOneOver` |
| file input limit after the load | `aFileOverTheInputLimitIsRefusedWithoutReadingIt` |
| size-equality check dropped | `aDecodeWhoseSizeDisagreesWithTheHeaderIsNil` |
| `ImageInfo` stricter than the decoder | `theUnlimitedInitStillDecodesEveryS2Fixture` + four more |
| `HeaderSource` made `public` | guard `theHeaderSurfaceIsReachableAndTheWalkIsNot` (**the new guard mutated red once**) |
| a byte of the guide block changed | `everyGuideBlockIsCompiledVerbatim` |

Not mutated: the 32-bit overflow arm itself is reached only through `exceedsPixelLimit` (tested at `Int.max`).

## 5 Docs and inventory

`docs/guides/cross-platform.md` block #4 (mirror in `GuideMirrorsImage.swift`), `docs/api-overview.md`,
`docs/migration.md` (one row: new names and the one new refusal), inventory map rows (`image-info` family and the
`ImageInfo.swift` source row), census re-recorded; `closeout-inventory-check.sh` and `closeout-undocumented.sh` print
nothing.

## 6 Carried

Cancellation of an in-range decode (`IH-K`); `ImageBitmap(data:limits:)` (`IH-L`); ImageIO-backed info for other
formats (`IH-B`); `hasAlpha` (`IH-C`). 
