import MetalUI
import MetalUIMarkdown
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Streaming a reply into a transcript (`BM-E`, `BM-H`, record 235): the work a token costs, counted. Every figure is
// work (content evaluations, bytes shaped, bytes parsed), never time, and equal for 10 and for 200 replies.

private let verifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

/// One token appended to the last reply of a transcript of `replies` replies of 20 blocks each: the frame's work, the
/// bytes the text system measured, and the accessibility id of the last paragraph before and after.
@MainActor private func streamOneToken(replies: Int, rich: Bool) throws -> (work: FrameWork, bytes: Int, strings: [String], before: AccessibilityNodeID, after: AccessibilityNodeID) {
    let meter = MarkdownMeterTextSystem(harnessTextSystem())
    let model = MarkdownTranscriptModel(documents: (0..<replies).map { MarkdownDocument(parsing: markdownReply($0 == replies - 1 ? 777 : $0, rich: rich)) })
    let window = try markdownTranscript(model, text: { meter })
    markdownSettle(window, frames: 10)
    func lastParagraph() throws -> TestElement {
        try #require(try window.elements(role: .staticText).first { ($0.value ?? "").hasPrefix("The last paragraph of reply 777") },
                     "the last paragraph is on screen")
    }
    let before = try lastParagraph().id
    window.resetFrameWork(); meter.reset()
    model.documents[replies - 1].append(" streaming")
    window.window.setNeedsRedraw(); window.tick()
    let work = markdownTotal(window.frameWork)
    let after = try lastParagraph()
    #expect((after.value ?? "").hasSuffix("still streaming"), "the token reached the screen: \(after.value ?? "-")")
    return (work, meter.measuredBytes, meter.measuredStrings, before, after.id)
}

/// **BM-E, test 13.** A token appended to the last paragraph of the last of N replies costs the same for N = 10 and
/// N = 200: the `MarkdownView` of that reply and the one block that changed evaluate their content (2), every other
/// block and every other reply is skipped, and the block keeps its accessibility identity. The text system shapes the
/// changed paragraph (twice: its ideal and its wrapped measure) and, **when the reply has no inline markup, nothing
/// else**; a reply whose unchanged blocks hold rich text re-measures those blocks too, because a rich `Text` has no
/// layout-memo key (`IV-`) and taints the reply's ancestors: counted, equal for both N, carried (`BM-J`). Mutations:
/// `.equatable()` dropped from the blocks in `MarkdownView` (every block of the reply evaluates); block ids hashed
/// from the text (the last paragraph's identity moves per token).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aTokenCostsTheLastBlockWhateverTheTranscriptHolds() throws {
    let paragraph = "The last paragraph of reply 777 is still streaming".utf8.count
    for rich in [false, true] {
        let small = try streamOneToken(replies: 10, rich: rich)
        let large = try streamOneToken(replies: 200, rich: rich)
        #expect(small.work.contentEvaluations == 2, "MarkdownView + the one block: \(small.work.contentEvaluations)")
        #expect(large.work.contentEvaluations == small.work.contentEvaluations, "\(large.work.contentEvaluations) at 200 replies")
        #expect(large.bytes == small.bytes, "bytes shaped (rich \(rich)): \(small.bytes) at 10 replies, \(large.bytes) at 200")
        #expect(small.before == small.after && large.before == large.after, "the last block keeps its identity across tokens")
        if rich {
            #expect(large.bytes == 2_200, "the rich blocks of the changed reply are measured again: \(large.bytes) bytes")
        } else {
            #expect(large.bytes == 2 * paragraph, "only the changed paragraph is shaped: \(large.bytes) bytes, paragraph \(paragraph)")
        }
    }
}

