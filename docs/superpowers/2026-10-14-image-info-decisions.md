# Header-only image read and bounded decode — decisions

Rulings for item S9 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), MetalCreator gap
XP-G10. Prefix `IH-`. **Next unused: `IH-O`.** Spec: [`specs/2026-10-14-image-info-design.md`](specs/2026-10-14-image-info-design.md).
Record: `../record/117-image-info.md` (Record phase). Branch `feat/image-info` from `ceca59f6`.
Divergence labels reserved 475–484: none taken.

Sources of truth. SwiftUI: none (no header-only image API; ImageIO's `CGImageSourceCopyPropertiesAtIndex` is the
analogue, **not probed**, because no SwiftUI-facing claim is made). gpui: no decode API, nothing consulted. Local:
S2's rulings `IB-A`…`IB-M` and `ImageEXIF.swift`/`ImageDecoding.swift` at `ceca59f6`, read for this design.

## IH-A — `ImageInfo` is a new value type, class M, no probe

**Ruling.** A `public struct ImageInfo: Sendable, Hashable` with `init?(data:)`/`init?(contentsOfFile:)`.
**Evidence.** `DecodedImage` carries pixels (`IB-A`); a header read must not allocate any. SwiftUI has no analogue
to spell after. **Cost if wrong.** A rename before first release; a `DecodedImage.info` convenience is additive.

## IH-B — PNG and JPEG only; every other format is `nil`

**Ruling.** Same boundary as `DecodedImage` (`IB-J`): no ImageIO. **Evidence.** One answer on every platform; an
Apple-only branch would make `ImageInfo` say yes where Linux says no, and `ImageBitmap(data:)` already reads other
formats through ImageIO on Apple only (`PX-C` item 5), so the *decoders* disagree there by design. **Cost if wrong.**
An app that needs TIFF/HEIC sizes on macOS calls ImageIO; an additive `Format.other` is possible later.

## IH-C — Fields: format, size, orientation, bitDepth, channelCount; no `hasAlpha`

**Ruling.** `bitDepth` and `channelCount` are what the header stores (PNG: IHDR; JPEG: SOF precision and component
count; palette counts 3). **Evidence.** Both are in the bytes already read. `hasAlpha` for PNG needs a `tRNS` scan to
IDAT and for JPEG is always false: not cheap, not obviously right. **Cost if wrong.** Additive.

## IH-D — `ImageInfo` applies no size limit

**Ruling.** It reports 1…2³¹−1 (PNG) / 1…65535 (JPEG) as written; only `DecodedImage` refuses above 16384
(`IB-I`). **Evidence.** The caller's own limit is the point of the item (MetalCreator: 8,192); an info that returned
nil above 16384 could not report *why* an image is refused. **Cost if wrong.** An app assuming `ImageInfo != nil`
means decodable is wrong; documented in the doc comment, and `Limits` is the supported check.

## IH-E — PNG: IHDR first, length 13, CRC checked; other chunks' CRCs are not

**Ruling.** IHDR must be the first chunk; its CRC is verified (17 bytes, cheap); legal (colour type, depth) pairs
only. The eXIf chunk is read by length, no CRC, as S2 (`IB-D`). **Evidence.** `pngStructureIsIntact` already refuses
any image with a bad IHDR CRC, so checking it makes `ImageInfo != nil` imply "the decoder will not refuse the header".
**Cost if wrong.** A tolerated bad IHDR CRC would be a decoder change too.

## IH-F — JPEG: the first SOF among the 13 dimension-bearing markers; height 0 and 0 or >4 components are `nil`

