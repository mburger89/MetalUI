# 308 - A downscaled image decode (`PX-W`)

Branch `feat/image-max-pixel-size` from master `2fbfcafc`. Alloy's per-window background, class M, no divergence label. Ruling `PX-W` in `docs/superpowers/2026-10-07-portable-app-decisions.md`.

**Need.** `ImageBitmap(contentsOfFile:)` decodes at full resolution: a 4000 x 3000 wallpaper keeps about 48 MB resident, a window-sized texture 8 to 15 MB. Alloy decodes off the main thread.

**API.** `ImageBitmap(contentsOfFile:maxPixelSize:)`, `ImageBitmap(data:maxPixelSize:)`. Same `nil` cases; `maxPixelSize < 1` traps naming `ImageBitmap`. A longest side that fits gives exactly `init(data:)`; otherwise the longest side is `maxPixelSize` and the other `max(1, round(other x max / longest))`.

**How.** `PX-C` forbids ImageIO's thumbnailer for PNG/JPEG (bytes must match across platforms), so they decode through stb and `Sources/MetalUI/ImageDownscale.swift` area-averages them (fractional coverage, premultiplied, rounded to nearest; the straight samples are premultiplied on read with `ImageTexture`'s rule). Other formats decode through ImageIO as before and the same resampler runs on the texture's premultiplied pixels. Only the resident size shrinks; the transient peak is the full decode.

**Tests.** `Tests/MetalUICrossPlatformTests/ImageMaxPixelSizeTests.swift`. Each was reddened by a mutation: premultiply on read removed (transparent neighbour), fractional weights replaced by 1 on x and on y (3 to 2 strips), the fit shortcut removed (upscales), `max(1, ...)` floor removed (traps), `.rounded()` made `.rounded(.down)` (shorter side), the `+ 0.5` rounding dropped (2x2 mean), the precondition deleted (trap test).
