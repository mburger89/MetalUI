# Public image decoding — design

Item S2 of the gpui-gap priority list (user request 2026-10-02; not a plan task), MetalCreator's SDL-port
gap 4 (developer-c0, 2026-10-13). Rulings: [`../2026-10-13-image-decode-api-decisions.md`](../2026-10-13-image-decode-api-decisions.md)
(`IB-A`…). Record: `../../record/113-image-decode-api.md` (Record phase). Branch `feat/image-decode-api`
from `fb9a7e42`. Divergence labels reserved 435–444: **435 taken** (`IB-G`).
Probe: `docs/probes/swiftui-image-orientation.swift` (header holds the output).

**Status: DESIGNED, not built.**

## 1 What exists and what is missing

`ImageBitmap(data:)`/`(contentsOfFile:)` decode PNG/JPEG on every platform through vendored stb_image 2.30
(`Sources/CStbImage`, internal; `ImageDecoding.swift` `decodeImage` returns straight RGBA8 internally;
`PX-B`…`PX-E`, divergence 138). The straight pixels are premultiplied once into an `ImageTexture` and the
straight copy is dropped; `ImageBitmap` exposes width/height only. No grey path, no EXIF read anywhere.
`Image`'s doc comment says `orientation:` is not offered. gpui has no image-decode API of its own (it hands
bytes to the `image` crate); not consulted further. SwiftUI's answers (probe, macOS 27.0.1):

- `Image.Orientation` exists: eight cases, the EXIF transforms under `CGImagePropertyOrientation`'s names
  (probe: 2x2 stored `R B / G W` renders `up RBGW`, `upMirrored BRWG`, `down WGBR`, `downMirrored GWRB`,
  `leftMirrored RGBW`, `right GRWB`, `rightMirrored WBGR`, `left BWRG`); its raw values are SwiftUI's own
  (up 0, left 1, upMirrored 2, leftMirrored 3, downMirrored 4, rightMirrored 5, down 6, right 7), not EXIF's.
  A rotated orientation swaps the drawn width and height (2x1 `.right` draws 1x2).
- The `CGImageSource` route ignores EXIF (4x2 JPEG tagged 6 gives a 4x2 `CGImage`); the `NSImage` route
  applies it (`NSImage.size` 2x4, `Image(nsImage:)` draws 2x4).

## 2 Public API (all MetalUI-only class `M` except `Image.Orientation` and the two `Image` inits, class `A`)

```swift
extension Image {
    public enum Orientation: UInt8, CaseIterable, Hashable, Sendable {   // SwiftUI's cases and raw values
        case up, left, upMirrored, leftMirrored, downMirrored, rightMirrored, down, right
        public init?(exifValue: Int)        // 1…8, anything else nil (M)
        public var exifValue: Int { get }   // 1…8 (M)
        public var swapsAxes: Bool { get }  // leftMirrored, right, rightMirrored, left (M)
    }
    public init(decorative bitmap: ImageBitmap, scale: Float, orientation: Orientation)
    public init(_ bitmap: ImageBitmap, scale: Float, orientation: Orientation, label: Text)
}

public struct DecodedImage: Sendable, Equatable {
    public enum Format: Sendable { case rgba, grey }
    public let format: Format
    public let width: Int, height: Int          // stored pixels, before orientation
    public let bytesPerRow: Int                 // width × 4 (rgba) or width (grey); no padding
    public let pixels: [UInt8]                  // row-major from the top-left
    public let orientation: Image.Orientation   // as reported; .up when the file says nothing
    public var orientedSize: (width: Int, height: Int) { get }
    public init?(data: Data, format: Format = .rgba)
    public init?(contentsOfFile path: String, format: Format = .rgba)
    public func applyingOrientation() -> DecodedImage      // pixels permuted, orientation .up
}
extension ImageBitmap {
    public init(_ decoded: DecodedImage)        // grey expands to R=G=B=v, A=255; ignores orientation
    public func oriented(_ orientation: Image.Orientation) -> ImageBitmap   // MetalUI-only, cached variants
}
```

