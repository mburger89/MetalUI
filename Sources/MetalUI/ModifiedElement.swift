import MetalUICore
import MetalUILayout

// The legacy path's outer modifiers, `.padding(_:)` and every `.frame(...)` spelling,
// as ONE flat wrapper type (lane 2 of
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
// **What it keeps, exactly.** Each layer is what one `Box` around one child
// carried — a `Style`, a `Decoration`, `Handlers` and an `ElementID?` — and
// contributes one node, one identity level, one `$anim` slot, one hitbox
// registration and one background fill, in the order nested `Box`es produce
// them. The oracle is hand-built nested `Box`es, compared observation by
// observation with a disagreeing oracle each (ruling MC-B):
// `aModifierChainIsIdenticalToHandBuiltNestedBoxes`
// (`ModifierCompositionProofTests.swift`) and
// `aGenericWrapOverAChainIsIdenticalToTheFlatChain`
// (`ModifiedElementTests.swift`).
//
// **What the oracle does NOT compare** is anything `Element`'s group defaults
// (`requestGroupLayout`/`prepaintGroup`/`paintGroup`) do per ELEMENT: a nested
// `Box` gets them at every level, a layer gets them once for the whole chain.
// On this branch those defaults only enter the id and bind/re-bind `@State`,
// and a layer holds no `@State`, so nothing is lost. **Any hook added to those
// defaults must be mirrored per layer here** (ruling MC-B's "does NOT cover";
// the spec's merge notes name the accessibility track's `display: none`
// suppression, AB-O). `prepaint` is written as one call per layer, covering the
// layer's registration AND everything inside it, so such a hook can wrap it.

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

    init(style: Style) {
        self.style = style
        self.decoration = Decoration()
        self.handlers = Handlers()
        self.elementID = nil
    }
}

/// One flat wrapper for the legacy path's outer modifiers, `.padding` and
/// `.frame` (ruling MC-A).
///
/// **Layers.** `L[n-1]` is the outermost (the one `StyledElement`'s accessors
/// read and write, so a `Self`-returning modifier written after a wrapper
/// configures that wrapper, as it configured `Box<Self>`), `L[0]` the innermost.
///
/// **Identity (ruling MC-C)** — exactly the path nested `Box`es produce:
/// `L[n-1]` takes the id its parent's cursor gives the whole element (named by
/// `elementID`, the outermost layer's); `L[k]` is
/// `.child(of: id(L[k+1]), at: 0, name: L[k].elementID)`; the content numbers
/// from 0 under `L[0]`. So `.id(_:)` names the layer it follows, a layer's
/// VALUES are not part of its identity, and a change in the layer COUNT moves
/// the content one level and resets its state
/// (`addingALayerAtRunTimeResetsTheWrappedElementsState`,
/// `changingALayersValueKeepsTheWrappedElementsState`). A layer added at run
/// time is adopted by the new outermost layer, which keeps the old outermost
/// id and its `$anim` baseline — a candidate divergence with no SwiftUI
/// analogue (`aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`).
///
/// **Storage (ruling MC-K).** The outermost layer inline and the rest in an
/// array, innermost first; the `Layout` likewise. An empty array owns no
/// buffer, so a one-layer chain pays no array; a k-layer chain pays array
/// buffers nested boxes did not (MC-K records the measured counts).
///
/// **A hole (ruling MC-A).** `ElementGroup._wrap(_:)` is a requirement, so a
/// conformer can declare `LayerBase` and forward `_wrap` to another value; its
/// `.padding` then silently drops the receiver. No access-control spelling
/// closes it.
public struct ModifiedElement<Content: ElementGroup>: Element, StyledElement {
    public typealias LayerBase = Content

    public var content: Content
    /// The layer the element's `StyledElement` accessors read and write.
    var outermost: ModifierLayer
    /// Every other layer, innermost first. Empty for a one-layer chain, and an
    /// empty array owns no buffer (ruling MC-K).
    var inner: [ModifierLayer]

