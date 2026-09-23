import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 1, lane 1 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
// §6 lane 1; rulings LR-B, LR-C, LR-D): the per-frame layout authority, every legacy
// registration site's own check, the element bounds log, and the differential
// harness (`LayoutDifferential.swift`).
//
// **Red before**: every test here failed to compile before lane 1's
// implementation (record §18, lane 1). The mutation each must redden is named in
// its doc comment and in spec §6's lane-1 table; the record names what each
// mutation actually reddened.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

/// A custom element outside the stage-1 lowering table: it registers through the
/// public legacy `requestNode`, which reports `customElement` (ruling LR-C).
///
/// **Spelled with the deprecated registrar on purpose since stage 6a** (record
/// §30, disposition Dep, `LR-CV`): the public registrar is its subject, and a
/// deprecated witness is not diagnosed at the call site.
private struct CustomNodeElement: Element {
    @available(*, deprecated, message: "spelled with the deprecated legacy registrar on purpose: it is the subject of aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority and everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn, which read the customElement report (stage 6a, LR-CV)")
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNode(style: Style(), children: []), ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// As `CustomNodeElement`, through the public legacy `requestLeaf`.
private struct CustomLeafElement: Element {
    @available(*, deprecated, message: "spelled with the deprecated legacy registrar on purpose: it is the subject of aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority and everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn, which read the customElement report (stage 6a, LR-CV)")
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestLeaf(style: Style()) { _, _ in SizeD(width: 10, height: 10) }, ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// A site that forgot its own check: it calls `Frame`'s internal legacy
/// registrar directly, so under the proposal authority only `Frame`'s backstop
/// stands between it and a legacy node (ruling LR-C). `leaf` picks
/// `requestLeaf` over `requestNode`; `registered` receives the node it got back.
private struct BackstopBypassElement: Element {
    var leaf = false
    var registered: (@MainActor (LayoutNodeID) -> Void)? = nil
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        let node = leaf
            ? pass.frame.requestLeaf(style: Style()) { _, _ in SizeD(width: 10, height: 10) }
            : pass.frame.requestNode(style: Style(), children: [])
        registered?(node)
        return (node, ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// A `Component` over proposal content, so its members register native nodes
/// under either authority and a caller's `.width`/`.padding` reaches
/// `StyledComponent`'s amend/wrap with nothing legacy inside it.
private struct ProposalProbeComponent: Component, ProposalElementGroup {
    var content: some ProposalElementGroup { Rectangle(width: Pixels(10), height: Pixels(10)) }
}

private struct ProbeItem: Identifiable, Sendable { let id: Int }

private func probeItems(_ n: Int) -> [ProbeItem] { (0..<n).map(ProbeItem.init) }

/// Logs what `ProbeLeaf.onLayout` saw, one entry per frame built.
@MainActor private final class AuthorityLog { var values: [Bool] = [] }

private func field(_ site: LoweringSite, _ name: String) -> UnlowerableField {
    UnlowerableField(site: site, field: name)
}

/// The proposal frame's diagnostics for `make()` inside the harness root.
@MainActor
private func diagnostics<C: ElementGroup>(@ElementBuilder _ make: @MainActor () -> C) -> [UnlowerableField] {
    LayoutDifferential.render(authority: .proposal, width: 100, height: 100, make).unlowerableFields
}

// MARK: - 1.1, 1.2 — the authority

/// **1.1.** Both defaults are `.legacy` (ruling LR-B).
///
/// **No mutation is claimed** (critic round 1 finding 13): changing either
/// default traps the suite's first legacy frame and truncates the run, which no
/// single test can report. The default is pinned by the whole suite's printed
/// count, read per CLAUDE.md.
@MainActor
@Test func aFrameAndAWindowDefaultToTheLegacyAuthority() throws {
    let frame = Frame(contentSize: Size(width: px(10), height: px(10)), scaleFactor: 1)
    #expect(frame.layoutAuthority == .legacy)
    #expect(frame.reportsUnlowerableFields == false)
    #expect(frame.recordsElementBounds == false)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device) { ProbeLeaf(width: 10, height: 10) }
    #expect(window.layoutAuthority == .legacy)
}

/// **1.2.** A `Window` builds each frame under its `layoutAuthority`, and a write
/// marks the window dirty. A `ProbeLeaf` root logs `pass.lowersToProposal`.
///
/// Mutation that must redden it: **M1b**, `Window` builds its `Frame` without
/// passing the authority.
@MainActor
@Test func aWindowBuildsEveryFrameUnderItsLayoutAuthority() throws {
    let log = AuthorityLog()
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device) {
        ProbeLeaf(width: 10, height: 10, onLayout: { log.values.append($0) })
    }
    window.drawFrameIfNeeded()
    #expect(window.needsRedraw == false)
    window.layoutAuthority = .proposal
    #expect(window.needsRedraw == true, "a write to layoutAuthority must mark the window dirty")
    window.drawFrameIfNeeded()
    window.layoutAuthority = .legacy
    window.drawFrameIfNeeded()
    #expect(log.values == [false, true, false])
}

// MARK: - 1.3–1.5 — every site's own check

/// **1.3** (exit test). A custom element's public legacy registrars trap under
/// the proposal authority, naming `customElement` and the registrar (ruling LR-C).
///
/// Mutation that must redden it: **M1c**, the public forwarder's check removed
/// (the message becomes the internal registrar's site-less one).
@Test func aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority() async {
    let node = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = CustomNodeElement()
            Frame(contentSize: Size(width: Pixels(50), height: Pixels(50)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
        }
    }
    let nodeErr = String(decoding: node?.standardErrorContent ?? [], as: UTF8.self)
    #expect(nodeErr.contains("customElement.requestNode has no proposal lowering"),
            "aborted, but not at the custom element's requestNode check:\n\(nodeErr)")

