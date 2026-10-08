# Vendored stb_image

- Version: 2.30 (`stb_image.h`, the header's first line: `stb_image - v2.30`)
- Source: https://raw.githubusercontent.com/nothings/stb/master/stb_image.h, fetched 2026-10-07
- SHA-256 (`stb_image.h`, unedited): 594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3
- Licence: the file's own dual licence, **MIT or public domain (Unlicense)**, at its end; copied verbatim to `LICENSE`.
- Kept: `stb_image.h` only, unedited.
- Added: `CStbImage.c` (the one translation unit: `STB_IMAGE_IMPLEMENTATION` with `STBI_ONLY_PNG`, `STBI_ONLY_JPEG`, `STBI_NO_STDIO`, `STBI_NO_LINEAR`, `STBI_NO_HDR`, `STBI_NO_FAILURE_STRINGS`, `STBI_NO_SIMD`, `STBI_MAX_DIMENSIONS 16384` — rulings PX-B, PX-O item 4), `include/CStbImage.h` (the five functions MetalUI calls, with plain C types).
- Warnings: none measured — `swift build --build-tests` on both build systems on macOS (Apple Swift 6.4) and in `swift:6.4-noble`, 2026-10-07, so `CStbImage.c` carries no `#pragma clang diagnostic`. No `unsafeFlags` (SwiftPM refuses them in a URL dependency).
- Ruling: PX-B (`docs/superpowers/2026-10-07-portable-app-decisions.md`). stb_image is not hardened against malicious input; MetalUI's pre-checks are in `Sources/MetalUI/ImageDecoding.swift`.
