import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIDemoContent
@testable import MetalUI

// The lazy containers demo (item L1, `LZ-Q`; human checks group LZ). `METALUI_LAZY_DEMO=1` opens
// `lazyContainersDemoContent()`; this pins what checks LZ1-LZ5 then look at: the demo is windowed (four
// containers of 10 000 children realise a few dozen between them, none unbounded) and settles without
// input. Red-before (record section 134): the demo did not exist, so the file failed to compile
// (`cannot find 'lazyContainersDemoContent' in scope`).

/// **L.1 (`LZ-Q`, `LZ-E`).** The demo in a 920 x 640 frame over one state table, drawn until it asks for
/// nothing (at most 12 frames): nothing unlowerable, no container unbounded (each section's scroller is
/// bounded on its own axis), and the four containers realise **fewer than 400** children between them
/// where the data holds 40 000. Derived before the run: a section's scroller is about 280 points of
/// viewport, rows of at least 24 and cells of at least 40, so each container holds well under 60 children
/// plus overscan; 400 leaves room for a tall first viewport and is 100 times below the eager 40 000.
/// Mutation: remove a section's scroller (the container goes unbounded and the count reaches 10 000).
@MainActor
@Test func theLazyContainersDemoIsWindowedAndSettles() throws {
    let preflight = LayoutDifferential.report(width: 920, height: 640) { lazyContainersDemoContent() }
    try #require(preflight.unlowerable.isEmpty, "\(preflight.unlowerable.map(\.description))")

    let states = StateTable()
    var frame = Frame(contentSize: Size(width: Pixels(920), height: Pixels(640)), scaleFactor: 1, stateTable: states)
    var drawn = 0
    repeat {
        frame = Frame(contentSize: Size(width: Pixels(920), height: Pixels(640)), scaleFactor: 1, stateTable: states)
        var root = lazyContainersDemoContent()
        frame.render(&root)
        drawn += 1
    } while frame.wantsAnotherFrame && drawn < 12
    #expect(!frame.wantsAnotherFrame, "the demo settles: \(drawn) frames")
    #expect(frame.lazyWork.unbounded == 0, "\(frame.lazyWork)")
    #expect(frame.lazyWork.unitsRealized > 0 && frame.lazyWork.unitsRealized < 400, "\(frame.lazyWork)")
}
