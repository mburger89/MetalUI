import MetalUICore
import MetalUILayout

// ONE flat wrapper type for both modifier vocabularies (plan task 7, stage 11,
// ruling `LR-FV` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`;
// spec `docs/superpowers/specs/2026-09-25-engine-stage-11-design.md` §3).
//
// **What it unifies.** Until stage 11 there were two wrappers: the legacy
// path's `ModifiedElement<Content>` — `.padding(_:)` and every legacy `.frame`,
// flat since `MC-A`, a `StyledElement` — and the proposal path's
// `ModifiedContent<Content>`, one nested value per modifier, a
// `ProposalElement`. Both are now `ModifiedContent<Content, Modifier>`, the
// second parameter naming the chain's VOCABULARY (its layer type), not a
// single modifier: `ModifierLayer` for the legacy chain, `LayoutModifier` for
// the proposal chain. Both chains are flat whatever their length (plan task
// 3's "a representation that can nest without forcing callers to expose
// ever-growing types"), and `ModifiedElement<Content>` is a typealias.
//
// **Why the second parameter is a vocabulary** (`LR-FV`'s reasoning, the
// skeleton probe `docs/probes/stage-11-unified-modifier-skeleton/`): a
// one-parameter flat type would be `StyledElement` unconditionally and
// `ProposalElement` whenever its content is proposal content, and
// `.background(token)`, `.opacity`, `.border` and `.allowsHitTesting` are
// declared on both protocols with different results, so every proposal
// chain's decoration call would go ambiguous. With the vocabulary in the type,
// a legacy chain is never a `ProposalElementGroup` and a proposal chain never a
// `StyledElement`, so each spelling has one candidate.
//
// **What it keeps, exactly** — every existing id path, byte for byte (`LR-FV`
// item 3, spec §3.3):
//
// - a legacy chain runs `ModifiedElement`'s code (`MC-A`/`MC-C`), moved here:
//   each layer is what one `Box` around one child carried and contributes one
//   node, one identity level, one `$anim` slot, one hitbox registration and one
//   background fill, in the order nested `Box`es produce them;
// - a proposal layer's id is `.child(of: outer, at: 0, name: nil)`, which is
//   what entering a nested one-parameter `ModifiedContent` as a group member at
//   cursor 0 produced (`GlobalElementID.enteringGroupMember` with a `nil`
//   `elementID`);
// - proposal layers a legacy wrapper absorbed (`prefix`) sit innermost, where
//   `ModifiedElement<ModifiedContent<X>>` put its nested proposal chain.
//
// **The per-layer mirrors (`MC-B`, `LR-AA`)**: anything `Element`'s group
// defaults (`requestGroupLayout`/`prepaintGroup`/`paintGroup`) do per ELEMENT
// is done here per inner LAYER — the element bounds log, `display: none`
// accessibility suppression (`AB-O`), the hidden-node pointer-disable scope and
// paint skip (`LR-DH`). A nested proposal `ModifiedContent` got them from those
// defaults at every level; a flat proposal chain gets them from this recursion.
// **Any hook added to those defaults must be mirrored per layer here.** The
// one default not mirrored is the `@State` re-bind: a layer holds no `@State`.

/// A modifier chain's vocabulary: the layer type one `ModifiedContent` holds.
///
/// **Not for conformers.** Exactly two types conform — `ModifierLayer` (the
/// legacy wrappers, `.padding(_:)` and `.frame(...)` on a `StyledElement`) and
/// `LayoutModifier` (the proposal modifiers on a `ProposalElementGroup`). The
/// protocol is public only because it constrains `ModifiedContent`'s public
/// generic parameter, which makes its requirements public too. An external
/// conformer compiles and is **inert**: nothing public builds a
/// `ModifiedContent` over it (the memberwise initializer is internal and the
/// public `init(content:modifier:)` is constrained to `LayoutModifier`),
/// pinned by the plain-import guard
/// `anExternalModifierLayerKindCannotBuildAModifiedContent`. No access-control
/// spelling closes the conformance itself (spec §3.7).
@MainActor
public protocol ModifierLayerKind {
    /// The layer's own name among its siblings (`.id(_:)` on a legacy layer);
    /// always `nil` for a proposal layer, which has no `.id(_:)`.
    var _elementID: ElementID? { get set }

    /// Registers this layer's node(s) around `children` under `id` and returns
    /// the layer's one node. Mutating, because a legacy layer stores the
    /// animated style and decoration its later phases read.
    mutating func _requestLayout(_ id: GlobalElementID, children: [LayoutNodeID],
                                 pass: inout LayoutPass) -> LayoutNodeID

