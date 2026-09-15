import Kit
struct LegacyComp: Component { var content: Legacy { Legacy() } }
extension LegacyComp: ProposalElementGroup {}
