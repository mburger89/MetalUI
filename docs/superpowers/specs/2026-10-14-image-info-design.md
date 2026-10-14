# Header-only image read and bounded decode — design

Item S9 of the gpui-gap priority list (user request 2026-10-02; not a plan task), MetalCreator gap XP-G10
(developer-c0, 2026-10-14, low priority). Rulings: [`../2026-10-14-image-info-decisions.md`](../2026-10-14-image-info-decisions.md)
(`IH-`). Record: `../../record/117-image-info.md` (Record phase). Branch `feat/image-info` from `ceca59f6`.
Divergence labels reserved 475–484: **none taken** (everything is class `M`; SwiftUI has no such API).

**Status: DESIGNED. One lane.**

## 1 What exists and what is missing

S2 (record 113) gave `DecodedImage(data:format:)`: size and orientation only after a full stb decode
(`ImageDecoding.swift` `decodeImage`, which checks `pngStructureIsIntact`/`jpegScanIsTerminated`, then stb, then
`decodedSizeIsAccepted` = each side 1…16384). `ImageEXIF.swift` has bounds-checked orientation walks over an
`UnsafeRawBufferPointer` (`exifOrientation(inJPEG:)`, `(inPNG:)`, `tiffOrientation`). Nothing reads PNG IHDR or a
JPEG SOF. An app that wants to refuse a 16 MB input or an 8,192² image **before** stb allocates (the decode peaks
near 450 MB at 8,192²) must keep its own header reader and cross-check afterwards (what MetalCreator does).
stb has no cancellation hook.

SwiftUI has no header-only image API (its `Image` takes a decoded `CGImage`/`NSImage`); the analogue is ImageIO's
`CGImageSourceCopyPropertiesAtIndex` (width, height, depth, orientation without a decode). That is a *precedent for
the shape*, not a claim: no SwiftUI-facing behaviour is asserted, so **no probe is owed** (`IH-A`). gpui has no
decode API (it takes frames from the Rust `image` crate); not consulted.

## 2 Public API (all MetalUI-only, class `M`)

```swift
public struct ImageInfo: Sendable, Hashable {
    public enum Format: Sendable, Hashable { case png, jpeg }
    public let format: Format
    public let width: Int            // stored, before orientation, ≥ 1
    public let height: Int
    public let orientation: Image.Orientation   // .up when absent/damaged (as DecodedImage, IB-C)
    public let bitDepth: Int         // PNG IHDR bit depth (1,2,4,8,16); JPEG SOF sample precision
    public let channelCount: Int     // stored channels: PNG grey 1, grey+alpha 2, RGB 3, palette 3, RGBA 4; JPEG components 1…4
    public var orientedSize: (width: Int, height: Int)
    public init?(data: Data)
    public init?(contentsOfFile path: String)
}

extension DecodedImage {
    public struct Limits: Sendable, Hashable {
        public var maxInputBytes: Int?   // nil = no limit of this kind
        public var maxSide: Int?         // applies to stored width and height
        public var maxPixels: Int?       // width × height
        public init(maxInputBytes: Int? = nil, maxSide: Int? = nil, maxPixels: Int? = nil)
    }
    public init?(data: Data, format: Format = .rgba, limits: Limits)
    public init?(contentsOfFile path: String, format: Format = .rgba, limits: Limits)
}
```

`ImageInfo` returns `nil` for any other format, a missing/unreadable file and every damaged header (never a trap).
It applies **no size limit** (`IH-D`): a 40000×40000 PNG reports 40000×40000; `DecodedImage` is the one that says
no above 16384. The existing `init?(data:format:)`/`init?(contentsOfFile:format:)` keep their signatures and results
for every image they decoded before, except the one new refusal of `IH-I`.

## 3 Behaviour

