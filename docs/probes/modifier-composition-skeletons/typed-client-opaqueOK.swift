import Kit
struct OpaqueComp: Component { var content: some ProposalElementGroup { Pair(Leaf(), Leaf()) } }
extension OpaqueComp: ProposalElementGroup {}
struct Both: ProposalElement {
    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) { (pass.requestNativeLeaf(), ()) }
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) { (pass.requestNode(children: []), ()) }
}
@MainActor func use() { _ = ProposalFrame(OpaqueComp()); _ = ProposalFrame(Both()) }