    /// Registers whatever this layer registers at `bounds` and runs `inside` —
    /// everything inside the layer — within whatever scope it opens.
    func _prepaint<R>(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PrepaintPass,
                      inside: () -> R) -> R

    /// Paints this layer at `bounds` around `inside`, everything inside it.
    func _paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PaintPass,
                inside: () -> Void)

    /// A legacy wrapper appended to a chain of this vocabulary: the proposal
    /// prefix and the legacy layers the new chain holds inside its new
    /// outermost layer (ruling `LR-FV` item 4). A legacy chain keeps its
    /// prefix and appends; a proposal chain moves every layer into the prefix.
    static func _legacyStack(_ outermost: Self, _ inner: [Self], _ prefix: [LayoutModifier])
        -> (prefix: [LayoutModifier], layers: [ModifierLayer])
}

/// One flat modifier chain over `Content`, in one vocabulary: `ModifierLayer`
/// (legacy wrappers) or `LayoutModifier` (proposal modifiers). SwiftUI's name
/// and generic arity; the second parameter is the chain's layer TYPE, so a
/// chain is one `ModifiedContent<Base, Vocabulary>` however long it grows
/// (ruling `LR-FV`).
///
/// **Layers.** `outermost` is the layer a legacy chain's `StyledElement`
/// accessors read and write (so a `Self`-returning modifier written after a
/// wrapper configures that wrapper) and a proposal chain's `modifier`; `inner`
/// holds every other layer of the vocabulary, innermost first; `prefix` holds
/// proposal layers a legacy wrapper absorbed, innermost of all (always empty on
/// a proposal chain, and on a legacy chain unless generic code wrapped a
/// proposal chain in a legacy `.frame`). Together they are one list, *prefix,
/// inner, outermost*, which every phase walks from the outside in.
///
/// **Identity (rulings MC-C, `LR-FV` item 3)** — exactly the path nested
/// `Box`es, or nested one-parameter `ModifiedContent`s, produced: the
/// outermost layer takes the id its parent's cursor gives the whole element
/// (named by the outermost layer's `elementID`); each layer inside is
/// `.child(of: id(next outer), at: 0, name: layer._elementID)`; the content
/// numbers from 0 under the innermost layer. So `.id(_:)` names the layer it
/// follows, a layer's VALUES are not part of its identity, and a change in the
/// layer COUNT moves the content one level and resets its state
/// (`addingALayerAtRunTimeResetsTheWrappedElementsState`,
/// `changingALayersValueKeepsTheWrappedElementsState`). A layer added at run
/// time is adopted by the new outermost layer, which keeps the old outermost
/// id and its `$anim` baseline
/// (`aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`).
///
/// **Storage (ruling MC-K).** The outermost layer inline and the rest in
/// arrays; an empty array owns no buffer, so a one-layer chain pays no array.
///
/// **A hole (rulings MC-A, `LR-FV`).** `ElementGroup._wrap(_:)` and
/// `ProposalElementGroup._wrapLayout(_:)` are requirements, so a conformer can
/// declare `LayerBase`/`ProposalBase` and forward them to another value; its
/// modifiers then silently drop the receiver. No access-control spelling
/// closes it.
public struct ModifiedContent<Content: ElementGroup, Modifier: ModifierLayerKind>: Element {
    public typealias LayerBase = Content

    /// The chain's base content — never another `ModifiedContent` of the same
    /// chain (spec §3.4: until stage 11 a proposal chain's `content` was the
    /// next-inner `ModifiedContent`).
    public var content: Content
    /// The layer the element's accessors read and write.
    var outermost: Modifier
    /// Every other layer of this vocabulary, innermost first. Empty for a
    /// one-layer chain, and an empty array owns no buffer (ruling MC-K).
    var inner: [Modifier]
    /// Proposal layers a legacy wrapper absorbed, innermost of all (`LR-FV`
    /// item 4). Empty on every chain but a legacy wrapper written, in generic
    /// code, over a proposal chain.
    var prefix: [LayoutModifier]

    init(content: Content, outermost: Modifier, inner: [Modifier] = [],
         prefix: [LayoutModifier] = []) {
        self.content = content
        self.outermost = outermost
        self.inner = inner
        self.prefix = prefix
    }

    /// How many layers the chain holds, the absorbed prefix included.
    var layerCount: Int { prefix.count + inner.count + 1 }