    let leaf = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = CustomLeafElement()
            Frame(contentSize: Size(width: Pixels(50), height: Pixels(50)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
        }
    }
    let leafErr = String(decoding: leaf?.standardErrorContent ?? [], as: UTF8.self)
    #expect(leafErr.contains("customElement.requestLeaf has no proposal lowering"),
            "aborted, but not at the custom element's requestLeaf check:\n\(leafErr)")
}

/// **1.4** (exit test). A modified `Component` in a **production** proposal
/// frame completes — `EXIT_SUCCESS` and an empty stderr — where before stage
/// 3's lane 4 it aborted on `component.amend` (`LR-BO`). Both ops, in both
/// orders, in one frame.
///
/// **Why it is a child process.** `Frame(…, layoutAuthority: .proposal)`
/// without `reportsUnlowerableFields` traps rather than reports, so a
/// regression here ends the whole run with no summary line (spec §6). In a
/// child it reddens this test by name instead.
///
/// Mutation that must redden it: **M4a′**, either op's lowered branch put back
/// to `noteUnlowerable` (the child aborts again).
///
/// **This test has lost two arms to two stages, and its name now names the one
/// that survives.**
///
/// - **Stage 3, lane 1 added a `ScrollView` arm and lane 2 retired it** (spec
///   §6 lanes 1 and 2, `LR-BI`). That arm ran a proposal-authority **`Window`**
///   over a plain `ScrollView` and required it to abort, because `Window` never
///   sets `reportsUnlowerableFields` — `Window.swift`'s `Frame(...)` call
///   passes `layoutAuthority` and `recordsElementBounds` and nothing else — so
///   `noteUnlowerable` takes its `preconditionFailure` branch and the process
///   ends with no summary line and no list of what failed. That is why lane 3
///   could not take a red-before by running the scroll suites under the
///   proposal authority.
/// - **Stage 4, lane 2 retired the `List` arm the same way** (§4.2(d),
///   `LR-BQ`). It required `ScrollView { List }` to abort with
///   `list.noLowering has no proposal lowering` and **not** to mention `box.`,
///   which pinned that the site's own check ran before the `Box` it builds.
///   `List` lowers now, so that abort cannot happen; its replacement is
///   `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape` and
///   `theListSiteReportsNothingAndItsRowsItemFieldsAreLowered` in
///   `ListLoweringTests.swift`. The general claim the arm carried — that a site
///   that skips its own check is caught rather than lowering silently — is
///   `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop`'s, below.
@Test func aComponentAmendDoesNotTrapUnderTheProposalAuthority() async {
    let amend = await #expect(processExitsWith: .success,
                              observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            // Both ops, in both orders, in one production frame.
            var root = DifferentialRoot(width: 100, height: 100) {
                ProposalProbeComponent().padding(Pixels(4)).width(Pixels(70))
                ProposalProbeComponent().width(Pixels(70)).padding(Pixels(4))
            }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
            FileHandle.standardOutput.write(Data("AMEND-BUILT\n".utf8))
        }
    }
    let amendOut = String(decoding: amend?.standardOutputContent ?? [], as: UTF8.self)
    let amendErr = String(decoding: amend?.standardErrorContent ?? [], as: UTF8.self)
    #expect(amendOut.contains("AMEND-BUILT\n"),
            "the production proposal frame did not finish:\nstdout \(amendOut)\nstderr \(amendErr)")
    #expect(!amendErr.contains("has no proposal lowering"),
            "a component op still reports under the proposal authority:\n\(amendErr)")
    #expect(!amendErr.contains("setStyle on a native layout node"),
            "the amend reached SA-G's setStyle precondition:\n\(amendErr)")
}

