import MetalUICore
import MetalUILayout
import MetalUIPrimitives

// C13 / PERF-a, lane 2 — `compositingGroup()` (ruling `PF-E`). Spec
// `docs/superpowers/specs/2026-10-09-shadow-cache-design.md` §5; SwiftUI's side
// is `docs/probes/swiftui-shadow-cache.swift`, arms P1, P2 and CG1–CG7.

// MARK: - The proposal vocabulary (one `LayoutModifier` layer, `PF-E`)

extension ProposalElementGroup {
    /// Composites this view's leaves into one before an enclosing shadow, blur or
    /// opacity sees them — SwiftUI's `compositingGroup()`. `.shadow` and `.blur`
    /// work **per leaf** (probe P1); written outside this modifier they see
    /// the group as **one** leaf instead: one shadow of the union silhouette
    /// drawn below the whole group (P2), one blur of the composite (CG2). An
    /// `.opacity` written outside it fades the **composited** group, so an overlap
    /// of two leaves reads the top colour over the backdrop, not one leaf through
    /// the other (CG1, `GO0`): the group renders into an offscreen target and is
    /// drawn back at that opacity (`GO-A`). Alone, or with no shadow, blur or
    /// opacity below 1 outside it, it changes nothing (CG4). **Render only**: no
    /// layout change (CG3), no hit region, nothing published, nothing animates.
    /// Not composited (divergence 221): a shadow or blur written outside an
    /// opacity group still sees its leaves faded one by one; (divergence 222): a
    /// group holding a material or glass fades its primitives one by one and keeps
    /// the live backdrop. A `Deferred` inside is not part of the group (its content
    /// is never shadowed, blurred or faded from outside). One layer, one identity
    /// level (`MC-C`).
    public func compositingGroup() -> ModifiedContent<ProposalBase, LayoutModifier> {
        _wrapLayout(.compositingGroup)
    }
}

// MARK: - The legacy vocabulary (`Decoration.renderEffects`, `PF-E`)

extension StyledElement {
    /// Composites this element's leaves into one before an enclosing shadow or
    /// blur sees them — SwiftUI's `compositingGroup()`, returning `Self` (no
    /// identity level). It joins the element's render effects in written order
    /// and, like them, wraps the whole element: its background, content and
    /// border (divergence 108), so `.compositingGroup().shadow(…)` casts one
    /// shadow and `.shadow(…).compositingGroup()` casts one per leaf. See the
    /// proposal spelling for the rules.
    public func compositingGroup() -> Self {
        appendingRenderEffect(.compositingGroup)
    }
}

// MARK: - The paint scope

extension PaintPass {
    /// Runs `body` inside a composite scope (`PF-E`).
    func withCompositingGroup(_ body: () -> Void) {
        frame.paintWithCompositingGroup(body)
    }
}

extension Frame {
    /// Paint inside a composite scope (`PF-E`, `GO-A`): pushed **only** when a shadow or blur scope is open outside it
    /// above the last `Deferred` barrier, or when an opacity below 1 is in force on it (the entry opacity times the alpha
    /// of every transition, fade and effect scope outside it) — otherwise `body` paints directly (CG4) and nothing is
    /// counted. While open, every leaf that reaches it (after the scopes inside it) is collected with the clip depth it
    /// was emitted at; when it closes, the collected primitives, in order, go through the scopes outside it as one leaf
    /// (`insertThroughScopes(leaf:depths:)`). An opacity group paints its content **unfaded** (`withOpacityBase`) and
    /// marks each leaf with the entry opacity as it leaves, so `insertLeaves` renders it as one offscreen group; a group
    /// that holds a backdrop is not marked and fades per primitive (divergence 222).
    func paintWithCompositingGroup(_ body: () -> Void) {
        let readers = compositeReaders
        let groupsOpacity = readers.opacity > 0 && readers.opacity < 1
        guard readers.leafEffect || groupsOpacity else { return body() }
        compositeScopesPushed += 1
        let scope = PaintScope(kind: .composite, effect: .identity, entryClipDepth: clipDepth)
        scope.leafEffect = readers.leafEffect
        scope.groupsOpacity = groupsOpacity
        scope.entryOpacity = activeOpacity
        paintScopes.append(scope)
        if groupsOpacity { withOpacityBase(body) } else { body() }
        paintScopes.removeLast()
        guard !scope.captures.isEmpty else { return }
        var captures = scope.captures
        if groupsOpacity {
            if captures.contains(where: { if case .backdrop = $0.kind { true } else { false } }) {
                // A material or glass keeps its live backdrop (divergence 222): the opacity multiplies each primitive.
                for i in captures.indices { captures[i].multiplyAlpha(scope.entryOpacity) }
            } else {
                let mark = GroupMark(token: GroupToken(), alpha: scope.entryOpacity)
                for i in captures.indices { captures[i].groups.insert(mark, at: 0) }
            }
        }
        insertThroughScopes(leaf: captures, depths: scope.captureDepths)
    }

    /// What reads a composite from outside, nearer than the last `Deferred` barrier (`PF-E` item 2, CG4, `GO-A`):
    /// whether a shadow or blur scope is open (the scopes that see a leaf's extent), and the opacity in force on the group
    /// — the active opacity times the alpha of every transition, fade and effect scope outside it, each of which
    /// multiplies the group's mark as the leaf passes. A capture maps or keeps each primitive alike, collected or not.
    private var compositeReaders: (leafEffect: Bool, opacity: Float) {
        var leafEffect = false
        var opacity = activeOpacity
        for scope in paintScopes.reversed() {
            if scope.suspended { continue }
            switch scope.kind {
            case .barrier: return (leafEffect, opacity)
            case .shadow, .blur: leafEffect = true
            case .transition, .fade, .effect: opacity *= scope.effect.alpha
            case .capture, .composite: continue
            }
        }
        return (leafEffect, opacity)
    }
}
