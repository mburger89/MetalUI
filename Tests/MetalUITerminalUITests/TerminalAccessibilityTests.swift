import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// Terminal phase 5.6 (`TRM-BH`): the view's accessibility node, headless on the portable text system. The value is the
// viewport's rows and is re-read after surface-only frames, so output keeps its 0-build, 0-request cost. Each test
// names the mutation it was shown red against.

extension TermRig {
    /// The terminal's text area node, read fresh from the window's last published tree.
    func textArea() throws -> TestElement {
        let nodes = try window.elements(role: .textArea)
        return try #require(nodes.first, "no text area node")
    }
    func areaValue() throws -> String { try textArea().value ?? "" }
}

/// **1** (`REQUIRED`, cost) With a client present, output frames stay surface-only: 0 builds, 0 element requests, no tree
/// build; the node's value changes through the refresh alone. Mutation: the wake calls `setNeedsRedraw` or the refresh
/// is replaced by a rebuild (builds 1).
@MainActor @Test func outputFramesStayZeroBuildWithAccessibility() async throws {
    let rig = try TermRig()
    await rig.settle()
    _ = try rig.textArea()   // the node exists before any output
    let a11y = rig.window.window.accessibility
    let builds = a11y.buildCount
    for i in 0..<5 {
        rig.feed("line \(i)\r\n")
        await rig.frame()
        let work = rig.window.lastFrameWork
        #expect(work.builds == 0 && work.elementRequests == 0 && work.surfaceOnlyFrames == 1,
                "frame \(i): \(work.builds) \(work.elementRequests) \(work.surfaceOnlyFrames)")
    }
    #expect(a11y.buildCount == builds, "no accessibility tree was built by output")
    #expect(try rig.areaValue().hasPrefix("line 0\nline 1\nline 2\nline 3\nline 4"), "the client still saw the output")
}

/// **2** The value is the viewport's rows, each with trailing blanks trimmed, joined by newlines; the node is a text area
/// labelled Terminal. Mutation: rows joined without trimming (a row's blanks appear), or the first row dropped.
@MainActor @Test func accessibilityValueIsTheVisibleRows() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("hello   \r\n  world  \r\n\r\nlast")
    await rig.frame()
    let node = try rig.textArea()
    #expect(node.label == "Terminal")
    let lines = try rig.areaValue().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(Array(lines.prefix(4)) == ["hello", "  world", "", "last"], "\(lines.prefix(4))")
    #expect(lines.count == rig.emulator.publishSnapshot().size.rows, "one line per viewport row: \(lines.count)")
    let rest = lines.dropFirst(4)
    #expect(rest.allSatisfy { $0.isEmpty })
}

/// **3** A fresh read after output and an idle run shows the new text. Mutation: the refresh is not called after a
/// surface-only frame (the value stays at the first build's).
@MainActor @Test func accessibilityValueFollowsOutput() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("one")
    await rig.frame()
    #expect(try rig.areaValue().hasPrefix("one"))
    rig.feed("\r\ntwo")
    try await rig.window.runUntilIdle()
    #expect(try rig.areaValue().hasPrefix("one\ntwo"))
    rig.feed("\u{1b}[2J\u{1b}[Hcleared")
    await rig.frame()
    #expect(try rig.areaValue().hasPrefix("cleared\n"))
    let cleared = try rig.areaValue()
    #expect(!cleared.contains("two"))
}

/// **4** The alternate screen exposes the rows it shows, and the primary screen's return. Mutation: the value keeps the
/// rows of the screen the node was built on.
@MainActor @Test func alternateScreenExposesItsRows() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("primary text")
    await rig.frame()
    rig.feed("\u{1b}[?1049h\u{1b}[HALT SCREEN")
    await rig.frame()
    var value = try rig.areaValue()
    #expect(value.hasPrefix("ALT SCREEN") && !value.contains("primary"), "\(value.prefix(30))")
    rig.feed("\u{1b}[?1049l")
    await rig.frame()
    value = try rig.areaValue()
    #expect(value.hasPrefix("primary text") && !value.contains("ALT"), "\(value.prefix(30))")
}

/// **5** With no client nothing is read and no node is published, however much output arrives. Mutation: the declaration
/// is not gated on the collecting flag (reads become nonzero).
@MainActor @Test func noClientReadsNothing() async throws {
    let rig = try TermRig(accessibility: false)
    await rig.settle()
    for i in 0..<5 { rig.feed("x\(i)\r\n"); await rig.frame() }
    #expect(rig.model.accessibilityReads == 0)
    let live = try TermRig()
    await live.settle()
    live.feed("x"); await live.frame()
    #expect(live.model.accessibilityReads > 0)
}