/// **BM-H, test 14.** Appending to an open fence shapes the last chunk and no more: a fence of 69 and one of 485 lines
/// (the last chunk is 5 lines in both) shape the same bytes, no measured string is longer than 32 lines, and the
/// highlighter is asked once for the changed fence. Mutation: one `Text` per fence (a measured string of 485 lines).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func appendingToAnOpenFenceShapesOneChunk() throws {
    func lines(_ s: String) -> Int { s.split(separator: "\n", omittingEmptySubsequences: false).count }
    var results: [(bytes: Int, longest: Int)] = []
    for count in [69, 485] {
        let meter = MarkdownMeterTextSystem(harnessTextSystem())
        var source = "```swift\n"
        for _ in 0..<count { source += "let value = x\n" }
        source.removeLast()
        let model = MarkdownTranscriptModel(documents: [MarkdownDocument(parsing: source)])
        let window = try markdownTranscript(model, text: { meter }, size: sz(420, 300))
        markdownSettle(window, frames: 8)
        meter.reset()
        model.documents[0].append(" // t")
        markdownSettle(window, frames: 1)
        results.append((meter.measuredBytes, meter.measuredStrings.map(lines).max() ?? 0))
    }
    #expect(results[0].bytes > 0, "the token was shaped")
    #expect(results[0].bytes == results[1].bytes, "69 lines and 485 lines shape the same bytes: \(results)")
    #expect(results[1].longest <= 32, "no measured string is longer than a chunk: \(results[1].longest) lines")
}

/// **BM-E, test 15.** A settled transcript's unchanged blocks replay: frames with nothing changed are retained hits and
/// the ineligible count does not grow (a code fence's and a table's horizontal scrollers are settled, `RW-`). Mutation:
/// the theme carried in a custom `EnvironmentKey` (`SB-`: a subtree under one is ineligible; `retainedIneligible` grows).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aSettledTranscriptReplaysItsUnchangedBlocks() throws {
    let model = MarkdownTranscriptModel(documents: (0..<3).map { MarkdownDocument(parsing: markdownReply($0, blocks: 10)) })
    let window = try markdownTranscript(model, size: sz(420, 900))
    markdownSettle(window, frames: 10)
    window.resetFrameWork()
    markdownSettle(window, frames: 4)
    let work = markdownTotal(window.frameWork)
    #expect(work.retainedHits > 0, "hits \(work.retainedHits), misses \(work.retainedMisses)")
    #expect(work.retainedIneligible == 0, "\(work.retainedIneligibleReasons)")
    #expect(work.retainedPrepaintIneligible == 0 && work.retainedGraftIneligible == 0,
            "\(work.retainedPrepaintIneligible) prepaint, \(work.retainedGraftIneligible) graft")
    #expect(work.contentEvaluations == 0 && work.contentRefusals == 0, "nothing re-evaluates or is refused: \(work.contentEvaluations), \(work.contentRefusals)")
}

@Observable @MainActor final class MarkdownSourceModel { var text = "" }