**PNG** (`IH-E`): signature; the first chunk must be `IHDR` with length 13 and a correct CRC-32 (the one
`pngStructureIsIntact` uses, made internal); width, height in `1…2³¹−1`; (colour type, bit depth) one of PNG's
legal pairs; compression/filter/interlace bytes are not interpreted (stb refuses what it cannot read, at decode).
Orientation from the eXIf walk (before first `IDAT`, else after the last, as `IB-K`).
**JPEG** (`IH-F`): `SOI` then the segment walk of `exifOrientation(inJPEG:)`; the first SOF marker wins
(`C0–C3, C5–C7, C9–CB, CD–CF`, never `C4` DHT, `C8` JPG, `CC` DAC); payload `length ≥ 8 + 3·components`,
precision byte, height, width (both `≥ 1`: height 0 means DNL, which stb refuses), components `1…4`; the walk stops
at the first `SOS` (a SOF after it is never read) and the first `Exif\0\0` `APP1` before it gives the orientation. A
file with no SOF before SOS is `nil`.
**File** (`IH-G`): `init?(contentsOfFile:)` reads **only the structure** through a seek-based reader: segment and
chunk headers (≤ 8 bytes each) plus the IHDR/SOF/EXIF payloads, never the pixel data; memory is O(1 MiB + a 64 KiB window, `IH-M`) and the
answer **equals `ImageInfo(data:)` of the whole file** (test 11). An EXIF payload larger than 1 MiB is treated as
damaged (`.up`) on both paths (`IH-G` item 3).
**Bounded decode** (`IH-J`): with `limits`, in order: input size (`data.count`, or the file's size before reading it)
→ `ImageInfo` (nil if unreadable) → `maxSide` on both sides → `maxPixels` → only then `decodeImage`. A refused
image never reaches stb. The result for an image inside the limits is byte-identical to the unlimited init.
**Agreement** (`IH-I`): after stb decodes, its width/height must equal the header's, else `nil`, in **both** inits
(the unlimited one too: a disagreement is a parser bug in one of the two and the bytes are untrustworthy).

## 4 Files (one lane)

New: `Sources/MetalUI/ImageInfo.swift` (public type, `Limits`, the two `DecodedImage` inits' bodies);
`Sources/MetalUI/ImageHeader.swift` (internal `HeaderSource` — `size: Int` plus `read(at:count:) -> [UInt8]?`, with a memory
and a `FileHandle` implementation — and the IHDR/SOF/EXIF walks over it).
Edited: `ImageEXIF.swift` (the two buffer walks become thin wrappers over the source walks so there is one walk, `IH-H`;
`tiffOrientation` unchanged); `ImageDecoding.swift` (`crc32` internal; `decodeImage(_:channels:expecting:)` adds the
size-equality check, default `nil` = skip for the ImageBitmap path); `DecodedImage.swift` (inits call the above).
`ImageBitmap(data:)` is **untouched** (`IH-L`). No `Package.swift`, no `CStbImage`, no shader, no Backends/SDL change
(everything is Foundation + Swift in `MetalUI`, built on Linux/Windows by the existing portable-target CI;
`FileHandle` is Foundation on all three). Docs: `docs/guides/cross-platform.md` (a block after the `DecodedImage` one,
mirrored byte for byte in `Tests/MetalUITestingTests/GuideMirrors*.swift`, `DG-C`), `docs/api-overview.md` (extend the
S2 paragraph), `docs/migration.md` (one row: `ImageInfo`/`DecodedImage.Limits` are new names; the new refusal),
`docs/probes/closeout-inventory-map.tsv` (`image-info` family, class `M`, plus the `ImageInfo.swift` source row),
`docs/probes/closeout-public-api.sh` re-recorded census. No demo section (no drawing). Human checks: **none added**
(nothing here is a look); the sign-off line says so.

## 5 Tests (all in `Tests/MetalUICrossPlatformTests/ImageInfoTests.swift`, generated bytes, S2's `ImageEXITests` builders; no files, no sleep)

"Red before" is "does not compile / symbol absent" for every test that names `ImageInfo` or `Limits` (they are new); the
mutation column is what must redden **that** test, applied to the named spelling, run on the full unfiltered suite.

| # | Test | Pins | Mutation that must redden it |
|---|---|---|---|
| 1 | `aPNGReportsSizeDepthAndChannelsForEveryColourType` | all 7 legal (colour type, depth) pairs incl. 16-bit and palette; 5×3 generated | colour-type→channels table: palette 3→1 |
| 2 | `aJPEGReportsSizePrecisionAndComponents` | 1- and 3-component baseline, and SOF2 progressive, precision 8 | SOF set loses `0xC2` |
| 3 | `everyDimensionBearingSOFMarkerIsRead` | loop `C0–C3,C5–C7,C9–CB,C D–CF` read; `C4`, `C8`, `CC` skipped (a DHT before the SOF must not be taken as SOF) | add `0xC4` to the set |
| 4 | `theSizeEqualsTheDecodersForEveryFixture` | every S2 fixture + generated PNG/JPEG: `ImageInfo` size/orientation == `DecodedImage`'s | IHDR width/height read swapped |
| 5 | `theOrientationMatchesTheS2WalksOnEveryFixture` | `ImageInfo.orientation == exifOrientation(inJPEG/inPNG) ?? .up` for all 8 tags × both formats, eXIf before/after IDAT, between IDATs ignored | drop the after-IDAT arm in the shared walk |
| 6 | `everyTruncationOfAPNGIsNilOrAPrefixAnswer` | for each length 0…N of a PNG with eXIf: never traps; below IHDR end → nil; at/after IHDR end → size right | IHDR bound `<=` → `<` (read past end traps or wrong) |
| 7 | `everyTruncationOfAJPEGIsNilOrAPrefixAnswer` | same, every length of a JPEG with APP0, APP1, SOF0, SOS | SOF length guard removed |
| 8 | `aHostileHeaderIsNilNotATrap` | PNG: IHDR length ≠13, bad CRC, width 0, width 2³¹, depth 3, (colour 3, depth 16); JPEG: SOF length 7, height 0, width 0, components 0/5, SOF only after SOS, 2 SOF (first wins), `FF` fill runs, APP1 length 65535 past EOF | drop the CRC check; drop height≥1 |
| 9 | `aFormatOtherThanPNGOrJPEGIsNil` | GIF, TIFF, WebP, BMP, empty `Data` | add a GIF arm that returns a made-up size |
| 10 | `aSizeAboveTheDecoderLimitStillReports` | 20000×20000 IHDR-only PNG (no pixels needed: header + IEND) → `ImageInfo` 20000×20000 while `DecodedImage` is nil | add `decodedSizeIsAccepted` to `ImageInfo` |
| 11 | `theFileReaderEqualsTheDataReaderAndReadsNoPixels` | temp file of every fixture (incl. eXIf after a 3 MB IDAT): equal to `Data` result; a counting source shows window refills <= 2 + size/64 KiB + payload reads and no refill starting inside the 3 MB IDAT payload (`IH-M`; pins work, not time); plus a directory path, a FIFO-like non-regular path and a size shortened after recording give `nil` (`IH-N`) | file reader reads `prefix(65536)` only (eXIf-after-IDAT fixture reddens) |
| 12 | `anEXIFPayloadOverOneMebibyteIsDamagedOnBothPaths` | cap and cap+1 | cap off by one / cap removed on the file path only |
| 13 | `limitsRefuseBeforeStbSeesTheBytes` | an oversize-side, over-pixels and over-input image with a `decodeImage` hook counter (internal `decodeImageCallCount` on a test seam): 0 calls; inside limits: 1 call and pixels == unlimited init | move the limit check after `decodeImage` |
| 14 | `eachLimitIsInclusiveAtItsBoundaryAndRefusedOneOver` | `maxSide`, `maxPixels`, `maxInputBytes` at N and N+1; `nil` = unlimited | `<=` → `<` |
| 15 | `aFileOverTheInputLimitIsRefusedWithoutReadingIt` | `contentsOfFile` with `maxInputBytes` below file size: counting source reads 0 bytes of pixel data and the file is not loaded (source seam counts `read` calls = 0) | check the limit after loading |
| 16 | `aDecodeWhoseSizeDisagreesWithTheHeaderIsNil` | internal `decodeImage(_,expecting:)` with a doctored expected size → nil; matching → value; both inits | drop the equality check |
| 17 | `theUnlimitedInitStillDecodesEveryS2Fixture` | `DecodedImage(data:)` result unchanged for all `DecodedImageTests` fixtures (re-run: those tests stay green and unedited) | make `ImageInfo` stricter than the decoder (e.g. require `Exif` before SOF) |
| 18 | `anImageInfoValueIsEqualHashableAndSendable` | typecheck guard G1 (plain import: `init`'s members public; `HeaderSource` and the walks unreachable) | make `HeaderSource` public (guard reddens); **the new guard is mutated red once** |
| 19 | `theGuideBlockIsMirrored` | `GuideMirrors*` region `cross-platform #n`, `GuideDocCheck` green | change a byte in the guide |

Inventory/undocumented scripts print nothing; census re-recorded; Linux image runs `MetalUICrossPlatformTests` (and the
portable target build); the fourteen offscreen images 0 px (nothing draws); `swift package clean` is **not** owed (no
stored property on an existing public type).

## 6 Carried (named, not built)

- **Cancellation of an in-range decode** (`IH-K`): stb_image has no hook; an input-callback cancel (`stbi_io_callbacks`
  returning short) is a lead whose behaviour per format is **unmeasured** (PNG reads all IDAT before inflating; JPEG
  reads progressively). Owner: a later item if an app asks; MetalCreator's bound-before-decode covers its 450 MB case.
- **`ImageBitmap(data:limits:)`** (`IH-L`) and ImageIO-backed info for other formats on Apple (`IH-B`): additive later.
- **`hasAlpha`** (PNG `tRNS`, JPEG never): needs a chunk scan; not cheap (`IH-C`).
