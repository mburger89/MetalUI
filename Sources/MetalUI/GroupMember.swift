import MetalUICore
import MetalUILayout

extension GlobalElementID {
    /// **The one place a group member's identity is entered** (ruling MC-H):
    /// `child(of:at:name:)`, then `StateBinder.bind`, then `cursor += 1`, in that
    /// order, returning the id.
    ///
    /// Called by `Element`'s untyped default `requestGroupLayout`
    /// (`ElementGroup.swift`), `ProposalElement`'s typed default and `Component`'s
    /// typed default (`ProposalNodeID.swift`). **One copy remains outside it:
    /// `Component`'s untyped default (`Component.swift`)**, whose bind and cursor
    /// advance are pinned by `aComponentsOwnStateSurvivesAcrossFrames` and
    /// `twoSiblingComponentsHoldIndependentState` — a change here must be made
    /// there too. `AnyElement`'s default is a second, older divergence and does
    /// not bind at all (its own doc).
    ///
    /// **Why a helper and not three copies.** A copy survives a change that
    /// alters behaviour without altering a signature, which is how `AnyElement`'s
    /// lost its bind and then its cursor advance. A mistake here breaks legacy and
    /// proposal `@State` together, loudly.
    ///
    /// Bounded by four mutations, each reddening
    /// `stateSurvivesFramesUnderAProposalModifierChain`
    /// (`ModifierCompositionProofTests.swift`): deleting the bind (`a` reads 0
    /// during layout and `c` reads 0; the legacy `@State` tests redden too),
    /// `ProposalElement`'s typed default bypassing this helper (`a` reads 0
    /// during layout), `Component`'s bypassing it (`c` reads 0), and deleting
    /// `cursor += 1` (`b` reads 2, on `c`'s id). **An element's bind here is
    /// visible only to a layout-time read**: `Element.prepaintGroup`/`paintGroup`
    /// re-bind before `prepaint`/`paint`, and the test saw the second mutation
    /// only once it read during layout (ruling MC-H, record §10).
    @MainActor
    static func enteringGroupMember<E>(_ element: E, name: ElementID?,
                                       under parent: GlobalElementID?,
                                       at cursor: inout Int,
                                       pass: inout LayoutPass) -> GlobalElementID {
        let id = GlobalElementID.child(of: parent, at: cursor, name: name)
        StateBinder.bind(element, in: pass.frame, id: id)
        cursor += 1
        return id
    }
}
