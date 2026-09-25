import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 1, lane 1 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
// §6 lane 1; rulings LR-B, LR-C, LR-D): every legacy registration site's own
// check, the element bounds log, and the harness root (`LayoutDifferential.swift`).
//
// **Red before**: every test here failed to compile before lane 1's
// implementation (record §18, lane 1). The mutation each must redden is named in
// its doc comment and in spec §6's lane-1 table; the record names what each
// mutation actually reddened.
//
// **Stage 9** (record §51, rulings `LR-FE`, `LR-FF`): the layout authority is
// deleted, so the tests of its default and of a window's authority, the custom
// element's and the deprecated registrars' traps, `Frame`'s legacy backstop and
// the harness's two-engine self-tests retired with it (rows 2–8); the file keeps
// its name so the record's citations resolve.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

/// A `Component` over proposal content, so its members register native nodes
/// and a caller's `.width`/`.padding` reaches
/// `StyledComponent`'s amend/wrap with nothing legacy inside it.
private struct ProposalProbeComponent: Component, ProposalElementGroup {
    var content: some ProposalElementGroup { Rectangle(width: Pixels(10), height: Pixels(10)) }
}

private struct ProbeItem: Identifiable, Sendable { let id: Int }

private func probeItems(_ n: Int) -> [ProbeItem] { (0..<n).map(ProbeItem.init) }

private func field(_ site: LoweringSite, _ name: String) -> UnlowerableField {
    UnlowerableField(site: site, field: name)
}

/// The frame's diagnostics for `make()` inside the harness root.
@MainActor
private func diagnostics<C: ElementGroup>(@ElementBuilder _ make: @MainActor () -> C) -> [UnlowerableField] {
    LayoutDifferential.render(width: 100, height: 100, make).unlowerableFields
}

