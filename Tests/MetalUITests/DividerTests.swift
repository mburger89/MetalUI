import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUITestSupport
@testable import MetalUI

// Platform services, lane 3 — `Divider()` as a view (ruling `SV-O`; spec §6.3
// tests 4.1–4.10, 4.G12). SwiftUI's answers are the probe's `V` arms
// (`docs/probes/swiftui-platform-services.swift`): a `Divider` is 1 point
// across the nearest `HStack`'s/`VStack`'s cross axis and its proposal along
// the other (`V1`–`V11`), horizontal outside any stack and in a `ZStack`
// (`V3`, `V4`), and publishes no accessibility node (`V15`). Its colour is the
// theme's `.separator` (divergence 127; SwiftUI's is black/white at α 0.098,
// `V12`). Red before: `Divider` is a `MenuContent` only at `be806c5`, so
// every test here fails by not compiling.
//
// Every rect is read from the scene by its colour: the fixtures paint nothing
// else in `.separator`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// The scene rects painted in the window theme's `.separator`, as
/// `[x, y, width, height]` in device pixels.
@MainActor private func separatorRects(_ window: Window) -> [[Float]] {
    let separator = window.theme[.separator]
    return window.lastScene.rects.filter { ixSame(ixHsla($0.background), separator) }.map {
        [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height]
    }
}

/// The sizes (`[width, height]`) of the `.separator` rects in a 300 × 300
/// window over `content`, after one frame.
@MainActor private func dividerSizes<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> [[Float]] {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 300, content: content)
    window.drawFrameIfNeeded()
    return separatorRects(window).map { [$0[2], $0[3]] }
}

/// A fixed-size swatch that paints in `.accent`, never `.separator`.
@MainActor private func swatch(_ w: Float, _ h: Float) -> some ProposalElement {
    Color(.accent).frame(width: px(w), height: px(h))
}

// MARK: - 4.1–4.3: the stack axes

/// **4.1** (`V1`). In a `VStack` proposed 120 wide the `Divider` spans the
/// width, 1 point tall. Mutation: swap the axes (an `HStack` pushes
/// `.vertical`, a `VStack` `.horizontal`).
@MainActor
@Test func aDividerInAVStackSpansItsWidthOnePointTall() throws {
    let sizes = try dividerSizes { VStack { swatch(20, 20); Divider() }.frame(width: px(120)) }
    #expect(sizes == [[120, 1]], "\(sizes)")
}

/// **4.2** (`V2`). In an `HStack` proposed 40 tall it spans the height, 1
/// point wide. (4.1's site.)
@MainActor
@Test func aDividerInAnHStackSpansItsHeightOnePointWide() throws {
    let sizes = try dividerSizes { HStack { swatch(20, 20); Divider() }.frame(height: px(40)) }
    #expect(sizes == [[1, 40]], "\(sizes)")
}

/// **4.3** (`V3`, `V4`). Outside any stack — the window's root, proposed the
/// window's 300 — it is horizontal; inside a `ZStack` it is horizontal even
/// when the `ZStack` sits in an `HStack`, because a `ZStack` is no stack.
/// Mutation: `ZStack` pushes nothing (it inherits the outer `HStack`'s axis).
@MainActor
@Test func aDividerOutsideAnyStackOrInAZStackIsHorizontal() throws {
    let root = try dividerSizes { Divider() }
    #expect(root == [[300, 1]], "the root: \(root)")
    let inZ = try dividerSizes {
        HStack { ZStack { Divider() }.frame(width: px(120)) }.frame(height: px(40))
    }
    #expect(inZ == [[120, 1]], "in a ZStack in an HStack: \(inZ)")
}

// MARK: - 4.4: the nearest stack decides

/// **4.4** (`V5`, `V6`, `V8`, `V9`, `V11`'s transparency through an
/// environment scope — MetalUI has no `Group`). The nearest stack decides
/// (`V5`: a `VStack` in an `HStack` → horizontal; `V6`: the reverse →
/// vertical); a `.frame` (`V8`), `.padding` (`V9`) and an environment scope
/// between are transparent; a stack that has finished its children no longer
/// decides for a later sibling. Mutation: drop the pop's `defer` (the
/// axis pushed by the first stack stays on top).
@MainActor
@Test func theNearestStackDecidesAndWrappersAreTransparent() throws {
    let v5 = try dividerSizes { HStack { VStack { Divider() }.frame(width: px(50)) }.frame(height: px(40)) }
    #expect(v5 == [[50, 1]], "V5: \(v5)")
    let v6 = try dividerSizes { VStack { HStack { Divider() }.frame(height: px(30)) }.frame(width: px(80)) }
    #expect(v6 == [[1, 30]], "V6: \(v6)")
    let v8 = try dividerSizes { HStack { Divider().frame(height: px(20)) }.frame(height: px(40)) }
    #expect(v8 == [[1, 20]], "V8: \(v8)")
    let v9 = try dividerSizes { HStack { Divider().padding(px(5)) }.frame(height: px(40)) }
    #expect(v9 == [[1, 30]], "V9: \(v9)")
    let scoped = try dividerSizes {
        HStack { Divider().environment(\.colorScheme, .light) }.frame(height: px(40))
    }
    #expect(scoped == [[1, 40]], "an environment scope: \(scoped)")
    let after = try dividerSizes {
        VStack { HStack { swatch(10, 10) }; Divider() }.frame(width: px(80))
    }
    #expect(after == [[80, 1]], "after a finished HStack sibling: \(after)")
}

// MARK: - 4.5–4.6: legacy stacks, no proposal

