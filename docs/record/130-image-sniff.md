# 130 — Header-only image format sniff (XP-G12: `ImageFileFormat`, `ImageInfo.sniffedFormat`)

Branch `feat/image-sniff` from `b15e038c`, merged with master `c55d44e8` (§128 retained geometry, §129 accessibility under a translated replay) at the Record phase; master had published
§128 and §129, so §130 stands (no renumbering). Not a plan task: item XP-G12 of the gpui-gap list (user request 2026-10-02), requested by MetalCreator 2026-10-20. Spec
`docs/superpowers/specs/2026-10-20-image-sniff-design.md` (Status: LANDED); rulings `IS-A`…`IS-K` in `docs/superpowers/2026-10-20-image-sniff-decisions.md` (next unused `IS-L`).
Divergence labels 595–604 reserved: **none taken** (class `M`: SwiftUI has no image sniff, so no SwiftUI claim and no probe, `IS-H`). One implementation lane, verified `ok: true` by a
separate checker. `Backends/SDL`, `Sources/MetalUIRender` and the shaders untouched. Demo: none (no drawing). Human checks: none (bytes in, enum out).

## §1 The defect

`ImageInfo(data:)`/`(contentsOfFile:)` (§117, `IH-`) reads a PNG IHDR or a JPEG SOF and is `nil` for everything else, so GIF, TIFF, BMP, WebP and HEIF/AVIF answered exactly as garbage and as a
damaged PNG did. A caller could not refuse the first as "unsupported type", the second as "not a picture" and the third as "damaged". MetalCreator kept `OtherPictureSignature` (seven prefixes,
about 15 lines) for it and will delete it.

## §2 What landed

**`ImageFileFormat`** (`Sources/MetalUI/ImageSniff.swift`, public, `Sendable, Hashable, CaseIterable`): `png, jpeg, gif, tiff, bmp, webp, heif, avif, unknown`. A **separate enum**, not new
cases of `ImageInfo.Format` (`IS-A`: that enum is not frozen, so a case would break every exhaustive `switch`, and `ImageInfo.format` could then hold a value no `ImageInfo` holds). Documented as
open: switch with a `default`.

**`ImageInfo.sniffedFormat(of: Data)` and `(ofFile: String)`** (`IS-B`): total, non-optional, `.unknown` for every miss. One internal function `sniffImageFormat(_ source: some HeaderSource)` reads
`min(size, 18)` bytes at offset 0 once and matches (`IS-F`): `Data` through `MemoryHeaderSource`, a path through `FileHeaderSource` (regular files only, `IH-M`, `IH-O`; a missing path, directory, FIFO,
device or unreadable file is `.unknown`; a `nil` read is `.unknown`, `IS-J`). `HeaderSource` stays unreachable (`G-IH1` unmoved, new guard `G-IS1`). No stb, no ImageIO, no new Foundation use.

**Signatures (`IS-D`).** A match needs the whole signature; one byte short is `.unknown`. PNG 8 bytes, JPEG `FF D8 FF`, GIF `GIF87a`/`GIF89a`, TIFF `II*\0`/`MM\0*` (BigTIFF is `.unknown`), BMP `BM`
plus a DIB header size at offset 14 in {12, 40, 52, 56, 64, 108, 124} (18 bytes; `BM` alone matches text), WebP `RIFF`…`WEBP` (12), `ftyp` major brand at 8–12: `.heif` for `heic heix hevc hevx
heim heis mif1 msf1`, `.avif` for `avif avis` (`IS-E`: AVIF is its own case, UTType keeps `public.avif` apart too). Compatible brands are not read, so an `mif1` AVIF reports `.heif`.

**A sniff names a prefix, never a promise (`IS-C`).** `.png`/`.jpeg` with `ImageInfo` `nil` is *damaged*; another case with `nil` is *unsupported*; `.unknown` is *not a picture*. Documented on the
type. Naming reference only, not probed: UTType's `public.png/jpeg/gif/tiff/bmp/heif/avif` (no `UTType` property: the type is portable, `IS-G`).

**One test seam in `ImageHeader.swift`** (`IS-K`): `FileHeaderSource.testingTraceForUntracedOpens` (internal `nonisolated(unsafe)` static, `nil` in production, valid under `--no-parallel` only, as its
comment says) lets a test see the work of the public file form, which passes no trace. This is the only edit to an existing source file.

## §3 Tests and guards

