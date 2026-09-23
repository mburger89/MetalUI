import Foundation
import Testing
import Metal
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 6b, lane 1 (`docs/superpowers/specs/2026-09-23-engine-stage-6b-design.md`
// §0 item 1 and §8 tests 1.7–1.8; ruling `LR-DO` item 1, honouring `LR-AQ`'s hand-off):
// the root's item fields under the proposal authority.
//
// A root's record is by definition consumed by no lowered container, so
// `reportUnconsumedLoweredItems` used to report every non-`auto` `minSize` /
// `maxSize` on it — a production trap for `Box { … }.height(370).minHeight(0)`, the
// shape `demoLikeRows` copies from real use. On an axis the root **declares** in px or
// rem, the element's own fixed frame already folds its px/rem minimum and maximum at
// registration (`paddedAndSized`, stage 2's `LR-AG`: `max(min, min(size, max))`), and
// CSS gives the same number because `CS-I` does not touch a declared root axis — so
// the report was the only thing wrong, and it is dropped for exactly that case.
// Everything else a root can carry with no lowering keeps trapping, and 1.8 pins
// each through a production `Window`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

/// The root under `authority` in a production-sized frame (920×560, the demo's
/// window), with diagnostics on under `.proposal` so a report reads red instead of
/// trapping, and the element bounds log on.
@MainActor
private func rootFrame<E: Element>(_ authority: LayoutAuthority, _ element: E) -> Frame {
    var element = element
    let frame = Frame(contentSize: Size(width: px(920), height: px(560)), scaleFactor: 2,
                      stateTable: StateTable(), theme: .dark, layoutAuthority: authority,
                      reportsUnlowerableFields: authority == .proposal,
                      recordsElementBounds: true)
    frame.render(&element)
    return frame
}

/// **1.7** (`LR-DO` item 1). Three roots declaring `.height(370)` with a px minimum or
/// maximum on that same axis — `.minHeight(0)` (the `demoLikeRows` shape),
/// `.minHeight(500)` and `.maxHeight(300)` — laid out as a production frame's root
/// under both authorities: the root is 370 / 500 / 300 tall on **both**, and the
/// proposal report is empty. The second and third arms disagree with the declared
/// height alone (the separating arms: a fold that ignored the bound would read 370).
///
/// Red before: each proposal arm reports `box.minSize.unconsumed` or
/// `box.maxSize.unconsumed`.
/// Mutation **M1h**: the root fold removed from `reportUnconsumedLoweredItems`.
@Test @MainActor func aRootsMinimumAndMaximumFoldIntoItsDeclaredSize() throws {
    func content() -> Box<Box<EmptyGroup>> {
        Box { Box().width(px(10)).height(px(10)) }.width(px(420)).height(px(370))
    }
    let arms: [(name: String, root: Box<Box<EmptyGroup>>, height: Float)] = [
        ("height(370).minHeight(0)", content().minHeight(px(0)), 370),
        ("height(370).minHeight(500)", content().minHeight(px(500)), 500),
        ("height(370).maxHeight(300)", content().maxHeight(px(300)), 300),
    ]
    try #require(arms.count == 3)
    for arm in arms {
        for authority in LayoutAuthority.allCases {
            let frame = rootFrame(authority, arm.root)
            #expect(frame.unlowerableFields.isEmpty,
                    "\(arm.name), \(authority): reported \(frame.unlowerableFields)")
            let bounds = try #require(frame.elementBounds[rootID], "\(arm.name), \(authority)")
            #expect(bounds.size.height == px(arm.height),
                    "\(arm.name), \(authority): the root is \(bounds.size.height), not \(arm.height)")
            #expect(bounds.size.width == px(420), "\(arm.name), \(authority): width \(bounds.size.width)")
        }
    }
}

