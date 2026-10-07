import Testing
import Foundation
import Metal
import Observation
import MetalUICore
import MetalUIScene
import MetalUIPlatform
@testable import MetalUI

// Port gaps (medium), lane 2 — the toolbar, native: tests 3.1–3.5 (rulings
// `MD-I`, `MD-J`, `MD-S`, `MD-U` items 1–2; spec
// `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §4.3).
// SwiftUI's side: `docs/probes/swiftui-toolbar.swift` (`TB1`, `UP`, `SR`) and
// `docs/probes/swiftui-toolbar-nested.swift` (`NT1`, `NT2`, `IF0`/`IF1`, `PO`).
//
// A window over `FakePlatformWindow` with `toolbarIsNative = true` (the fake's
// default) stands for AppKit: the window hands the evaluated toolbar to
// `setToolbar(_:)` and the platform shows it; actions come back as queued
// `InputEvent.toolbarAction`s. Red before: the file does not compile at
// `34f68c3` (no `.toolbar`, `ToolbarItem`, `PlatformToolbar`).

private func px(_ v: Float) -> Pixels { Pixels(v) }

@Observable @MainActor private final class TBModel {
    var mode = 0
    var advanced = false
    var filter = ""
    var search = ""
    var showsToolbar = true
    var pressed = 0
}

/// One opaque 1 × 1 bitmap, shared, so its texture's identity is stable.
@MainActor private let shareBitmap = ImageBitmap(width: 1, height: 1, rgba: [0, 0, 0, 255])

@MainActor private func binding<V>(_ get: @escaping @MainActor () -> V,
                                   _ set: @escaping @MainActor (V) -> Void) -> Binding<V> {
    Binding(get: get, set: set)
}

/// Test 3.1's tree: one item per control kind and placement, then `.searchable`.
@MainActor private func fullTree(_ m: TBModel) -> some Element {
    Column {
        Text("Body")
            .toolbar {
                ToolbarItem(placement: .navigation) { Button("Nav") { m.pressed += 1 } }
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: binding({ m.mode }, { m.mode = $0 })) {
                        Text("A").tag(0)
                        Text("B").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(id: "share", placement: .primaryAction) {
                    Button(action: { m.pressed += 10 }) { Image(shareBitmap, scale: 1, label: Text("Share")) }
                }
                ToolbarItem { Toggle("Advanced", isOn: binding({ m.advanced }, { m.advanced = $0 })) }
                ToolbarItem { TextField("Filter", text: binding({ m.filter }, { m.filter = $0 })) }
                ToolbarItem(placement: .status) { Text("Ready") }
            }
            .searchable(text: binding({ m.search }, { m.search = $0 }))
    }
}

@MainActor private func expectedFull(advanced: Bool = false, mode: Int = 0, filter: String = "",
                                     search: String = "") -> PlatformToolbar {
    PlatformToolbar(items: [
        PlatformToolbarItem(id: "navigation.0", placement: .navigation, control: .button(title: "Nav", image: nil)),
        PlatformToolbarItem(id: "principal.1", placement: .principal,
                            control: .picker(title: "Mode", options: ["A", "B"], selected: mode, style: .segmented)),
        PlatformToolbarItem(id: "share", placement: .primaryAction,
                            control: .button(title: "Share", image: shareBitmap.texture)),
        PlatformToolbarItem(id: "automatic.3", placement: .automatic,
                            control: .toggle(title: "Advanced", isOn: advanced)),
        PlatformToolbarItem(id: "automatic.4", placement: .automatic,
                            control: .textField(placeholder: "Filter", text: filter)),
        PlatformToolbarItem(id: "status.5", placement: .status, control: .label(text: "Ready")),
        PlatformToolbarItem(id: "search", placement: .search, control: .search(prompt: "Search", text: search)),
    ])
}

@MainActor private func tbWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    try makeFakeWindowOnDefaultDevice(size: 300, content: content)
}

// MARK: - 3.1

/// **3.1** (`MD-I` items 2–4, 6; `MD-J` item 1). A `.toolbar` with one item per
/// control kind and placement, plus `.searchable`, reaches the platform as one
/// neutral `PlatformToolbar`: ids (given, else placement and merged index),
/// placements, controls with their current states, declaration order, the
/// search item last. Mutation **M3.1**: `.status` mapped to `.automatic`.
@MainActor
@Test func aToolbarReachesThePlatformAsOneNeutralDescription() throws {
    let m = TBModel()
    let (window, platform) = try tbWindow { fullTree(m) }
    window.drawFrameIfNeeded()
    let sent = try #require(platform.toolbars.last, "no setToolbar call")
    #expect(sent == expectedFull(), "\(String(describing: sent))")
    #expect(sent?.items.map(\.id) == ["navigation.0", "principal.1", "share", "automatic.3", "automatic.4",
                                      "status.5", "search"])
    #expect(sent?.items.map(\.placement) == [.navigation, .principal, .primaryAction, .automatic, .automatic,
                                             .status, .search])
}

