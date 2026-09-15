import Kit
// A marker conformer that registers a legacy node: today's Liar shape.
struct Liar: Element {
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) { (pass.requestNode(children: []), ()) }
}
extension Liar: ProposalElementGroup {}
