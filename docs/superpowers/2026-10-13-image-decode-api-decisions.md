# Public image decoding — decisions

Rulings for item S2 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**).
Prefix `IB-`. **Next unused: `IB-N`.** Spec: [`specs/2026-10-13-image-decode-api-design.md`](specs/2026-10-13-image-decode-api-design.md).
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
chunk before the first or after the last `IDAT` (see `IB-K`). TIFF: `II*\0`/`MM\0*`, IFD0 offset, entry count clamped to the bytes left, tag `0x0112`,
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

## IB-K — Critic's rulings: `orientation:` has no default; `eXIf` after `IDAT` is read; JPEG fill bytes

**Ruling.** (1) SwiftUI's `Image(_:scale:orientation:label:)` defaults `orientation` to `.up`; here the two
inits are **overloads with a required `orientation`**, beside the unchanged `scale:`-only inits, because a
defaulted parameter would make `Image(decorative:scale:)` ambiguous with the existing init (every old call
compiles, every SwiftUI call with an explicit orientation compiles; a call that relies on the default resolves
to the existing init, same result). Not a divergence in behaviour. (2) `IB-D`'s "`eXIf` before `IDAT`" was
narrower than PNG 1.5 (anywhere before `IEND` except between `IDAT`s): accept before the first and after the
last `IDAT`. (3) The JPEG walk skips `0xFF` fill bytes and length-less markers (`RSTn`, `TEM`) and refuses a
segment length below 2. (4) The spec's luma example (10,20,30) was 19; it is 18 by hand. (5) `init(_ decoded:)`
moved to lane 1 (test 1 needs it; it was a hidden lane 1 -> lane 2 dependency). **Rejected:** a SwiftUI
claim without a probe: none remains; the probe was re-run, both arms (2x2 table, O10) byte for byte.

## IB-L — Lane 1 as built: whole entries only, the permutation lives in `ImageOrientation.swift`, tests 1-15 pinned

**Ruling.** (1) `tiffOrientation` clamps the entry count to the **whole** 12-byte entries present
(`(count - firstEntry) / 12`): a tag whose value field is cut by the end of the block is `nil`, not a value
read from the bytes that happen to be there (mutation M10, dropping the clamp, reddens test 8 at every cut
between the tag and the end of the entry). Every read is `offset >= 0 && offset <= count - n`, with no
addition that can overflow; dropping the upper bound of `read16` traps (mutation M8, `Fatal error` in
`UnsafeRawBufferPointer`, tests 8 and 9). (2) The sample permutation (`permuteSamples`) is in
`ImageOrientation.swift`, not `DecodedImage.swift` as spec section 3 said, because lane 2's `oriented(_:)` reads it and
the type file is lane 1's second commit. (3) `decodeImage(_:channels:)` returns `samples` (was `straightRGBA`;
the only caller outside the file was `decodeImageTexture`); `isPNG`/`isJPEG` are internal so `DecodedImage` can pick
the EXIF reader after the structure checks passed. (4) The guard G-IB1 is in `Tests/MetalUITests/ImageDecodeCompileGuards.swift`
(guards need the built `Modules`; the cross-platform target cannot run them). **Evidence.** Mutations M1-M18 (record 113 section
on lane 1): every one reddened a named test. **Cost if wrong.** None observable: a block cut mid-entry is not a real file.

## IB-M — Lane 2 as built: the variants box is a final class on `ImageBitmap`, no new `ImageTexture` init

**Ruling.** (1) `ImageBitmap` gains one stored `let variants: OrientedVariants` (a lock-guarded
`[Image.Orientation: ImageTexture]`, `@unchecked Sendable`), created by each of the three designated
initialisers and shared by every copy; it is a stored-property change on a public type, so `swift package clean`
preceded the lane's build. `oriented(_:)` returns `self` for `.up` (identity, no work) and otherwise permutes the
**premultiplied** texels with `permuteSamples` (lane 1's, `IB-L`) into `ImageTexture(width:height:premultipliedRGBA:)`,
which already exists, so no `ImageTexture` change and `AI-E`/`AI-F` are untouched. (2) The two `Image` inits
route through `bitmap.oriented(orientation)` into the existing inits, so labelling, `isDecorative`, layout and
paint see an ordinary bitmap of the oriented size. (3) The guide block (cross-platform #3) is mirrored in a
new `GuideMirrorsImage.swift` (the checker reads every `GuideMirrors*.swift`), not in lane 1's or lane 2's
developer-guide mirror files. (4) The census rule for the new `Image` inits is an `M` row on the declaration text
`orientation`, ahead of the generic `Image.swift` row. **Evidence.** Tests 16-19 red on `extra argument 'orientation'
in call`, green after; mutations M1-M4 (record 113). **Cost if wrong.** One lock acquisition per `oriented(_:)`
call; a bitmap that is never oriented pays one empty box allocation.