// MARK: - 3.2

/// **3.2** (`MD-J` item 2, `MD-U` item 1). The window calls `setToolbar` only
/// when the evaluated toolbar differs from the last one sent: two unchanged
/// frames make one call (the image compares by identity, so it is not
/// re-sent); a binding written from outside makes one more, with the new
/// state; removing the `.toolbar` sends `nil` once. Mutation **M3.2**: sent
/// every frame.
@MainActor
@Test func theToolbarIsSentOnlyWhenItChanges() throws {
    let m = TBModel()
    let (window, platform) = try tbWindow {
        Column {
            if m.showsToolbar {
                fullTree(m)
            } else {
                Text("Body")
            }
        }
    }
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(platform.toolbars.count == 1, "two unchanged frames: one call, read \(platform.toolbars.count)")

    m.advanced = true
    window.drawFrameIfNeeded()
    #expect(platform.toolbars.count == 2, "a changed state: one more call, read \(platform.toolbars.count)")
    #expect(platform.toolbars.last == expectedFull(advanced: true))

    m.showsToolbar = false
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(platform.toolbars.count == 3, "the toolbar removed: one nil call, read \(platform.toolbars.count)")
    #expect(platform.toolbars.last == .some(nil), "the last call is setToolbar(nil)")
}

/// A window with no `.toolbar` never calls `setToolbar` (`MD-J` item 2: the
/// last sent toolbar starts as `nil`).
@MainActor
@Test func aWindowWithNoToolbarNeverCallsSetToolbar() throws {
    let (window, platform) = try tbWindow { Column { Text("Body") } }
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(platform.toolbars.isEmpty, "read \(platform.toolbars)")
}

// MARK: - 3.3

/// A component placed twice as one value — its `@State` box aliased (`ID-F`) —
/// whose toolbar button's title shows its own occurrence's count.
private struct Panel: Component {
    @State var count = 0
    var content: some ElementGroup {
        Text("panel").toolbar {
            ToolbarItem { Button("+\(count)") { count += 1 } }
        }
    }
    var elementID: ElementID? { nil }
}

/// **3.3** (`MD-J` item 4). A queued `.toolbarAction` runs its item under
/// `StateDispatch`: `.press` runs the button of the occurrence that declared it
/// (an aliased `@State` box writes that occurrence's slot, shown next frame);
/// `.toggle`, `.select` and `.text` write their bindings; an unknown id, or an
/// action of the wrong kind, changes nothing. Mutation **M3.3**: the action run
/// outside `StateDispatch` (the `@State` arm: the last-bound occurrence counts).
@MainActor
@Test func aToolbarActionRunsItsItemUnderStateDispatch() throws {
    let panel = Panel()
    let (window, platform) = try tbWindow { Column { panel; panel } }
    window.drawFrameIfNeeded()
    #expect(platform.toolbars.last??.items.map(\.id) == ["automatic.0", "automatic.1"])
    _ = platform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "automatic.0", action: .press)))
    window.drawFrameIfNeeded()
    let titles = platform.toolbars.last??.items.map(\.control)
    #expect(titles == [.button(title: "+1", image: nil), .button(title: "+0", image: nil)],
            "the first occurrence's count moves: \(String(describing: titles))")

    let m = TBModel()
    let (full, fullPlatform) = try tbWindow { fullTree(m) }
    full.drawFrameIfNeeded()
    _ = fullPlatform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "automatic.3", action: .toggle(true))))
    _ = fullPlatform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "principal.1", action: .select(1))))
    _ = fullPlatform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "automatic.4", action: .text("q"))))
    _ = fullPlatform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "search", action: .text("s"))))
    _ = fullPlatform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "navigation.0", action: .press)))
    #expect(m.advanced == true && m.mode == 1 && m.filter == "q" && m.search == "s" && m.pressed == 1,
            "advanced \(m.advanced) mode \(m.mode) filter \(m.filter) search \(m.search) pressed \(m.pressed)")
    full.drawFrameIfNeeded()
    #expect(fullPlatform.toolbars.last == expectedFull(advanced: true, mode: 1, filter: "q", search: "s"))

    let calls = fullPlatform.toolbars.count
    _ = fullPlatform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "nope", action: .press)))
    _ = fullPlatform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "automatic.3", action: .press)))
    _ = fullPlatform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "principal.1", action: .select(7))))
    full.drawFrameIfNeeded()
    #expect(m.advanced == true && m.mode == 1 && m.pressed == 1, "an unknown id or a wrong action runs nothing")
    #expect(fullPlatform.toolbars.count == calls, "nothing changed, nothing re-sent")
}

