# 33 — Portable font resolution, 2026-09-23

Branch `feat/portable-font-resolver`, from `feat/portable-content-sizes` (PR
#14, record §32). Spec: `docs/superpowers/specs/2026-09-23-portable-font-resolver-design.md`,
rulings `FN-A`…`FN-D` (next `FN-E`). Roadmap item 4.

## What changed

- `FreeTypeFont.familyName`, `postScriptName`, `fullName` (name-table entry
  4); `CFreeType`'s own umbrella header gains `FT_SFNT_NAMES_H`.
- `PortableFontResolver` (`FN-A`…`FN-C`) in `MetalUIPortableText`.
- Pins: `FontResolverDeterminismTests` (`FN-D`).
- Roadmap: system font discovery split out as item 8b.

## Measured first

CoreText's `CTFontCreateWithName` over 25 queries with the bundled faces
registered for the process (table in the spec): PostScript, family and full
names, case-insensitive, nothing else; unmatched → Helvetica.

## Mutations

| # | Mutant | Reddens |
|---|---|---|
| R1 | case-sensitive match | `everyQueryResolvesToTheFaceCoreTextResolvesTo` |
| R2 | full name not matchable | `everyQueryResolves…` |
| R3 | family name not matchable | `everyQueryResolves…` |
| R4 | PostScript name not matchable | `everyQueryResolves…` |
| R5 | a leading space trimmed from the query | `everyQueryResolves…` — **green at first**; see below |
| R6 | last registration wins | `theFirstRegisteredFaceWinsASharedName` |
| R7 | no memo | `aResolvedFontIsMemoizedPerFaceAndSize`, `theFirstRegistered…` |
| R8 | unmatched resolves to the last face | `aResolvedFontIsMemoized…`, `everyQueryResolves…`, `nilIsTheDefaultFace`, `theFirstRegistered…` |
| R9 | full name prefers the Macintosh record | **none** — the bundled faces' Mac and Windows full names are equal |

**R5 was green against the first oracle**, whose only default face was Noto
Sans: `" Noto Sans"` wrongly matching Noto Sans is indistinguishable from
correctly substituting a Noto Sans default. The oracle now runs once per
bundled face as the default. The shared-name test had the same shape (two
registrations of one file have one PostScript name whichever wins) and now
reads the winner through the memo's instance identity.

A slip in taking R5 by hand: `git checkout` does not restore an untracked
file, and the mutant sat in the new source until reverted by hand — checked
by grep before anything else ran. The scratchpad runner restores from memory
and is unaffected.

## Counts

1675 + 6 = **1681**; see `CLAUDE.md`. `Tests/PortableTests`: 16 + 6 + 5.
