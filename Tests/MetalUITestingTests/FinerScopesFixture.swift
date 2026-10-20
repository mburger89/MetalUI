import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14-d (`FS-`, record 126): the fixture of the finer-scopes pins, ported from `docs/probes/finer-scopes/`'s throw-away instrument.
// 24 `.equatable()` card rows at scale 2 in a 320 x 400 window; counts only (`FrameWork`), never time.

@MainActor final class FSModel {
    var values: [Int] = Array(0..<24)      // card i shows values[i]
    var ids: [Int] = Array(0..<24)         // `ForEach` identities, in order
}

struct FSCard: Component, @MainActor Equatable {
    let id: Int
    let value: Int
    static func == (l: FSCard, r: FSCard) -> Bool { l.id == r.id && l.value == r.value }
    var content: some ElementGroup {
        HStack(spacing: 4) {
            Color(red: 0.2, green: 0.4, blue: 0.8).frame(width: Pixels(10), height: Pixels(10))
            Text("Card \(id) = \(value)")
            Color(red: 0.8, green: 0.4, blue: 0.2).frame(width: Pixels(10), height: Pixels(10))
        }
        .frame(height: Pixels(20))
    }
}

struct FSRow: Identifiable { let id: Int }

/// The two `List` branches (`VL-I`): `rowHeight:` and rows sized from their content.
enum FSBranch: CaseIterable, CustomStringConvertible {
    case uniform, variable
    var description: String { self == .uniform ? "uniform" : "variable" }
}

/// The cards in a `VStack` (F1) or in a `List` in a scroller (F4). `changing` is the row whose value the model moves.
struct FSListRoot: Component {
    let model: FSModel
    let branch: FSBranch
    var content: some ElementGroup {
        ScrollView(.vertical) {
            switch branch {
            case .uniform:
                List(model.ids.map { FSRow(id: $0) }, rowHeight: Pixels(22)) { r in
                    Column { FSCard(id: r.id, value: r.id == 3 ? model.values[3] : 0).equatable() }
                }
            case .variable:
                List(model.ids.map { FSRow(id: $0) }) { r in
                    Column { FSCard(id: r.id, value: r.id == 3 ? model.values[3] : 0).equatable() }
                }
            }
        }.frame(width: Pixels(300), height: Pixels(150))
    }
}

struct FSStackRoot: Component {
    let model: FSModel
    var content: some ElementGroup {
        VStack(spacing: 2) {
            ForEach(model.ids, id: \.self) { i in FSCard(id: i, value: model.values[i % 24]).equatable() }
        }
    }
}

/// Three frames of work after four warm frames; `mutate` runs before each of the three.
@MainActor func fsFrames(graft: Bool, accessibility: Bool = true, list branch: FSBranch? = nil,
                         mutate: (FSModel) -> Void = { _ in }) throws -> [FrameWork] {
    let model = FSModel()
    let options = HeadlessPlatformWindow.Options(scaleFactor: 2, accessibilityClientActive: accessibility)
    let w = try TestWindow(size: Size(width: Pixels(320), height: Pixels(400)), scaleFactor: 2, options: options,
                           textSystem: { harnessTextSystem() }) {
        VStack(spacing: 0) {
            if let branch { FSListRoot(model: model, branch: branch) } else { FSStackRoot(model: model) }
        }
    }
    w.window.testingRetainedGraft = graft
    for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
    w.resetFrameWork()
    for _ in 0..<3 { mutate(model); w.window.setNeedsRedraw(); w.tick() }
    return w.frameWork
}
