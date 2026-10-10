import Testing
import MetalUITestSupport

// App shell, lane 2, guard 2.1 (rulings `AS-B`…`AS-G`, `AS-N`; spec
// `docs/superpowers/specs/2026-10-08-app-shell-design.md` §4.2). Whole-file
// Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN `import MetalUI` — a
// `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `AS-B spellings` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// Every spelling of spec §1.2 from an external module.
private let positiveFixture = """
    import Foundation

    @MainActor func shell(_ app: App, _ url: URL, _ name: String) throws {
        let window = try app.openWindow(title: "Doc", size: Size(width: Pixels(400), height: Pixels(300)),
                                        windowStyle: .hiddenTitleBar) {
            Column {
                Text("x").navigationTitle("T").navigationDocument(url).onOpenURL { _ in }
                HStack { ProposalText("y") }.navigationTitle(name)
                Box().navigationTitle("x")
            }
        }
        window.title = "Renamed"
        let _: String = window.title
        window.isDocumentEdited = true
        let _: Bool = window.isDocumentEdited
        window.representedURL = url
        let _: URL? = window.representedURL
        window.windowStyle = .titleBar
        window.windowStyle = .automatic
        let _: WindowStyle = window.windowStyle
        window.onCloseRequest = { .later }
        window.onCloseRequest = { CloseRequestReply.now }
        window.onCloseRequest = nil
        let _: Bool = window.isCloseRequestPending
        window.replyToCloseRequest(true)
        window.close()
        window.performClose()
        app.onTerminateRequest = { .cancel }
        app.replyToTerminateRequest(false)
        app.terminate()
        app.onOpenURL = { url in print(url) }
        app.open([url])
        let _: Bool = WindowStyle.hiddenTitleBar == .automatic
    }

    struct InsetReader: Element {
        @Environment(\\.titleBarInsets) var insets
        var elementID: ElementID? { nil }
        func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
            let top: Pixels = insets.top
            _ = top
            return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
        }
        func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
        func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                   prepaint: inout Void, pass: inout PaintPass) {}
    }
    """

/// Each negative: a spelling that must not compile, and the word its refusal
/// names.
private let negatives: [(name: String, fixture: String, mentions: String)] = [
    ("titleBarInsets setter", """
        func write(_ values: inout EnvironmentValues) {
            values.titleBarInsets = Edges(all: Pixels(1))
        }
        """, "titleBarInsets"),
    ("navigationTitle(Text)", """
        @MainActor func tree() -> some Element {
            Column { Box().navigationTitle(Text("x")) }
        }
        """, "navigationTitle"),
    ("WindowStyle.plain", """
        let style: WindowStyle = .plain
        """, "plain"),
    ("decoration after a window-preference scope (EV-B)", """
        @MainActor func tree() -> some Element {
            Column { Box().navigationTitle("x").padding(4) }
        }
        """, "padding"),
    ("window-preference scope as a window root (AS-N)", """
        @MainActor func open(_ app: App) throws {
            _ = try app.openWindow(title: "w", size: Size(width: Pixels(100), height: Pixels(100))) {
                Box().navigationTitle("x")
            }
        }
        """, "Element"),
]

/// **2.1** (`AS-B`…`AS-G`, `AS-N`). Every app-shell spelling compiles from an
/// external module; each negative — writing `titleBarInsets`, a `Text`
/// title, `WindowStyle.plain`, a legacy decoration after the scope, the scope
/// as a window root — does not. Mutation: make `titleBarInsets`' setter
/// public (that negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anOutsideModuleCanSpellTheAppShellAPI() throws {
    let positive = try typecheckFile(positiveFixture, importing: "MetalUI")
    print("AS-B spellings: succeeded=\(positive.succeeded) messages=[\(positive.messages)]")
    try #require(positive.succeeded, "every app-shell spelling must compile:\n\(positive.output)")
    for negative in negatives {
        let result = try typecheckFile(negative.fixture, importing: "MetalUI")
        print("AS-B negative \(negative.name): succeeded=\(result.succeeded) messages=[\(result.messages)]")
        #expect(!result.succeeded, "\(negative.name) must not compile:\n\(result.output)")
        #expect(result.messages.contains(negative.mentions),
                "\(negative.name) must be refused naming \(negative.mentions):\n\(result.output)")
    }
}
