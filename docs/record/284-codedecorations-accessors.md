# 284 - CodeDecorations read-back accessors (Alloy G36, `CV-AT`)

Branch `feat/codedecorations-accessors` from master `ec3940d2`. Class `M`, no divergence added or retired.

**What.** Alloy's tests could not read back the highlight runs on a layer (the styling accessors are package-scoped) and so could only check their own bookkeeping, not what `CodeView` paints. `CodeDecorations.highlights(in:layer:) -> [CodeStyleRun]` returns the runs a `CodeHighlightLayer` stores over a byte range, clipped, in order, in the buffer's current offsets. `CodeDecorations.paintedRuns(in:) -> [CodePaintedRun]` returns the merged result across layers with a resolved `CodeStyle` per run. An id resolves through the existing `style(_:)`.

**How.** Both call `sync()` first. `paintedRuns` calls `stylingOfLine` for each line the range touches, the same call the plan makes, and cuts the line at the foreground, background and underline boundaries, so layer precedence and the `CV-AM` underline rule are the frame's. No cache, counter or state is added; an unstyled buffer answers `[]` before computing any styling. A background is the one painted last, not blended with a translucent one below it.

**Tests** (`Tests/MetalUITestingTests/CodeDecorationReadbackTests.swift`, each shown to fail by mutation): `aLayersRunsReadBackClippedToTheRange`, `anEmptyLayerReadsEmpty`, `runsFollowAnEditAboveThem` (the `sync()` removed), `thePaintedAccessorAgreesWithTheFrame` (two overlapping layers and an underline; the reported colours match the glyph colours the window draws; foreground resolution broken), `backgroundsReadBackAndAnUnstyledBufferCostsNothing`.
