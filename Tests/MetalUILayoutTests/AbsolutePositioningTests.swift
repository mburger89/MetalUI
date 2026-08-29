import Testing
import MetalUICore
@testable import MetalUILayout

/// `.static` is the default, and is not yet read by anything.
///
/// Deliberately weak and deleted in Task 2 — its only job is to prove the enum
/// gained a case and the default moved without disturbing the flex path.
@Test func positionDefaultsToStaticAndIsNotYetRead() {
    #expect(Style().position == .static)

    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: .length(.pixels(Pixels(40))),
                    height: .length(.pixels(Pixels(20))))
    kid.position = .absolute          // set, read by nothing yet
    let child = tree.newNode(style: kid, children: [])

    var row = Style()
    row.flexDirection = .row
    let node = tree.newNode(style: row, children: [child])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    // Still laid out in flow, because nothing reads `.absolute` yet.
    #expect(tree.layout(child).width == 40)
    #expect(tree.layout(child).x == 0)
}

/// `.relative` survives as the opt-in: it is how a caller becomes a containing
/// block without positioning itself. A two-case enum could not express that.
@Test func relativeIsStillDistinctFromStatic() {
    #expect(Position.relative != Position.static)
    #expect(Position.absolute != Position.static)
}