`Tests/MetalUICrossPlatformTests/ImageSniffTests.swift` (runs on Linux and Windows CI, `IS-I`), 9 tests: `everyFormatsMinimalSignatureSniffsItsCase`, `everyTruncatedByOnePrefixSniffsUnknown`,
`emptyAndGarbageSniffUnknown` (empty, one byte, text, `BM` + text, `RIFF….WAVE`, BigTIFF, `ftyp isom`, zeros), `aDamagedPNGSniffsPNGWhileImageInfoIsNil` (also a SOF-less JPEG, GIF and WebP: the
three-way answer), `sniffReadsOnlyThePrefix` (a spy source: one read at 0 of `min(size, 18)`; a `nil` read), `theFileFormAgreesWithTheDataFormAndRefusesWhatIsNotARegularFile` (every case, a
directory, missing, empty, symlinks off Windows; the *public* file form on a 200 KB file: `refills == [0]`, `payloadReads == 0`, `wholeFileLoads == 0`, the `IS-K` pin),
`sniffNeverTrapsOnAnySingleByteMutationOfAValidSignature` (0x00/0xFF at every byte against an independent oracle), `sniffAndImageInfoAgreeOnPNGAndJPEGFixtures`, `iterationCoversNineCases`. `Tests/MetalUITests/ImageSniffCompileGuards.swift`: guard **`G-IS1`** (`theSniffSurfaceIsReachableAndItsWalkIsNot`, plain-import `typecheckFile`: the enum, its cases and
both statics compile; `sniffImageFormat` over a concrete `MemoryHeaderSource` does not).

## §4 Red first, and mutations

**Red on arrival** (`638838a2`, at `c3f42e9a`): the symbol did not exist, so the test file failed to compile; the guard failed on `ImageFileFormat`. Green at `e9e72158`.

**Mutations** (applied after commit, restored from a copy, `git status --short` clean after each). The IS-K pass found two residues in the first run, fixed at `72199654`:
1. `sniffedFormat(ofFile:)` rewritten over `Data(contentsOf:)` passed every pin (no work counter on the public file form). After the fix, the same rewrite reddens
   `theFileFormAgreesWithTheDataFormAndRefusesWhatIsNotARegularFile` (`publicTrace.refills == [0] && payloadReads == 0 && wholeFileLoads == 0`).
2. `sniffImageFormat` made reachable from a plain import (a public concrete overload over a public `MemoryHeaderSource`) reddens `theSniffSurfaceIsReachableAndItsWalkIsNot`
   (`!walk.succeeded && walk.messages.contains("sniffImageFormat")`); the guard's negative now fails for access, not generic inference.
The per-signature arm mutations of the spec (§5) are pinned by tests 1–3 (the case's own sub-test); **the lane's mutation runs used filtered sets** (`--filter ImageSniff`, a full run took 963 s on a
loaded machine), so a test outside the set that a mutation reddens is not listed.

## §5 Verification

- `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice; native unfiltered run: see §6.
- Inventory map: an `M` row for `ImageSniff.swift` and an `F` family row `image-sniff` beside `image-info` (`IS-J`); `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; census
  **3683** (master's 3680 + 3: the enum and the two statics; the nine cases are not counted, so the spec's +4 was +3; re-recorded after the merge, the script's output equals the file).
- No change to `Sources/MetalUIRender`; the fourteen images were not re-taken for this branch (nothing draws).
- Linux image `metalui-portable` (OrbStack, volume `metalui-root-build-image-sniff`), on the merged tree at the Record phase: root portable build, then `MetalUITestingTests` + the portable tests 419 in 2 suites, `MetalUILayoutTests` 233, `MetalUICoreTests` **137** (128 + the nine sniff tests, which live in `Tests/MetalUICrossPlatformTests`), the cross-platform 22, all passed (the lane itself ran 26–27 filtered tests). `Backends/SDL` untouched, not re-taken.

## §6 Counts

Measured by the Record phase on the merged tree after `swift package clean` on a **locked screen**: native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `Test run with 4091 tests in 5 suites
failed after 874.585 seconds with 5 issues`, the five being exactly `AppKitPresentationTests`' sheet expectations (`CI-AF`, `attachedSheet != nil`) and nothing else; `FR-J no-argument frame: succeeded=true`.
**4091 tests, 0 goldens, 251 typecheck guards** (master's 4081 + 9 tests and guard `G-IS1`, the guard counted as a test: 4060 + 10 = 4070 at the lane on `b15e038c`; guards 250 + 1, 468 `typecheck`/`typecheckFile` calls
against 465 on master `c55d44e8`, the three being `G-IS1`'s). Default-build-system `swift build --build-tests`: 0 `warning:` (build complete). Inventory and undocumented scripts print nothing; census 3683.

## §7 Hazards and deferrals

- `testingTraceForUntracedOpens` is a mutable static: safe only under `--no-parallel` and the test's `defer` reset (the repository's rule).
- `ImageFileFormat` is not frozen: a later case is source-breaking for exhaustive switches (documented; `IS-A`).
- An `mif1`-branded AVIF sniffs `.heif`; reading compatible brands needs a bounded box walk (`IS-D`).
- Carried, named, not built: BigTIFF, OS/2 bitmaps, JPEG 2000, ICO and APNG distinctions (additive cases); `mimeType`/`UTType` property and `ImageFileFormat(_: ImageInfo.Format)` (additive);
  header-only size for GIF/BMP/WebP/TIFF (`ImageInfo` for them, a separate item).
