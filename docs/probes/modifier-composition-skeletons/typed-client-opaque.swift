import Kit
struct OpaqueComp: Component { var content: some ElementGroup { Pair(Leaf(), Leaf()) } }
extension OpaqueComp: ProposalElementGroup {}
