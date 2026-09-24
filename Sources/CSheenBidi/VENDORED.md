# SheenBidi 3.0.0, vendored (ruling BD-A)

- Upstream: https://github.com/Tehreer/SheenBidi, tag `v3.0.0`.
- Tarball `https://github.com/Tehreer/SheenBidi/archive/refs/tags/v3.0.0.tar.gz`,
  SHA-256 `86c56014034739ba39a24c23eb00323b0bf6f737354f665786015fca842af786`.
- Licence: Apache-2.0 (`LICENSE`).
- Copied: `Headers/` and `Source/` only, **unedited**. The package compiles
  `Source/SheenBidi.c` alone with `SB_CONFIG_UNITY` defined, which
  `#include`s every other translation unit — upstream's own unity build.
- Used for: the Unicode Bidirectional Algorithm (UAX #9) over a paragraph,
  per-line visual runs, and script runs, by `MetalUIPortableText`.
