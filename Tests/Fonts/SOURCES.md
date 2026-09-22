# Test fonts (ruling FT-G)

Two static, open-licensed faces for the FreeType rasterizer's CoreText oracle
tests (`Tests/MetalUIFreeTypeTests/FreeTypeOracleTests.swift`), one per
outline format so both FreeType drivers are exercised. Loaded by path from
`#filePath`, not as SwiftPM resources. Not a layout fixture (TX-B bans text
from the WebKit goldens only).

| File | Outlines | Version | Licence |
| --- | --- | --- | --- |
| `NotoSans-Regular.ttf` | TrueType (`glyf`/`loca`), no `fvar` | Noto Sans v2.015, unhinted build | SIL OFL 1.1, `NotoSans-OFL.txt` |
| `SourceSans3-Regular.otf` | CFF (`CFF `), no `fvar` | Source Sans 3 3.052R | SIL OFL 1.1, `SourceSans3-LICENSE.md` |

Outline tables were checked by reading each file's sfnt table directory:
Noto Sans has sfnt version `00 01 00 00` and tables `GDEF GPOS GSUB OS/2 cmap
glyf head hhea hmtx loca maxp name post`; Source Sans 3 has `OTTO` and `BASE
CFF  DSIG GDEF GPOS GSUB OS/2 cmap head hhea hmtx maxp name post`.

## Noto Sans Regular

- Release: https://github.com/notofonts/latin-greek-cyrillic/releases/tag/NotoSans-v2.015
- Archive: https://github.com/notofonts/latin-greek-cyrillic/releases/download/NotoSans-v2.015/NotoSans-v2.015.zip
  (SHA-256 `0c34df072a3fa7efbb7cbf34950e1f971a4447cffe365d3a359e2d4089b958f5`)
- Member `NotoSans/unhinted/ttf/NotoSans-Regular.ttf`, SHA-256
  `f3961a9cde016d41a4879aecda1474d3a36d6bf54fa0e4643de029cc2248b0e8`
- Member `OFL.txt` -> `NotoSans-OFL.txt`, SHA-256
  `cee9892f9f0cc8fe882c9e9537ee6a89621d86ee7ceaf70b02e2b2b1c25c061a`

## Source Sans 3 Regular

- Release: https://github.com/adobe-fonts/source-sans/releases/tag/3.052R
- Archive: https://github.com/adobe-fonts/source-sans/releases/download/3.052R/OTF-source-sans-3.052R.zip
  (SHA-256 `a4ebbdea20b08ccbd7bf3665a9462454eefdd01d9a6307129d3b3d4672981074`)
- Member `OTF/SourceSans3-Regular.otf`, SHA-256
  `08df266400933d3178d081a45f94a08814c3e55b4b7dd2e0ff69cb1329f13ab6`
- Licence: https://raw.githubusercontent.com/adobe-fonts/source-sans/3.052R/LICENSE.md
  -> `SourceSans3-LICENSE.md`, SHA-256
  `89ad2c4f66dd29127527493e729c31e731f111cf10faf5774c3db9275ed0c22c`
