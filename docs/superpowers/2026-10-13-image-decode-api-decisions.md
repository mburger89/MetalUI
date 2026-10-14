# Public image decoding — decisions

Rulings for item S2 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**).
Prefix `IB-`. **Next unused: `IB-K`.** Spec: [`specs/2026-10-13-image-decode-api-design.md`](specs/2026-10-13-image-decode-api-design.md).
Record: `../record/113-image-decode-api.md` (Record phase). Branch `feat/image-decode-api` from `fb9a7e42`.
Divergence labels reserved 435–444: **435 taken** (`IB-G`).

Sources of truth. SwiftUI: `docs/probes/swiftui-image-orientation.swift` (macOS 27.0.1, output in its header):
`Image.Orientation` semantics and raw values, the `CGImage` route ignoring EXIF and the `NSImage` route
applying it. gpui, where SwiftUI has none: gpui has no decode API of its own (it takes decoded frames from
the `image` crate) — **recalled from memory, not read here**, a precedent only for `IB-A`.

## IB-A — A new value type `DecodedImage`, not `ImageBitmap` members

**Question.** Where do straight pixels live? **Ruling.** `DecodedImage` (straight RGBA8 or grey, width,
height, `bytesPerRow`, `orientation`). **Evidence.** `ImageBitmap` wraps a premultiplied `ImageTexture`
(`AI-E`, `TE-AR` item 2); straight alpha cannot be recovered losslessly from it (alpha 1 of 255 loses 8 bits).
Keeping both in the bitmap doubles every bitmap's memory. **Cost if wrong.** A second type to learn; an
`ImageBitmap.decoded` accessor is additive later. `ImageTexture` is unchanged.

## IB-B — Grey is stb's own: native for grey sources, Rec. 601 integer luma otherwise, alpha dropped

**Ruling.** `decodeImage(…, channels: 1)` asks stb for one channel: a grey source is exact; RGB/RGBA gives
`(77r + 150g + 29b) >> 8` (`stbi__compute_y`); alpha is **not** composited; a 16-bit PNG rounds as the RGBA
path does. **Evidence.** One formula, already in the vendored decoder, identical on every platform;
RGB(255,0,0)→76 etc. in test 3. **Cost if wrong.** An app wanting Rec. 709 or alpha-over-white takes `.rgba`
and computes; the grey bytes would change (documented as a formula, so a change is a migration note).

## IB-C — Decoding reports the orientation and does not apply it; absent or invalid is `.up`

**Ruling.** `DecodedImage.pixels` are the stored pixels; `orientation` is non-optional (`.up` when there is no
tag, a bad tag or a damaged block); `orientedSize` and `applyingOrientation()` are explicit. **Evidence.** The
app (MetalCreator) wants both the grey pixels and the tag; stb returns stored pixels; the SwiftUI `CGImage`
route does the same (probe O10). A nil-vs-`.up` distinction has no consumer. **Cost if wrong.** A caller
wanting to know "was there a tag" cannot; add `hasOrientation` later.

## IB-D — EXIF read in Swift, bounds-checked, JPEG APP1 and PNG `eXIf`

**Ruling.** JPEG: walk segments by length from `SOI` to the first `SOS` (never a byte search — a thumbnail holds
its own markers, as `jpegScanIsTerminated`), take the first `APP1` starting `Exif\0\0`; PNG: the first `eXIf`
chunk before `IDAT`. TIFF: `II*\0`/`MM\0*`, IFD0 offset, entry count clamped to the bytes left, tag `0x0112`,
type SHORT (3), count 1, value `1…8`; anything else nil. All arithmetic `addingReportingOverflow`; no
recursion (a self-pointing IFD is never followed: only IFD0 is read). No C, no Foundation. **Evidence.** The
parser is ~80 lines; stb has no EXIF; a C parser would put unreviewed bounds logic in an internal C target.
Tests 7–11. **Cost if wrong.** A file with a nonstandard type (BYTE, LONG) reads `.up`: conservative.

## IB-E — `Image.Orientation` is SwiftUI's enum with SwiftUI's raw values, plus `exifValue`

**Ruling.** Spelling, cases and raw values as probed (up 0, left 1, upMirrored 2, leftMirrored 3, downMirrored
4, rightMirrored 5, down 6, right 7); MetalUI-only `init?(exifValue:)`, `exifValue`, `swapsAxes`. **Evidence.**
Probe arms 2x1/2x2: the transforms equal EXIF 1…8 (table in the spec); raw values are not EXIF's, so a caller
must not pass `rawValue` as EXIF (`exifValue` exists for that). **Cost if wrong.** Raw values are rarely read;
changing them breaks only code that stored them.

## IB-F — `Image(…orientation:)` is built, through cached CPU variants of the bitmap

**Ruling.** `Image(decorative:scale:orientation:)` and `Image(_:scale:orientation:label:)` are SwiftUI's
spellings; `bitmap.oriented(_:)` returns a permuted `ImageBitmap` cached per orientation in a class box on the
bitmap, so the texture identity is stable (`TE-AF`). No shader or renderer change (so no `replay.hlsl`).
**Evidence.** The alternative, a `MUITransform` effect, would not change layout size (a rotation swaps the box)
and would add a mode to image hit-testing and clip; a permutation is exact and costs one pass per
orientation per bitmap. **Cost if wrong.** Memory: one extra texture per used orientation of a bitmap, never
evicted with the bitmap (freed with it).

## IB-G — A decoded bitmap is not oriented by default; divergence 435

**Ruling.** `ImageBitmap(data:)`/`(contentsOfFile:)` keep drawing stored pixels. Divergence 435: SwiftUI's
`Image(nsImage:)` from a tagged JPEG draws upright (probe O10: 2x4), MetalUI's `ImageBitmap` of the same file
draws stored (4x2), as SwiftUI's `CGImageSource` route does. **Evidence.** Probe O10; pixels must not move
for existing files (0 px, fourteen images); an app opts in through `DecodedImage.applyingOrientation()` or
`Image(…orientation:)` with a tag it read. **Cost if wrong.** A photo app sees rotated photos until it opts
in; the switch is one line plus a migration note.

## IB-H — Fuzz-like tests are enumerations, not random

Every truncation length of a valid block, a table of hostile fields, mutation of each bounds check (tests 8–9).
No randomness (a failing seed is not reproducible in CI); a one-off ASan run is recorded. **Cost if wrong.**
A hostile shape not in the table; add it as a row.

## IB-I — Limits are the existing decoder's

`DecodedImage` returns `nil` on every refusal `ImageBitmap(data:)` has (`PX-D`, `PX-O`: 16384 per side,
`Int32.max` bytes, CRC, `IEND`, JPEG `EOI`); the EXIF read happens after the structure checks and never
rescues a refused file. **Cost if wrong.** None: it is the stricter side.

## IB-J — PNG and JPEG only; no ImageIO fallback for the new type

`DecodedImage(data:)` is `nil` for GIF/TIFF/HEIC even on macOS, so a file decodes to the same bytes on every
platform (`PX-C`'s point). **Cost if wrong.** A macOS-only app needing HEIC pixels uses ImageIO itself;
owner S2-b.
