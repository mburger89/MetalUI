# Images

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Image decoding and orientation (`IB-`, record §113).** `DecodedImage` (MetalUI-only) is the public pixel
read: PNG/JPEG bytes through the one vendored decoder to **straight** RGBA8 or 8-bit grey (grey sources
native, otherwise stb's Rec. 601 integer luma, alpha dropped, `IB-B`), `bytesPerRow` unpadded; it is a type of its own
because `ImageTexture` stays premultiplied (`AI-E`, `IB-A`). It **reports** the EXIF orientation (JPEG `APP1`, PNG
`eXIf`, whole entries only, every read bounds-checked, damaged or absent is `.up`, never a trap) and **does not
apply it**: `applyingOrientation()` or `Image(…orientation:)` (no default, `IB-K`) does, through
`ImageBitmap.oriented(_:)`, one cached texture per orientation, `.up` the same bitmap; `ImageBitmap(data:)` keeps
the stored pixels, unlike SwiftUI's `NSImage` route (divergence 435, `IB-G`). `Image.Orientation` has SwiftUI's
raw values. No C, shader or `ImageTexture` change; a new reader of the file bytes stays Foundation-free.

**Image cursors and the headless SDL launch (`IC-`, record §116).** `PointerStyle.image(_:hotSpot:)` is SwiftUI's
spelling (class A): the cursor is the `Image`'s one bitmap at `pixels / scale` points (probe `swiftui-image-cursor.swift`;
`resizable()`/`interpolation` ignored), the hot spot a `UnitPoint` of that size from the top-left, **clamped per axis**
(divergence 465). It reaches the platform as the seam case `PlatformPointerStyle.image(PlatformCursorImage)` (`CI-AC`: an
outside exhaustive `switch` owes an arm), **compared by texture identity, never bytes**, so a bitmap rebuilt into an `Image`
every frame is one cursor and `Window` still sends on a change only (`IC-A`, `IC-F`). AppKit wraps the premultiplied pixels
as stored in an `NSCursor` (LRU 16 per window); SDL un-premultiplies through `SDLIcon.straightRGBA` (`AI-F`) into
`SDL_CreateColorCursor` (an integer scale >= 2 adds the bitmap as an alternate), through `SDLImageCursorTable` (pure,
LRU 8, **the platform's**, a shown cursor parked and destroyed at the next sweep, all destroyed on the last close; tests
read the C recorders `mui_cursor_*`, which count even a refused create). **No hand or zoom art is bundled**: the app
supplies SDL's (`IC-H`). `.shape` is not built. `SDLPlatform.Options` (`.default`, `.headless` = hidden windows + offscreen
renderers, `headlessIfRequested()` reading `METALUI_SDL_HEADLESS` exactly `"1"`, never read by `init`) with
`SDLPlatform(options:)` is the public CI smoke-test launch (`IC-J`…`IC-M`); the `@_spi(Checks)` initialiser forwards. A
`.task` can run before `platform.run()` starts, so a smoke test stops from the display-link tick (`IC-Q`); the recipe is
`docs/testing.md`, `HeadlessLaunchCheck` its compiled twin. Cursor looks and the SDL recipe are group IC.

**Header-only image read and bounded decode (`IH-`, record §117).** `ImageInfo(data:)`/`(contentsOfFile:)` (MetalUI-only,
class `M`, no divergence) reads a PNG's IHDR (length 13, CRC, legal colour/depth pairs) or a JPEG's first SOF (all thirteen
dimension-bearing markers, never DHT/DAC) plus the EXIF orientation: `format`, stored size, `orientation`, `bitDepth`,
`channelCount`, `orientedSize`; PNG and JPEG only, anything else or a damaged header is `nil`, no pixel work, no stb, no limit
of its own (`IH-A`…`IH-C`). **One header walk** (`ImageHeader.swift`) serves `ImageInfo`, `DecodedImage` and `ImageEXIF`'s two
wrappers (`IH-H`); the file form seeks over the pixels through one 64 KiB window and refuses non-regular files (`IH-M`, `IH-O`).
`DecodedImage.Limits(maxInputBytes:maxSide:maxPixels:)` (all optional, inclusive) with the two `limits:` initialisers refuses
from the header **before stb allocates** (an overflowing product is a refusal, `IH-N`); **`decodeImage` refuses a stb size that
disagrees with the header** (`IH-I`), so the unlimited init is `nil` on a header it cannot read. A JPEG damaged after its first
SOF still answers `ImageInfo` (`IH-P`). Cancellation is not built (`IH-K`); `ImageBitmap` is untouched (`IH-L`). A new reader of
image bytes goes through the one walk; `HeaderSource` stays unreachable (guard G-IH1).

**Header-only format sniff (`IS-`, record §130).** `ImageFileFormat` (`png jpeg gif tiff bmp webp heif avif unknown`, a **separate enum**: `ImageInfo.Format` stays `png`/`jpeg` so no exhaustive
switch breaks and `ImageInfo.format` never holds a format no `ImageInfo` can, `IS-A`) and `ImageInfo.sniffedFormat(of:)`/`(ofFile:)` (MetalUI-only, class `M`, no divergence, no probe) are total and
`.unknown` answers every miss: one read of `min(size, 18)` bytes at offset 0 through the one header source (`IS-F`; the file form is `IH-M`'s regular-file window), never stb, never a trap. **A sniff names a
prefix, never a promise** (`IS-C`): `.png`/`.jpeg` with a `nil` `ImageInfo` is damaged, another case with `nil` is unsupported, `.unknown` is not a picture. Whole signatures only (one byte short is
`.unknown`); BMP needs a DIB size at offset 14, `ftyp` is matched on the major brand only (an `mif1` AVIF reads `.heif`), AVIF is its own case, BigTIFF and OS/2 are `.unknown` (`IS-D`, `IS-E`). A new case
owes an arm in the minimal-prefix table (`CaseIterable` pins every case). `FileHeaderSource.testingTraceForUntracedOpens` is a `--no-parallel` test seam (`IS-K`); guard `G-IS1`.