    /// The outermost layer's name: a legacy chain's `.id(_:)`, and always `nil`
    /// on a proposal chain. A legacy chain's settable `elementID` is
    /// `StyledElement`'s, in the extension below.
    public var elementID: ElementID? { outermost._elementID }

    /// Adds `layer` outside every existing one. On a legacy chain the old
    /// outermost layer moves in, keeping its values and its name — the `_wrap`
    /// witness that makes a chain APPEND rather than nest, through the
    /// requirement, so a `.padding` in generic code over a chain appends too
    /// (`aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`).
    /// On a proposal chain every layer moves into the new chain's `prefix`,
    /// innermost, where `ModifiedElement<ModifiedContent<X>>` put it
    /// (`aLegacyWrapperAfterAProposalChainAbsorbsItAsItsInnermostLayers`).
    public func _wrap(_ layer: ModifierLayer) -> ModifiedContent<Content, ModifierLayer> {
        let (prefix, layers) = Modifier._legacyStack(outermost, inner, prefix)
        return ModifiedContent<Content, ModifierLayer>(content: content, outermost: layer,
                                                       inner: layers, prefix: prefix)
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
        /// Every inner layer's id and node — the prefix's, then `inner`'s —
        /// innermost first; empty for one layer.
        var inner: [LayerPlacement]
        var content: Content.GroupLayout
    }

    /// The id the content numbers under: the outermost layer's `id`, then one
    /// `.child(at: 0)` level per inner layer, named by that layer.
    private func innermostID(_ id: GlobalElementID) -> GlobalElementID {
        var innermostID = id
        for k in inner.indices.reversed() {
            innermostID = GlobalElementID.child(of: innermostID, at: 0, name: inner[k]._elementID)
        }
        for _ in prefix.indices {
            innermostID = GlobalElementID.child(of: innermostID, at: 0, name: nil)
        }
        return innermostID
    }

