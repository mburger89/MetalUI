# Header-only image format sniff — decisions

Rulings for item XP-G12 of the gpui-gap priority list (user request 2026-10-02, requested by MetalCreator 2026-10-20;
**not a plan task**). Prefix `IS-`. **Next unused: `IS-L`.** Spec:
[`specs/2026-10-20-image-sniff-design.md`](specs/2026-10-20-image-sniff-design.md). Record: `../record/130-image-sniff.md`
(Record phase). Branch `feat/image-sniff` from `b15e038c`. Divergence labels reserved 595-604: none taken.

Sources of truth. SwiftUI: none (no image sniff, no header read), so **no SwiftUI claim is made and no probe is owed**.
gpui: none (images come from the Rust `image` crate, which sniffs by `guess_format`; not consulted, no claim). Naming
reference only, **not probed**: UTType's `public.png/jpeg/gif/tiff/bmp/heif/heic/avif` and `org.webmproject.webp`.
Local: `ImageInfo.swift`, `ImageHeader.swift`, record 117's `IH-` rulings, read at `b15e038c`.

## IS-A — A separate enum `ImageFileFormat`; `ImageInfo.Format` is not extended

**Ruling.** `public enum ImageFileFormat: Sendable, Hashable, CaseIterable` with `png, jpeg, gif, tiff, bmp, webp, heif,
avif, unknown`. `ImageInfo.Format` stays `png, jpeg`.
**Evidence.** `ImageInfo.Format` is neither `@frozen` nor resilient (a plain SwiftPM module), so a new case breaks every
caller's exhaustive `switch` at compile time, and it would also let `ImageInfo.format` be `.gif`, a value no `ImageInfo`
can hold (`IH-B`). `ImageInfo.format` today means "readable by the header walk"; the sniff means "starts like". Two
meanings, two types. `Format` is the name `DecodedImage` also uses (`rgba`/`grey`), so `ImageFileFormat` avoids a third.
**Cost if wrong.** A later `ImageFileFormat` case is source-breaking for exhaustive switches (documented: switch with
`default`); folding it into `Format` later would be the same break. Additive `ImageFileFormat(_: ImageInfo.Format)` is
possible later (carried, spec 6).

## IS-B — The entry points are `ImageInfo.sniffedFormat(of:)` and `(ofFile:)`, total, non-optional

**Ruling.** `static func sniffedFormat(of data: Data) -> ImageFileFormat` and `static func sniffedFormat(ofFile path:
String) -> ImageFileFormat`; `.unknown` answers every miss. **Evidence.** The caller's question is "name what these bytes
look like", a total function; an `Optional` would repeat the `nil`-means-everything problem this item exists to fix, and
`.unknown` is the brief's spelling. They sit on `ImageInfo` because the sniff is its companion (the same bytes, one step
earlier). **Cost if wrong.** A rename before first release.

## IS-C — A sniff names a prefix, never a promise

**Ruling.** `.png`/`.jpeg` mean the signature matched; `ImageInfo(data:)` may still be `nil` (a damaged IHDR, a bad CRC,
no SOF) and `DecodedImage` may refuse. That pair, sniff `.png` with `ImageInfo` `nil`, **is** the caller's "damaged"
answer; `.gif` etc. with `ImageInfo` `nil` is "unsupported type"; `.unknown` is "not a picture". Documented on the type.
**Evidence.** A signature check reads at most 18 bytes; verifying IHDR is `readImageInfo`'s job (`IH-E`). **Cost if
wrong.** None to the code; a doc fix.

## IS-D — Signatures, and why each is that long

**Ruling.** A match needs the whole signature; a prefix one byte short is `.unknown` (never a trap, never a guess):
- PNG: `89 50 4E 47 0D 0A 1A 0A` (8, as `pngSignatureBytes`). JPEG: `FF D8 FF` (3, as `readImageInfo`).
- GIF: `GIF87a` or `GIF89a` (6).
- TIFF: `49 49 2A 00` or `4D 4D 00 2A` (4, both byte orders). **BigTIFF (`.. 2B 00`) is `.unknown`**: no decoder here or
  in ImageIO's common path is promised, and MetalCreator's list has none; additive later.
- BMP: `42 4D` **plus** a plausible DIB header size at offset 14 (little-endian 12, 40, 52, 56, 64, 108 or 124) (18
  bytes). Two bytes `BM` match ASCII text; the DIB size is the cheapest second witness. The size set includes the OS/2 1.x/2.x headers (12, 64) carried in a `BM` file; OS/2
  array/icon/pointer files (`BA`, `CI`, `CP`, `IC`, `PT`) are `.unknown`.
- WebP: `RIFF`, any four bytes, `WEBP` (12). A `RIFF....WAVE` is `.unknown`.
- HEIF/AVIF: bytes 4-8 `ftyp` and the **major brand** at 8-12 (12 bytes, the box size is not read). HEIF brands: `heic`,
  `heix`, `hevc`, `hevx`, `heim`, `heis`, `mif1`, `msf1`; `.avif`: `avif`, `avis`. Compatible-brand lists are not read, so
  an `mif1` file that is really AVIF sniffs `.heif` (documented; reading them would exceed the 12-byte floor and the box
  size is attacker-controlled).