`DecodedImage` is a new value type, not `ImageBitmap` members (`IB-A`): a bitmap holds premultiplied
texels and cannot hand back straight alpha without loss (AI-E/AI-F stay untouched: `ImageTexture` is not
changed). Decoding the same bytes through `DecodedImage` and `ImageBitmap(data:)` gives the same decoder, the
same refusals (`nil` per `PX-D`), no second copy of stb.

## 3 Implementation (no C change, no new target)

- `Sources/MetalUI/DecodedImage.swift` (new): the type, `Format`, `applyingOrientation()`, the
  permutation (one function over a byte count per pixel, shared by rgba, grey and the premultiplied
  variant of `oriented`).
- `Sources/MetalUI/ImageDecoding.swift` (edit): `decodeImage` gains a `channels: 1 | 4` parameter (default 4,
  existing callers byte for byte). Grey: stb `desired_channels = 1`: a grey source is returned exactly;
  RGB/RGBA sources go through stb's `(77r + 150g + 29b) >> 8` (Rec. 601 integer luma, **alpha dropped, not
  composited**); a 16-bit PNG decodes at 16 bits with `desired_channels = 1` and rounds
  `(v × 255 + 32767) / 65535` as the RGBA path does (`IB-B`).
- `Sources/MetalUI/ImageEXIF.swift` (new, Foundation-free): `exifOrientation(inJPEG:)`,
  `exifOrientation(inPNG:)`, both over `UnsafeRawBufferPointer`, both calling
  `tiffOrientation(_:)` (`IB-D`). Every read is `offset + n <= count` checked with `addingReportingOverflow`;
  a failure returns nil, which `DecodedImage` reports as `.up`.
- `Sources/MetalUI/ImageOrientation.swift` (new): `Image.Orientation` and the sample permutation tables.
- `ImageBitmap` gains one stored `let variants: OrientedVariants` (final class, lock-guarded
  `[Orientation: ImageTexture]`, created in every `init`) so `oriented(_:)` and `Image(…orientation:)`
  hand the same `ImageTexture` identity each frame (`TE-AF`: the renderer uploads once). `.up` returns
  `self`. **`swift package clean` after this stored-property change** (public type crossing a module
  boundary in tests). The oriented texture is built from the source texture's premultiplied bytes by the
  same permutation (a permutation commutes with premultiplication; no alpha arithmetic).
- `Image.swift` (edit): the two inits set `self.bitmap = bitmap.oriented(orientation)`, the doc comment's
  "`orientation:` is not offered" goes. Layout, hit testing, accessibility see an ordinary bitmap of the
  oriented size: nothing else moves.

## 4 Files and lanes

- **Lane 1 (decode, EXIF, orientation type):** `ImageOrientation.swift`, `ImageEXIF.swift`,
  `DecodedImage.swift`, the `decodeImage` edit, `Tests/MetalUICrossPlatformTests/DecodedImageTests.swift`,
  `ImageEXIFTests.swift`, `ImageOrientationTests.swift`. Commits `Image.Orientation` first.
- **Lane 2 (drawing, docs, guide), after lane 1's first commit:** `ImageBitmap.swift` variants,
  `Image.swift` inits, `Tests/MetalUITests/ImageOrientationDrawTests.swift`, the guide block and its
  `GuideMirrors` copy (`docs/guides/cross-platform.md`, `Tests/MetalUITestingTests/GuideMirrors*.swift`),
  `docs/api-overview.md`, `docs/migration.md` (note: `Image.Orientation` and `DecodedImage` are new names; a
  third-party `extension Image { enum Orientation }` would collide), `docs/divergences.md` 435, inventory
  rows (`closeout-inventory-map.tsv`, census re-record), `docs/verification/human-checks.md` group `IB`.
  Files disjoint from lane 1.