    /// The untyped entry — `Frame`'s root and a legacy parent: the content is
    /// registered through `requestGroupLayout`, then `wrapLayers`.
    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let innermostID = innermostID(id)
        // The content's own index space starts at 0 under the innermost layer,
        // as it does under a `Box`.
        var cursor = 0
        let (contentNodes, contentLayout) = content.requestGroupLayout(under: innermostID,
                                                                       at: &cursor, pass: &pass)
        let (node, placements) = wrapLayers(contentNodes, id: id, innermostID: innermostID, pass: &pass)
        return (node, Layout(node: node, inner: placements, content: contentLayout))
    }

    /// The order nested `Box`es produce, node minting included: the content
    /// laid out under the innermost layer (by the caller), then each layer —
    /// innermost first — registered around the node inside it, through its
    /// vocabulary (`_requestLayout`: a legacy layer is lowered from its
    /// `animated(_:_:for:pass:)` style under its own id, a proposal layer
    /// registers its native wrapper). Shared by the untyped and the typed entry,
    /// so only the content-entry line is written twice (spec §3.2).
    mutating func wrapLayers(_ contentNodes: [LayoutNodeID], id: GlobalElementID,
                             innermostID: GlobalElementID,
                             pass: inout LayoutPass) -> (LayoutNodeID, [LayerPlacement]) {
        var children = contentNodes
        var placements: [LayerPlacement] = []
        let depth = prefix.count + inner.count
        guard depth > 0 else {
            return (outermost._requestLayout(id, children: children, pass: &pass), placements)
        }
        placements.reserveCapacity(depth)
        var layerID = innermostID
        for k in prefix.indices {
            // Layer d+1's id is layer d's parent, by `innermostID`'s construction.
            if k > 0, let parent = layerID.parent { layerID = parent }
            let node = prefix[k]._requestLayout(layerID, children: children, pass: &pass)
            placements.append(LayerPlacement(id: layerID, node: node))
            children = [node]
        }
        for k in inner.indices {
            if k > 0 || !prefix.isEmpty, let parent = layerID.parent { layerID = parent }
            let node = inner[k]._requestLayout(layerID, children: children, pass: &pass)
            placements.append(LayerPlacement(id: layerID, node: node))
            children = [node]
        }
        return (outermost._requestLayout(id, children: children, pass: &pass), placements)
    }

    /// Outermost layer first, then each layer inside it, then the content once:
    /// a nested handler registers later and so ranks above its container, as
    /// in `Box.prepaint`.
    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        prepaintLayer(prefix.count + inner.count, id: id, bounds: bounds, layout: &layout, pass: &pass)
    }

    /// Registers layer `depth` (`prefix.count + inner.count` is the outermost,
    /// 0 the innermost) and then prepaints everything inside it, by recursion.
    ///
    /// **One call covers a layer's registration AND everything inside it**, so
    /// a hook that `Element.prepaintGroup` wraps around a whole element's
    /// prepaint is wrapped around this call per layer (the merge notes'
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
        guard depth < prefix.count + inner.count else {
            return prepaintLayerBody(depth, id: id, bounds: bounds, layout: &layout, pass: &pass)
        }
        // Stage 6b (ruling `LR-DH` item 4): the pointer-disable scope for an inner
        // layer a lowered `hidden()` put in `Frame.hiddenNodes`, mirrored here as the
        // suppression is.
        let node = layout.inner[depth].node
        return pass.frame.suppressingAccessibilityIfHidden(node) {
            pass.frame.disablingHitTestingIfHidden(node) {
                prepaintLayerBody(depth, id: id, bounds: bounds, layout: &layout, pass: &pass)
            }
        }
    }

    private mutating func prepaintLayerBody(_ depth: Int, id: GlobalElementID, bounds: Bounds<Pixels>,
                                            layout: inout Layout,
                                            pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // Everything inside layer `depth`.
        func inside() -> Content.GroupPrepaint {
            guard depth > 0 else {
                return content.prepaintGroup(layout: &layout.content, pass: &pass)
            }
            let next = layout.inner[depth - 1]
            // The element bounds log, per inner layer — `Element.prepaintGroup`'s
            // recording mirrored here, as ruling MC-B requires of any hook in the
            // group defaults (plan task 7, ruling LR-D).
            pass.frame.recordElementBounds(next.id, pass.bounds(of: next.node))
            return prepaintLayer(depth - 1, id: next.id, bounds: pass.bounds(of: next.node),
                                 layout: &layout, pass: &pass)
        }
        // The layer's own work, by its vocabulary: a legacy layer through
        // `registerAndScope`, exactly as `Box.prepaint` is (so a layer that
        // declares `.clipped()` bounds the hitboxes inside it as well as the
        // pixels); a proposal layer opens its hit-testing or clip scope, or
        // none, and registers nothing.
        if depth < prefix.count {
            let layer = prefix[depth]
            return layer._prepaint(id, bounds: bounds, pass: pass, inside: inside)
        }
        let layer = depth == prefix.count + inner.count ? outermost : inner[depth - prefix.count]
        return layer._prepaint(id, bounds: bounds, pass: pass, inside: inside)
    }

    /// Outermost layer first, then each layer inside it, then the content once
    /// — **nested, not looped** (plan task 5's lane 2): an opacity and a clip
    /// are scopes that contain the layers inside them and the content, and
    /// `OM-V`'s border is emitted AFTER the layer's content, so a two-layer
    /// chain draws inner-then-outer borders as the recursion unwinds.
    ///
    /// **Background emission order** is outermost fill, then each inner fill
    /// from outermost in, then the content.
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        paintLayer(prefix.count + inner.count, id: id, bounds: bounds, layout: &layout,
                   prepaint: &prepaint, pass: &pass)
    }

    /// Paints layer `depth` and everything inside it, by the recursion
    /// `prepaintLayer` mirrors.
    private mutating func paintLayer(_ depth: Int, id: GlobalElementID, bounds: Bounds<Pixels>,
                                     layout: inout Layout,
                                     prepaint: inout Content.GroupPrepaint,
                                     pass: inout PaintPass) {
        // Stage 6b (ruling `LR-DH` item 4): an inner layer a lowered `hidden()` put
        // in `Frame.hiddenNodes` paints nothing, and nothing inside it paints —
        // `Element.paintGroup`'s skip mirrored per layer (the outermost layer's node
        // is the element's, which `paintGroup` checks before calling `paint`).
        let depthCount = prefix.count + inner.count
        if depth < depthCount, pass.frame.hiddenNodes.contains(layout.inner[depth].node) { return }
        func inside() {
            guard depth > 0 else {
                content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
                return
            }
            let next = layout.inner[depth - 1]
            paintLayer(depth - 1, id: next.id, bounds: pass.bounds(of: next.node),
                       layout: &layout, prepaint: &prepaint, pass: &pass)
        }
        if depth < prefix.count {
            let layer = prefix[depth]
            layer._paint(id, bounds: bounds, pass: pass, inside: inside)
            return
        }
        let layer = depth == depthCount ? outermost : inner[depth - prefix.count]
        layer._paint(id, bounds: bounds, pass: pass, inside: inside)
    }
}

