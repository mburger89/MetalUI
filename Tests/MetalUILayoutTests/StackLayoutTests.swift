import Testing
import MetalUICore
@testable import MetalUILayout

/// `Display.stack` exists and is inert until Task 2 gives it a reader.
///
/// This test is deliberately weak and is deleted in Task 2 — its only job is to
/// prove the enum gained a case without disturbing the flex path, so that a
/// golden moving in Task 2 is unambiguously Task 2's doing.
@Test func displayStackIsDeclaredAndNotYetRead() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: .length(.pixels(Pixels(40))),
                    height: .length(.pixels(Pixels(20))))
    let child = tree.newNode(style: kid, children: [])

    var s = Style()
    s.display = .stack           // set, and read by nothing yet
    s.flexDirection = .row
    let node = tree.newNode(style: s, children: [child])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(50)))
    // Still laid out as a flex row, because nothing reads `.stack` yet.
    #expect(tree.layout(child).width == 40)
    #expect(tree.layout(child).height == 20)
}

/// `justifyItems` defaults to `nil` and is read by nothing yet.
@Test func justifyItemsDefaultsToNil() {
    #expect(Style().justifyItems == nil)
}
