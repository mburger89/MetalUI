# Record 234: the suggestion overlay and image content types (Alloy gap G8)

Branch `feat/suggestion-overlay` (master `2da93ec6`). Rulings `SOC-A`..`SOC-H` in `docs/superpowers/2026-11-07-suggestion-overlay-decisions.md` (new prefix; next `SOC-I`). Class `M`; no divergence.

## 1. What was asked and built

Alloy's chat composer needs (1) a list anchored above its `TextField` that the user keeps typing past, with up/down/Return/Tab/Esc routed by the app, and (2) image content types readable from the clipboard and drops.

**Overlay.** `Sources/MetalUI/SuggestionOverlay.swift` (`VerticalEdge`, `suggestionOverlay` on both vocabularies, `SuggestionPlacement`); a third `PopoverKind` and `PresentationPlacement` case; `AnchoredPresentation.prepaint` skips `registerOpenPopover` for it (the whole difference from `anchoredOverlay`: the window's popover stage, which eats Escape and dismisses on outside presses, never sees it); the chrome box takes `popoverHint: false` so it is not a `.popover` node. The raw opaque hitbox stays, so the layer blocks what lies beneath.

**Image types.** `ContentType.image/.png/.tiff/.jpeg` (+ `ContentType.builtIn`), `Clipboard.readData(of:)`, `ImageData` (`Sources/MetalUI/ImageData.swift`), `ClipboardMime` rows for `image/png|jpeg|tiff`. AppKit and the headless window needed no source change; SDL's mapping is the table row (its drops are files and text only).

## 2. Findings along the way

- The first design had a `fitsOther` branch for the flip; a mutation of it reddened nothing because the "side with more room" branch below it produces the same flip. It was deleted (one rule: if `edge`'s side is too small take the side with more room, capped).
- A press on the overlay does not blur the field even inside a `.hoverKeyRegion()` pane: the press-time focus stage only clears for a region on the cover's own layer. Pinned with a separating arm (a press on the pane's background does clear).
- A clipboard holding only a PNG read `nil` as `Data` before (the identifier had no conformance); it now reads the bytes. A `mime:image/png` identifier is now `public.png`.
- A `Button`'s accessibility frame is its label, so a row's frame is asserted with the size inside the label.

## 3. Tests

`Tests/MetalUITestingTests/SuggestionOverlayTests.swift` (15), `ImageContentTypeTests.swift` (7), `Tests/MetalUICrossPlatformTests/ClipboardMimeTests.swift` (+1 and one foreign-mime example moved to `image/webp`).

## 4. Mutations (each alone, filtered run, reverted)

| Mutation | Reddened |
| --- | --- |
| register the overlay in `openPopovers` (with a real dismiss) | `anOutsideClickLeavesItShown`, `theFieldsOnKeyPressSeesTheNavigationKeysAndEscape`, `clickingARowRunsItAndTheFieldKeepsFocus`, `typingContinuesIntoTheFieldWhileTheOverlayIsShown`, `aPressOnARowInsideAKeyRegionDoesNotBlurTheField` (registered alone, with the empty dismiss: only the Escape test) |
| `popoverHint: true` | `itsContentIsASiblingGroupNotAPopover` |
| non-opaque hitbox | `aPressOnTheOverlaysPaddingDoesNotReachWhatLiesBeneath` (the row-press test did not: a row has its own target) |
| top/bottom swapped in `place` | `itSitsAboveTheFieldOnTopAndBelowOnBottom`, `itFlipsToTheOtherEdgeWhereItWouldLeaveTheWindow`, `whereItFitsNeitherSideItIsCappedToTheRoomOfTheBetterOne`, `anOutsideClickLeavesItShown` |
| no flip/cap (`if false`) | `itFlipsToTheOtherEdgeWhereItWouldLeaveTheWindow`, `whereItFitsNeitherSideItIsCappedToTheRoomOfTheBetterOne` |
| no horizontal clamp | `itIsClampedInsideTheWindowHorizontally` (the first version of the test did not: the overlay fitted; the field was moved right) |
| the overlay's chrome focusable on press | `clickingARowRunsItAndTheFieldKeepsFocus`, `aPressOnARowInsideAKeyRegionDoesNotBlurTheField` |
| `presenting` ignores the binding | `nothingIsDrawnOrHitWhileNotPresented` |
| `.png` conforms to `.data` only | `aClipboardPNGReadsByExactTypeAndByParent`, `aRequestForTIFFGetsTIFFWhenPNGIsListedFirst`, `imageDataExportsItsOwnFormatOnly`, `theImageTypesHaveTheirUTIsAndConformToPublicImage` |
| `.png` left out of `builtIn` | `aClipboardPNGReadsByExactTypeAndByParent`, `aRequestForTIFFGetsTIFFWhenPNGIsListedFirst` |
| `readData` ignores the type | `aClipboardPNGReadsByExactTypeAndByParent`, `aRequestForTIFFGetsTIFFWhenPNGIsListedFirst`, `anEmptyOrAbsentImageReadsNil` |
| `ImageData` imports `.fileURL` | `aDroppedPNGFileArrivesAsAFileURL` |
| `ImageData` imports `[.image]` | `aRequestForTIFFGetsTIFFWhenPNGIsListedFirst`, `imageDataExportsItsOwnFormatOnly`, `rawImageDataArrivesWithItsFormat` |
| delete the `image/png` mime row | `theImageMimesAreTheBuiltInImageTypes` |

Not mutated: `theWheelScrollsTheOverlaysScrollView` pins the claim; no source line is specific to it. `itWorksOnAProposalContainerToo` is separated by compilation (delete the overload).

## 5. Carried

- SDL on Windows: images from other applications probably not listed (human check SOC4). SDL raw image drops do not exist.
- No png/tiff/jpeg conversion; no decoding of `ImageData` (the existing image decoder takes the bytes).
- A demo section was not added.
