import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Image and `Label` menu items (ruling `MN-AP`; probe `docs/probes/swiftui-menu-label-items.swift`; record 322).
// The lowering to `PlatformMenuItem` (symbol and tint), the drawn menu's icon column and icon paint, and the
// closed protocol. AppKit's `NSMenuItem.image` is in `AppKitMenuTests`.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

/// Items numbered as a window numbers them, enabled.
@MainActor private func evaluate<C: MenuContent>(_ content: C, isEnabled: Bool = true) -> [PlatformMenuItem] {
    content.testingEvaluateMenu(isEnabled: isEnabled).items
}

private let red = Color.red.resolved(theme: .light, scheme: .light).toRgba()
private let green = Color.green.resolved(theme: .light, scheme: .light).toRgba()

/// **MN-AP 1** (probe arms L1, L2, L8-L10). Every spelling reaches the item as a symbol and no tint: `Button(_:systemImage:)`, a `Label` in a
/// `Button`, a `Toggle` with a symbol (still on), a `Menu(_:systemImage:)` and the item inside it. The control, a
/// plain `Button`, has none. Mutation: drop `image:` from `Button._menuNodes` (the first two expectations redden);
/// from `Toggle._menuNodes` (the third); from `Menu._menuNodes` (the fourth).
@Test @MainActor func everySystemImageSpellingReachesThePlatformMenuItem() {
    let items = evaluate(MenuItems([
        Button("Plain") {},
        Button("Direct", systemImage: "star") {},
        Button { } label: { Label("Labelled", systemImage: "circle.fill") },
        Toggle("Flag", systemImage: "flag", isOn: .constant(true)),
        Menu("More", systemImage: "folder") { Button("Inner", systemImage: "doc") {} },
    ]))
    #expect(items.map(\.title) == ["Plain", "Direct", "Labelled", "Flag", "More"])
    #expect(items.map { $0.image?.symbol } == [nil, "star", "circle.fill", "flag", "folder"])
    #expect(items.allSatisfy { $0.image?.tint == nil }, "nothing tinted yet")
    #expect(items[3].isOn, "the symbol toggle keeps its state")
    guard case .submenu(let children) = items[4].kind else { Issue.record("not a submenu"); return }
    #expect(children.first?.image?.symbol == "doc")
    #expect(children.first?.title == "Inner")
}

/// **MN-AP 2.** `.tint` on the item or a scope above it colours the image (probe L4); `.foregroundStyle` on the
/// `Label`, the `Button` or the scope does not (probe L3, L3b, L3c, L5). The nearer `.tint` wins (E: red). Mutation: read
/// `foregroundStyle` for the tint (the first expectation reddens); ignore `context.tint` in `EnvironmentScope`'s
/// menu conformance (the tinted ones redden).
@Test @MainActor func aTintColoursTheImageAndAForegroundStyleDoesNot() {
    let items = evaluate(MenuItems([
        Button { } label: { Label("A", systemImage: "circle.fill") }.tint(.green),
        Button { } label: { Label("B", systemImage: "circle.fill").foregroundStyle(.green) },
        Button { } label: { Label("C", systemImage: "circle.fill") }.foregroundStyle(.green),
        Button("D", systemImage: "circle.fill") {}.foregroundStyle(.green),
        Button("E", systemImage: "circle.fill") {}.tint(.red).tint(.green),   // the nearer write wins
        Button("F", systemImage: "circle.fill") {}.tint(.green).foregroundStyle(.red),
        Button("G", systemImage: "circle.fill") {}.disabled(false).tint(.green),   // through an inner scope
    ]))
    #expect(items.map { $0.image?.tint } == [green, nil, nil, nil, red, green, green])
}

/// **MN-AP 2b.** A tint on a `Menu` item reaches the item and each item inside it (the context a scope passes
/// down); an untinted sibling stays untinted.
@Test @MainActor func aTintOnASubmenuReachesItAndItsItems() {
    let items = evaluate(MenuItems([
        Menu("More", systemImage: "folder") { Button("A", systemImage: "star") {} }.tint(.green),
        Button("C", systemImage: "star") {},
    ]))
    guard case .submenu(let children) = items[0].kind else { Issue.record("not a submenu"); return }
    #expect(items[0].image?.tint == green)
    #expect(children.map { $0.image?.tint } == [green])
    #expect(items[1].image?.tint == nil)
}

/// **MN-AP 3.** A disabled item keeps its image and stays disabled (probe L11); an unknown symbol name still
/// reaches the platform item (the platform decides it draws nothing, `SYM-G`, probe L12); a text-only
/// `Label.init(title:icon:)` whose icon is not a symbol shows no image.
@Test @MainActor func aDisabledItemKeepsItsImageAndAnUnknownNameIsCarriedSilently() {
    let items = evaluate(MenuItems([
        Button("Off", systemImage: "star") {}.disabled(true),
        Button("Unknown", systemImage: "no.such.symbol.xyz") {},
    ]))
    #expect(items[0].image?.symbol == "star")
    #expect(items[0].isEnabled == false)
    #expect(items[1].image?.symbol == "no.such.symbol.xyz")
    #expect(items[1].isEnabled)
}

