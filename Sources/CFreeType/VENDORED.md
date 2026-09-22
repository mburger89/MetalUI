# Vendored FreeType

- Version: 2.14.3
- Source: https://download.savannah.gnu.org/releases/freetype/freetype-2.14.3.tar.xz
- SHA-256 (tarball): 36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f
- Kept: `include/`, `src/{base,sfnt,truetype,cff,psaux,psnames,smooth}`, `LICENSE.TXT`, `FTL.TXT` (used under the FTL).
- Removed: build-system files (`*.mk`, `*.bazel`, `*.py`).
- Edited: `include/freetype/config/ftmodule.h` (only the six drivers MetalUIFreeType uses), `include/freetype/config/ftoption.h` (`FT_CONFIG_OPTION_USE_ZLIB` off: no gzip module).
- Added: `include/cfreetype.h`, `include/module.modulemap`.
- Compiled: the per-module amalgamation files listed in `Package.swift` (ruling FT-A).