/// **1.5.** With diagnostics on, every legacy site reports `(site, field)` by
/// itself and the frame completes. In lane 1 every site reports its site-level
/// entry; lanes 2–4 replace `box`, `stack`, `text` and `modifierLayer` with
/// field-level entries (spec §6).
///
/// **Lane 2** lowers a childless `Box` and a `Text`, so their arms carry a field
/// the leaf table reports (`flexGrow`) and still name their own site; the
/// `ModifiedElement` arms' `Box` lowers and reports nothing; `List`'s spacer is a
/// childless `Box` declaring `flexShrink: 0` (`box.flexShrink`).
///
/// **Lane 3** lowers containers, so the zero-row `Box` around the spacer — a
/// column with one child, a declared height and no declared width, where its
/// default `stretch` has no free space to show (ruling LR-E) — reports nothing.
///
/// **Lane 4** lowers `Stack` and both `ModifiedElement` registrars, so their arms
/// declare a field the tables report: the `Stack` `flexGrow`, the outermost layer
/// `flexGrow`, and the inner-layer arm `flexGrow` inside and `margin` outside.
///
/// **Stage 2, lane 1** moves item fields to the parent (ruling LR-AB): under the
/// harness root — a proposal overlay, which consumes no record — `flexGrow` and
/// `margin` report `…unconsumed` after the root returns (ruling LR-AQ). So the
/// `Box`, `Stack`, `Text` and registrar arms declare every-node fields the element
/// still reports itself: `position`, and `inset` on the inner-layer arm's outer
/// layer (inner first, as before).
///
/// **The `Component` amend arm runs in a child process** and prints its entries:
/// in-process, a regression that removes the amend's lowered branch reaches
/// `SA-G`'s `setStyle` precondition and ends the whole run with no summary line
/// (lane-1 verifier, mutation M1d′, re-aimed as M4a′ in lane 4); in a child it
/// reddens this test by name.
///
/// **Stage 3, lane 2** lowers `ScrollView` (`LR-BB`), so its arm stops being a
/// site-level `noLowering` entry and becomes a field-level one like `Box`'s and
/// `Stack`'s. The field is **`flexGrow.weights`**, raised by two scroller
/// children with unequal declared grow factors: `lowerLegacyNode` passes its
/// `site:` to `planLegacyItems` as `parentSite:`, and that is the **only** field
/// `planLegacyItems` raises at the parent's site — every per-child report is
/// raised at `item.site`, the child's own (`LR-BM`). A **plain** `ScrollView`
/// now reports nothing at all, which is 2.1's business, not this test's.
///
/// **Stage 3, lane 4 lowers both `Component` ops, and `component` has no
/// reachable report left** (`LR-BO`). The two `Component` arms therefore assert
/// the **absence** of an entry rather than its name — they are the only two
/// arms of this test that do, and the reason is written down rather than
/// inferred:
///
/// - an **amend** records its frame with `kind: .frameLayer`, which
///   `reportUnconsumedLoweredItems` skips by construction, and its own
///   `planLegacyItems` call has exactly one child, so it can never raise
///   `flexGrow.weights` — the one entry `parentSite:` names (`LR-BM`);
/// - a **wrap** lowers `paddingWrapperStyle`, whose every field is a default
///   except a pixel `padding`, and it too has exactly one child.
///
/// So `LoweringSite.component` survives for `UnlowerableField.owningStage`'s
/// trap message and for whatever field a later stage puts on it, and these two
/// arms are what would notice a regression that made either op report again.
/// The amend arm stays a **child process** for the reason above: in-process a
/// regression that removed the branch entirely reaches `SA-G`'s `setStyle`
/// precondition and ends the whole run with no summary line.
///
/// Mutations that must redden it: **M1e**, `ScrollView`'s record dropped;
/// **M1e′**, `List`'s check moved after its `Box` is built (row boxes appear);
/// **M4a′**, either component op's lowered branch put back to
/// `noteUnlowerable` (the entry reappears);
/// **M2e**, the lowered content node registered with the wrong `site:`.
@MainActor
@Test func everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn() async throws {
    typealias Arm = (name: String, entries: [UnlowerableField], expected: [UnlowerableField])
    var arms: [Arm] = []
    arms.append(("Box", diagnostics { Box().width(px(10)).height(px(10)).position(.relative) },
                 [field(.box, "position")]))
    arms.append(("Stack", diagnostics { Stack { ProbeLeaf(width: 10, height: 10) }.position(.relative) },
                 [field(.stack, "position")]))
    arms.append(("Text", diagnostics { Text("a").position(.relative) }, [field(.text, "position")]))
    arms.append(("ModifiedElement, outermost registrar", diagnostics { Box().padding(px(4)).position(.relative) },
                 [field(.modifierLayer, "position")]))
    // The inner layer declares `position`, the outermost `inset`, so the two
    // registrars' entries are told apart by name and by order (inner first).
    arms.append(("ModifiedElement, inner-layer registrar",
                 diagnostics { Box().padding(px(4)).position(.relative).padding(px(8)).inset(px(3)) },
                 [field(.modifierLayer, "position"), field(.modifierLayer, "inset")]))
    arms.append(("ScrollView", diagnostics {
        ScrollView {
            Box().width(px(10)).height(px(10)).flexGrow(1)
            Box().width(px(10)).height(px(10)).flexGrow(2)
        }
    }, [field(.scrollView, "flexGrow.weights")]))
    // **An ABSENCE arm since stage 4's lane 2** (§4.2(d), `LR-BV` as amended),
    // the third of the three this test has — the two `Component` arms are the
    // others. A `List` lowers now, and `LoweringSite.list`'s one remaining
    // entry, `flexGrow.weights` at `parentSite:`, is **unreachable from outside
    // `List`**: `planLegacyItems`' weights check fires only at two or more
    // distinct non-zero `flexGrow` factors among the records it is handed, every
    // record `ListRows` hands it is a row `Box` carrying `rowStyle` (built in
    // `List.requestLayout`, which sets no `flexGrow`), and a caller's closure
    // builds the row's CONTENT one level below, whose records are planned at the
    // row `Box`'s own site. So the site survives for
    // `UnlowerableField.owningStage`'s trap message and for whatever field a
    // later stage puts on a row, and this arm is what would notice a regression
    // that made `List` report again. The rows here are real: `ProbeLeaf`
    // registers a native leaf directly, which records no `LoweredItem` and so
    // reports nothing of its own either.
    arms.append(("List", diagnostics {
        List(probeItems(3), rowHeight: px(10)) { _ in ProbeLeaf(width: 10, height: 10) }
    }, []))
    let amendChild = await #expect(processExitsWith: .success,
                                   observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            let entries = LayoutDifferential.render(authority: .proposal, width: 100, height: 100) {
                ProposalProbeComponent().width(Pixels(70))
            }.unlowerableFields
            FileHandle.standardOutput.write(Data("AMEND-ENTRIES \(entries)\n".utf8))
        }
    }
    let amendOut = String(decoding: amendChild?.standardOutputContent ?? [], as: UTF8.self)
    let amendErr = String(decoding: amendChild?.standardErrorContent ?? [], as: UTF8.self)
    #expect(amendOut.contains("AMEND-ENTRIES []\n"),
            "Component amend: stdout \(amendOut)\nstderr \(amendErr)")
    arms.append(("Component wrap", diagnostics { ProposalProbeComponent().padding(px(4)) }, []))
    arms.append(("custom requestNode", diagnostics { CustomNodeElement() },
                 [field(.customElement, "requestNode")]))
    arms.append(("custom requestLeaf", diagnostics { CustomLeafElement() },
                 [field(.customElement, "requestLeaf")]))
    try #require(arms.count == 10)
    for arm in arms {
        #expect(arm.entries == arm.expected, "\(arm.name): \(arm.entries)")
    }
    // **Stage 5, lane 1 (`LR-CL`): site `deferred`.** Its entries are raised in
    // `Frame.computeRootLayout` against the ROOT's record, so this arm renders
    // the tree as the frame's root rather than under the harness root (whose
    // native node has no record and is the window by construction). Compared by
    // description so the arm compiled before `LoweringSite.deferred` existed.
    // Mutation that must redden it: **M1i**, the containing-block check deleted.
    var bordered = Style()
    bordered.border = Edges(all: .pixels(px(4)))
    var presentationRoot = Box(style: bordered) {
        Deferred {
            Box().width(px(10)).height(px(10)).position(.absolute)
                .inset(Edges(top: .length(.pixels(px(5))), right: .auto, bottom: .auto,
                             left: .length(.pixels(px(5)))))
        }
    }
    let presentationFrame = Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1,
                                  layoutAuthority: .proposal, reportsUnlowerableFields: true)
    presentationFrame.render(&presentationRoot)
    #expect(presentationFrame.unlowerableFields.map(\.description) == ["deferred.containingBlock"],
            "Deferred (a bordered root over a presentation): \(presentationFrame.unlowerableFields)")
}

