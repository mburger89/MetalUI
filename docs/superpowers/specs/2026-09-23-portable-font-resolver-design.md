# Portable font resolution — design

**Status: implemented** on `feat/portable-font-resolver` (record §33);
roadmap item 4 of `plans/2026-09-23-cross-platform-roadmap.md`. **Ruling
prefix:** `FN-` (lettered; `FN-A`…`FN-D`, next `FN-E`; rulings here, no
separate decisions doc).

## Goal

`Text` asks for a font as `family: String?` and a size;
`FontResolver.resolve(family:size:)` turns that into a CoreText font with
`CTFontCreateWithName` (or the system UI font for `nil`). The portable path
needs the same request answered from font files, with no Apple framework.

## Rulings

### FN-A — A registry of faces, matched by their own names

`PortableFontResolver(defaultFont:faceIndex:)` holds registered faces
(`register(_:faceIndex:)`), each matchable by its **PostScript name, family
name and full name** as the font's own tables give them: FreeType's
`FT_Get_Postscript_Name`, `FT_Face.family_name`, and name-table entry 4
(`FreeTypeFont.postScriptName`, `familyName`, `fullName`; Windows UTF-16BE
US-English record first, then any Windows Unicode record, then Macintosh
Roman). Matching **ignores case and nothing else**: no whitespace folding,
no family-plus-style synthesis. A face registered earlier wins a name two
faces share.

These are CoreText's rules, measured with the three bundled faces
registered for the process (`CTFontManagerRegisterFontsForURL`):

| query | CoreText |
|---|---|
| `Noto Sans`, `noto sans`, `NOTO SANS` | Noto Sans (family) |
| `NotoSans-Regular`, `notosans-regular` | Noto Sans (PostScript) |
| `Noto Sans Regular` | Noto Sans (full name) |
| `Source Sans 3 Regular` | **Helvetica** — its full name is `Source Sans 3` |
| `NotoSans`, `Noto  Sans`, `␠Noto Sans`, `Noto Sans␠`, `Noto`, `Source Sans` | Helvetica |
| `Noto Sans Bold`, `Noto Sans-Bold`, `Noto Sans Italic`, `Nope`, `""` | Helvetica |

### FN-B — `nil` and every unmatched name resolve to the default face

`family: nil` is the default face (the Apple path's system UI font), and a
name that matches nothing — `""` included — **substitutes** the default face,
as `CTFontCreateWithName` substitutes Helvetica: it never fails. Callers key
caches on the resolved `PortableFont.key`, never on the request (`FontKey`'s
rule). A size that is not finite and positive traps, as
`FontResolver.resolve` does.

Oracle: 28 queries resolve to the face CoreText resolves to, or to the
default where CoreText substitutes — **run once with each bundled face as
the default**, because a near-miss that wrongly matched the default face's
own name would look like a correct substitution in the run where that face
is the default (found by mutation R5, which trims a leading space and was
green against a single-default oracle).

### FN-C — Memoized per face and size; no discovery

`resolve` returns the same `PortableFont` instance for the same resolved face
and size. The resolver reads no file system: this target imports nothing
that could. Finding a platform's installed fonts (fontconfig on Linux,
DirectWrite or the Fonts directory on Windows) and registering them belongs
to the platform layer — roadmap item 8b.

**Not handled:** weight, width and slope (the Apple API has none either:
`family` and `size` only); choosing among several registered faces of one
family (the first registered wins; CoreText's choice there is unmeasured —
no bundled family has a second face); name-table entry 16 (typographic
family), which no bundled face sets apart from entry 1.

### FN-D — Pins

`Tests/PortableTests`' `FontResolverDeterminismTests`: fourteen queries'
resolved faces as literals, and a substitution distinguished from a match.