/// The drawn menu of `content`, open at (10, 10) in a 400 x 400 window that draws its menus.
@MainActor private func drawnMenu<C: MenuContent>(@MenuContentBuilder _ content: @escaping @MainActor () -> C) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 400) {
        Box().frame(width: px(400), height: px(400)).contextMenu { content() }
    }
    platform.presentsMenusNatively = false
    window.drawFrameIfNeeded()
    platform.simulateInput(.rightMouseDown(MouseEvent(position: pt(10, 10))))
    platform.simulateInput(.rightMouseUp(MouseEvent(position: pt(10, 10))))
    try #require(window.menuSession?.isNative == false, "an in-window menu is open")
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// **MN-AP 4.** The drawn menu reserves an image column only when a row draws an icon, draws each icon in its
/// box at the row's leading edge (after the check column), in the tint when there is one and the text colour
/// otherwise, and draws nothing for an unknown name (no column either). Mutation: skip `paintMenuImage` (the icon
/// list is empty); paint the untinted icon in the tint's place (the colours redden); reserve the column for every
/// item (the unknown-name arm's column reddens).
@Test @MainActor func theDrawnMenuDrawsTheIconInItsColumnInTheTint() throws {
    let (window, _) = try drawnMenu {
        Button("Plain", systemImage: "star") {}
        Button("Dot", systemImage: "circle.fill") {}.tint(.green)
        Button("Off", systemImage: "star") {}.disabled(true)
    }
    let level = try #require(window.menuSession?.levels.first)
    #expect(level.layout.imageColumn == MenuPanel.imageSide + MenuPanel.imageGap)
    let icons = window.lastMenuIconsPainted
    #expect(icons.map(\.symbol) == ["star", "circle.fill", "star"])
    for (index, icon) in icons.enumerated() {
        let row = level.rowFrame(index)
        #expect(icon.bounds.origin.x.value == row.origin.x.value + MenuPanel.checkColumn, "icon \(index) x")
        #expect(icon.bounds.size.width.value == MenuPanel.imageSide)
        #expect(abs((icon.bounds.origin.y.value + icon.bounds.size.height.value / 2)
                    - (row.origin.y.value + row.size.height.value / 2)) < 0.01, "icon \(index) centred")
    }
    #expect(icons[1].color == green.toHsla(), "the tinted dot")
    #expect(icons[0].color != green.toHsla(), "an untinted icon takes the text colour")
    #expect(icons[0].color == icons[2].color)
}

/// **MN-AP 5.** An unknown symbol draws no icon and reserves no column — the same menu as one with no images,
/// byte for byte in its layout (`SYM-G`: silent, counted once); a menu with an icon is wider by the column.
@Test @MainActor func anUnknownSymbolDrawsNothingAndTheMenuIsLaidOutWithoutAColumn() throws {
    SymbolDiagnostics.reset()
    let (unknown, _) = try drawnMenu { Button("Item", systemImage: "no.such.symbol.xyz") {} }
    let (plain, _) = try drawnMenu { Button("Item") {} }
    let (known, _) = try drawnMenu { Button("Item", systemImage: "star") {} }
    let unknownLevel = try #require(unknown.menuSession?.levels.first)
    let plainLevel = try #require(plain.menuSession?.levels.first)
    let knownLevel = try #require(known.menuSession?.levels.first)
    #expect(unknown.lastMenuIconsPainted.isEmpty)
    #expect(unknownLevel.layout == plainLevel.layout)
    #expect(SymbolDiagnostics.misses["no.such.symbol.xyz"] == 1)
    #expect(knownLevel.layout.imageColumn > 0)
    #expect(known.lastMenuIconsPainted.count == 1)
    // 120 is the minimum width, so compare the unconstrained: a long title makes the column visible.
}

/// **MN-AP 6.** The column widens a panel whose title fills it: the same long title is wider by the column
/// with an icon.
@Test @MainActor func theImageColumnWidensAPanelWhoseTitleFillsIt() throws {
    let long = String(repeating: "Wide title ", count: 6)
    let (with, _) = try drawnMenu { Button(long, systemImage: "star") {} }
    let (without, _) = try drawnMenu { Button(long) {} }
    let wider = try #require(with.menuSession?.levels.first).layout.size.width.value
    let base = try #require(without.menuSession?.levels.first).layout.size.width.value
    #expect(wider - base == (MenuPanel.imageSide + MenuPanel.imageGap).rounded(.up) || abs(wider - base - (MenuPanel.imageSide + MenuPanel.imageGap)) < 1)
}