/// **1.5b** (exit test for the production half). `Frame`'s internal legacy
/// registrars are a backstop under the proposal authority (ruling LR-C): a site
/// that bypasses its own check and calls `Frame.requestNode`/`requestLeaf`
/// directly traps with the site-less backstop message in production; under
/// diagnostics it gets a native 0×0 leaf and records **nothing**, so
/// `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` sees the missing entry.
///
/// Mutation that must redden it: **M1n**, the backstop guard removed from
/// `Frame.requestNode` (the legacy node is registered; no trap, and the
/// diagnostics arm's node is not native) — lane-1 verifier finding: that mutation
/// left the suite green.
@Test func aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop() async throws {
    let node = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = BackstopBypassElement()
            Frame(contentSize: Size(width: Pixels(50), height: Pixels(50)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
        }
    }
    let nodeErr = String(decoding: node?.standardErrorContent ?? [], as: UTF8.self)
    #expect(nodeErr.contains("Frame.requestNode reached under the proposal layout authority"),
            "aborted, but not at the requestNode backstop:\n\(nodeErr)")

    let leaf = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = BackstopBypassElement(leaf: true)
            Frame(contentSize: Size(width: Pixels(50), height: Pixels(50)), scaleFactor: 1,
                  layoutAuthority: .proposal).render(&root)
        }
    }
    let leafErr = String(decoding: leaf?.standardErrorContent ?? [], as: UTF8.self)
    #expect(leafErr.contains("Frame.requestLeaf reached under the proposal layout authority"),
            "aborted, but not at the requestLeaf backstop:\n\(leafErr)")

    try await MainActor.run {
        for leaf in [false, true] {
            var got: [LayoutNodeID] = []
            var root = BackstopBypassElement(leaf: leaf, registered: { got.append($0) })
            let frame = Frame(contentSize: Size(width: Pixels(50), height: Pixels(50)), scaleFactor: 1,
                              layoutAuthority: .proposal, reportsUnlowerableFields: true)
            frame.render(&root)
            try #require(got.count == 1)
            #expect(frame.tree.isNativeLayoutNode(got[0]), "leaf: \(leaf)")
            #expect(frame.unlowerableFields.isEmpty, "leaf: \(leaf): \(frame.unlowerableFields)")
        }
    }
}

