import Kit
struct MyLeaf: ProposalElement {
    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) { (pass.requestNativeLeaf(), ()) }
}
struct MyComp: Component { var content: some ProposalElementGroup { Pair(Leaf(), MyLeaf()) } }
extension MyComp: ProposalElementGroup {}
@MainActor func use() {
    let a: ModifiedElement<Legacy> = Legacy().padding(1).padding(2)
    let b: ModifiedElement<MyComp> = MyComp().padding(1).padding(2)
    let c: ModifiedElement<ProposalFrame<MyLeaf>> = ProposalFrame(MyLeaf()).padding(3)
    _ = (a, b, c, ProposalFrame(Pair(MyComp(), MyLeaf())))
}
