import JotterKit
import MetalUI
import MetalUITesting
import Testing

@MainActor
@Test func aWindowShrunkToMinimumKeepsEveryControlHittable() throws {
    let model = seededModel()
    // The drawn toolbar strip (SDL's answer), so every control is in the tree.
    let window = try jotterWindow(model, options: .init(showsToolbarNatively: false), size: jotterMinimumSize)
    let bounds = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: jotterMinimumSize)
    func inside(_ rect: Bounds<Pixels>) -> Bool {
        rect.origin.x >= 0 && rect.origin.y >= 0
            && rect.origin.x + rect.size.width <= bounds.size.width && rect.origin.y + rect.size.height <= bounds.size.height
    }
    for label in ["New", "Delete", "Stats", "Export", "Import", "Theme"] {
        let button = try window.element(label: label)
        #expect(inside(button.frame), "\(label) lies inside the window: \(button.frame)")
    }
    #expect(inside(try window.element(label: "Search notes").frame), "the search field lies inside the window")
    #expect(inside(try window.element(identifier: "title-field").frame))
    #expect(inside(try window.element(identifier: "body-field").frame))
    // And a click at each one's centre runs it.
    try window.click(window.element(label: "New"))
    #expect(model.notes.count == 5)
    try window.click(window.element(label: "Stats"))
    #expect(model.showsStats)
    try window.click(window.element(label: "Notes"))
    #expect(!model.showsStats)
    try window.click(window.element(label: "Theme"))
    #expect(model.scheme == .dark)
}