    init(content: Content, layer: ModifierLayer) {
        self.content = content
        self.outermost = layer
        self.inner = []
    }

    /// How many layers the chain holds.
    var layerCount: Int { inner.count + 1 }

    public var style: Style {
        get { outermost.style }
        set { outermost.style = newValue }
    }

    public var decoration: Decoration {
        get { outermost.decoration }
        set { outermost.decoration = newValue }
    }

    public var handlers: Handlers {
        get { outermost.handlers }
        set { outermost.handlers = newValue }
    }

    public var elementID: ElementID? {
        get { outermost.elementID }
        set { outermost.elementID = newValue }
    }

    /// Adds `layer` outside every existing one; the old outermost layer moves
    /// in, keeping its values and its name. This is the `_wrap` witness that
    /// makes a chain APPEND rather than nest — through the requirement, so a
    /// `.padding` in generic code over a chain appends too
    /// (`aGenericWrapOverAChainIsIdenticalToTheFlatChain`).
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Content> {
        var copy = self
        copy.inner.append(copy.outermost)
        copy.outermost = layer
        return copy
    }

    /// One inner layer's identity and node, carried from layout to the later
    /// phases.
    struct LayerPlacement {
        var id: GlobalElementID
        var node: LayoutNodeID
    }

    public struct Layout {
        /// The outermost layer's node.
        var node: LayoutNodeID
        /// Every inner layer's id and node, innermost first; empty for one layer.
        var inner: [LayerPlacement]
        var content: Content.GroupLayout
    }

    /// The order nested `Box`es produce, node minting included: identities
    /// entered from the outside in, the content laid out under the innermost
    /// layer, then each layer — innermost first — substituted through
    /// `animated(_:_:for:pass:)` under its own id and registered around the
    /// node inside it.
    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var innermostID = id
        for k in inner.indices.reversed() {
            innermostID = GlobalElementID.child(of: innermostID, at: 0, name: inner[k].elementID)
        }