/// `ModifiedElement<Content>` — the legacy vocabulary's chain (ruling
/// `LR-FV` item 1). **Undeprecated**: every `ModifiedElement<X>` annotation,
/// `extension ModifiedElement` and `ElementGroup._wrap`'s signature still
/// compile; its fate is plan task 15's, with the other spelling-only
/// decisions. `String(describing:)` of the type prints
/// `ModifiedContent<X, ModifierLayer>`.
public typealias ModifiedElement<Content: ElementGroup> = ModifiedContent<Content, ModifierLayer>

// MARK: - The legacy vocabulary

extension ModifiedContent where Modifier == ModifierLayer {
    init(content: Content, layer: ModifierLayer) {
        self.init(content: content, outermost: layer)
    }
}

extension ModifiedContent: StyledElement where Modifier == ModifierLayer {
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
}

extension ModifierLayer: ModifierLayerKind {
    public var _elementID: ElementID? {
        get { elementID }
        set { elementID = newValue }
    }

    /// `ModifiedElement.requestLayout`'s per-layer body, moved: `lowered` before
    /// `animated`, so the `$anim` baseline holds the style the layer registers
    /// with (ruling CN-N); then the layer lowers onto kernel nodes from its
    /// animated style, checked against `declared` (plan task 7, rulings LR-C,
    /// `LR-H`).
    public mutating func _requestLayout(_ id: GlobalElementID, children: [LayoutNodeID],
                                        pass: inout LayoutPass) -> LayoutNodeID {
        style = lowered(style, childCount: children.count)
        let declared = style
        (style, decoration) = animated(style, decoration, for: id, pass: &pass)
        return pass.lowerLegacyLayer(self, declared: declared, children: children)
    }

    /// Through `registerAndScope`, exactly as `Box.prepaint` is: the hitbox,
    /// focus, accessibility record and the disabled gate, and the clip scope.
    public func _prepaint<R>(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PrepaintPass,
                             inside: () -> R) -> R {
        pass.registerAndScope(handlers, decoration, at: bounds, for: id, content: inside)
    }

    /// Background before `inside`, border after it (`OM-V`), inside the opacity
    /// and clip scopes the decoration declares.
    public func _paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PaintPass,
                       inside: () -> Void) {
        pass.paintDecoration(decoration, in: bounds, for: id, content: inside)
    }

    public static func _legacyStack(_ outermost: ModifierLayer, _ inner: [ModifierLayer],
                                    _ prefix: [LayoutModifier])
        -> (prefix: [LayoutModifier], layers: [ModifierLayer]) {
        var layers = inner
        layers.append(outermost)
        return (prefix, layers)
    }
}

// MARK: - The proposal vocabulary

extension ModifiedContent where Modifier == LayoutModifier {
    /// The outermost proposal modifier.
    public var modifier: LayoutModifier {
        get { outermost }
        set { outermost = newValue }
    }
}

extension ModifiedContent where Content: ProposalElementGroup, Modifier == LayoutModifier {
    /// One proposal modifier over `content`. Over an existing chain this
    /// NESTS — `ModifiedContent<ModifiedContent<X, LayoutModifier>,
    /// LayoutModifier>` — with the same ids as the flat chain (spec §3.3); the
    /// modifier methods append instead, through `_wrapLayout`.
    public init(content: Content, modifier: LayoutModifier) {
        self.init(content: content, outermost: modifier)
    }
}

extension ModifiedContent: ProposalElementGroup, ProposalElement
    where Content: ProposalElementGroup, Modifier == LayoutModifier {
    /// A proposal modifier written after this chain appends a layer to it
    /// rather than nesting it (ruling `LR-FV` item 4, `MC-A`'s `LayerBase`
    /// mirrored).
    public typealias ProposalBase = Content

    public func _wrapLayout(_ modifier: LayoutModifier) -> ModifiedContent<Content, LayoutModifier> {
        var copy = self
        copy.inner.append(copy.outermost)
        copy.outermost = modifier
        return copy
    }

    /// The typed entry — a proposal parent: the content is registered through
    /// `requestProposalGroupLayout`, then the shared `wrapLayers`.
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let innermostID = innermostID(id)
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: innermostID,
                                                                           at: &cursor, pass: &pass)
        let (node, placements) = wrapLayers(children.map(\.layoutNodeID), id: id,
                                            innermostID: innermostID, pass: &pass)
        return (ProposalNodeID(node), Layout(node: node, inner: placements, content: contentLayout))
    }
}

