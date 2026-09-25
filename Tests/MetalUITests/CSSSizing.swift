import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 8 (spec `docs/superpowers/specs/2026-09-24-engine-stage-8-design.md`
// §4, §5.2 class K; ruling `LR-EW`).
//
// **Class K's spelling.** Stage 8 deprecates the eight `StyledElement` sizing
// modifiers (`LR-ER` item 1, `LR-EU`). A test whose subject is the lowering of a
// legacy `Style` field (K1) or a registration site's own behaviour (K2) must keep
// writing that field on that element — `.frame` would wrap it in a
// `ModifiedElement` layer and change the subject or move the pin unseen (record
// §50 §5). These helpers are that write, undeprecated and visible to this test
// target alone — stage 6a's precedent of the internal, undeprecated registrar
// (`LR-CV`). Each is ONE line with **the same closure body** as the public
// modifier it stands in for (`Box.swift`), so identity, answers and sites are
// unchanged by construction; `theCSSSizingHelpersWriteWhatTheDeprecatedModifiersWrite`
// pins it. Stage 8 wrote that they die with `Style.size`/`minSize`/`maxSize` at
// stage 10 (its spec §9); those fields survive stage 10 as the lowering's inputs
// (`LR-FM` item 2), so the helpers stay, and the reason above still holds
// (`LR-FO` item 6).

extension StyledElement {
    func cssWidth(_ points: Pixels) -> Self { modifying { $0.size.width = .length(.pixels(points)) } }
    func cssHeight(_ points: Pixels) -> Self { modifying { $0.size.height = .length(.pixels(points)) } }
    func cssMinWidth(_ points: Pixels) -> Self { modifying { $0.minSize.width = .length(.pixels(points)) } }
    func cssMaxWidth(_ points: Pixels) -> Self { modifying { $0.maxSize.width = .length(.pixels(points)) } }
    func cssMinHeight(_ points: Pixels) -> Self { modifying { $0.minSize.height = .length(.pixels(points)) } }
    func cssMaxHeight(_ points: Pixels) -> Self { modifying { $0.maxSize.height = .length(.pixels(points)) } }
    func cssWidth(fraction: Float) -> Self { modifying { $0.size.width = .length(.percent(fraction)) } }
    func cssHeight(fraction: Float) -> Self { modifying { $0.size.height = .length(.percent(fraction)) } }
}

// MARK: - Class D: the deprecated spelling, called without a warning

/// Class D's instrument (spec §5.2): a test whose subject is the deprecated
/// sizing modifier itself calls it inside a `@available(*, deprecated, …)`
/// **protocol witness** reached through its requirement, which warns nothing
/// (`docs/probes/swift-deprecated-witness-silence.sh`, stage 6a's `LR-CV`). The
/// requirement is undeprecated; each conformer's witness carries the attribute.
@MainActor
protocol DeprecatedSpelling {
    associatedtype Output
    func spelled() -> Output
}

/// Reaches a `DeprecatedSpelling`'s witness through the requirement — the call
/// site that does not warn.
@MainActor
func oldSpelling<S: DeprecatedSpelling>(_ spelling: S) -> S.Output { spelling.spelled() }

/// The eight deprecated modifiers on a `Box()`, each with a value distinct from
/// every other entry, so a helper that writes the wrong field or the wrong axis
/// differs from its row.
private struct EightDeprecatedSizingWrites: DeprecatedSpelling {
    @available(*, deprecated, message: "calls the deprecated sizing modifiers on purpose: they are the subject of theCSSSizingHelpersWriteWhatTheDeprecatedModifiersWrite (stage 8, LR-EW class D)")
    func spelled() -> [(String, Style)] {
        [("width", Box().width(Pixels(11)).style),
         ("height", Box().height(Pixels(12)).style),
         ("minWidth", Box().minWidth(Pixels(13)).style),
         ("maxWidth", Box().maxWidth(Pixels(14)).style),
         ("minHeight", Box().minHeight(Pixels(15)).style),
         ("maxHeight", Box().maxHeight(Pixels(16)).style),
         ("width(fraction:)", Box().width(fraction: 0.17).style),
         ("height(fraction:)", Box().height(fraction: 0.18).style)]
    }
}

/// N1.1 (stage 8 spec §6, lane 1). Each `css*` helper writes exactly the `Style`
/// its deprecated modifier writes — the promise that makes class K "unchanged by
/// construction". Values are distinct per row, so a helper writing the other
/// axis, or `maxSize` for `minSize`, differs from its row; and the table is also
/// checked row-against-row to be pairwise distinct, so the comparison can fail.
///
/// Red before: the helpers did not exist (build error). Mutation **M1g**
/// (`cssMinHeight` writes `maxSize.height`) reddens this test and no other
/// (record §50, lane 1).
@Test @MainActor func theCSSSizingHelpersWriteWhatTheDeprecatedModifiersWrite() throws {
    let old = oldSpelling(EightDeprecatedSizingWrites())
    let new: [(String, Style)] = [
        ("width", Box().cssWidth(Pixels(11)).style),
        ("height", Box().cssHeight(Pixels(12)).style),
        ("minWidth", Box().cssMinWidth(Pixels(13)).style),
        ("maxWidth", Box().cssMaxWidth(Pixels(14)).style),
        ("minHeight", Box().cssMinHeight(Pixels(15)).style),
        ("maxHeight", Box().cssMaxHeight(Pixels(16)).style),
        ("width(fraction:)", Box().cssWidth(fraction: 0.17).style),
        ("height(fraction:)", Box().cssHeight(fraction: 0.18).style),
    ]
    try #require(old.count == 8)
    try #require(new.count == 8)
    // The arms must be able to disagree: every row differs from an untouched
    // `Box()` and from every other row.
    for i in 0..<8 {
        #expect(old[i].1 != Box().style, "\(old[i].0) wrote nothing")
        for j in 0..<8 where j != i { #expect(old[i].1 != old[j].1, "\(old[i].0) == \(old[j].0)") }
    }
    for (o, n) in zip(old, new) {
        #expect(o.0 == n.0)
        #expect(o.1 == n.1, "css\(n.0) writes a different Style from \(o.0)")
    }
}
