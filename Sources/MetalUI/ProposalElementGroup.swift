/// Marks an element subtree whose layout is entirely owned by MetalUI's
/// proposal/measurement/placement engine.
///
/// The marker is the migration boundary between the new SwiftUI-style surface
/// and CSS-derived elements. It lets an overload such as `.frame(...)` select
/// proposal-layout semantics at compile time instead of asking a runtime
/// wrapper to guess which layout engine owns its child.
public protocol ProposalElementGroup: ElementGroup {}

extension EmptyGroup: ProposalElementGroup {}
extension Pair: ProposalElementGroup where First: ProposalElementGroup, Second: ProposalElementGroup {}
extension OptionalGroup: ProposalElementGroup where Wrapped: ProposalElementGroup {}
extension ArrayGroup: ProposalElementGroup where Group: ProposalElementGroup {}

extension HStack: ProposalElementGroup where Content: ProposalElementGroup {}
extension VStack: ProposalElementGroup where Content: ProposalElementGroup {}
extension ZStack: ProposalElementGroup where Content: ProposalElementGroup {}
extension Spacer: ProposalElementGroup {}
extension Rectangle: ProposalElementGroup {}
extension Color: ProposalElementGroup {}
extension ModifiedContent: ProposalElementGroup where Content: ProposalElementGroup {}
extension OnTapModifier: ProposalElementGroup where Content: ProposalElementGroup {}
extension NativeOverlayModifier: ProposalElementGroup
    where Content: ProposalElementGroup, Overlay: ProposalElementGroup {}