**Evidence.** The brief's list; the ISO 14496-12 `ftyp` layout; BMP's weakness as above. **Cost if wrong.** A format
sniffed wrongly is a caller mislabel in an error message, never a decode.

## IS-E — `avif` is its own case

**Ruling.** `.avif` is separate from `.heif`. **Evidence.** The caller's message names the format ("AVIF is not
supported"); AVIF and HEIC differ in codec and in what platforms read (ImageIO reads both only on recent systems), and UTType
keeps `public.avif` apart from `public.heif`. Folding them would lose a distinction the caller cannot recover
from bytes it no longer has. **Cost if wrong.** An app that wants "any HEIF family" matches two cases.

## IS-F — The sniff goes through the one header source, reads at most 18 bytes, and imports nothing new

**Ruling.** One internal function `sniffImageFormat(_ source: some HeaderSource)` reads `min(size, 18)` bytes at offset
0 once and matches on that array; `Data` goes through `MemoryHeaderSource`, a path through `FileHeaderSource`
(regular files only, `IH-M`, `IH-O`; a directory, FIFO, device or missing path is `.unknown`). `HeaderSource` stays
unreachable (guard `G-IH1` unmoved, new guard `G-IS1`). No stb, no ImageIO, no pixel work, no new Foundation use beyond
`ImageHeader.swift`'s own (`IH-H`). **Evidence.** One walk (`IH-H`). The file window loads up to 64 KiB once at offset 0;
the pin is "one refill at 0, no payload read". **Cost if wrong.** A directory sniffing `.unknown` rather than a trap is
what `IH-M` already does for `ImageInfo`.

## IS-G — `CaseIterable` is offered, `rawValue` and `UTType` mapping are not

**Ruling.** `CaseIterable` (the pins iterate every case, so a new case cannot ship without an arm), no raw type, no
`UTType`/MIME property. **Evidence.** `UTType` is Apple-only and the type must be portable (Linux/Windows). A MIME
string is a convenience the caller can write in one `switch`. **Cost if wrong.** Additive `mimeType` later.

## IS-H — Class M, no divergence, no probe

**Ruling.** Class `M` (SwiftUI has no analogue); inventory row `ImageSniff.swift` -> `image-sniff` with `IS-A`…`IS-G`; no
divergence label. **Cost if wrong.** A row edit.

## IS-I — Portable, tests in the cross-platform target, one macOS guard

**Ruling.** Tests live in `Tests/MetalUICrossPlatformTests/ImageSniffTests.swift` (where `ImageInfoTests` run on Linux and
Windows CI); only the typecheck guard is in `Tests/MetalUITests`. **Cost if wrong.** None.

## IS-J — Critic's revisions: inventory family row, nil reads, symlink pins gated, no probe stands

**Ruling.** (1) The inventory owes **two** rows, not one: the `M` row for `ImageSniff.swift` and an `F` family row
`image-sniff` beside `image-info` (line 114 of `closeout-inventory-map.tsv`), listing `IS-A`..`IS-J`. (2) `HeaderSource.read`
returns `[UInt8]?`: a `nil` read (short or failed file) is `.unknown`, never a trap; a pin with a spy returning `nil`. (3) Test 6's
symlink cases are gated off Windows (`#if !os(Windows)`: creating a symlink needs a privilege there); the other file cases run
everywhere. (4) A file form that reads a 64 KiB window is bounded by `FileHeaderSource`, so the "min(size, 18)" read is the data
form's and the spy's; the file pin is the trace (one refill at 0, `payloadReads == 0`). (5) A mutation run that hangs follows the
brief's 12-minute rule. **Rejected:** a SwiftUI probe (no SwiftUI claim is made, `IS-H`); folding AVIF into `.heif` (`IS-E`);
reading compatible brands (`IS-D`). **Evidence.** `ImageHeader.swift` lines 10-13 and the inventory map at `b15e038c`.
**Cost if wrong.** A map row or a test gate.

## IS-K — Measured residues of the mutation run (lane, 2026-10-20; amended by the fix pass)

**Ruling.** (1) `sniffedFormat(ofFile:)` rewritten over `Data(contentsOf:)` passed every pin, because the public file form had no
work counter. **Fixed:** `FileHeaderSource.testingTraceForUntracedOpens` (internal, `nil` in production) makes an untraced open report
into a test's `HeaderTrace`; the file-form pin goes through the *public* `sniffedFormat(ofFile:)` on a 200 KB file and requires
`refills == [0]`, no payload read, no whole-file load. A `Data(contentsOf:)` rewrite never opens a `FileHeaderSource`, so the trace
stays empty and the pin reddens (mutation re-run recorded in record 130). (2) Guard `G-IS1`'s walk negative now calls
`sniffImageFormat(MemoryHeaderSource(...))` with concrete internal values, so it fails for access reasons, not generic inference;
making the function `public` alone still cannot compile while `HeaderSource` is internal, so `G-IH1` carries that guarantee for the
protocol. **Residue (dated).** The lane's mutations ran on filtered sets and the Linux image ran 26-27 filtered tests; record 130
must say so and the full root portable run in `metalui-portable` is re-taken before merge.