**Ruling.** `C0–C3, C5–C7, C9–CB, CD–CF`; never `C4`, `C8`, `CC`. The walk is S2's (segment lengths to the first
SOS, no byte search). Precision is reported as stored (stb refuses ≠ 8 at decode, not the header's business).
**Evidence.** The marker list is the JPEG standard's; the `C4` separating arm (test 3) guards the classic bug of
taking DHT for a frame. **Cost if wrong.** A wrong size would disagree with stb, which `IH-I` turns into `nil`.

## IH-G — The file reader is seek-based and exact; an EXIF payload over 1 MiB is damaged

**Question.** "Reading only a bounded prefix if practical." **Ruling.** Not a prefix: a `HeaderSource` that reads
chunk/segment headers and the needed payloads at their offsets, so the answer equals `ImageInfo(data:)` for every
file including a PNG whose `eXIf` follows megabytes of `IDAT` (a prefix would silently say `.up`). Memory is bounded
by the 1 MiB payload cap (applied on the data path too, one walk). **Evidence.** A PNG's metadata may legally follow
the pixels (`IB-K`); exactness beats a hidden prefix rule. **Cost if wrong.** More syscalls than one prefix read (a
handful per file, counted by test 11 — **corrected by `IH-M`: not a handful for a PNG with metadata after the pixels**); the cap changes a >1 MiB EXIF from "read" to `.up`, which no real file has
(APP1 ≤ 64 KiB; PNG eXIf is a few KiB).

## IH-H — One walk: `ImageEXIF`'s buffer functions wrap the source walks

**Ruling.** `exifOrientation(inJPEG:)`/`(inPNG:)` keep their signatures and call the source walk over a memory source.
**Evidence.** Two copies of a bounds-checked walk drift; S2's `ImageEXIFTests` stay unedited and are the proof.
**Cost if wrong.** A regression in S2's orientation reads, caught by those tests and test 5.

## IH-I — `DecodedImage` refuses a stb size that disagrees with the header, always

**Question.** MetalCreator does this itself. **Ruling.** Yes, in both inits (`decodeImage(_:channels:expecting:)`).
**Evidence.** The two parsers see the same bytes; if they disagree one is wrong and the pixels are not to be trusted.
For every image S2's tests decode they agree (test 17), so this should change no result. **Cost if wrong.** An image
stb decodes and the header reader rejects (or sizes differently) becomes `nil`: the one new refusal, in the migration
note; reverting is deleting the equality guard.

## IH-J — A bounded decode is (a): `Limits` checked from the header before stb allocates

**Ruling.** `DecodedImage.Limits(maxInputBytes:maxSide:maxPixels:)`, all optional, inclusive bounds, checked in the
order input → header → side → pixels → decode; `nil` result for any refusal (no throwing variant: `DecodedImage` is
nil-on-failure throughout, and `ImageInfo` lets an app tell a refusal from a damaged file). The file init checks the
file's size before reading it. **Evidence.** The 450 MB peak is stb's allocation after it has read the header; refusing
before it is the only bound available without touching vendored C. **Cost if wrong.** Extra field later is additive;
a `throws` variant is additive.

## IH-K — Cancellation is not built

**Ruling.** Declined for now. stb has no cancellation; an `stbi_io_callbacks` read callback returning short is the only
lead, **unmeasured** (PNG collects all IDAT before inflating, so it would not interrupt the allocation; JPEG reads
progressively). **Evidence.** No claim without a measurement; the 450 MB case is covered by `IH-J`. **Cost if wrong.**
An in-range 16384² decode still cannot be stopped; carried to an owner if an app asks.

## IH-L — `ImageBitmap(data:)` is untouched

**Ruling.** No limits on the drawing path in this item. **Evidence.** `ImageBitmap` pixels must stay byte-identical
(fourteen images, `PX-` tests); MetalCreator uses `DecodedImage`. **Cost if wrong.** `ImageBitmap(data:limits:)` later, additive.


## IH-M — The file source reads through one 64 KiB window; a PNG trailer walk is chunk-count bound, not O(1)

**Question (critic).** `IH-G` said "a handful of syscalls per file". A PNG's after-IDAT `eXIf` lookup must walk every chunk
header to IEND; a 16 MB PNG has ~2,000 IDAT chunks (8–64 KiB), a hostile one up to ~1.4 million 12-byte chunks, so one
`read(at:count:)` per header is thousands to millions of syscalls. **Ruling.** The `FileHandle` source keeps one 64 KiB
window and serves any read inside it from memory; a read outside it refills the window at that offset. The walk still
**never reads a byte it does not need** only in the sense that skipped IDAT payloads are seeked over, not that every window
byte is unneeded (a window may span a short chunk). Test 11's bound becomes: refills <= 2 + (file size / 64 KiB) + payload
reads, and no refill starts inside a chunk's payload larger than the window (the 3 MB IDAT fixture). Total bytes read from the
file is **not** claimed minimal. **Evidence.** Window size is a work counter, pinned by count, never time. **Cost if wrong.** A
hostile many-chunk PNG costs one refill per 64 KiB of chunk headers: bounded by file size / 64 KiB.

## IH-N — Overflow, non-regular files and a changing file

**Ruling.** (1) `maxPixels` compares `width.multipliedReportingOverflow(by: height)`; an overflow is a refusal (32-bit
`Int` on a 32-bit target, and PNG sides reach 2^31-1). Test 14 gains a 2^31-1 x 2^31-1 header-only PNG. (2) `init?(contentsOfFile:)` answers
`nil` for a path that is not a regular file (directory, FIFO, device: a zero or lying size must not defeat
`maxInputBytes`), checked from the handle's own metadata. (3) The file's size is read **once**, from the same handle that
then reads; a read that returns short of the recorded size is damage (`nil` for the walk position, never a trap); a file
that grows after the check is read only to the recorded size. **Evidence.** Each is a branch a test can reach with a
temp file (a directory path, a size recorded then shortened). **Cost if wrong.** A wrong answer to `maxInputBytes` is the one
failure the limit exists to prevent.