// MARK: - 1.6, 1.7 — the element bounds log

/// **1.6.** Under the legacy authority the log holds the root (recorded by
/// `Frame.render`), every group member (`Element.prepaintGroup`) and every inner
/// `ModifiedElement` layer (`prepaintLayer`), at the rects below, derived by hand:
/// the root fills the 200×100 frame (divergence 4); a top-leading `Stack` places
/// its children at (0, 0); `.padding(4).padding(8)` over a 30×40 `Box` is an
/// outermost 8pt layer 54×64 at (0, 0), an inner 4pt layer 38×48 at (8, 8), and
/// the `Box` at (12, 12).
///
/// Mutations that must redden it: **M1f**, inner-layer recording removed; **M1g**,
/// root recording removed.
@MainActor
@Test func theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer() throws {
    var root = Stack(alignment: .topLeading) {
        Box().width(px(20)).height(px(10))
        Box().width(px(30)).height(px(40)).padding(px(4)).padding(px(8))
    }
    let frame = Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1,
                      recordsElementBounds: true)
    frame.render(&root)
    let outer = child(rootID, 1)
    let inner = child(outer, 0)
    let expected: [GlobalElementID: Bounds<Pixels>] = [
        rootID: bounds(0, 0, 200, 100),
        child(rootID, 0): bounds(0, 0, 20, 10),
        outer: bounds(0, 0, 54, 64),
        inner: bounds(8, 8, 38, 48),
        child(inner, 0): bounds(12, 12, 30, 40),
    ]
    try #require(frame.elementBounds.count == 5, "\(frame.elementBounds)")
    #expect(frame.elementBounds == expected)
}