## 5 Tests (each: red before, mutation that must redden it). Fixtures are bytes built in the test
(PNG writer with stored-deflate and CRC; a baseline JPEG from `docs/probes/image-decoder-parity/gen-fixtures.py`
is checked in as a Swift byte literal only if the existing `ImageDecodingTests` already carries one — it does
not need one for EXIF: a JPEG *header* with an APP1 and a minimal valid scan is assembled in the test).

Lane 1 (`MetalUICrossPlatformTests`, runs on Linux):
1. `rgbaPixelsAreTheSamePixelsAnImageBitmapDraws` — a 2x2 RGBA PNG with alpha 128: `DecodedImage.pixels`
   straight equal the file's samples; `ImageBitmap(decoded).texture.pixels` the premultiplied ones. Red before:
   no type. Mutation: store premultiplied bytes in `DecodedImage` reddens.
2. `greyFromAGreySourceIsTheSourceSample` — 8-bit grey PNG and a 16-bit grey PNG (rounding). Mutation: use
   `v >> 8` for 16-bit reddens the 16-bit arm; use RGBA-then-luma reddens neither (equal by construction), so a
   third arm: grey+alpha PNG with alpha 0 keeps its grey (alpha dropped) — mutation compositing over black reddens.
3. `greyFromRGBIsStbLuma` — pixels (255,0,0), (0,255,0), (0,0,255), (10,20,30) give 76, 149, 28, 19.
   Mutation: Rec. 709 weights reddens (separating arm: all four values differ).
4. `strideIsTheRowWidthWithNoPadding` — `bytesPerRow` 12 rgba / 3 grey for width 3; mutation: round to 4 reddens grey.
5. `aCorruptOrOversizeFileIsNilInEveryFormat` — truncated PNG, bad CRC, JPEG with no EOI, 16385-wide header:
   nil for `.rgba` and `.grey` (`PX-D` unmoved). Mutation: skip `pngStructureIsIntact` on the grey path reddens.
6. `rgbaDecodeIsByteForByteWhatItWasBeforeTheChannelParameter` — the existing `ImageDecodingTests` literals
   stay unedited and pass (0 edits is the pin; checked by diff, `git diff fb9a7e42 -- Tests/…/ImageDecodingTests.swift` empty).
7. `exifOrientationOfAllEightValuesInBothByteOrders` — a JPEG header with APP1 `Exif\0\0`, `II*\0` and `MM\0*`,
   values 1…8 → `Image.Orientation`. Mutation: read the value as the low byte of a big-endian SHORT in `MM` reddens
   (a value of 6 reads 0 → `.up`... separating because 6≠1).
8. `anExifBlockThatIsTruncatedAtEveryLengthIsUpAndNeverTraps` — the full APP1 of test 7 cut at every byte
   offset 0…count: always `.up` or the true value, no trap, ASan-free (swift test with `-sanitize=address`
   run once by hand, recorded). Mutation: drop one `offset + n <= count` check reddens (out-of-bounds trap in debug).
9. `hostileExifFieldsAreIgnored` — IFD offset past the end, offset `0xFFFFFFFF`, entry count 65535 with 2 bytes
   left, an IFD pointing at itself, type LONG with count 1, count 2, value 0, 9, 0xFFFF: nil/`.up` each.
   Mutation: accept type != SHORT reddens; drop the entry-count clamp reddens.
10. `theFirstExifSegmentWinsAndOnlyBeforeSOS` — two APP1s (first 6, second 3) → right; an APP1 after SOS ignored;
    a non-Exif APP1 (XMP) skipped; an APP1 inside a thumbnail's `FF D8` ignored (walk by lengths, as
    `jpegScanIsTerminated`). Mutation: raw byte search for `Exif` reddens (thumbnail arm).
11. `aPngExifChunkIsRead` — `eXIf` before `IDAT` value 6 → `.right`; after `IDAT` ignored; bad CRC makes the file nil
    anyway. Mutation: read `eXIf` after IDAT reddens.
