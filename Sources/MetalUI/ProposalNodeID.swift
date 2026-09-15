import MetalUICore
import MetalUILayout

// The typed native node id: the compile-time half of ruling SA-R, delivered by
// plan task 3 (ruling MC-G in
// `docs/superpowers/2026-09-15-modifier-composition-decisions.md`).
//
// **What the type checks.** Only `MetalUI` can mint a `ProposalNodeID` — its
// initializer is `internal`, and every public native registrar on `LayoutPass`
// returns one and takes them as children — and `ProposalElementGroup` requires
// `requestProposalGroupLayout`, which returns them. So a proposal container can
// be handed only nodes a native registrar produced, and five lies that compiled
// before this file are compile errors (`ProposalNodeIDCompileGuards.swift`,
// guards 1–5):
//
// 1. an `Element` that declares the marker and registers a legacy node;
// 2. a `ProposalNodeID` minted from a legacy node outside `MetalUI`;
// 3. a `Component` taking the marker over legacy (or `some ElementGroup`) content;
// 4. a native registrar handed a legacy child;
// 5. a custom-layout container handed its content's untyped nodes.
//
// **What it does not check — seven holes, each pinned or cited (MC-G):**
//
// 1. a group writing both entry points, which can disagree (guard 6, pinned wrong
//    on purpose);
// 2. a legacy NODE registered on the side during a typed entry and discarded
//    (`anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected`, arm a);
// 3. `unsafeBitCast`, or `@testable` code calling the internal initializer — the
//    run-time traps of ruling SA-G stay the backstop
//    (`aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`);
// 4. one typed id used twice (`aNativeNodeRegisteredTwiceIsNotRejected`);
// 5. a legacy style modifier on a proposal `Component`, whose `StyledComponent`
//    is a plain `ElementGroup` (`aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`);
// 6. a legacy SUBTREE laid out on the side and discarded, which still binds
//    `@State` and moves `$anim` baselines (the same test as 2, arm b);
// 7. a typed id stored from an earlier frame, caught at run time by
//    `LayoutTree.slot`'s generation check
//    (`aTypedNodeIDStoredFromAnEarlierFrameTraps`).

/// A layout node registered by one of `LayoutPass`'s native registrars.
///
/// **It has no public initializer**, so code outside `MetalUI` holds one only if
/// a native registrar returned it — which is what lets `ProposalElementGroup`'s
/// requirement promise a proposal container native children (ruling MC-G). Read
/// `layoutNodeID` to ask a pass for the node's bounds.
///
/// It constrains who mints an id, not how often or when one is used: see holes 4
/// and 7 in this file's header.
public struct ProposalNodeID: Hashable, Sendable {
    /// The untyped node, for `bounds(of:)` and the other untyped pass queries.
    public let layoutNodeID: LayoutNodeID

    /// `internal`, deliberately: pinned by `aProposalNodeIDCannotBeMintedOutsideMetalUI`.
    init(_ layoutNodeID: LayoutNodeID) {
        self.layoutNodeID = layoutNodeID
    }
}

/// An `Element` whose layout is owned by the proposal engine.
///
/// A conformer writes `requestProposalLayout`, which returns the node a native
/// registrar produced, plus `prepaint` and `paint`. Both layout entry points come
/// from the defaults below: the untyped `requestLayout`, which `Frame` calls for a
/// root, and `requestProposalGroupLayout`, which every proposal container calls.
///
/// **A conformer that also writes its own `requestLayout` compiles**, and the two
/// can then disagree (ruling MC-G, hole 1). The untyped entry is reached only as
/// a root or under a legacy container, and a proposal node under a legacy
/// container already traps (ruling SA-G).
@MainActor
public protocol ProposalElement: Element, ProposalElementGroup {
    /// Restated from `Element`. It was required in the `TypedNodeKit.swift`
    /// skeleton, whose conformers failed with "does not conform to protocol
    /// 'Element'" without it (ruling MC-G). **It is not required in this module:**
    /// deleting it here built and passed the whole suite, and a plain-import
    /// external `ProposalElement` still typechecked (the lane 3 verifier's V-LS,
    /// at `dbc2bc9`). Why the two differ is unmeasured (the verifier's guess: real
    /// conformers name `LayoutState` in `prepaint`/`paint`). Kept as harmless; no
    /// case in this module that needs it has been measured.
    associatedtype LayoutState

    /// Registers this element's native nodes and returns its one outermost node.
    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, LayoutState)
}

extension ProposalElement {
    /// The untyped entry, for `Frame`'s root and legacy containers: the typed
    /// entry, unwrapped.
    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutState) {
        let (node, state) = requestProposalLayout(id, pass: &pass)
        return (node.layoutNodeID, state)
    }

    /// One element is one index, entered exactly as `Element`'s untyped default
    /// enters it — through the one shared helper (ruling MC-H), so binding
    /// `@State` and advancing the cursor cannot drift between the two engines.
    ///
    /// **The bind here serves LAYOUT-time reads only.** `Element.prepaintGroup`
    /// and `paintGroup` re-bind the element's `@State` before `prepaint` and
    /// `paint`, so bypassing the helper (a bare `.child` and `cursor += 1`) left
    /// every paint-time read and prepaint-registered handler working and the
    /// whole suite green (measured, ruling MC-H). Pinned since then by
    /// `stateSurvivesFramesUnderAProposalModifierChain`'s layout-time reading:
    /// the bypass reads `a` as 0 during layout.
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], SingleElementLayout<Self>) {
        let id = GlobalElementID.enteringGroupMember(self, name: elementID, under: parent,
                                                     at: &cursor, pass: &pass)
        let (node, state) = requestProposalLayout(id, pass: &pass)
        return ([node], SingleElementLayout(id: id, node: node.layoutNodeID, state: state))
    }
}

extension Component where Content: ProposalElementGroup {
    /// `Component`'s untyped default (`Component.swift`) on the typed entry: the
    /// component's own identity through the shared helper (ruling MC-H), `content`
    /// materialized once, and laid out under the component's id with a fresh
    /// cursor. Its nodes are returned unchanged — a component stays
    /// layout-transparent.
    ///
    /// **Only `where Content: ProposalElementGroup`**, so a component over legacy
    /// content, or over content spelled `some ElementGroup`, cannot take the
    /// marker (`aComponentOnlyTakesTheProposalMarkerWithProposalContent`).
    /// Pinned by `stateSurvivesFramesUnderAProposalModifierChain`: bypassing the
    /// helper here reads `c` as 0 in paint and during layout — a component has
    /// no prepaint re-bind, and its `content` is evaluated during layout.
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], ComponentLayout<Self>) {
        let id = GlobalElementID.enteringGroupMember(self, name: elementID, under: parent,
                                                     at: &cursor, pass: &pass)
        var materialized = content
        var innerCursor = 0
        let (nodes, contentLayout) =
            materialized.requestProposalGroupLayout(under: id, at: &innerCursor, pass: &pass)
        return (nodes, ComponentLayout(content: materialized, contentLayout: contentLayout))
    }
}
