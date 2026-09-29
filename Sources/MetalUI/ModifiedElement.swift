import MetalUICore
import MetalUILayout

// The legacy path's outer modifiers, `.padding(_:)` and every `.frame(...)` spelling,
// as the layers of ONE flat wrapper type (lane 2 of
// `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`; rulings
// MC-A, MC-B, MC-C, MC-I, MC-K in
// `docs/superpowers/2026-09-15-modifier-composition-decisions.md`).
//
// **What it replaces.** `.padding` returned `Box<Self>` and `.frame` returned
// the deleted `FrameModifier<Self>`, so a chain nested one TYPE level per
// modifier — `Box<FrameModifier<Box<Text>>>` — and a stored subtree had to
// spell every level. Here every modifier after the first adds a LAYER to the
// same `ModifiedElement<Base>`; the type grows once, at the first wrapper.
//
// **Since stage 11 (ruling `LR-FV`) the wrapper is `ModifiedContent<Content,
// ModifierLayer>`**, declared with the layer recursion in `ModifiedContent.swift`;
// `ModifiedElement<Content>` is its typealias. This file keeps the legacy
// vocabulary's layer type, `ModifierLayer` (whose `ModifierLayerKind` arm is in
// `ModifiedContent.swift`), `_wrap`'s default and the fixed `frame` overload.
//
// **What it keeps, exactly.** Each layer is what one `Box` around one child
// carried — a `Style`, a `Decoration`, `Handlers` and an `ElementID?` — and
// contributes one node, one identity level, one `$anim` slot, one hitbox
// registration and one background fill, in the order nested `Box`es produce
// them. The oracle is hand-built nested `Box`es, compared observation by
// observation with a disagreeing oracle each (ruling MC-B):
// `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`
// (`ModifierCompositionProofTests.swift`) and
// `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`
// (`ModifiedElementTests.swift`) — stage 7b's N2.2 and N2.1, which replaced the
// legacy-authority originals (record §49 §4 rows 230–231) and compare every
// observation but the node count (`LR-EN`).
//
// **What the oracle does NOT compare** is anything `Element`'s group defaults
// (`requestGroupLayout`/`prepaintGroup`/`paintGroup`) do per ELEMENT: a nested
// `Box` gets them at every level, a layer gets them once for the whole chain.
// **Any hook added to those defaults must be mirrored per layer** in
// `ModifiedContent.swift`'s recursion (ruling MC-B's "does NOT cover"; the
// accessibility track's `display: none` suppression, AB-O, and the element
// bounds log are mirrored there).

/// One legacy wrapper modifier's worth of state: exactly what one `Box` around
/// one child carries (ruling MC-A).
///
/// A public type so `ElementGroup._wrap(_:)` can name it; its members and its
/// initializer are internal, so tasks 4 and 5 can add layer kinds without a
/// public break, and no module outside `MetalUI` can build one.
public struct ModifierLayer {
    var style: Style
    var decoration: Decoration
    var handlers: Handlers
    var elementID: ElementID?
    /// What the `.frame(...)` overload that built this layer asked for, before
    /// `FrameSpec.style()`'s CSS lowering wrote `style`; `nil` for a `.padding`
    /// layer (plan task 7, ruling `LR-H`). A frame layer lowers onto ONE kernel
    /// frame, reading its ideals, its infinite maxima and its alignment from
    /// here, and the rest from the animated `style`
    /// (`LayoutPass.lowerLegacyLayer`). Until stage 9 the legacy authority
    /// trapped on a non-`nil` ideal at registration (`FR-D`).
    var frameSpec: FrameSpec?

    /// Whether a `.frame(...)` overload built this layer (ruling `CN-N`). A frame
    /// layer over EXACTLY ONE node registers as a one-cell `display: .stack`,
    /// so an oversized child overflows both axes as SwiftUI's does; over zero or
    /// several nodes it keeps `FR-C`'s flex row. The choice is
    /// `lowered(_:childCount:)`'s, made in `requestLayout` per layer.
    var isFrame: Bool { frameSpec != nil }

    init(style: Style, frameSpec: FrameSpec? = nil) {
        self.style = style
        self.decoration = Decoration()
        self.handlers = Handlers()
        self.elementID = nil
        self.frameSpec = frameSpec
    }

    /// The `Style` this layer registers with around `childCount` nodes (ruling
    /// `CN-N`). A frame layer over exactly one node becomes `display: .stack`:
    /// the stack reads `alignItems` (vertical) and `justifyItems` (horizontal),
    /// both written by `FrameSpec.style()`'s one `switch` over the nine
    /// alignments, and offers its child fit-content, so the child keeps its own
    /// size and overflows the frame centred on the alignment
    /// (probe arms `A5`/`B9`; its legacy pin was retired by stage 7b, record §49
    /// §4 row 198, the lowered frame's overflow being
    /// `aLoweredFixedFrameLayerPlacesAFixedChildAtEachAlignment`). The flex fields the row lowering wrote stay and are ignored
    /// by a stack; item fields the layer carries in ITS parent (`flexGrow`,
    /// `alignSelf`, `minSize`, `position`) are untouched.
    ///
    /// **Several nodes keep the row**: a frame over a two-member `Component`
    /// lays the members out side by side, where SwiftUI frames each member
    /// (component-distribution `G7`); neither lowering is that answer, and the
    /// row is today's.
    ///
    /// **`display: .none` is kept.** `hidden()` is a `Self`-returning modifier,
    /// so written directly after a frame it sets `display` on the frame layer
    /// itself (outermost, or inner once a wrapper follows); lowering over it
    /// undid `hidden()` for layout and for accessibility (the branch checker's
    /// regression, record §17). `display` is the only field this method writes,
    /// so it is the only one a caller's modifier could lose here. Pinned by
    /// `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient` (its
    /// layout twin, `hiddenAfterASingleChildLegacyFrameStillHidesTheElement`,
    /// was retired by stage 7b with `display: none` taking no space — record §49
    /// §4 row 200).
    func lowered(_ style: Style, childCount: Int) -> Style {
        guard isFrame, childCount == 1, style.display != .none else { return style }
        var style = style
        style.display = .stack
        return style
    }
}

extension ElementGroup where LayerBase == Self {
    /// Every conformer but `ModifiedContent`: the first wrapper modifier wraps.
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Self> {
        ModifiedElement(content: self, layer: layer)
    }
}

extension ElementGroup {
    /// Applies a SwiftUI-style outer frame without overwriting the content's
    /// own declared size. Passing `nil` leaves that axis unconstrained.
    ///
    /// Adds one layer to a `ModifiedElement` (ruling MC-A). **The lowering
    /// lives in `FrameLayer.swift`** — `FrameSpec.style()`, ruling FR-C — which
    /// is where every later change to the legacy frame's meaning goes, along
    /// with the flexible `frame(minWidth:…)` overload. This file is shared with
    /// a parallel track, so the declaration stays here, in place (frame-sizing
    /// critic finding 14); `alignment:` was added to it in place rather than
    /// declared as a second overload, because two applicable fixed `frame`
    /// overloads make a long chain exponential for the solver (ruling FR-S).
    public func frame(width: Pixels? = nil, height: Pixels? = nil,
                      alignment: ProposalAlignment = .center) -> ModifiedElement<LayerBase> {
        let spec = FrameSpec(width: width, height: height, alignment: alignment)
        return _wrap(ModifierLayer(style: spec.style(), frameSpec: spec))
    }
}