/// **4.5**. In a legacy `Row` the `Divider` is vertical (1 wide), in a
/// `Column` horizontal (1 tall) — each spanning the container's fixed cross
/// size. Mutation: `Row` pushes nothing.
@MainActor
@Test func aDividerInARowIsVerticalAndInAColumnHorizontal() throws {
    let row = try dividerSizes { Row { Divider() }.frame(width: px(100), height: px(40)) }
    #expect(row == [[1, 40]], "Row: \(row)")
    let column = try dividerSizes { Column { Divider() }.frame(width: px(100), height: px(40)) }
    #expect(column == [[100, 1]], "Column: \(column)")
}

/// **4.6** (`V3`, `V7`'s nil arm). With no proposal along its length — under
/// `.fixedSize()` — a `Divider` is 10 long. Mutation: `proposal ?? 0`.
@MainActor
@Test func anUnconstrainedDividerIsTenLong() throws {
    let sizes = try dividerSizes { Divider().fixedSize() }
    #expect(sizes == [[10, 1]], "\(sizes)")
}

// MARK: - 4.7–4.9: colour, accessibility, menus

/// **4.7** (`SV-O` item 4, divergence 127). The line is one rect of the
/// window theme's `.separator` in light and in dark, and 1 point is 2 device
/// pixels at scale 2. Mutation: paint `.textSecondary`.
@MainActor
@Test func aDividerPaintsTheSeparatorTokenOnePointThick() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for appearance in [Appearance.light, .dark] {
        let (window, platform) = try makeFakeWindow(device: device, size: 300, appearance: appearance) {
            VStack { swatch(20, 20); Divider() }.frame(width: px(120))
        }
        window.drawFrameIfNeeded()
        let expected = appearance == .light ? Theme.light.separator : Theme.dark.separator
        #expect(ixSame(window.theme[.separator], expected), "\(appearance): the window's variant")
        let rects = separatorRects(window)
        #expect(rects.count == 1 && rects.first?[3] == 1, "\(appearance): one 1-px line at scale 1: \(rects)")
        platform.simulateBackingScaleChange(to: 2)
        window.drawFrameIfNeeded()
        let scaled = separatorRects(window)
        #expect(scaled.count == 1 && scaled.first?[2] == 240 && scaled.first?[3] == 2,
                "\(appearance): 2 device px at scale 2: \(scaled)")
        withExtendedLifetime(window) {}
    }
}

/// **4.8** (`V15`). A `Divider` publishes no accessibility node: the
/// published tree of a stack holding one has exactly the nodes of the same
/// stack without it. Mutation: emit a node (a `.separator`-roled record).
@MainActor
@Test func aDividerPublishesNoAccessibilityNode() throws {
    func nodes(withDivider: Bool) throws -> Int {
        let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 300) {
            VStack {
                Text("Above")
                if withDivider { Divider() }
                Text("Below")
            }
        }
        platform.simulateAccessibilityRequest(.activate)
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        let tree = try #require(platform.publishedAccessibilityTrees.last)
        return tree.nodes.count
    }
    let without = try nodes(withDivider: false)
    try #require(without > 0, "set up: the texts publish")
    #expect(try nodes(withDivider: true) == without)
}

/// **4.9** (`MN-H` item 3, unchanged). Inside a menu builder `Divider` is
/// still a separator item. (Existing behaviour, pinned now that the type is
/// also an `Element`.)
@MainActor
@Test func aDividerInAMenuIsStillASeparator() throws {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 300) {
        Column {
            Box().frame(width: px(300), height: px(300)).background(.surface).contextMenu {
                Button("Copy") {}
                Divider()
                Button("Paste") {}
            }
        }
    }
    platform.presentsMenusNatively = true
    window.drawFrameIfNeeded()
    platform.simulateInput(.rightMouseDown(MouseEvent(position: Point(x: px(150), y: px(150)))))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: Point(x: px(150), y: px(150)))))
    let menu = try #require(platform.presentedMenus.last?.menu)
    #expect(menu.items.map(\.kind) == [.action, .separator, .action])
    withExtendedLifetime(window) {}
}

// MARK: - 4.10: no leak

/// **4.10**. The axis does not leak past its stack: a root-level `VStack`'s
/// `Divider` after an `HStack` sibling is horizontal, and one inside a
/// `Button` label inside a `Row` is vertical (the button's own box pushes
/// nothing). Mutation: push without popping.
@MainActor
@Test func theAxisDoesNotLeakPastItsStack() throws {
    let sibling = try dividerSizes {
        VStack {
            HStack { swatch(10, 10); swatch(10, 10) }
            Divider()
        }.frame(width: px(90))
    }
    #expect(sibling == [[90, 1]], "after an HStack: \(sibling)")
    let inButton = try dividerSizes {
        Row { Button(action: {}) { Divider() } }.frame(width: px(200), height: px(40))
    }
    #expect(inButton.count == 1 && inButton.first?[0] == 1, "a Button label in a Row: vertical: \(inButton)")
}

// MARK: - 4.G12: both vocabularies (guard)

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **4.G12** (`SV-O` item 1). From a plain `import MetalUI`, `Divider()` is
/// an element in a legacy `Row`, in an `HStack` and a menu item in a `Menu`
/// — one type, both builders. Positive; its fixture was mutated red once
/// (record §77, lane 3's table).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aDividerIsBothAMenuItemAndAnElement() throws {
    let source = """
        @MainActor func row() -> some Element { Row { Divider() } }
        @MainActor func stack() -> some Element { HStack { Divider() } }
        @MainActor func menu() -> some Element { Menu("m") { Button("a") {}; Divider() } }
        """
    let result = try typecheckFile(source, importing: "MetalUI")
    print("DIVIDER GUARD 4.G12: succeeded=\(result.succeeded)\n\(result.messages)")
    #expect(result.succeeded, "\(result.output)")
}
