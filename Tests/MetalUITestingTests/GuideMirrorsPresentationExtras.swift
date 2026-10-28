import MetalUI
import MetalUITesting
import Testing

// The mirrors of four newer blocks of the guides (`DG-C`, `DG-D`): `input` #12 (`SpatialTapGesture.Value.clickCount`,
// `IF-O`), `input` #13 (`Window.backgroundDragBehavior`, `BG-G`), `presentations-and-app-shell` #7
// (`.presentationBackground`, `BG-A`) and `drawing-and-gpu` #10 (`glassEffect`, `GlassEffectContainer`, `LG-G`).
// Copied BY HAND between the `// guide:` and `// end guide` markers, byte for byte; `GuideDocCheck.swift` compares
// them with the guides. Below each, the test the guide pins.

// guide: input #12
/// A tap target that shows the click count of its last tap.
struct InputClickCountPad: Component {
    @State var lastCount = 0

    var content: some ElementGroup {
        Text("Last click count: \(lastCount)")
        Rectangle()
            .frame(width: Pixels(160), height: Pixels(40))
            .accessibilityIdentifier("click-pad")
            .gesture(SpatialTapGesture().onEnded { lastCount = $0.clickCount })
    }
}

@MainActor
func inputClickCountRoot() -> some Element {
    VStack { InputClickCountPad() }
}
// end guide

// guide: input #13
/// Lets a press on empty space move the window.
@MainActor
func inputDragFromBackground(_ window: Window) {
    window.backgroundDragBehavior = .enabled
}
// end guide

// guide: presentations-and-app-shell #7
/// A button whose popover panel is filled red.
struct ShellTintedPopover: Component {
    @State var shown = false

    var content: some ElementGroup {
        Button("Tint") { shown.toggle() }
            .popover(isPresented: $shown) {
                Text("Details")
                    .frame(width: Pixels(120), height: Pixels(40))
                    .presentationBackground(Color.red)
            }
    }
}

@MainActor
func shellTintedPopoverRoot() -> some Element {
    VStack { ShellTintedPopover() }
}
// end guide

// guide: drawing-and-gpu #10
/// Three glass circles that merge inside a container, and one capsule that stands alone.
@MainActor
func drawingGlassRoot() -> some Element {
    VStack(spacing: Pixels(8)) {
        GlassEffectContainer(spacing: Pixels(40)) {
            HStack(spacing: Pixels(10)) {
                Color.clear.frame(width: Pixels(60), height: Pixels(60)).glassEffect(in: Circle())
                Color.clear.frame(width: Pixels(60), height: Pixels(60)).glassEffect(in: Circle())
                Color.clear.frame(width: Pixels(60), height: Pixels(60)).glassEffect(in: Circle())
            }
        }
        Color.clear.frame(width: Pixels(80), height: Pixels(40)).glassEffect(.regular.tint(Color.blue.opacity(0.2)))
    }
}
// end guide

/// A click reports 1 and a double-click's second press reports 2. Mutation: delete `lastCount = $0.clickCount`.
@Test @MainActor func theInputGuideAnInputTapReportsItsClickCount() throws {
    let window = try harnessWindow { inputClickCountRoot() }
    let pad = try window.element(identifier: "click-pad").frame
    let centre = Point(x: pad.origin.x + pad.size.width / 2, y: pad.origin.y + pad.size.height / 2)
    _ = try window.element(label: "Last click count: 0")
    window.click(at: centre); window.window.setNeedsRedraw(); window.tick()
    _ = try window.element(label: "Last click count: 1")
    window.doubleClick(at: centre); window.window.setNeedsRedraw(); window.tick()
    _ = try window.element(label: "Last click count: 2")
}

/// With the behaviour on, a press on empty space asks for a title-bar drag and a press on a button does not.
/// Mutation: delete the assignment.
@Test @MainActor func theInputGuideTheBackgroundDragsOnlyWhereNothingClaimsThePress() throws {
    let window = try harnessWindow { VStack { Button("Save") {} } }
    inputDragFromBackground(window.window)
    window.window.setNeedsRedraw(); window.tick()
    try window.click(window.element(label: "Save"))
    #expect(window.platformWindow.titleBarPresses.isEmpty, "a button keeps its press")
    window.click(at: Point(x: Pixels(5), y: Pixels(250)))
    #expect(window.platformWindow.titleBarPresses == [1], "\(window.platformWindow.titleBarPresses)")
}

/// The open popover's panel is a red rect the closed window lacks. Mutation: delete `.presentationBackground`.
@Test @MainActor func theShellGuideAPresentationBackgroundFillsThePopoverPanel() throws {
    func reds(_ window: TestWindow) -> Int {
        var count = 0
        for rect in window.scene.rects where rect.background.a == 1 && rect.background.s > 0.8 && (rect.background.h < 0.05 || rect.background.h > 0.95) {
            count += 1
        }
        return count
    }
    let window = try harnessWindow { shellTintedPopoverRoot() }
    let before = reds(window)
    try window.click(window.element(label: "Tint"))
    window.window.setNeedsRedraw(); window.tick()
    #expect(try window.elements(role: .popover).count == 1)
    #expect(reds(window) == before + 1, "before \(before), after \(reds(window))")
}

/// Two backdrop records: the container's blob of three members and the standalone glass.
/// Mutation: delete the `GlassEffectContainer` (three records, one per member, plus the standalone one).
@Test @MainActor func theDrawingGuideAContainerMergesItsMembersIntoOneBlob() throws {
    let window = try harnessWindow { drawingGlassRoot() }
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.scene.backdrops.count == 2, "\(window.scene.backdrops.count)")
    #expect(window.scene.backdrops.contains { $0.glassMemberCount == 3 })
}
