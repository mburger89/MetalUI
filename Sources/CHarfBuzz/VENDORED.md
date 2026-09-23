# Vendored HarfBuzz

- Version: 14.5.0
- Source: https://github.com/harfbuzz/harfbuzz/releases/download/14.5.0/harfbuzz-14.5.0.tar.xz
- SHA-256 (tarball): b7132e148358a45185c9feafd049dbaf243649d3c44414b3534d9c95d18592b9
- Kept: the whole `src/` tree (the amalgamation `#include`s subdirectory sources such as `OT/Var/VARC/VARC.cc`) and `COPYING` (Old MIT).
- Removed: generator/check scripts (`*.py`), docs, build files (`meson.build`, `Makefile*`), test sources, fuzzers.
- Edited: nothing. No `unsafeFlags`; the vendored code builds warning-free on both macOS build systems and on Linux (measured).
- Compiled: `src/harfbuzz.cc` only (ruling SH-A), C++17, no optional backend (no FreeType, ICU, GLib, CoreText).
