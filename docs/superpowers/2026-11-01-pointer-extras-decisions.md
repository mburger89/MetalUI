# Pointer and hover extras (round 3 item R3-10 part 2) - decisions

Prefix `PH-`. **Next unused: `PH-K`.** Record: `../record/188-pointer-extras.md`. Branch `feat/pointer-extras` from master `5be22a6a`.
Divergence labels 1015-1024 reserved: **none taken** (`PH-H`). Probe: `docs/probes/swiftui-pointer-extras.swift` (output recorded in its header; arms
`D` and `V`). Code: `PointerStyle.swift` (MetalUI), `Frame.swift` (the region count), `MetalUIPlatform/PointerStyle.swift` (the seam),
`AppKitCursor.swift`, `SDLInputMapping.swift`, `SDLPlatform.swift`, `SDLBridge.c`. Tests: `PointerExtrasTests.swift` (11),
`AppKitInputAPITests.swift` (1.8b), `SDLInputAPITests.swift` (1.17b), `ImageCursorTests.swift` (7), `ModifierTests.swift` (table 66 -> 67).

## PH-A: what the macOS SDK has and MetalUI lacked

The SDK's `SwiftUI.swiftinterface` / `SwiftUICore.swiftinterface` (macOS 27.2 SDK), searched for `PointerStyle`, `pointerVisibility`,
`onContinuousHover`, `HoverPhase`, `hoverEffect`, `FrameResizePosition`, `FrameResizeDirection`, `onHover`, `pointerStyle`:

| declaration | macOS | MetalUI before |
|---|---|---|
| `PointerStyle` statics `default`, `horizontalText`, `verticalText`, `rectSelection`, `grabIdle`, `grabActive`, `link`, `zoomIn`, `zoomOut`, `columnResize`, `rowResize`, `image(_:hotSpot:)`, `image(_ resource:hotSpot:)` | 15 | built (`CI-H`, `IC-`); the `ImageResource` spelling needs DeveloperToolsSupport, not offered |
| `PointerStyle.frameResize(position:directions:)`, `FrameResizePosition`, `FrameResizeDirection(.Set)` | 15 | **built** (`CI-H`); the brief expected it missing |
| `PointerStyle.columnResize(directions: HorizontalDirection.Set)`, `rowResize(directions: VerticalDirection.Set)`, `HorizontalDirection(.Set)`, `VerticalDirection(.Set)` | 15 | **missing - built here** |
| `PointerStyle.shape(_:eoFill:size:)` | **unavailable on macOS** (visionOS 2) | MetalUI-only look (`BG-K`, divergence 735) |
| `View.pointerStyle(_:)` | 15 | built |
| `View.pointerVisibility(_:)` | 15 | **missing - built here** |
| `View.onContinuousHover(coordinateSpace: some CoordinateSpaceProtocol, perform:)` and the `CoordinateSpace` overload, `HoverPhase` | 13/14 | **built** (`OV-F` took `.global` and `.named`; the "Not offered" row said otherwise and was stale - removed) |
| `View.onHover(perform:)` | 10.15 | built |
| `TableRowContent.onHover(perform:)` | 14 | not built: MetalUI has no `Table` (carried, `PH-J` below) |
| `hoverEffect(_:isEnabled:)`, `HoverEffect`, `CustomHoverEffect`, `HoverEffectContent`, `HoverEffectGroup`, `defaultHoverEffect`, `hoverEffectDisabled`, `listRowHoverEffect(Disabled)`, `ContentShapeKinds.hoverEffect` | **`@available(macOS, unavailable)`** (iOS, tvOS, visionOS) | not applicable |

So the work is `columnResize(directions:)`, `rowResize(directions:)` (with the two direction types) and `pointerVisibility(_:)`.
**Hover effects are not on macOS**: nothing to build, and `docs/divergences.md` does not list them (a framework with no macOS API has no
divergence from it).

## PH-B: the probe (compiled form, macOS 27.2, two runs, byte-identical)