/// **6** A host's `.accessibilityLabel` (the terminal's title) replaces the default label. Mutation: the view's own label
/// wins over the host's.
@MainActor @Test func aHostLabelReplacesTheDefault() async throws {
    let emulator = TerminalEmulator(cols: 80, rows: 24)
    let source = TerminalSnapshotSource(emulator: emulator, queue: .main)
    let window = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300)), textSystem: { portableSystem() }) {
        VStack(spacing: 0) {
            TerminalView(snapshotSource: source, theme: .xterm, accessibilityLabel: "vim notes.txt",
                         onInput: { _ in }, onResize: { _ in }, onLink: { _ in nil })
        }
    }
    window.runsSurfaceDraws = true
    window.tick()
    let area = try #require(try window.elements(role: .textArea).first)
    #expect(area.label == "vim notes.txt", "\(String(describing: area.label))")
}

/// **7** (cost) The steady frame of a view with a client present costs what it costs with none (literals as on master).
/// Mutation: the declaration adds an element request (a wrapper element).
@MainActor @Test func aSteadyFrameCostsTheSameWithOrWithoutAClient() async throws {
    var costs: [FrameWork] = []
    for accessibility in [false, true] {
        let rig = try TermRig(accessibility: accessibility)
        await rig.settle()
        rig.window.window.setNeedsRedraw(); rig.window.tick()
        costs.append(rig.window.lastFrameWork)
    }
    for cost in costs {
        #expect(cost.elementRequests == 2 && cost.builds == 1, "requests \(cost.elementRequests) builds \(cost.builds) hits \(cost.retainedHits) misses \(cost.retainedMisses) ineligible \(cost.retainedIneligible)")
    }
    #expect(costs[0].retainedHits == costs[1].retainedHits && costs[0].retainedMisses == costs[1].retainedMisses
            && costs[0].retainedIneligible == costs[1].retainedIneligible)
}

/// **8** A frame in which the terminal's subtree replays its prepaint (an unrelated sibling changed, the terminal neither
/// focused nor hovered) registers the live value again from the ledger, beside the re-appended node. The window's entry is
/// forgotten first (as a refresh forgets one whose node the published tree lacked), so only the replay can restore it: the
/// next surface-only frame then refreshes the node. Mutation: drop the ledger capture (`ledger.liveValues` is never filled
/// or replayed) - the entry stays forgotten and the value stays at what the replayed frame read.
@MainActor @Test func aRetainedPrepaintReplayKeepsTheLiveValue() async throws {
    let emulator = TerminalEmulator(cols: 80, rows: 24)
    let source = TerminalSnapshotSource(emulator: emulator, queue: .main)
    let window = try TestWindow(size: Size(width: Pixels(400), height: Pixels(340)),
                                options: .init(accessibilityClientActive: true), textSystem: { portableSystem() }) {
        VStack(spacing: 0) {
            SiblingCounter()
            TerminalView(snapshotSource: source, theme: .xterm, onInput: { _ in }, onResize: { _ in }, onLink: { _ in nil })
        }
    }
    window.runsSurfaceDraws = true
    func pump() async { for _ in 0..<20 { await Task.yield() } }
    await pump()
    for _ in 0..<3 { window.tick(); window.advance(by: 0.05); await pump() }
    window.window.focus(nil)   // a focused or hovered terminal never replays prepaint (`RK-E`)
    window.tick()
    func clickSibling() throws {
        let button = try #require(try window.elements(role: .button).first)
        window.resetFrameWork()
        try window.click(button)
        window.tick()
    }
    try clickSibling()   // the first frame after a focus change builds and records the ledger
    try clickSibling()
    window.window.accessibility.forgetLiveValuesForTesting()
    try clickSibling()
    let replays = window.lastFrameWork.retainedPrepaintHits
    #expect(replays > 0, "the terminal's prepaint replayed on a sibling-only frame: \(replays)")
    Array("after replay".utf8).withUnsafeBytes { source.feed($0) }
    await pump()
    window.advance(by: 0.05)
    await pump()
    let area = try #require(try window.elements(role: .textArea).first)
    #expect((area.value ?? "").hasPrefix("after replay"), "\(String(describing: area.value?.prefix(30)))")
}

private struct SiblingCounter: Component {
    @State private var count = 0
    var content: some ProposalElementGroup {
        VStack(spacing: 0) { Button("n\(count)") { count += 1 } }
    }
}