/// **1.4** (exit test). A modified `Component` in a **production** frame
/// completes — `EXIT_SUCCESS` and an empty stderr — where before stage
/// 3's lane 4 it aborted on `component.amend` (`LR-BO`). Both ops, in both
/// orders, in one frame.
///
/// **Why it is a child process.** A `Frame` without `reportsUnlowerableFields`
/// traps rather than reports, so a
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
///   `aLoweredListLaysOutEveryWindowedShape` and
///   `theListSiteReportsNothingAndItsRowsItemFieldsAreLowered` in
///   `ListLoweringTests.swift`. The general claim the arm carried — that a site
///   that skips its own check is caught rather than lowering silently — was
///   `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop`'s, retired at stage 9
///   with the backstop (record §51, lane 1 row 8).
///
/// **Stage 9**: its absence check of `SA-G`'s `setStyle` message is dropped — lane
/// 3 deletes that precondition with `LayoutTree.setStyle`, so the check could
/// never fail; the `.success` exit is what sees any trap.
@Test func aComponentAmendDoesNotTrapUnderTheProposalAuthority() async {
    let amend = await #expect(processExitsWith: .success,
                              observing: [\.standardOutputContent, \.standardErrorContent]) {
        await MainActor.run {
            // Both ops, in both orders, in one production frame.
            var root = DifferentialRoot(width: 100, height: 100) {
                ProposalProbeComponent().padding(Pixels(4)).width(Pixels(70))
                ProposalProbeComponent().width(Pixels(70)).padding(Pixels(4))
            }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1).render(&root)
            FileHandle.standardOutput.write(Data("AMEND-BUILT\n".utf8))
        }
    }
    let amendOut = String(decoding: amend?.standardOutputContent ?? [], as: UTF8.self)
    let amendErr = String(decoding: amend?.standardErrorContent ?? [], as: UTF8.self)
    #expect(amendOut.contains("AMEND-BUILT\n"),
            "the production proposal frame did not finish:\nstdout \(amendOut)\nstderr \(amendErr)")
    #expect(!amendErr.contains("has no proposal lowering"),
            "a component op still reports:\n\(amendErr)")
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
/// So `LoweringSite.component` survives for `UnlowerableField`'s (since stage
/// 10, `owner`'s) trap message and for whatever field a later stage puts on it, and these two
/// arms are what would notice a regression that made either op report again.
/// The amend arm stays a **child process** for the reason above: in-process a
/// regression that removed the branch entirely reached `SA-G`'s `setStyle`
/// precondition and ended the whole run with no summary line.
///
/// **Stage 9** (record §51, lane 1; `LR-FF`): the two `customElement` arms go
/// with the site and the public registrars (lane 3 deletes both; a plain-import
/// caller of the registrars is pinned by the re-spelled guard G6a), and the
/// `deferred` arm — a bordered root over a presentation, which reported
/// `deferred.containingBlock` — goes with that report (`LR-FF`; `LR-FI`: lane 3
/// cannot edit this file, and its N3.1 carries the same tree's new answer, the
/// window rect with nothing reported). Eleven arms become nine.
///
/// **Stage 10** (record §53, lane 1; `LR-FM` item 1 deletes `Position.relative`
/// in lane 2): every `.position(.relative)` arm is re-spelled as `.inset(px(1))`
/// on the same static element, expecting `<site>.inset` — an inset on a
/// non-absolute box is a leaf row every site runs (`legacyLeafDiagnostics`), and
/// the test's subject is every SITE reporting by name, not `position`. The
/// inner-layer arm's inner layer declares a percentage width instead
/// (`<modifierLayer>.size.percent`, again a leaf row), the outermost still
/// `inset`, so the two registrars stay told apart by name and by order.
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
    arms.append(("Box", diagnostics { Box().cssWidth(px(10)).cssHeight(px(10)).inset(px(1)) },
                 [field(.box, "inset")]))
    arms.append(("Stack", diagnostics { Stack { ProbeLeaf(width: 10, height: 10) }.inset(px(1)) },
                 [field(.stack, "inset")]))
    arms.append(("Text", diagnostics { Text("a").inset(px(1)) }, [field(.text, "inset")]))
    // Roadmap item 14: `TextField` is its own site, lowered as `text` is.
    arms.append(("TextField", diagnostics { TextField("a", text: "", onChange: { _ in }).inset(px(1)) },
                 [field(.textField, "inset")]))
    arms.append(("TextEditor", diagnostics { TextEditor(text: "", onChange: { _ in }).inset(px(1)) },
                 [field(.textEditor, "inset")]))
    arms.append(("ModifiedElement, outermost registrar", diagnostics { Box().padding(px(4)).inset(px(1)) },
                 [field(.modifierLayer, "inset")]))
    // The inner layer declares a percentage width, the outermost `inset`, so the
    // two registrars' entries are told apart by name and by order (inner first).
    arms.append(("ModifiedElement, inner-layer registrar",
                 diagnostics { Box().padding(px(4)).cssWidth(fraction: 0.5).padding(px(8)).inset(px(3)) },
                 [field(.modifierLayer, "size.percent"), field(.modifierLayer, "inset")]))
    arms.append(("ScrollView", diagnostics {
        ScrollView {
            Box().cssWidth(px(10)).cssHeight(px(10)).flexGrow(1)
            Box().cssWidth(px(10)).cssHeight(px(10)).flexGrow(2)
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
    // `UnlowerableField`'s trap message (stage 10: `owner`) and for whatever field a
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
            let entries = LayoutDifferential.render(width: 100, height: 100) {
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
    try #require(arms.count == 10)
    for arm in arms {
        #expect(arm.entries == arm.expected, "\(arm.name): \(arm.entries)")
    }
}

// MARK: - N1.1 — every report's owner (stage 10, `LR-FO`)

/// **N1.1** (stage 10, lane 1; `LR-FO` items 1–3, spec §4.3). Every `(site,
/// field)` the lowering can raise at lane 1's head — except the three lane 2
/// deletes with their fields (`flexWrap`, `alignContent`, `border.percent`) —
/// names a **live** owner or none: `deferred.amended` is stage 11's
/// (`"plan task 7, stage 11"`, `LR-FF`), a baseline field is plan task 11's
/// (`"plan task 11"`, parent spec §8), and everything else is a **permanent
/// refusal** (`owner == nil`) whose trap message says so and names no stage.
///
/// The table was found by grepping `entry(`, `reports.append(`, `names.append(`
/// and `UnlowerableField(` in `LegacyLowering.swift`, `LoweringState.swift`,
/// `Component.swift` and `Deferred.swift` at `8095fd9`, and crossing each field
/// with the sites that raise it:
///
/// - **container rows** (`legacyContainerDiagnostics`: `gap.percent`,
///   `alignItems.baseline`) at every site that lowers a container — `box`,
///   `stack`, `scrollView` (its content), `modifierLayer` (an unframed layer),
///   `component` (a `.padding` wrap);
/// - **leaf rows** (`legacyLeafDiagnostics`: `size.percent`, `padding.percent`,
///   `position`, `inset`) at those and at `text`, `textField` and `textEditor`
///   (`TI-H`, merged from `master` after the table was taken: a leaf lowered as
///   `textField` is, through `lowerLegacyLeaf` at site `textEditor`);
/// - **item rows** (`planLegacyItems`, raised at the child's `item.site`: a
///   negative `flexGrow`/`flexShrink`, a length `flexBasis`,
///   `alignSelf.baseline`, `minSize.percent`, `maxSize.percent`, a non-greedy
///   `maxSize`, `margin.percent`, the three floored `space-*`, and `position`/
///   `inset` from `.absolute`) at every recording site, `list` (a row) included;
///   `flexGrow.weights` at each `parentSite:` (`box`, `stack`, `scrollView`,
///   `modifierLayer`, `component`, `list`);
/// - **presentation rows** (`lowerPresentation`: `minSize.absolute`,
///   `maxSize.absolute`) at every site whose record a `Deferred` consumes;
/// - **unconsumed rows** (`reportUnconsumedLoweredItems`: each of `flexGrow`,
///   `flexShrink`, `flexBasis`, `alignSelf`, `minSize`, `maxSize`, `margin`,
///   `position`, `inset` + `.unconsumed`) at every recording site;
/// - `modifierLayer.style` (`legacyFrameLayerDiagnostics`) and
///   `deferred.amended` (`loweredComponentFrame`).
///
/// **242** distinct entries (10 container, 32 leaf, 101 item — 99 at the nine
/// recording sites plus `position`/`inset` at `list` — 6 weights, 10
/// presentation, 81 unconsumed, 2 singletons), derived before the run. Stage 10
/// took it as 218 over eight recording sites; `master`'s `TextEditor` (`TI-H`)
/// adds the ninth, +4 leaf, +11 item and +9 unconsumed rows (the merge).
///
/// Red before: `owner` did not exist (build); with a scratch `owner` forwarding
/// to the old `owningStage`, every permanent row read a stage number. Mutation
/// **M1a** (the `nil` arm returns `"plan task 7, stage 10"` for a `position`/
/// `inset` field) must redden this test and
/// `anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame`. The table is
/// a pure function of `UnlowerableField` — it pins the owner scheme, not which
/// entries a tree raises — so **M1d** (the leaf `inset` row deleted from
/// `legacyLeafDiagnostics`) does not redden it; spec §6 predicted it would, and
/// `LR-FS` corrects the prediction (the raising half is
/// `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s).
@Test func everyReportNamesALiveOwnerOrIsRefusedByName() throws {
    let containerSites: [LoweringSite] = [.box, .stack, .scrollView, .modifierLayer, .component]
    let leafSites: [LoweringSite] = containerSites + [.text, .textField, .textEditor]
    let recordingSites: [LoweringSite] = leafSites + [.list]
    let parentSites: [LoweringSite] = [.box, .stack, .scrollView, .modifierLayer, .component, .list]
    let presentedSites: [LoweringSite] = [.box, .stack, .text, .modifierLayer, .component]

    let stage11 = "plan task 7, stage 11"
    let task11 = "plan task 11"
    var expected: [UnlowerableField: String?] = [:]
    func add(_ fields: [String], at sites: [LoweringSite], owner: String?) {
        for site in sites {
            for name in fields { expected[UnlowerableField(site: site, field: name)] = .some(owner) }
        }
    }
    add(["gap.percent"], at: containerSites, owner: nil)
    add(["alignItems.baseline"], at: containerSites, owner: task11)
    add(["size.percent", "padding.percent", "position", "inset"], at: leafSites, owner: nil)
    add(["flexGrow", "flexShrink", "flexBasis", "minSize.percent", "maxSize.percent", "maxSize",
         "margin.percent", "justifyContent.spaceBetween", "justifyContent.spaceAround",
         "justifyContent.spaceEvenly", "position", "inset"], at: recordingSites, owner: nil)
    add(["alignSelf.baseline"], at: recordingSites, owner: task11)
    add(["flexGrow.weights"], at: parentSites, owner: nil)
    add(["minSize.absolute", "maxSize.absolute"], at: presentedSites, owner: nil)
    add(["flexGrow", "flexShrink", "flexBasis", "alignSelf", "minSize", "maxSize", "margin",
         "position", "inset"].map { "\($0).unconsumed" }, at: recordingSites, owner: nil)
    add(["style"], at: [.modifierLayer], owner: nil)
    add(["amended"], at: [.deferred], owner: stage11)
    try #require(expected.count == 242, "the table holds \(expected.count) entries")

    let permanent = "and is refused by name (plan task 7, LR-FO)"
    for (field, owner) in expected.sorted(by: { $0.key.description < $1.key.description }) {
        #expect(field.owner == owner, "\(field): owner \(field.owner ?? "nil"), expected \(owner ?? "nil")")
        let message = field.trapMessage
        #expect(message.hasPrefix("MetalUI: \(field.description) has no proposal lowering"),
                "\(field): \(message)")
        if let owner {
            #expect(message.contains("(\(owner))"), "\(field): \(message)")
        } else {
            #expect(message.contains(permanent), "\(field): \(message)")
            #expect(!message.contains("stage "), "\(field) names a stage: \(message)")
        }
    }
}

// MARK: - 1.6, 1.7 — the element bounds log

/// **1.6.** The log holds the root (recorded by
/// `Frame.render`), every group member (`Element.prepaintGroup`) and every inner
/// `ModifiedElement` layer (`prepaintLayer`), at the rects below, derived by hand:
/// the root fills the 200×100 frame; a top-leading `Stack` places
/// its children at (0, 0); `.padding(4).padding(8)` over a 30×40 `Box` is an
/// outermost 8pt layer 54×64 at (0, 0), an inner 4pt layer 38×48 at (8, 8), and
/// the `Box` at (12, 12).
///
/// Mutations that must redden it: **M1f**, inner-layer recording removed; **M1g**,
/// root recording removed.
///
/// Stage 6b (`LR-DG`, R-fill): the root declares the 200×100 frame's extent on
/// its two auto axes — what divergence 4 gave the legacy root, now spelled — so
/// the rects above held under both authorities until stage 9 deleted the legacy
/// one.
@MainActor
@Test func theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer() throws {
    var root = Stack(alignment: .topLeading) {
        Box().cssWidth(px(20)).cssHeight(px(10))
        Box().cssWidth(px(30)).cssHeight(px(40)).padding(px(4)).padding(px(8))
    }.cssWidth(px(200)).cssHeight(px(100))
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
            Box().cssWidth(px(20)).cssHeight(px(10))
            Box().cssWidth(px(30)).cssHeight(px(40))
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

/// **1.10.** `DifferentialRoot` sits at (0, 0) at its declared size and places
/// fixed children top-leading at their own size (spec §5.3).
///
/// Mutation that must redden it: **M1k**, the root's native frame aligned
/// `.center`.
///
/// **Renamed at stage 9** from
/// `theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities`
/// (`LR-FE` item 6); its legacy-side assertion went with the legacy root.
@MainActor
@Test func theDifferentialRootPlacesItsContentTopLeadingAtItsSize() throws {
    let report = LayoutDifferential.report(width: 120, height: 80) {
        ProbeLeaf(width: 30, height: 20)
        ProbeLeaf(width: 50, height: 10)
    }
    try #require(report.elements == 3)
    let expected: [GlobalElementID: Bounds<Pixels>] = [
        rootID: bounds(0, 0, 120, 80),
        child(rootID, 0): bounds(0, 0, 30, 20),
        child(rootID, 1): bounds(0, 0, 50, 10),
    ]
    #expect(report.bounds == expected)
    #expect(report.unlowerable.isEmpty)
}