12. `decodeReportsOrientationAndDoesNotApplyIt` — a JPEG-like PNG with eXIf 6: `width`/`height` stored, `pixels`
    unpermuted, `orientedSize` swapped; `ImageBitmap(data:)` width/height stored (the default draw is unchanged,
    `IB-G`). Mutation: permute in `init` reddens.
13. `applyingOrientationPermutesEveryOneOfTheEightLikeSwiftUI` — the 2x2 `RBGW` table of the probe (8 arms), grey and
    rgba, a 3x2 non-square for the axis swap. Mutation: swap `left` and `right` tables reddens; transpose
    instead of rotate reddens `rightMirrored`/`leftMirrored` vs `right`/`left`.
14. `orientationRawValuesAreSwiftUIsAndExifValuesRoundTrip` — raw values 0…7 as probed, `exifValue` 1…8, `init?(exifValue: 0/9)` nil.
    Mutation: set `up = 1` reddens.
15. Guard `ImageEXIF` imports nothing beyond the target's existing imports (plain-import typecheck guard is not needed:
    the new declarations are `internal`; the public ones are covered by `typecheckFile` guard G-IB1: `DecodedImage`
    members are reachable from a plain `import MetalUI`, and `ImageBitmap.texture` still is not). Mutation: make
    `texture` public reddens G-IB1 (the one new guard, mutated red once).

Lane 2 (`MetalUITests`, macOS; the draw tests also in `MetalUITestingTests`):
16. `anOrientedImageLaysOutAtTheOrientedSize` — `Image(decorative: 4x2, scale: 1, orientation: .right)` in a
    `TestWindow`: `frame` 2x4; `.up` 4x2. Mutation: ignore the argument reddens.
17. `anOrientedBitmapKeepsOneTextureIdentityAcrossBuilds` — `bitmap.oriented(.right)` twice, `===` on the texture; a
    frame drawn twice uploads once (work counter). Mutation: build the variant per call reddens.
18. `orientedPixelsEqualSwiftUIsForAllEight` — the probe table through the headless scene's image run pixels. Mutation as 13.
19. `upOrientedIsTheSameBitmapAndZeroWork` — `.up` returns the identical texture. Mutation: always copy reddens.
20. Pixels: `docs/probes/demo-pixels/compare.sh <scratch> fb9a7e42 HEAD`: 0 px, fourteen images (no demo section uses
    an orientation); `DemoFrameDeterminismTests` unedited.
21. Guide block `cross-platform.md`: decode, read orientation, `applyingOrientation()`, hand to `ImageBitmap`, with a byte-for-byte
    mirror; `GuideDocCheck` red before the mirror exists, green after.

Linux image: lanes 1's tests run in `swift:6.4-noble` (volume `metalui-sdl-build-image-decode-api`), with the whole
`MetalUICrossPlatformTests` target.

## 6 Demo and human checks

No demo section (no new visible default). Human check group `IB`: IB1 draw a JPEG tagged 6 decoded through
`DecodedImage` + `applyingOrientation()` beside `Image(…orientation: .right)` over the untagged bitmap and read
that both are upright; IB2 compare with `Image(nsImage:)` of the same file in a SwiftUI window (the
divergence 435 claim, already probed headless; the look is the human's).

## 7 Deferred, named

- Orientation from formats ImageIO decodes (HEIC, TIFF) and from WebP/other: none read; `DecodedImage` is
  PNG/JPEG only (`nil` for others, no ImageIO fallback; `IB-J`). Owner: S2-b if MetalCreator asks.
- Applying EXIF by default on `ImageBitmap(data:)` (`IB-G`): one-line switch, owner S2-b with a migration note.
- Colour profiles stay ignored (divergence 138). 16-bit and float output are not offered. Premultiplied
  readback of an `ImageBitmap` is not offered (`IB-A`).
- `CGImagePropertyOrientation` is not exposed (Apple type; `Image.Orientation.exifValue` is the bridge).
