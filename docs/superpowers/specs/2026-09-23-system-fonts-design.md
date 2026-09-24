# System font discovery — design

**Status: implemented** on `feat/system-fonts` (record §46); roadmap item 8b
of `plans/2026-09-23-cross-platform-roadmap.md`. **Ruling prefix:** `SF-`
(`SF-A`…`SF-D`, next `SF-E`; rulings here).

## Problem

`PortableFontResolver` resolves only faces the caller registers from bytes
(`FN-A`). An app on Linux or Windows had to ship its fonts, and could not ask
for "the system font". The resolver's cascade is every other registered face
(`FB-B`), so registering an installation's hundreds of faces would open all
of them the first time any font resolved.

## Rulings

### SF-A — Discovery reads names, not fonts

A new portable target, `MetalUISystemFonts`, is the one text target with a
file system. It imports Foundation (swift-corelibs-foundation off Apple),
`MetalUIFreeType` and `MetalUIPortableText`, and is a library product.

- `SystemFonts.directories` lists the platform's font directories:
  - **Linux:** `/usr/share/fonts`, `/usr/local/share/fonts`,
    `$XDG_DATA_HOME/fonts` (or `~/.local/share/fonts`) and `~/.fonts`.
  - **Windows:** `%WINDIR%\Fonts` and the per-user
    `%LOCALAPPDATA%\Microsoft\Windows\Fonts`.
  - **macOS:** `/System/Library/Fonts`, `/Library/Fonts` and
    `~/Library/Fonts`.
- `scan(_:)` walks the directories recursively for `.ttf`, `.otf`, `.ttc` and
  `.otc` files, in path order.
- `FreeTypeFaceNames.read(path:)` (in `MetalUIFreeType`) opens each face with
  `FT_New_Face`, which streams from the file, and reads its PostScript,
  family, full and style names. It reads every face of a collection, and
  skips what `FreeTypeFont` would refuse: bitmap-only faces and faces with no
  PostScript name.

### SF-B — Faces load when first needed

`PortableFontResolver.register(_:inCascade:load:)` registers a face by its
names alone. Its bytes are read through `load` the first time a request or a
cascade needs the face, once, whatever the size. There is a matching
`init(defaultFont:load:)`. The byte-registering API is unchanged.

### SF-C — The cascade is a list, not everything

A face registered with `inCascade: false` resolves by name but is never
another face's fallback. `FB-B` still holds for byte-registered faces.

`SystemFonts.resolver()` puts only the platform's fallback families that are
installed into the cascade, in `fallbackFamilies` order:
- **macOS:** Helvetica, Arial Unicode MS, Apple Symbols, PingFang SC,
  Hiragino Sans and others.
- **Windows:** Segoe UI, Segoe UI Symbol, Microsoft YaHei, Yu Gothic UI,
  Malgun Gothic, Nirmala UI and others.
- **Linux:** DejaVu Sans, then the Noto families by script, FreeSans and
  Liberation Sans.

Every other face is registered with `inCascade: false`.

### SF-D — The default face

`family: nil` resolves to the first installed of `defaultFamilies`, in its
regular style:
- **macOS:** Helvetica, then Arial. CoreText substitutes Helvetica too.
- **Windows:** Segoe UI, Arial, Tahoma.
- **Linux:** fontconfig's own `fc-match -f %{family[0]} sans-serif` when
  `fc-match` is installed, then DejaVu Sans, Noto Sans, Liberation Sans,
  Ubuntu, Cantarell and FreeSans.

If no default family is installed, the first regular face is the default.
Regular faces (style Regular, Book, Normal, Roman or none) are registered
before a family's other styles, so a family name resolves to the regular face
(the earlier registration wins a shared name, `FN-A`). No font at all throws
`SystemFonts.NoFontsFound`.

## Tested, and what is not

- The repository's three test fonts stand in for a system directory, so the
  scan, the names, the default, the cascade, the laziness (reads counted
  through an injected `load`) and the ordering have the same answers on every
  platform.
- The real system is checked where a platform guarantees something:
  - **macOS:** `Helvetica.ttc` reads as many faces in order, and the default
    is its regular face.
  - **Windows:** the default is Segoe UI.
  - **Linux:** a container may have no fonts at all, so a resolver is required
    to build only when faces exist.
- **Not measured:**
  - the scan's time on a large installation — one name read per face;
  - whether fontconfig's configured substitutions (aliases, `<prefer>`)
    should shape the cascade, which uses fixed family lists instead;
  - colour emoji faces, which `FT-` cannot draw.
