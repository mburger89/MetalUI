# 406: `METALUI_TRACE_SHAPING=1` (`TS-E`, Alloy)

Class `M` (an environment switch and package types; no public API), no divergence (labels unchanged). Branch `feat/shaping-trace`, base master `361c9944`. **Numbering:** 404 belongs to an in-flight PR and master's last record is 405, so this is 406. Alloy sees 1.4-1.7 ms of real CoreText shaping per keystroke in a chat composer (`CoreTextTextSystem.measure`, `Shaper.shape`) and could not see which strings missed `ShapingCache` each frame: the cache's `hits`/`misses` were internal counters with no switch and no log.

## Change

- `Sources/MetalUITextSystem/ShapingTrace.swift`: `ShapingTrace` (package) with the switch `active`, a `sink` (default standard output, as `RetainedTrace`), the quoting (40 characters then `…`, newline, tab, quote and backslash escaped), the key description (font PostScript name and size, `var=<n>` for variations, `matrix` when not identity, ` w=<width>`, the non-default `lines`, `trunc`, `align`) and a per-system `Recorder` (hits, misses, the first 20 missed entries and a count of the rest, the uncached entries). `finish(frame:system:)` writes the line and clears the recorder.
- `ShapingCache` records in `shaped` and `styled` (hit, miss) and writes the line in `endFrame()`; `CoreTextTextSystem.caretOffsets` records an uncached entry. `PortableTextSystem` records at its three dictionaries and writes in `endFrame()`.
- `MetalUI` reads `METALUI_TRACE_SHAPING` (value exactly `"1"`) once at the first `Window` or `Frame` (`shapingTraceFromEnvironment`), because `MetalUITextSystem` imports no Foundation.

## Example

```
shaping frame 3: hits 4 misses 2 [portable] missed: "alpha beta changed"(NotoSans-Regular 13 w=200), "alpha beta changed"(NotoSans-Regular 13 w=120.96499999999997)
shaping frame 3: hits 1 misses 2 [coretext] missed: "changed"(.SFNS-Regular 13 var=1), "hello world"(.SFNS-Regular 15 var=1 w=100)
```

A changed string misses twice, once at the proposed width it was measured at and once at the width it is drawn at: a finding the counters alone hid.

## Paths that shape without the cache

`CoreTextTextSystem.caretOffsets` (`Shaper.caretOffsets`) and `PortableTextSystem.caretOffsets` (`PortableText.caretOffsets`) shape on every call, with no cache: a text field asks for its caret offsets, which makes them the likeliest source of per-keystroke shaping that no hit/miss count shows. The portable system's styled `layOut` is also uncached (`GT-H`). The trace lists these under `uncached:` and counts them in neither number. Not changed here: caching them is a separate decision.

## Cost

Off: one `Bool` read per shape call, no allocation (`ShapingTrace.described` stays 0 and `frameWork` equals the traced frame's). On: one string per miss, appended to an array capped at 20 a frame.

## Tests (7 new)

`ShapingTraceTests` (`MetalUITestingTests`, portable system): `eachFrameReportsItsHitsMissesAndMissedStrings`, `missedStringsAreTruncatedEscapedAndCapped`, `twoMissesOfOneStringShowTheKeyThatDiffers`, `aWindowWithTracingOffBuildsNothingAndCostsTheSameWork` (descriptions built 0, equal counted work, on Darwin more allocations traced than untraced). `ShapingTraceCoreTextTests` (`MetalUITextTests`, Darwin): `theCoreTextCacheReportsHitsMissesAndTheKeyPerFrame`, `aCaretOffsetsCallIsReportedAsUncached`, `aCacheWithTracingOffDescribesNothing`.

## Mutations (each reddens)

`Recorder.finish` not clearing (3 tests); `hit()` a no-op (4); the `active` guard dropped around the CoreText miss (`aCacheWithTracingOffDescribesNothing`); the `caretOffsets` bypass call removed (`aCaretOffsetsCallIsReportedAsUncached`); the `active` guard dropped around the portable miss (`aWindowWithTracingOffBuildsNothingAndCostsTheSameWork`).
