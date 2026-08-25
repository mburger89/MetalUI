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

    // Box model. CSS initial values: margin/padding/border are 0 on every edge,
    // inset is `auto`, min-width/height are `auto` and max-width/height are
    // `none` — which `Dimension` spells `.auto`, having no `none` case.
    #expect(s.inset == Edges<Dimension>(all: .auto))
    #expect(s.margin == Edges<Dimension>(all: .length(.pixels(Pixels(0)))))
    #expect(s.padding == Edges<Length>(all: .pixels(Pixels(0))))
    #expect(s.border == Edges<Length>(all: .pixels(Pixels(0))))
    #expect(s.minSize == Size(width: Dimension.auto, height: Dimension.auto))
    #expect(s.maxSize == Size(width: Dimension.auto, height: Dimension.auto))
    #expect(s.aspectRatio == nil)

    // Container and overflow.
    #expect(s.gap == Axes<Length>(both: .pixels(Pixels(0))))
    #expect(s.overflow == Axes<Overflow>(both: .visible))
    #expect(s.justifyContent == nil)  // nil means "flex-start" at use site
    #expect(s.alignContent == nil)    // nil means "stretch" at use site
}

/// `Style.default` is a stored static, so it can drift from `Style()` the moment
/// anyone gives it a hand-written body. Nothing else in the suite would notice.
@Test func defaultStaticIsExactlyTheMemberwiseDefault() {
    #expect(Style.default == Style())
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
