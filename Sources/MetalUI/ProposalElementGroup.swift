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

extension HStack: ProposalElementGroup {}
extension VStack: ProposalElementGroup {}
extension ZStack: ProposalElementGroup {}
extension ProposalFrame: ProposalElementGroup {}
extension Padding: ProposalElementGroup {}
extension Background: ProposalElementGroup {}
extension FixedSize: ProposalElementGroup {}
extension Spacer: ProposalElementGroup {}
extension Rectangle: ProposalElementGroup {}
extension Color: ProposalElementGroup {}
extension ModifiedContent: ProposalElementGroup {}
extension OnTapModifier: ProposalElementGroup {}
extension OverlayModifier: ProposalElementGroup {}