extension LayoutModifier: ModifierLayerKind {
    /// A proposal layer has no `.id(_:)`: always `nil`, and a write is dropped.
    public var _elementID: ElementID? {
        get { nil }
        set {}
    }

    /// The native wrapper this modifier registers around its one child — or
    /// the child itself, for a paint-only modifier. No `$anim`, no record.
    public mutating func _requestLayout(_ id: GlobalElementID, children: [LayoutNodeID],
                                        pass: inout LayoutPass) -> LayoutNodeID {
        nativeWrapperNode(for: children.map(ProposalNodeID.init), pass: &pass).layoutNodeID
    }

    /// The hit-testing or clip scope, or none. **No** `registerHandlers`: a
    /// proposal layer registers no hitbox, focus or accessibility record.
    public func _prepaint<R>(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PrepaintPass,
                             inside: () -> R) -> R {
        switch self {
        case let .allowsHitTesting(enabled):
            var result: R?
            pass.allowsHitTesting(enabled) { result = inside() }
            return result!
        case let .clip(cornerRadius):
            var result: R?
            pass.clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0)),
                         cornerRadii: Corners(all: cornerRadius)) {
                result = inside()
            }
            return result!
        default:
            return inside()
        }
    }

    /// An opacity scope around `inside`; a fill before it; a clip around it; a
    /// border after it.
    public func _paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PaintPass,
                       inside: () -> Void) {
        switch self {
        case let .opacity(value):
            pass.opacity(value, inside)
        case let .background(token):
            pass.fill(bounds, color: pass.theme[token], cornerRadii: Corners(all: Pixels(0)))
            inside()
        case let .clip(cornerRadius):
            pass.clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0)),
                         cornerRadii: Corners(all: cornerRadius), inside)
        case let .border(token, width, cornerRadius):
            inside()
            pass.fill(bounds, color: .transparent, cornerRadii: Corners(all: cornerRadius),
                      borderColor: pass.theme[token], borderWidths: Edges(all: width))
        default:
            inside()
        }
    }

    public static func _legacyStack(_ outermost: LayoutModifier, _ inner: [LayoutModifier],
                                    _ prefix: [LayoutModifier])
        -> (prefix: [LayoutModifier], layers: [ModifierLayer]) {
        var absorbed = prefix
        absorbed.append(contentsOf: inner)
        absorbed.append(outermost)
        return (absorbed, [])
    }

    @MainActor
    private func nativeWrapperNode(for children: [ProposalNodeID], pass: inout LayoutPass) -> ProposalNodeID {
        precondition(children.count == 1,
                     "a native outer modifier must wrap exactly one native layout node")
        let child = children[0]
        switch self {
        case let .frame(width, height, alignment):
            return pass.requestNativeFrame(
                child: child,
                width: width.map { Double($0.value) }, height: height.map { Double($0.value) },
                alignment: alignment
            )
        case let .flexibleFrame(minWidth, idealWidth, maxWidth, minHeight, idealHeight, maxHeight, alignment):
            return pass.requestNativeFrame(
                child: child,
                minWidth: minWidth.map { Double($0.value) }, idealWidth: idealWidth.map { Double($0.value) },
                maxWidth: maxWidth.map { Double($0.value) },
                minHeight: minHeight.map { Double($0.value) }, idealHeight: idealHeight.map { Double($0.value) },
                maxHeight: maxHeight.map { Double($0.value) }, alignment: alignment
            )
        case let .padding(insets):
            return pass.requestNativePadding(
                child: child,
                insets: Edges(top: Double(insets.top.value), right: Double(insets.right.value),
                              bottom: Double(insets.bottom.value), left: Double(insets.left.value))
            )
        case let .fixedSize(horizontal, vertical):
            return pass.requestNativeFixedSize(child: child, horizontal: horizontal, vertical: vertical)
        case let .aspectRatio(ratio, contentMode):
            return pass.requestNativeAspectRatio(child: child, ratio: ratio, contentMode: contentMode)
        case let .layoutPriority(priority):
            return pass.requestNativeLayoutPriority(child: child, priority: priority)
        case .background, .clip, .border, .opacity, .allowsHitTesting:
            // A paint-only modifier has no independent layout footprint.
            // Returning the content node lets the layer observe its resolved
            // bounds during paint while preserving the layer's own identity level.
            return child
        }
    }
}