`docs/probes/swiftui-pointer-extras.swift` reuses `swiftui-input-apis.swift`'s instrument (a hosted window, pointer events and `cursorUpdate`
driven into every tracking area, `NSCursor.current` read). It ran in this session. Results (recorded in the probe's header):

- `D1` `.columnResize(directions: .all)` = `D0` `.columnResize` = `resizeLeftRight` = `NSCursor.columnResize(directions: .all)`; **`D2` `.leading` =
  `NSCursor.columnResize(directions: .left)`** (`resizeLeft`), **`D3` `.trailing` = `.right`** (`resizeRight`); **`D4` the empty set shows the arrow.**
  `D6`-`D9` the same for rows: `.up` = `rowResize(.up)` (`resizeUp`), `.down` (`resizeDown`), empty = arrow.
- `V2` `.pointerVisibility(.hidden)`: AppKit's counted **`+[NSCursor hide]` once on entering, `unhide` once on leaving** (the instrument swizzles the
  three hide entry points; the control `V0` is a direct `NSCursor.hide()`); `NSCursor.current` is unchanged. `V3` `.visible` and `V4` `.automatic`
  alone: no call. **`V5`** outer `.hidden`, inner `.visible`, pointer over the inner: no hide (the inner wins). **`V6`** inner `.automatic`: hides
  (it defers to the outer). **`V7`/`V7b`** with a `pointerStyle(.link)` in either order: hide **and** `current` = pointing hand (the two are independent; `V7c`
  the control: the hand alone). `V8` off the inner square: hides. **`V9`** an opaque `onTapGesture` sibling over the pointer: no hide (covered, as a style is).

## PH-C: the API

```swift
public enum HorizontalDirection: Int8, CaseIterable, Sendable, Hashable, Codable { case leading, trailing; struct Set: OptionSet }   // .leading .trailing .all, init(_:)
public enum VerticalDirection: Int8, CaseIterable, Sendable, Hashable, Codable { case up, down; struct Set: OptionSet }              // .up .down .all, init(_:)
extension PointerStyle {
    public static func columnResize(directions: HorizontalDirection.Set) -> PointerStyle
    public static func rowResize(directions: VerticalDirection.Set) -> PointerStyle
}
extension StyledElement          { public func pointerVisibility(_ visibility: Visibility) -> Self }
extension ProposalElementGroup   { public func pointerVisibility(_ visibility: Visibility) -> PointerStyleModifier<Self> }
```

`Visibility` already existed (`SV-AO`). The direction types are in SwiftUICore (macOS 15 for the resize cursors; the types themselves older), spelled as
SwiftUI's; `Hashable` and `Sendable` are additive (SwiftUI's `VerticalDirection.Set` lists only `OptionSet`). The raw values are MetalUI's bit layout.

## PH-D: the directional resize rulings

1. `columnResize(directions: .all)` **is** `.columnResize` (equal), `rowResize(directions: .all)` is `.rowResize`: the factory normalises so
   `PointerStyle`'s equality and the window's change-only send see one value.