        // The content's own index space starts at 0 under the innermost layer,
        // as it does under a `Box`.
        var cursor = 0
        let (contentNodes, contentLayout) = content.requestGroupLayout(under: innermostID,
                                                                       at: &cursor, pass: &pass)
        var children = contentNodes
        var placements: [LayerPlacement] = []
        if !inner.isEmpty {
            placements.reserveCapacity(inner.count)
            var layerID = innermostID
            for k in inner.indices {
                // Layer k+1's id is layer k's parent, by the construction above.
                if k > 0, let parent = layerID.parent { layerID = parent }
                (inner[k].style, inner[k].decoration) = animated(inner[k].style, inner[k].decoration,
                                                                 for: layerID, pass: &pass)
                let node = pass.requestNode(style: inner[k].style, children: children)
                placements.append(LayerPlacement(id: layerID, node: node))
                children = [node]
            }
        }
        (outermost.style, outermost.decoration) = animated(outermost.style, outermost.decoration,
                                                           for: id, pass: &pass)
        let node = pass.requestNode(style: outermost.style, children: children)
        return (node, Layout(node: node, inner: placements, content: contentLayout))
    }

    /// Outermost layer first, then each layer inside it, then the content once:
    /// a nested handler registers later and so ranks above its container, as
    /// in `Box.prepaint`.
    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        prepaintLayer(inner.count, id: id, bounds: bounds, layout: &layout, pass: &pass)
    }

    /// Registers layer `depth` (`inner.count` is the outermost, 0 the
    /// innermost) and then prepaints everything inside it, by recursion.
    ///
    /// **One call covers a layer's registration AND everything inside it**, so
    /// a hook that `Element.prepaintGroup` wraps around a whole element's
    /// prepaint can be wrapped around this call per layer (the merge notes'
    /// AB-O mirroring). Written as a loop, the layers' registrations would run
    /// before any of their contents and no such scope would exist.
    private mutating func prepaintLayer(_ depth: Int, id: GlobalElementID, bounds: Bounds<Pixels>,
                                        layout: inout Layout,
                                        pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // The outermost layer's `display: none` is `Element.prepaintGroup`'s
        // check; each inner layer mirrors it here, around its registration and
        // everything inside it (ruling AB-O, mirrored per layer at integration
        // as ruling MC-B requires). Deleting the wrap reddens
        // `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`.
        guard depth < inner.count else {
            return prepaintLayerBody(depth, id: id, bounds: bounds, layout: &layout, pass: &pass)
        }
        return pass.frame.suppressingAccessibilityIfHidden(layout.inner[depth].node) {
            prepaintLayerBody(depth, id: id, bounds: bounds, layout: &layout, pass: &pass)
        }
    }

    private mutating func prepaintLayerBody(_ depth: Int, id: GlobalElementID, bounds: Bounds<Pixels>,
                                            layout: inout Layout,
                                            pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let layer = depth == inner.count ? outermost : inner[depth]
        // Through `registerAndScope`, exactly as `Box.prepaint` is, so a layer
        // that declares `.clipped()` bounds the hitboxes inside it as well as
        // the pixels (plan task 5's lane 2, `DecorationScope.swift`).
        return pass.registerAndScope(layer.handlers, layer.decoration, at: bounds, for: id) {
            guard depth > 0 else {
                return content.prepaintGroup(layout: &layout.content, pass: &pass)
            }
            let next = layout.inner[depth - 1]
            return prepaintLayer(depth - 1, id: next.id, bounds: pass.bounds(of: next.node),
                                 layout: &layout, pass: &pass)
        }
    }

    /// Outermost layer first, then each layer inside it, then the content once
    /// — **nested, not looped** (plan task 5's lane 2).
    ///
    /// **This used to be a loop and could not stay one.** It emitted every
    /// layer's fill in sequence and then painted the content once, which is
    /// correct only while a `Decoration` is a set of leaf emissions. An opacity
    /// and a clip are **scopes**: they have to contain the layers inside them
    /// and the content, so the layers nest — outermost layer's
    /// `paintDecoration { next layer's paintDecoration { … { content } } }`, by
    /// the same recursion `prepaintLayer` above already used. `OM-V`'s border
    /// needs the same shape for a different reason: it is emitted AFTER the
    /// layer's content, so a two-layer chain draws inner-then-outer borders as
    /// the recursion unwinds.
    ///
    /// **Background emission order is unchanged**, which is what keeps the demo
    /// pixel-identical: outermost fill, then each inner fill from outermost in,
    /// then the content — exactly the sequence the loop produced.
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        paintLayer(inner.count, id: id, bounds: bounds, layout: &layout,
                   prepaint: &prepaint, pass: &pass)
    }

    /// Paints layer `depth` (`inner.count` is the outermost, 0 the innermost)
    /// and everything inside it, by the recursion `prepaintLayer` mirrors.
    private mutating func paintLayer(_ depth: Int, id: GlobalElementID, bounds: Bounds<Pixels>,
                                     layout: inout Layout,
                                     prepaint: inout Content.GroupPrepaint,
                                     pass: inout PaintPass) {
        let decoration = depth == inner.count ? outermost.decoration : inner[depth].decoration
        pass.paintDecoration(decoration, in: bounds, for: id) {
            guard depth > 0 else {
                content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
                return
            }
            let next = layout.inner[depth - 1]
            paintLayer(depth - 1, id: next.id, bounds: pass.bounds(of: next.node),
                       layout: &layout, prepaint: &prepaint, pass: &pass)
        }
    }
}

extension ElementGroup where LayerBase == Self {
    /// Every conformer but `ModifiedElement`: the first wrapper modifier wraps.
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
        _wrap(ModifierLayer(style: FrameSpec(width: width, height: height,
                                             alignment: alignment).style()))
    }
}
