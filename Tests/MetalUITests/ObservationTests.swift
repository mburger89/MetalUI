import Testing
import Metal
import Observation
@testable import MetalUI
import MetalUICore

/// A stand-in for an application's own model. `@Observable` and mutated from
/// tests; nothing in the framework knows this type exists, which is the point —
/// there is no opt-in, no registration and no annotation on the framework side.
@Observable
final class ProbeModel {
    var label: String = "a"
    var untouched: Int = 0
}

/// Spec §3 and §4: an `@Observable` property read anywhere during a frame build
/// becomes a dependency of that frame, and mutating it marks the window dirty.
///
/// This is the assertion the whole spec exists for: before it, `grep -rn
/// "withObservationTracking" Sources/` returned nothing and no model could
/// dirty a window at all.
@MainActor
@Test func mutatingAnObservedModelMarksTheWindowDirty() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, _) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }

    // Drain the initial dirty state so the next write is the only cause.
    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw, "set up: the window must be clean")

    model.label = "bb"

    #expect(window.needsRedraw,
            "an @Observable property read during the frame build must dirty the window")
    #expect(window.observationDirtyings == 1,
            "exactly one dirty-marking for one write, not zero and not several")
}

/// Spec §4.2: a property the frame build never reads is not a dependency.
/// Without this, a passing sibling test could be explained by the window
/// dirtying on *any* observable write anywhere, which is not what
/// `withObservationTracking` promises and not what §3 specifies.
@MainActor
@Test func mutatingAnUnreadPropertyDoesNotDirtyTheWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let model = ProbeModel()
    let (window, _) = try makeFakeWindow(device: device) {
        Box().background(.surface).width(Pixels(10)).height(Pixels(Float(model.label.count)))
    }

    window.drawFrameIfNeeded()
    try #require(!window.needsRedraw, "set up: the window must be clean")

    model.untouched += 1        // never read by the content closure

    #expect(!window.needsRedraw,
            "a property no frame read is not a dependency of any frame")
    #expect(window.observationDirtyings == 0)
}
