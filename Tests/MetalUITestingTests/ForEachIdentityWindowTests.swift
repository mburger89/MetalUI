import Testing
import MetalUI
import MetalUIScene

// C20 (`FI-A`, spec test 2.9): a real `Window` over the harness shows both
// elements of a `ForEach` whose ids print alike.

private struct WindowTwin: Hashable, CustomStringConvertible {
    let u: Int
    var description: String { "twin" }
}

/// **2.9 — a `ForEach` in a harness window shows both twins.** Two `Text`s found
/// by label. Red before: "Second" absent. Mutation **M1** reddens it.
@Test @MainActor func aForEachInATestWindowShowsBothTwins() throws {
    let window = try harnessWindow {
        Column {
            ForEach([WindowTwin(u: 1), WindowTwin(u: 2)], id: \.self) { t in
                Text(t.u == 1 ? "First" : "Second")
            }
        }
    }
    _ = try window.element(label: "First")
    _ = try window.element(label: "Second")
}
