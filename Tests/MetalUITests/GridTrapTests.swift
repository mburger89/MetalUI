import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lane 4 of `docs/superpowers/specs/2026-09-17-grids-design.md`, test 4.13:
// **every proposal modifier written on a MULTI-CELL `GridRow` traps** (ruling
// GR-J; divergence `GR-O` 6). SwiftUI applies such a modifier to each cell
// (probe arms GG4 for `.padding` and GG7 for `.onTapGesture`); MetalUI's
// wrappers precondition exactly one native child, so the row's several nodes
// abort the registration instead.
//
// **The preconditions are not grid-owned** — they are
// `ModifiedContent.nativeWrapperNode`'s and `OnTapModifier`'s, which predate
// this stage — so the lane mutates each once in its shared file and reverts,
// recording the arms each reddens rather than claiming a grid mutation.
//
// The control arm is the same three modifiers on a ONE-cell row, which is the
// spelling `GR-I`'s walk keeps a row cell; it must exit `.success`, or "the
// multi-cell arms trap" would be satisfied by a grid that cannot take a modifier
// at all.
//
// `@testable` rather than a plain import only because `Frame.init` is internal;
// nothing here reads past the public API otherwise. Each render is reached
// through `MainActor.run` from the exit test's nonisolated body, as
// `EnvironmentTrapTests.swift` reaches its own.

private enum RowModifier {
    case padding, tap, background, allThreeOnOneCell
}

@MainActor
private func renderModifiedRow(_ modifier: RowModifier) {
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1)
    switch modifier {
    case .padding:
        var root = Grid {
            GridRow {
                Rectangle(width: Pixels(30), height: Pixels(10))
                Rectangle(width: Pixels(20), height: Pixels(20))
            }
            .padding(Edges(all: Pixels(5)))
        }
        frame.render(&root)
    case .tap:
        var root = Grid {
            GridRow {
                Rectangle(width: Pixels(30), height: Pixels(10))
                Rectangle(width: Pixels(20), height: Pixels(20))
            }
            .onTap {}
        }
        frame.render(&root)
    case .background:
        var root = Grid {
            GridRow {
                Rectangle(width: Pixels(30), height: Pixels(10))
                Rectangle(width: Pixels(20), height: Pixels(20))
            }
            .background(.accent)
        }
        frame.render(&root)
    case .allThreeOnOneCell:
        var root = Grid {
            GridRow { Rectangle(width: Pixels(30), height: Pixels(10)) }
                .padding(Edges(all: Pixels(5)))
                .background(.accent)
                .onTap {}
        }
        frame.render(&root)
    }
}

private func stderrText(_ result: ExitTest.Result?) -> String {
    String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
}

/// **A `.padding`, an `.onTap` or a `.background` on a two-cell `GridRow`
/// traps**, each with its own message; the same three on a one-cell row do not.
///
/// Mutations (shared files, applied once and reverted): relaxing
/// `ModifiedContent.nativeWrapperNode`'s `children.count == 1` to `>= 1` leaves
/// the padding and background arms exiting `.success`; the same on
/// `OnTapModifier.requestProposalLayout` leaves the tap arm exiting `.success`.
@Test func aModifierOnAMultiCellGridRowTraps() async {
    let padding = await #expect(processExitsWith: .failure,
                                observing: [\.standardErrorContent]) {
        await MainActor.run { renderModifiedRow(.padding) }
    }
    #expect(stderrText(padding).contains("a native outer modifier must wrap exactly one native layout node"),
            "GG4 aborted, but not at the wrapper's precondition:\n\(stderrText(padding))")

    let tap = await #expect(processExitsWith: .failure,
                            observing: [\.standardErrorContent]) {
        await MainActor.run { renderModifiedRow(.tap) }
    }
    #expect(stderrText(tap).contains("a native tappable wrapper requires one native child"),
            "GG7 aborted, but not at the tappable's precondition:\n\(stderrText(tap))")

    let background = await #expect(processExitsWith: .failure,
                                   observing: [\.standardErrorContent]) {
        await MainActor.run { renderModifiedRow(.background) }
    }
    #expect(stderrText(background).contains("a native outer modifier must wrap exactly one native layout node"),
            "a paint-only modifier aborted, but not at the wrapper's precondition:\n\(stderrText(background))")

    // The control: one cell, the same three modifiers, no trap.
    await #expect(processExitsWith: .success) {
        await MainActor.run { renderModifiedRow(.allThreeOnOneCell) }
    }
}