/// A production `Window` (a `FakePlatformWindow`, no diagnostics — `Window` never
/// sets them) under the proposal authority, showing `root`, drawn once. Run inside a
/// child process only.
@MainActor
private func drawInAProductionProposalWindow<E: Element>(_ root: @escaping @MainActor () -> E) {
    guard let device = MTLCreateSystemDefaultDevice() else {
        FileHandle.standardError.write(Data("no Metal device\n".utf8))
        exit(3)
    }
    let (window, _) = try! makeFakeWindow(device: device, size: 200, layoutAuthority: .proposal,
                                          content: root)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

/// **1.8** (`LR-DO` item 1). Every root field that still has no lowering **traps a
/// production `Window`** naming it — a trap production ships is a trap the suite
/// shows. Three arms, each an exit test through a `.proposal` `makeFakeWindow`
/// (explicit, since lane 1 runs before the default flips), each with its control —
/// the same root without the field — which must draw and exit successfully, so the
/// abort is the field and not the window, the tree or the authority:
///
/// - a `minHeight` on the root's **auto** height (no declared size to fold into;
///   stage 8's recipe spells it as a `.frame`): `box.minSize.unconsumed`;
/// - a root **margin** (owner 9): `box.margin.unconsumed`;
/// - a root **percentage** `maxWidth`, on a declared width (a percentage never folds;
///   stage 8): `box.maxSize.unconsumed`.
///
/// Green on arrival — the traps exist at `aef88ce`. Its red is the instrument's
/// (`docs/probes/stage-6b-flip-instrument.patch` makes every trap non-fatal): all
/// three failure arms then exit successfully.
@Test func aRootFieldWithNoLoweringTrapsInAProductionWindow() async throws {
    // minHeight on an auto axis.
    let minimum = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            drawInAProductionProposalWindow {
                Box { Box().width(Pixels(10)).height(Pixels(10)) }.width(Pixels(100)).minHeight(Pixels(50))
            }
        }
    }
    let minimumErr = String(decoding: minimum?.standardErrorContent ?? [], as: UTF8.self)
    #expect(minimumErr.contains("box.minSize.unconsumed has no proposal lowering"), "aborted, but not at the root's auto-axis minimum:\n\(minimumErr)")
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            drawInAProductionProposalWindow {
                Box { Box().width(Pixels(10)).height(Pixels(10)) }.width(Pixels(100))
            }
        }
    }

    // A root margin.
    let margin = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            drawInAProductionProposalWindow {
                Box { Box().width(Pixels(10)).height(Pixels(10)) }
                    .width(Pixels(100)).height(Pixels(100)).margin(Pixels(4))
            }
        }
    }
    let marginErr = String(decoding: margin?.standardErrorContent ?? [], as: UTF8.self)
    #expect(marginErr.contains("box.margin.unconsumed has no proposal lowering"), "aborted, but not at the root's margin:\n\(marginErr)")
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            drawInAProductionProposalWindow {
                Box { Box().width(Pixels(10)).height(Pixels(10)) }.width(Pixels(100)).height(Pixels(100))
            }
        }
    }

    // A percentage maxWidth on a declared width.
    let percent = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            drawInAProductionProposalWindow {
                var style = Style()
                style.size = Size(width: .length(.pixels(Pixels(100))), height: .length(.pixels(Pixels(100))))
                style.maxSize.width = .length(.percent(0.5))
                return Box(style: style) { Box().width(Pixels(10)).height(Pixels(10)) }
            }
        }
    }
    let percentErr = String(decoding: percent?.standardErrorContent ?? [], as: UTF8.self)
    #expect(percentErr.contains("box.maxSize.unconsumed has no proposal lowering"), "aborted, but not at the root's percentage maximum:\n\(percentErr)")
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            drawInAProductionProposalWindow {
                var style = Style()
                style.size = Size(width: .length(.pixels(Pixels(100))), height: .length(.pixels(Pixels(100))))
                style.maxSize.width = .length(.pixels(Pixels(50)))
                return Box(style: style) { Box().width(Pixels(10)).height(Pixels(10)) }
            }
        }
    }
}