// MARK: - 3.4

/// **3.4** (`MD-I` item 5, `MD-S` item 2; probe arms `NT1`, `PO`). Toolbars
/// merge window-wide in build pre-order, an outer `.toolbar` before its
/// content's; one inside a presented popover and one inside a `Deferred`
/// presentation root are ignored; one under an `if false` contributes nothing
/// (`IF1`). Mutation **M3.4**: presentation contributions kept.
@MainActor
@Test func toolbarsMergeInTreeOrderAndIgnorePresentationRoots() throws {
    func item(_ id: String) -> some ToolbarContent { ToolbarItem(id: id) { Button(id) {} } }
    let hidden = false
    let (window, platform) = try tbWindow {
        Column {
            Column {
                Text("b").toolbar { item("B") }
                Text("c").toolbar { item("C") }
                if hidden { Text("h").toolbar { item("H") } }
            }
            .toolbar { item("A") }
            Text("anchor").popover(isPresented: .constant(true)) { Text("p").toolbar { item("P") } }
            Deferred { Box { Text("d").toolbar { item("D") } }.position(.absolute).inset(px(0)) }
            Text("e").toolbar { item("E") }
        }
    }
    window.drawFrameIfNeeded()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(platform.toolbars.last??.items.map(\.id) == ["A", "B", "C", "E"],
            "read \(String(describing: platform.toolbars.last??.items.map(\.id)))")
}

// MARK: - 3.5

/// **3.5** (`MD-I` item 1). A `ToolbarScope` is transparent: on both
/// vocabularies a tree records the same element ids and bounds with and
/// without `.toolbar`/`.searchable` on a child that has a following sibling.
/// Mutation **M3.5**: the scope consumes a cursor index (the sibling's id
/// shifts); **M3.5b** the same on the typed proposal entry.
@MainActor
@Test func aToolbarScopeIsTransparentToLayoutAndIdentity() throws {
    func bounds<E: Element>(_ element: E) -> [GlobalElementID: Bounds<Pixels>] {
        var root = element
        let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                          recordsElementBounds: true)
        frame.render(&root)
        return frame.elementBounds
    }
    let search = Binding.constant("")
    let legacyPlain = bounds(Column { Text("a"); Text("b"); Box().frame(width: px(20), height: px(20)) })
    let legacyScoped = bounds(Column {
        Text("a").toolbar { ToolbarItem { Button("x") {} } }.searchable(text: search)
        Text("b")
        Box().frame(width: px(20), height: px(20))
    })
    #expect(!legacyPlain.isEmpty)
    #expect(legacyPlain == legacyScoped, "legacy: ids and bounds moved")

    // The proposal arm's members carry a `.frame` layer each: a proposal leaf
    // records no element bounds, a layer's inner level does, so the sibling's
    // id is visible only through one (`MD-Y`; a bare `Text` sibling left M3.5b
    // green).
    let proposalPlain = bounds(Column {
        VStack(spacing: 0) {
            Rectangle().frame(width: px(10), height: px(10))
            Rectangle().frame(width: px(11), height: px(10))
        }
    })
    let proposalScoped = bounds(Column {
        VStack(spacing: 0) {
            Rectangle().frame(width: px(10), height: px(10))
                .toolbar { ToolbarItem { Button("x") {} } }.searchable(text: search)
            Rectangle().frame(width: px(11), height: px(10))
        }
    })
    #expect(proposalPlain.count >= 3, "the proposal arm must see its members' ids: \(proposalPlain.count)")
    #expect(proposalPlain == proposalScoped, "proposal: ids and bounds moved")
}

// MARK: - 3.6

