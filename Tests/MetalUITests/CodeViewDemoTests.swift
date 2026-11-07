import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIDemoContent
@testable import MetalUI

// The code view demo (`CV-`, record 227; human checks group CV). `METALUI_CODE_DEMO=1` opens
// `codeViewDemoContent()`; this pins what checks CV1-CV8 then look at: the demo of a generated 100 000-line file
// builds in a window, lowers, settles, and paints only a screenful of rows.

/// **CD.1** — the demo over a 100 000-line model in a 1100 x 700 frame, drawn until it asks for nothing (at most 12
/// frames): everything lowers, it settles, and the two views shaped a few dozen rows between them, not the file.
/// **Mutation:** the row loop over all display rows shapes 100 000 lines per view.
@MainActor
@Test func theCodeViewDemoBuildsWindowedAndSettles() throws {
    let model = CodeViewDemoModel()
    #expect(model.buffer.lineCount > 100_000 && model.decorations.virtualLineCount == 600, "virtual \(model.decorations.virtualLineCount)")
    let preflight = LayoutDifferential.report(width: 1100, height: 700) { codeViewDemoContent(model: model) }
    try #require(preflight.unlowerable.isEmpty, "\(preflight.unlowerable.map(\.description))")
    let states = StateTable()
    var frame = Frame(contentSize: Size(width: Pixels(1100), height: Pixels(700)), scaleFactor: 1, stateTable: states)
    var drawn = 0
    var shaped = 0
    repeat {
        frame = Frame(contentSize: Size(width: Pixels(1100), height: Pixels(700)), scaleFactor: 1, stateTable: states)
        var root = codeViewDemoContent(model: model)
        frame.render(&root)
        shaped += frame.codeWork.linesShaped
        drawn += 1
    } while frame.wantsAnotherFrame && drawn < 12
    #expect(!frame.wantsAnotherFrame, "the demo settles: \(drawn) frames")
    #expect(shaped > 0 && shaped < 400, "lines shaped across \(drawn) frames: \(shaped)")
}