2. One direction is a one-way arrow towards that side; **`leading` is the left** (the layout direction is not mirrored, exactly as `frameResize`'s edges, `CI-P`), probe `D2`/`D3`/`D7`/`D8`.
3. **The empty set is `.default`**, the arrow (probe `D4`/`D9`).
4. The seam gets two cases: `PlatformPointerStyle.columnResizeOneWay(towardTrailing:)` and `rowResizeOneWay(towardDown:)`. A `PlatformWindow` conformer with an exhaustive `switch` owes them (or `default:`, which shows the arrow): a migration row, **not** a new `PlatformWindow` requirement.
5. AppKit: `NSCursor.columnResize(directions: .left/.right)`, `rowResize(directions: .up/.down)` on macOS 15+; on macOS 14 `resizeLeft`/`resizeRight`/`resizeUp`/`resizeDown` (`CI-X` item 2's fallback family, one-way). SDL: **SDL has no one-arrow divider cursor**; the nearest is its single-edge resize cursor on that side (`W`/`E`/`N`/`S_RESIZE`, the ones `frameResize` edges use), a documented platform constraint like the hands (`CI-H` item 8), not a divergence. Headless: recorded in `pointerStyles`.

## PH-E: `onContinuousHover(coordinateSpace:)`

Already built (`OV-F`, record 92): `.local`, `.global` and `.named(_:)` are all reported and tested (`CoordinateSpaceTests` A9, the compile guard). The `docs/divergences.md`
"Not offered" row (`SV-N` item 1) predated it and is **removed**; the neighbouring `CoordinateSpace.named` row (`CI-AC`) was equally stale (`OV-D` built it) and is removed with it. No code change.
SwiftUI's generic `some CoordinateSpaceProtocol` overload is spelled with MetalUI's `CoordinateSpace` enum (`NamedCoordinateSpace` conforms to the same literal spelling `.named("x")`), as everywhere else (`OV-D`).

## PH-F: `pointerVisibility(_:)`

1. **It rides the pointer attachment** (`PointerAttachment.visibility`, a class box already on `Handlers.pointer`: no new `Handlers` member, so the fingerprint shape and the
   eighteenth-member size are unchanged). Registration goes through `registerHandlers`, inside the same disabled / `allowsHitTesting` / `hidden()` gates as the style
   (`CI-H` item 3); the modifier test table gains its row (66 -> 67), the D2-style withdrawal is test 8.
2. **`.hidden` and `.visible` attach; `.automatic` attaches nothing** and defers to an outer declaration (probe `V6`). The innermost declaration wins, and on one element the first
   written is the inner, as `pointerStyle` (`CI-AH` item 2; probe `V5`).
3. **Resolution is the style's, one walk**: the cover is the topmost hitbox that is opaque, hovers, or carries a style *or a visibility*; the innermost style and the innermost visibility
   on the cover's layer whose id the cover is or descends from are found independently (probe `V7`: they do not interact); a press holds the pressed chain's pair (`CI-H` item 6); an in-window
   menu or a drawn alert shows the pointer (`SV-N` item 6). An opaque target above covers a visibility region (`V9`).
4. **The resolved value** is one `PointerStyle`: `.hidden` (an internal kind, no public static) when the winning visibility is `.hidden`, else the winning style or `.default`. It is
   sent only on a change, like a style. The hidden pointer's style is not lost: when the pointer reaches a visible part the style is resolved and sent again.
5. **Leaving shows the pointer** (probe `V2`: SwiftUI unhides on leaving): a pointer exit while `.hidden` was the sent value sends `.arrow` once, then forgets (`CI-S`). Re-entry sends again.
6. `pointerVisibility` is a pointer-region modifier: a region tally (`pointerStyleRegionCount`) counts visibility regions so a frame with only those still resolves.

## PH-G: the seam and the platforms

`PlatformPointerStyle.hidden` is the seam's hidden pointer. **No new `PlatformWindow` requirement**: a case beside the image cursor's (`IC-A`) is enough, and a conformer that ignores it
(a `default:` arm) leaves the pointer visible, the honest degradation.

- **AppKit**: a **transparent 1x1 cursor** (`AppKitCursor.hiddenCursor`) is the host view's cursor while hidden. SwiftUI uses the counted `NSCursor.hide()`/`unhide()` (probe `V2`); a counter must be
  balanced, and a window closing, the pointer leaving the host view, or the app resigning while hidden would leave the pointer invisible for good. A cursor that is replaced by the next
  `set()` has nothing to balance. The visible difference: SwiftUI's hide survives the pointer crossing into the title bar's own cursor rects; the transparent cursor does not (the system's
  cursor shows there, which is what a person expects over chrome). Measured by test and a human check (`PH3`).
- **SDL**: `SDL_HideCursor()` / `SDL_ShowCursor()` through two bridge functions (`mui_set_cursor_visible`, `mui_cursor_visible`); every other style shows the pointer first. SDL's visibility is
  process-global and idempotent. A driver that refuses leaves it as it was. `SDLCursorTable.systemCursor(for: .hidden)` is `.default` and is never asked.
- **Headless** (`HeadlessPlatformWindow`, `TestWindow.pointerStyle`): records the style, `.hidden` included; the answer is "the pointer was asked to hide", which is what the platform seam can say.
- Every test fake already records the style (`pointerStyles`); none switches exhaustively.

## PH-H: divergences

None taken (1015-1024 stay unused). `columnResize(directions:)`, `rowResize(directions:)` and `pointerVisibility(_:)` have SwiftUI's spellings and measured behaviour; the platform
approximations (SDL's edge cursors, the transparent cursor) are platform constraints in the style of `CI-H` item 8, listed in the `PointerStyle` doc comment and the human checks. The divergences
page loses two stale "Not offered" rows (`PH-E`) and the `columnResize(directions:)`/`rowResize(directions:)` half of a third; its live count (190) and next label (210) do not move.

## PH-I: tests (mutations in the record)

`PointerExtrasTests.swift` 1-11 (the option sets; the lowering; the window's send on both vocabularies; hidden sent/shown/re-sent; innermost and `.automatic`; independence from style; the
opaque cover; the three withdrawing gates; a press hold; a drawn alert; the region tally); `appKitMapsTheOneWayResizesAndTheHiddenCursor` (the cursors as values, the hidden
cursor's pixel, the host view); `sdlOneWayResizesMapToEdgeCursorsAndHiddenHidesTheCursor` (macOS-run in `Backends/SDL`, not in the root suite); the headless test in
`MetalUITestingTests`. The probe is the oracle for each expectation named with a probe arm.

## PH-J: carried

- `TableRowContent.onHover(perform:)` (macOS 14): MetalUI has no `Table`; it arrives with one.
- `PointerStyle.image(_ resource: ImageResource, hotSpot:)`: needs `DeveloperToolsSupport`'s asset catalog type; MetalUI has no resources.
- A right-to-left layout does not mirror `leading`/`trailing` for the resize cursors (`CI-P` item 3's rule, unprobed).
- `hoverEffect` and its family: not on macOS (`PH-A`); would only arrive for an iOS product, which is a boundary (`PB-A`).
