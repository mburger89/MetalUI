import Testing
import MetalUITestSupport

// Plain-import guards for the public test harness (ruling `HT-M`, spec §4.3
// tests 3.1–3.3; `SA-P`). Each fixture is a whole Swift 6 file importing
// `MetalUI` and `MetalUITesting` and nothing else — what an app's test target
// writes — so a `@testable` import cannot hide an access level. This file's
// own imports are irrelevant; the fixture's are the ones that count.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Build and test"): `MetalUITests` depends on `MetalUITesting`
// so its module is built where `#filePath` expects. Each guard was mutated red
// once on a `--build-system native` build; the mutations are recorded in
// record §91.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI and MetalUITesting not found — guard skipped"

private let harnessModulesBuilt = canTypecheck(module: "MetalUI") && canTypecheck(module: "MetalUITesting")

/// **3.1** (`HT-M`, the positive). An outside test file opens a `TestWindow`,
/// acts by point and by element, reads a laid-out frame, answers an alert,
/// evaluates a menu, reads the menu bar, drives the clock and reads the frame
/// work — with plain imports only. Mutation: `TestWindow.click(_:modifierFlags:)`
/// made `internal` → red.
@Test(.enabled(if: harnessModulesBuilt, skipReason))
func anOutsideTestFileCanDriveATestWindowWithAPlainImport() throws {
    let result = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func drive() async throws {
            let window = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300))) {
                Column {
                    Button("Save") {}
                    Box().frame(width: Pixels(10), height: Pixels(10)).id("inspector")
                }
            }
            try window.click(window.element(label: "Save"))
            window.click(at: Point(x: Pixels(10), y: Pixels(10)))
            let frame: Bounds<Pixels> = try window.frame(ofID: "inspector")
            _ = frame
            if window.presentedAlert != nil { try window.respondToAlert(button: "OK") }
            let menu = MenuEvaluation { Button("Copy") {} }
            try menu.perform("Copy")
            let bar: [PlatformMenu] = window.testApp.menuBar
            _ = bar
            window.advance(by: 0.5)
            try await window.runUntilIdle()
            let work: FrameWork = window.lastFrameWork
            _ = work
        }
        """, importing: "MetalUI")
    #expect(result.succeeded, "an outside test file must drive a TestWindow from public API:\n\(result.output)")
}

/// **3.2** (`HT-C` item 2, `HT-M`). The harness's read-back hooks are
/// `package`: an outside file cannot reach any of them. The first fixture is
/// the separating control — a public member read the same way compiles.
/// Mutation: `testingElementBounds` made `public` → red.
@Test(.enabled(if: harnessModulesBuilt, skipReason))
func anOutsideFileCannotReachTheTestingHooks() throws {
    let control = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func reach(_ window: TestWindow) -> Int { window.window.framesDrawn }
        """, importing: "MetalUI")
    try #require(control.succeeded, "the control (a public member) must compile:\n\(control.output)")

    let result = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func reach(_ window: TestWindow) {
            _ = window.window.testingElementBounds
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded, "a package hook must be unreachable from an outside file:\n\(result.output)")
    #expect(result.messages.contains("testingElementBounds"),
            "rejected, but not for the hook:\n\(result.output)")
}

/// **3.3** (`HT-C`, `HT-M`). The harness adds no way to build a `Window` by
/// hand: an outside file still cannot call `Window.init(platformWindow:…)`,
/// even with a `HeadlessPlatformWindow` in hand (which it can make). Mutation:
/// `Window.init` made `public` → red.
@Test(.enabled(if: harnessModulesBuilt, skipReason))
func anOutsideFileStillCannotConstructAWindow() throws {
    let control = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func make() -> HeadlessPlatformWindow {
            HeadlessPlatformWindow(title: "t", size: Size(width: Pixels(10), height: Pixels(10)))
        }
        """, importing: "MetalUI")
    try #require(control.succeeded, "the control (a public initialiser) must compile:\n\(control.output)")

    let result = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func make() -> Window {
            let platformWindow = HeadlessPlatformWindow(title: "t", size: Size(width: Pixels(10), height: Pixels(10)))
            return Window(platformWindow: platformWindow) { Box() }
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded, "Window.init must stay unspellable outside MetalUI:\n\(result.output)")
    #expect(result.messages.contains("initializer"), "rejected, but not for the initialiser:\n\(result.output)")
}