/// **BM-E, test 16.** `MarkdownView(String)` grown by appended text parses only the tail: the bytes scanned are the
/// tail plus the token, the memo compares the old source once (`bytesCompared`), and the output is the same as a fresh
/// parse. A replaced string re-parses fully and shows only its own blocks. Mutation: the prefix compare skipped (a
/// longer replacement is taken for an extension and the old blocks stay on screen).
@Test @MainActor func aSourceStringGrownByPrefixAppendsAndAReplacementReparses() throws {
    let model = MarkdownSourceModel()
    var source = ""
    for n in 0..<60 { source += "Paragraph number \(n) of the reply.\n\n" }
    source += "Last"
    model.text = source
    let window = try harnessWindow(size: sz(400, 3000)) {
        VStack(alignment: .leading, spacing: Pixels(0)) { MarkdownView(model.text).equatable() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    markdownSettle(window, frames: 4)
    func texts() throws -> [String] {
        try window.elements(where: { $0.role == .staticText || $0.role == .heading }).compactMap { $0.value ?? $0.label }
    }
    #expect(try texts().count == 61)
    MarkdownParseStats.reset()
    model.text += " word"
    markdownSettle(window, frames: 4)
    #expect(try texts().last == "Last word")
    #expect(MarkdownParseStats.bytesScanned <= "Last word".utf8.count + 4, "scanned the tail and the token: \(MarkdownParseStats.bytesScanned)")
    #expect(MarkdownParseStats.bytesCompared == source.utf8.count, "the old source compared once: \(MarkdownParseStats.bytesCompared)")
    // A replacement that is longer but not an extension.
    let replacement = "# Fresh start\n\nA different reply that is longer than the earlier one only in its first letters, not its tail. " +
        String(repeating: "More text. ", count: 600)
    model.text = replacement
    markdownSettle(window, frames: 4)
    let after = try texts()
    #expect(after.count == 2 && after[0] == "Fresh start" && !after.contains { $0.hasPrefix("Paragraph number") },
            "only the replacement is shown: \(after.count) texts, first \(after.first ?? "-")")
    let fresh = MarkdownDocument(parsing: replacement).blocks
    #expect(fresh.count == 2)
}

/// **Stop condition (plan), BM2, `BM-H`.** A horizontal scroller inside the vertical transcript **takes a vertical wheel
/// for itself** (measured: the wheel over a fence, long lines or not, scrolls nothing). So the default theme has no
/// scroller: `codeWraps` is true, and a vertical wheel over the fence scrolls the transcript. With `codeWraps = false`
/// the fence scrolls sideways under a horizontal wheel and **swallows the vertical one: pinned wrong on purpose, the
/// carried limitation**; a framework change that passes the wheel on would redden that arm and is a fix. In both arms
/// a transcript wheeled back to its end follows the next tokens again (`defaultScrollAnchor(.bottom)` is unharmed).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aHorizontalCodeScrollerSwallowsTheVerticalWheelSoTheDefaultHasNone() throws {
    var source = "Intro paragraph above the code.\n\n```swift\n"
    source += String(repeating: "let aVeryLongIdentifier = someFunction(argumentOne, argumentTwo, argumentThree, argumentFour)\n", count: 6)
    source += "```\n\n"
    for n in 0..<12 { source += "Filler paragraph number \(n) so that the reply is taller than the window.\n\n" }
    source += "The end is near"
    for wraps in [true, false] {
        let model = MarkdownTranscriptModel(documents: [MarkdownDocument(parsing: source)])
        model.theme.codeWraps = wraps
        let window = try markdownTranscript(model, size: sz(420, 300))
        markdownSettle(window, frames: 8)
        func element(_ prefix: String) throws -> TestElement {
            try #require(try window.elements(role: .staticText).first { ($0.value ?? "").hasPrefix(prefix) }, "no \(prefix)")
        }
        let end = try element("The end is near")
        #expect(end.frame.origin.y.value + end.frame.size.height.value == 300, "pinned at the end: \(end.frame)")
        window.scroll(at: pt(200, 8), byDeltaX: 0, deltaY: 100_000)   // over the intro text: to the top
        markdownSettle(window, frames: 6)
        let fence = try element("let aVeryLong")
        let over = pt(60, fence.visibleFrame.origin.y.value + 10)
        let intro0 = try element("Intro paragraph").frame.origin.y.value, x0 = fence.frame.origin.x.value
        window.scroll(at: over, byDeltaX: 0, deltaY: -30)
        markdownSettle(window, frames: 6)
        let moved = try element("Intro paragraph").frame.origin.y.value - intro0
        #expect(moved == (wraps ? -30 : 0), "wheel over the fence (codeWraps \(wraps)): the transcript moved \(moved)")
        #expect(try element("let aVeryLong").frame.origin.x.value == x0)
        if !wraps {
            window.scroll(at: over, byDeltaX: -50, deltaY: 0)
            markdownSettle(window, frames: 6)
            #expect(try element("let aVeryLong").frame.origin.x.value == x0 - 50, "the horizontal wheel scrolled the fence")
        }
        window.scroll(at: pt(200, 8), byDeltaX: 0, deltaY: -1_000_000)
        markdownSettle(window, frames: 6)
        for _ in 0..<5 {
            model.documents[0].append(" token token token token token token token token token")
            markdownSettle(window, frames: 4)
            let last = try element("The end is near")
            #expect(last.frame.origin.y.value + last.frame.size.height.value == 300, "followed (codeWraps \(wraps)): \(last.frame)")
        }
    }
}