/// **1.7.** Nothing is recorded unless the frame was built to record; the
/// recording arm is the control.
///
/// Mutation that must redden it: **M1h**, recording defaults on.
@MainActor
@Test func theElementBoundsLogIsEmptyUnlessRequested() throws {
    func tree() -> Stack<Pair<Box<EmptyGroup>, Box<EmptyGroup>>> {
        Stack(alignment: .topLeading) {
            Box().width(px(20)).height(px(10))
            Box().width(px(30)).height(px(40))
        }
    }
    var quiet = tree()
    let quietFrame = Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1)
    quietFrame.render(&quiet)
    var recorded = tree()
    let recordingFrame = Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1,
                               recordsElementBounds: true)
    recordingFrame.render(&recorded)
    try #require(recordingFrame.elementBounds.count == 3)
    #expect(quietFrame.elementBounds.isEmpty)
}

// MARK: - 1.8–1.10 — the differential harness

/// **1.8.** Three `ProbeLeaf`s, the second answering one point wider under the
/// proposal authority only: exactly that element disagrees, at exactly those
/// rects, and the root and the other two agree.
///
/// Mutation that must redden it: **M1i**, `compare` renders the legacy authority twice.
@MainActor
@Test func theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement() throws {
    let report = LayoutDifferential.compare(width: 100, height: 60) {
        ProbeLeaf(width: 10, height: 10)
        ProbeLeaf(width: 20, height: 20, proposalWidthOffset: 1)
        ProbeLeaf(width: 30, height: 5)
    }
    try #require(report.elements == 4)
    #expect(report.unlowerable.isEmpty)
    #expect(report.legacyOnly.isEmpty && report.loweredOnly.isEmpty)
    #expect(Set(report.agreeing) == [rootID, child(rootID, 0), child(rootID, 2)])
    try #require(report.disagreeing.count == 1)
    #expect(report.disagreeing[0].id == child(rootID, 1))
    #expect(report.disagreeing[0].legacy == bounds(0, 0, 20, 20))
    #expect(report.disagreeing[0].lowered == bounds(0, 0, 21, 20))
}

