import Kit
struct Liar: ProposalElementGroup {
    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([LayoutNodeID], Void) { ([pass.requestNode(children: [])], ()) }
    mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int, pass: inout LayoutPass) -> ([ProposalNodeID], Void) { ([], ()) }
}
@MainActor func use() { _ = ProposalFrame(Liar()) }
