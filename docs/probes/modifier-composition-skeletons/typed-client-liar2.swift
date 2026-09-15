import Kit
struct Liar: ProposalElement {
    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (ProposalNodeID(pass.requestNode(children: [])), ())
    }
}
