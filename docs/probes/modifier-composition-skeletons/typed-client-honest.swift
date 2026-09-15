import Kit
struct MyLeaf: ProposalElement {
    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) { (pass.requestNativeLeaf(), ()) }
}
struct MyComp: Component { var content: Pair<Leaf, MyLeaf> { Pair(Leaf(), MyLeaf()) } }
extension MyComp: ProposalElementGroup {}
@MainActor func use() { _ = ProposalFrame(Pair(MyComp(), MyLeaf())); _ = ProposalFrame(ProposalFrame(Leaf())) }