/// **1.9.** The four whole-frame comparisons, each shown able to read `false` by
/// an arm that differs in exactly that observation:
///
/// - (a) a clickable, labelled leaf 5pt wider under the proposal authority: the
///   scene, the hitboxes and the accessibility records (their geometry) differ;
///   the state slots do not;
/// - (b) the same leaf unoffset, minting a `$probe` state entry only under the
///   proposal authority: only the state slots differ;
/// - (c) unoffset, no extra entry: all four agree;
/// - (d) two unoffset leaves, the first painted on a raised layer under the
///   proposal authority only: the emitted rect bytes are identical, and only the
///   finalized scene (the order the GPU receives) differs, so only the scenes
///   differ (verifier finding, lane 1: the comparison read emission bytes only).
///
/// Mutations that must redden it: **M1j**, the hitbox comparison returns `true`
/// (arm a); **M1l**, `stateSlotsEqual` returns `true` (arm b); **M1m**, the scene
/// comparison reads emission bytes only (arm d).
@MainActor
@Test func theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState() throws {
    let a = LayoutDifferential.compare(width: 100, height: 60) {
        ProbeLeaf(width: 20, height: 10, proposalWidthOffset: 5, clickable: true)
    }
    #expect(a.scenesEqual == false)
    #expect(a.hitboxesEqual == false)
    #expect(a.accessibilityEqual == false)
    #expect(a.stateSlotsEqual == true)

    let b = LayoutDifferential.compare(width: 100, height: 60) {
        ProbeLeaf(width: 20, height: 10, clickable: true, mintsProbeStateUnder: .proposal)
    }
    #expect(b.scenesEqual == true)
    #expect(b.hitboxesEqual == true)
    #expect(b.accessibilityEqual == true)
    #expect(b.stateSlotsEqual == false)

    let c = LayoutDifferential.compare(width: 100, height: 60) {
        ProbeLeaf(width: 20, height: 10, clickable: true)
    }
    #expect(c.scenesEqual == true)
    #expect(c.hitboxesEqual == true)
    #expect(c.accessibilityEqual == true)
    #expect(c.stateSlotsEqual == true)
    #expect(c.disagreeing.isEmpty)

    let d = LayoutDifferential.compare(width: 100, height: 60) {
        ProbeLeaf(width: 20, height: 10, paintsOnRaisedLayerUnder: .proposal)
        ProbeLeaf(width: 30, height: 5)
    }
    #expect(d.scenesEqual == false)
    #expect(d.hitboxesEqual == true)
    #expect(d.accessibilityEqual == true)
    #expect(d.stateSlotsEqual == true)
    #expect(d.disagreeing.isEmpty)
}

/// **1.10.** `DifferentialRoot` sits at (0, 0) at its declared size and places
/// fixed children top-leading at their own size under both authorities (spec
/// §5.3: fixed children only, because the root's own offer differs, divergence 53).
///
/// Mutation that must redden it: **M1k**, the proposal-side root aligned `.center`.
@MainActor
@Test func theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities() throws {
    let report = LayoutDifferential.compare(width: 120, height: 80) {
        ProbeLeaf(width: 30, height: 20)
        ProbeLeaf(width: 50, height: 10)
    }
    try #require(report.elements == 3)
    let expected: [GlobalElementID: Bounds<Pixels>] = [
        rootID: bounds(0, 0, 120, 80),
        child(rootID, 0): bounds(0, 0, 30, 20),
        child(rootID, 1): bounds(0, 0, 50, 10),
    ]
    #expect(report.legacyBounds == expected)
    #expect(report.loweredBounds == expected)
    #expect(report.unlowerable.isEmpty)
}
