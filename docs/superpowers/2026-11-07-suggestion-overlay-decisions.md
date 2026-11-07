# Suggestion overlay and image content types - decisions (prefix `SOC-`)

Two small requests from Alloy (a chat composer): an anchored list that never takes focus or keys, and image content types. Branch `feat/suggestion-overlay` from master `2da93ec6`; record 234. Class `M` for both (no SwiftUI counterpart; `VerticalEdge`, `ContentType.png` and friends are SwiftUI/UTType's names). No divergence added. Next unused: `SOC-I`.

## SOC-A: `suggestionOverlay(isPresented:edge:alignment:spacing:content:)`

On `StyledElement` and `ProposalElementGroup`: `edge: VerticalEdge = .top` (a new public two-case enum, SwiftUI's name), `alignment: HorizontalAlignment = .leading`, `spacing: Pixels = 4`. It is the `PopoverModifier` wrapper (one identity level, the anchor's frame recorded by last frame's prepaint, so it appears a frame after the anchor was first laid out and follows it within a frame) with a third `PopoverKind` (`.suggestion`) and a `PresentationPlacement.suggestion` laid out by `SuggestionPlacement`. No chrome and no padding: the content draws its own background. Placement is pure (`SuggestionPlacement.place`): `spacing` off the anchor's frame on `edge`'s side; if that side's room is less than the content's height the side with more room (the flip when the other fits, and when neither fits the height is capped to that room and the content re-measured at it, so a `ScrollView` scrolls); the `alignment` edge flush with the anchor's, then clamped to `0...window - width`. Reference: the same window-sized presentation root as `.popover` (`MN-M`), measured at the ideal size capped at the window.

## SOC-B: nothing dismisses it but the app, and it takes no key

It is not registered with `Frame.registerOpenPopover`, so the window's popover stage (`MN-N`, `MN-Y`) never sees it: an outside press does not dismiss and passes on, Escape is not consumed before the keymap, and `lastOpenPopovers` stays empty (the drawn-chrome regions are untouched). The binding is read and never written; the `dismiss` closure is empty. Why a popover takes keys (`MN-Z`, `MN-N` item 2): it is the dismissal stage that eats Escape and the outside press, not the layer; the layer alone takes none. The use is a composer: `.onKeyPress` on the field routes up/down/Return/Tab/Esc to the app's selection model and returns `.ignored` for everything else, so the field types.

## SOC-C: input on the overlay

The presentation keeps `AnchoredPresentation`'s raw opaque hitbox (`MN-Z`): a press, wheel or drop on the overlay's padding never reaches what lies beneath, and the content ranks above it, so a `Button` row or a tap runs and a `ScrollView` scrolls. A press never moves focus by itself (`Window.focus` doc; `focusOnPress` only focuses a `focusable(.edit)`/text field or clears for a key region **on the cover's own layer**, `KF-F` item 3): the overlay is on the presentation layer, so even a `hoverKeyRegion()` pane around the composer does not blur the field when a row is pressed (pinned). A row that is itself `.focusable(interactions: .edit)` would take focus: that is the app's choice.

## SOC-D: accessibility

The chrome box is built with `popoverHint = false`: no `.popover` node, so the overlay is not a modal sibling and its rows are ordinary nodes beside the field in the window's tree.

## SOC-E: `ImageData`

`public struct ImageData: Transferable` (`data: Data`, `contentType: ContentType`), importing `[.png, .tiff, .jpeg]` in that order and told the exact type that arrived (the drop path's exact-match rule, `DN-S` item 2; the clipboard path's `importClipboardItem`). It exports its one type (and its parents). A non-image type, empty bytes, or being told `.data` is refused. It exists because `Data` is always told `.data` (`T7e`) and cannot learn what it holds.

## SOC-F: `ContentType.image`, `.png`, `.tiff`, `.jpeg`

`public.image` conforms to `public.data`; `public.png` (ext `png`), `public.tiff` (`tiff`, `tif`) and `public.jpeg` (`jpg`, `jpeg`) conform to `public.image`. All four are built-ins (`ContentType.builtIn`), so a clipboard listing them carries the conformance and `hasContent(of: .image)` is true for any. A file importing both MetalUI and UniformTypeIdentifiers spells `ContentType.image` where `.image` is ambiguous (as `.json`). Behaviour change, stated: a clipboard holding only a PNG used to read as `nil` for `Data` (the type had no conformance); it now reads the bytes.

## SOC-G: `Clipboard.readData(of:)` and the platforms

`readData(of: ContentType) -> Data?` mirrors `hasContent(of:)`: item 0's first offered type that is the type or conforms to it, its bytes if non-empty. `.png` takes PNG only, `.image` the first image the source listed; **nothing converts between formats** (a TIFF-only pasteboard answers `nil` for `.png`). AppKit: no source change, the seam's identifiers are `NSPasteboard` raw types (`public.png`, `public.tiff`, `public.jpeg`). SDL: `ClipboardMime` maps `public.png`/`.jpeg`/`.tiff` to `image/png`, `image/jpeg`, `image/tiff` (they were `mime:image/png` foreign identifiers before, which conform to nothing); SDL lists whatever mime the source offers: X11 and Wayland applications that offer `image/png` read, and Windows is **not measured**: SDL's Windows clipboard does not translate `CF_DIB`/`CF_BITMAP` to `image/png`, so an image copied from another Windows application is probably not listed (human check SOC4). The headless window stores any identifier (`HT-X` item 1): nothing to add, pinned.

## SOC-H: drops

A dropped `.png` **file** is a `URL` (`.fileURL`) on every platform and an `ImageData` destination refuses it. Raw image data drops (AppKit: a browser or app dragging an image; the pasteboard types carry their `UTType` supertypes) reach `dropDestination(for: ImageData.self)` told the offered format, and `Data` takes the bytes. SDL delivers files and text only (`DN-M`), so there is no raw image drop there.