/// **3.6** (`MD-J` item 1). `.disabled(true)` on a toolbar control, and on a
/// container holding a `.toolbar`, reaches the platform as `isEnabled == false`;
/// a queued `.toolbarAction` for a disabled item runs nothing, while its
/// enabled sibling's runs. Mutations (lane 2 review): **V1** the
/// `target.isEnabled` guard in `Window.handleToolbarAction` dropped; **V2**
/// `EnvironmentScope`'s toolbar conformance ignoring its write; **V7**
/// `noteToolbar` evaluating with `isEnabled: true`.
@MainActor
@Test func aDisabledToolbarItemReachesThePlatformDisabledAndRunsNothing() throws {
    let m = TBModel()
    let (window, platform) = try tbWindow {
        Column {
            Text("a").toolbar {
                ToolbarItem(id: "off") { Button("Off") { m.pressed += 1 }.disabled(true) }
                ToolbarItem(id: "on") { Button("On") { m.pressed += 10 } }
            }
            Column {
                Text("b").toolbar {
                    ToolbarItem(id: "inner") { Toggle("T", isOn: binding({ m.advanced }, { m.advanced = $0 })) }
                }
            }
            .disabled(true)
        }
    }
    window.drawFrameIfNeeded()
    let sent = try #require(platform.toolbars.last, "no setToolbar call")
    #expect(sent == PlatformToolbar(items: [
        PlatformToolbarItem(id: "off", placement: .automatic, control: .button(title: "Off", image: nil),
                            isEnabled: false),
        PlatformToolbarItem(id: "on", placement: .automatic, control: .button(title: "On", image: nil)),
        PlatformToolbarItem(id: "inner", placement: .automatic, control: .toggle(title: "T", isOn: false),
                            isEnabled: false),
    ]), "\(String(describing: sent))")

    _ = platform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "off", action: .press)))
    _ = platform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "inner", action: .toggle(true))))
    #expect(m.pressed == 0 && m.advanced == false,
            "a disabled item runs nothing: pressed \(m.pressed) advanced \(m.advanced)")
    _ = platform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "on", action: .press)))
    #expect(m.pressed == 10, "the enabled sibling runs: pressed \(m.pressed)")
}

// MARK: - 3.7

/// **3.7** (`MD-I` items 3 and 6, `MD-X` item 3). The item-mapping rules: a
/// `.pickerStyle(.menu)` picker is a pop-up and every other style (the default
/// included) is segmented; `.help(_:)` on a toolbar button reaches
/// `PlatformToolbarItem.help`; a `ToolbarItemGroup` of one control is numbered
/// `<base>.0`; a scope whose content is empty contributes nothing; a caller's
/// `onClick` replaces a toolbar button's action. Mutations (lane 2 review):
/// **V4** every picker `.segmented`; **V3** `help: nil` in `Button`'s
/// conformance; **V5** a group of one not numbered; **V6** an empty scope
/// noted; **V8** `Button`'s conformance running `action` over `onClick`.
@MainActor
@Test func theToolbarItemMappingRulesReachThePlatform() throws {
    let m = TBModel()
    let mode = binding({ m.mode }, { m.mode = $0 })
    let (window, platform) = try tbWindow {
        Column {
            Text("a").toolbar {
                ToolbarItem(id: "menu") {
                    Picker("M", selection: mode) { Text("x").tag(0); Text("y").tag(1) }.pickerStyle(.menu)
                }
                ToolbarItem(id: "auto") {
                    Picker("A", selection: mode) { Text("x").tag(0); Text("y").tag(1) }
                }
                ToolbarItem(id: "radio") {
                    Picker("R", selection: mode) { Text("x").tag(0); Text("y").tag(1) }.pickerStyle(.radioGroup)
                }
                ToolbarItem(id: "help") { Button("H") {}.help("Tip") }
                ToolbarItemGroup { Button("G") {} }
                ToolbarItem(id: "click") { Button("C") { m.pressed += 100 }.onClick { m.pressed += 1000 } }
            }
            EmptyGroup().toolbar { ToolbarItem(id: "empty") { Button("E") {} } }
        }
    }
    window.drawFrameIfNeeded()
    let sent = try #require(platform.toolbars.last, "no setToolbar call")
    #expect(sent == PlatformToolbar(items: [
        PlatformToolbarItem(id: "menu", placement: .automatic,
                            control: .picker(title: "M", options: ["x", "y"], selected: 0, style: .menu)),
        PlatformToolbarItem(id: "auto", placement: .automatic,
                            control: .picker(title: "A", options: ["x", "y"], selected: 0, style: .segmented)),
        PlatformToolbarItem(id: "radio", placement: .automatic,
                            control: .picker(title: "R", options: ["x", "y"], selected: 0, style: .segmented)),
        PlatformToolbarItem(id: "help", placement: .automatic, control: .button(title: "H", image: nil),
                            help: "Tip"),
        PlatformToolbarItem(id: "automatic.4.0", placement: .automatic, control: .button(title: "G", image: nil)),
        PlatformToolbarItem(id: "click", placement: .automatic, control: .button(title: "C", image: nil)),
    ]), "\(String(describing: sent))")

    _ = platform.simulateInput(.toolbarAction(ToolbarActionEvent(item: "click", action: .press)))
    #expect(m.pressed == 1000, "onClick replaces the action: pressed \(m.pressed)")
}
