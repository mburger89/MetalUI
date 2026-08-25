import Testing
import MetalUICore
@testable import MetalUILayout

@Test func defaultStyleMatchesCSSInitialValues() {
    let s = Style()
    #expect(s.display == .flex)
    #expect(s.position == .relative)
    #expect(s.flexDirection == .row)
    #expect(s.flexWrap == .noWrap)
    #expect(s.flexGrow == 0)
    #expect(s.flexShrink == 1)
    #expect(s.flexBasis == .auto)
    #expect(s.size == Size(width: Dimension.auto, height: Dimension.auto))
    #expect(s.alignItems == nil)     // nil means "stretch" at use site
    #expect(s.alignSelf == nil)      // nil means "inherit alignItems"
}

@Test func flexDirectionKnowsItsAxis() {
    #expect(FlexDirection.row.isRow)
    #expect(FlexDirection.rowReverse.isRow)
    #expect(!FlexDirection.column.isRow)
    #expect(!FlexDirection.columnReverse.isRow)
    #expect(!FlexDirection.row.isReverse)
    #expect(FlexDirection.rowReverse.isReverse)
    #expect(FlexDirection.columnReverse.isReverse)
}

@Test func styleIsValueSemantic() {
    var a = Style()
    var b = a
    b.flexGrow = 5
    #expect(a.flexGrow == 0)
    #expect(b.flexGrow == 5)
    a.flexGrow = 9
    #expect(b.flexGrow == 5)
}
