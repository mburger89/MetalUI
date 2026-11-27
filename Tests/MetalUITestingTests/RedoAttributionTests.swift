import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Record 431 (`RK-AP`): a redo names its cause and its quarantine on the trace, and every miss that says `quarantine` names who holds it.
// The fixtures are Alloy's transcript (`ChromeTranscriptFixture.swift`) and the same rows with a content-shaped button, whose hitbox refuses every layout move.

private let raVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and redoes more: the redo counts this test pins are not its to read"

/// The trace lines of `steps` streamed words of a transcript, and the work of each step.
@MainActor private func raRun(_ pair: RPPair<some Element>, steps: Int, compare: Bool = false) async throws -> (lines: [String], frames: [FrameWork]) {
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    var frames: [FrameWork] = []
    for step in 0..<steps {
        frames.append(await ctStep(pair).reduce(FrameWork(), +))
        if compare { try pair.compare("step \(step)") }
    }
    return (lines, frames)
}

/// Every redo the transcript makes has a line that names the site that could not replay and what the decisions found, and a line for the quarantine it
/// earned; every miss that says `quarantine` names who holds it. Mutations: the `requestRedo` line removed, the cause left empty, `quarantineOwner` answering `none`.
@Test(.enabled(if: !rsVerifying, raVerifyingNote)) @MainActor
func everyRedoNamesItsCauseAndItsQuarantine() async throws {
    let pair = try ctPair()
    let (lines, frames) = try await raRun(pair, steps: 40)
    let redos = frames.map(\.retainedRedos).reduce(0, +)
    let requested = lines.filter { $0.hasPrefix("retained redo requested") }
    let quarantined = lines.filter { $0.hasPrefix("retained redo quarantine") }
    try #require(redos >= 1, "the fixture redoes")
    #expect(requested.count >= redos, "a line for each redo's cause: \(requested.count) for \(redos)")
    for line in requested {
        #expect(["at graftedPrepaint", "at paintPlain", "at paintRecord"].contains { line.contains($0) }, "\(line)")
        #expect(!line.contains("prepaint [] paint [none]"), "no cause named: \(line)")
    }
    #expect(quarantined.count >= redos, "a quarantine line for each redo")
    for line in lines where line.hasPrefix("retained prepaint miss") && line.contains("quarantine") {
        #expect(line.contains("quarantinedBy:") && !line.contains("quarantinedBy: none"), "\(line)")
    }
}

/// The lines are built only while something listens (`RK-AO`'s discipline): with no sink, 40 streamed words with redos build no line and render no path.
/// Mutation: the `requestRedo` or `noteRedo` line built outside `emit`'s autoclosure.
@Test(.enabled(if: !rsVerifying && !retainedTraces, raVerifyingNote)) @MainActor
func theRedoLinesAreBuiltOnlyWhileSomethingListens() async throws {
    let pair = try ctPair()
    RetainedTrace.linesBuilt = 0; RetainedTrace.pathsBuilt = 0
    var redos = 0
    for _ in 0..<40 { redos += await ctStep(pair).reduce(FrameWork(), +).retainedRedos }
    try #require(redos >= 1, "the fixture redoes")
    #expect(RetainedTrace.linesBuilt == 0 && RetainedTrace.pathsBuilt == 0, "lines \(RetainedTrace.linesBuilt), paths \(RetainedTrace.pathsBuilt)")
}

/// What the trace found on the transcript (the attribution of record 431): every redo of the chrome transcript is a grafted occurrence whose prepaint
/// could not replay for geometry alone (a hitbox cut by the clip, or a ledger whose clip and offset moved with the row), and every quarantine miss is
/// held by one of those redos. Mutation: a redo of another kind (the shaped fixture's) puts `observed` or a paint cause on a line.
@Test(.enabled(if: !rsVerifying, raVerifyingNote)) @MainActor
func theChromeTranscriptRedoesOnlyForGeometry() async throws {
    let pair = try ctPair()
    let (lines, _) = try await raRun(pair, steps: 40)
    let requested = lines.filter { $0.hasPrefix("retained redo requested") }
    try #require(!requested.isEmpty)
    #expect(requested.allSatisfy { $0.contains("at graftedPrepaint") && !$0.contains("observed") && !$0.contains("quarantine") }, "\(requested.first ?? "")")
}

/// The same rows with a content-shaped button: every grafted row refuses every layout move, and the trace names both causes the paint and prepaint sides give
/// (`hitboxShape` for the ledger, `innerScope` for the paint record behind `recordCannotMove`). The redos are spread by the backoff (3 frames in 40 words,
/// never two running) and the frames equal a fresh frame's. Mutation: a cause left off the line (the last expectation).
@Test(.enabled(if: !rsVerifying, raVerifyingNote)) @MainActor
func aRowThatAlwaysRefusesNamesItsCausesAndRedoesNoMoreOftenThanTheBackoffAllows() async throws {
    let pair = try raShapedPair()
    let (lines, frames) = try await raRun(pair, steps: 40, compare: true)
    let redoFrames = frames.enumerated().filter { $0.element.retainedRedos > 0 }.map(\.offset)
    try #require(!redoFrames.isEmpty, "the fixture redoes")
    #expect(redoFrames.count <= 3, "redo frames \(redoFrames)")
    #expect(!zip(redoFrames, redoFrames.dropFirst()).contains { $1 - $0 < 2 }, "a redo in two frames running: \(redoFrames)")
    #expect(frames.allSatisfy { $0.retainedRedoEscalations == 0 })
    let causes = Set(lines.filter { $0.hasPrefix("retained redo requested") }.compactMap { $0.components(separatedBy: " because ").last })
    #expect(causes.contains { $0.contains("hitboxShape") } && causes.contains { $0.contains("innerScope") }, "causes: \(causes)")
}

// MARK: The shaped fixture

/// A row whose button has a content shape: its hitbox refuses every layout move by name.
struct RAShapedRow: Component, @MainActor Equatable {
    let id: Int
    let text: String
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 6) {
            CTParagraph(text: text).equatable()
            Button("Allow") {}.contentShape(RoundedRectangle(cornerRadius: Pixels(4)))
        }
        .padding(Edges(all: Pixels(8)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.18))
        .cornerRadius(Pixels(8))
    }
}

struct RAShapedRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        let rows = (0..<50).map { RAShapedRow(id: $0, text: "row \($0) some words that wrap onto more than one line in a narrow column") }
            + [RAShapedRow(id: 999, text: ctText(Int(side.inputs.offset)))]
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                    ForEach(rows, id: \.id) { row in row.equatable() }
                }.padding(g49Inset)
            }
            .defaultScrollAnchor(.bottom).contentMargins(.bottom, Pixels(40), for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor private func raShapedPair() throws -> RPPair<some Element> {
    try RPPair(size: sz(420, 600), scale: 2, warm: 8, accessibility: false) { side in VStack(spacing: 0) { RAShapedRoot(side: side) } }
}
