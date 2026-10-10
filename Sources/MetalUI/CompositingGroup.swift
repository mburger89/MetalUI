import MetalUICore
import MetalUILayout
import MetalUIPrimitives

// C13 / PERF-a, lane 2 — `compositingGroup()` (ruling `PF-E`). Spec
// `docs/superpowers/specs/2026-10-09-shadow-cache-design.md` §5; SwiftUI's side
// is `docs/probes/swiftui-shadow-cache.swift`, arms P1, P2 and CG1–CG7.

// MARK: - The proposal vocabulary (one `LayoutModifier` layer, `PF-E`)

extension ProposalElementGroup {
    /// Composites this view's leaves into one before an enclosing shadow or
    /// blur sees them — SwiftUI's `compositingGroup()`. `.shadow` and `.blur`
    /// work **per leaf** (probe P1); written outside this modifier they see
    /// the group as **one** leaf instead: one shadow of the union silhouette
    /// drawn below the whole group (P2), one blur of the composite (CG2).
    /// Alone, or with no shadow or blur outside it, it changes nothing (CG4).
    /// **Render only**: no layout change (CG3), no hit region, nothing
    /// published, nothing animates. An enclosing opacity still multiplies each
    /// primitive (divergence 205: SwiftUI composites it, CG1). A `Deferred`
    /// inside is not part of the group (its content is never shadowed or
    /// blurred from outside). One layer, one identity level (`MC-C`).
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
    /// Paint inside a composite scope (`PF-E`): pushed **only** when a shadow
    /// or blur scope is open outside it above the last `Deferred` barrier —
    /// otherwise `body` paints directly (CG4) and nothing is counted. While
    /// open, every leaf that reaches it (after the scopes inside it) is
    /// collected with the clip depth it was emitted at; when it closes, the
    /// collected primitives, in order, go through the scopes outside it as one
    /// leaf (`insertThroughScopes(leaf:depths:)`).
    func paintWithCompositingGroup(_ body: () -> Void) {
        guard compositeHasAReader else { return body() }
        compositeScopesPushed += 1
        let scope = PaintScope(kind: .composite, effect: .identity, entryClipDepth: clipDepth)
        paintScopes.append(scope)
        body()
        paintScopes.removeLast()
        if !scope.captures.isEmpty { insertThroughScopes(leaf: scope.captures, depths: scope.captureDepths) }
    }

    /// Whether a shadow or blur scope is open outside, nearer than the last
    /// `Deferred` barrier: the only scopes that see a leaf's extent (`PF-E`
    /// item 2, CG4). An effect, a transition or a capture maps or keeps each
    /// primitive alike, collected or not.
    private var compositeHasAReader: Bool {
        for scope in paintScopes.reversed() {
            switch scope.kind {
            case .barrier: return false
            case .shadow, .blur: return true
            case .transition, .effect, .capture, .composite: continue
            }
        }
        return false
    }
}
