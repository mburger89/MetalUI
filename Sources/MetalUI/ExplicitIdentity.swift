import MetalUICore
import MetalUILayout

/// What an `IdentifiedGroup` carries between phases: its content's layout.
public struct IdentifiedGroupLayout<ContentLayout> {
    var content: ContentLayout
}

/// A group named among its siblings: `.id(_:)` on any `ElementGroup` (plan task
/// 8, ruling `ID-G`).
///
/// **One cursor index, named.** It consumes one index of its parent's cursor and
/// takes the component `.named(name)` there — a name replaces a position, as
/// `PathComponent`'s rule has it — then numbers its content from 0 under that id
/// with a fresh cursor, and contributes the content's nodes unchanged: it is
/// **layout-transparent** (no node of its own) and has an identity level of its
/// own, like `GridRow`. So changing the name re-seeds everything under it
/// (SwiftUI's `.id(_:)`: probe `swiftui-composition-identity.swift` X4–X6), and a
/// named item in a `for` loop keeps its state through a reorder (`ForEach`'s
/// rule), on proposal content as on legacy.
///
/// **A `StyledElement` keeps its own `id(_:) -> Self`** (`Box.swift`), which is
/// more specific and wins: `Box().id("x")` and a legacy chain's `.id` still
/// NAME the element (replacing its position) rather than wrapping it, so their
/// paths are unchanged. The two spellings differ by one level for a path built
/// by hand — the wrapper adds a level, the element's own `.id` replaces one
/// (`ID-G`'s cost). Pinned by guard `anIDOnAStyledElementStillReturnsItsOwnType`.
///
/// **Two entries, one slot** (the `OverlayModifier` shape): the untyped
/// `requestGroupLayout` — a legacy parent — and the typed
/// `requestProposalGroupLayout` — a proposal parent, only when the content is
/// proposal content. Only the content-registration line is written twice; the
/// slot (`slot(under:at:)`) is shared, so a mutation of it reaches both entries.
/// Pinned by `ExplicitIdentityTests` (E3.1 runs both a `Row` and a `VStack`
/// parent).
///
/// Two siblings with the same name share one identity (divergence 72, `ID-H`,
/// pinned on this API by `twoSiblingGroupsWithTheSameIDShareOneIdentity`).
/// A frame that goes back to a name it used before finds that name's entries
/// still in the table until the sweep reaps them — the same as an element's own
/// `.id`.
public struct IdentifiedGroup<Content: ElementGroup>: ElementGroup {
    public var content: Content
    public var name: ElementID

    public init(content: Content, name: ElementID) {
        self.content = content
        self.name = name
    }

    /// The id this group's content numbers under: one index of the parent's
    /// cursor, named. Advances the cursor by exactly one.
    func slot(under parent: GlobalElementID?, at cursor: inout Int) -> GlobalElementID {
        let id = GlobalElementID.child(of: parent, at: cursor, name: name)
        cursor += 1
        return id
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], IdentifiedGroupLayout<Content.GroupLayout>) {
        let id = slot(under: parent, at: &cursor)
        var inner = 0
        let (nodes, layout) = content.requestGroupLayout(under: id, at: &inner, pass: &pass)
        return (nodes, IdentifiedGroupLayout(content: layout))
    }

    public mutating func prepaintGroup(layout: inout IdentifiedGroupLayout<Content.GroupLayout>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paintGroup(layout: inout IdentifiedGroupLayout<Content.GroupLayout>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// A named proposal group is proposal content, so it enters an `HStack`, a
/// `Grid` or a `GridRow` (guard `anIDOnAProposalGroupEntersAProposalContainer`).
/// **The typed entry is a copy of the untyped one's content line**, sharing
/// `slot(under:at:)`; E3.1's `VStack` arm and E3.2, E3.6, E3.7 reach it.
extension IdentifiedGroup: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], IdentifiedGroupLayout<Content.GroupLayout>) {
        let id = slot(under: parent, at: &cursor)
        var inner = 0
        let (nodes, layout) = content.requestProposalGroupLayout(under: id, at: &inner, pass: &pass)
        return (nodes, IdentifiedGroupLayout(content: layout))
    }
}

extension ElementGroup {
    /// Names this group among its siblings: one index, named; its content
    /// numbers from 0 under it (ruling `ID-G`). Changing the name starts
    /// everything inside over, as SwiftUI's `.id(_:)` does.
    ///
    /// A `StyledElement` (`Box`, `Text`, a legacy modifier chain) keeps its own
    /// `id(_:) -> Self`, which names the element itself instead of wrapping it.
    public func id(_ name: String) -> IdentifiedGroup<Self> {
        IdentifiedGroup(content: self, name: ElementID(name))
    }
}
