import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12 part 2, lane 2 (spec `2026-09-29-accessibility-design.md` §7,
// tests 2.1–2.12, 2.14, 2.19; rulings `IX-V`…`IX-Y`): the `StyledElement`
// accessibility modifiers and the builder's rules for them, read at builder
// level as `ControlAccessibilityTests`' `tree(_:)` does. Every expectation is a
// SwiftUI arm of `docs/probes/swiftui-accessibility-part2.swift` (named per
// arm) unless it says MetalUI's choice. Helpers are `ButtonTests.swift`'s
// `control…`.

/// A collecting frame's build, as `Window` builds it.
@MainActor
func accessibilityBuild<E: Element>(_ root: E, focused: GlobalElementID? = nil) throws
    -> (Frame, AccessibilityBuild) {
    var root = root
    let frame = Frame(contentSize: Size(width: controlPx(400), height: controlPx(200)), scaleFactor: 1,
                      focusedElement: focused, collectsAccessibility: true, reportsUnlowerableFields: true)
    frame.render(&root)
    try #require(frame.unlowerableFields.isEmpty,
                 "the fixture reported \(frame.unlowerableFields.map(\.description))")
    let build = AccessibilityTreeBuilder.buildResult(emissions: frame.axEmissions, focused: frame.focusedElement,
                                                     hitboxes: frame.hitboxes,
                                                     pressOnly: frame.accessibilityPressOnly,
                                                     focusRegistry: frame.focusRegistry)
    return (frame, build)
}

extension AccessibilityTree {
    /// What a node reads as: its label, or its value when it has none.
    func reading(_ id: AccessibilityNodeID) -> String? {
        nodes[id].flatMap { $0.label ?? $0.value }
    }

    /// Every published node in reading order (depth first from the roots).
    var readingOrder: [AccessibilityNodeID] {
        var result: [AccessibilityNodeID] = []
        func walk(_ id: AccessibilityNodeID) {
            result.append(id)
            for child in nodes[id]?.children ?? [] { walk(child) }
        }
        for root in roots { walk(root) }
        return result
    }

    /// The texts of every published node, in reading order.
    var readings: [String] { readingOrder.compactMap(reading) }

    /// The one node that reads as `text`.
    func one(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws
        -> (id: AccessibilityNodeID, node: AccessibilityNode) {
        let matches = nodes.filter { ($0.value.label ?? $0.value.value) == text }
        try #require(matches.count == 1, "exactly one node reads \(text): \(readings)",
                     sourceLocation: sourceLocation)
        return (matches.first!.key, matches.first!.value)
    }
}

@MainActor private final class Log {
    var lines: [String] = []
}

// MARK: - 2.1–2.4 `accessibilityElement(children:)` (`IX-V`)

/// **2.1.** `.accessibilityElement()` is `.ignore`: one `.group` node (SwiftUI
/// `AXUnknown`, divergence 33 amended), labelled only when declared, with no
/// children and none of their text (E1, E2, E12). Mutation M2a (`.ignore` keeps
/// the subtree) must redden it.
@Test @MainActor func anAccessibilityElementIgnoresItsChildrenByDefault() throws {
    let (_, e1) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityElement()
    })
    try #require(e1.tree.roots.count == 1, "E1: one node: \(e1.tree.readings)")
    let node = try #require(e1.tree.nodes[e1.tree.roots[0]])
    #expect(node.role == .group && node.label == nil && node.value == nil, "E1: \(node)")
    #expect(node.children.isEmpty, "E1: no children")
    #expect(e1.tree.nodes.count == 1, "E1: the children are gone: \(e1.tree.readings)")

    let (_, e2) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityElement(children: .ignore).accessibilityLabel("L")
    })
    #expect(e2.tree.nodes.count == 1 && e2.tree.readings == ["L"], "E2: \(e2.tree.readings)")
    #expect(try e2.tree.one("L").node.role == .group, "E2")
    #expect(try e2.tree.one("L").node.label == "L", "E2: the declared label, not a value")

    let (_, e12) = try accessibilityBuild(controlRoot {
        Column {
            Box().frame(width: 20, height: 20).accessibilityLabel("x")
            Box().frame(width: 20, height: 20).accessibilityLabel("y")
        }.accessibilityElement(children: .ignore)
    })
    #expect(e12.tree.nodes.count == 1 && e12.tree.readings.isEmpty, "E12: \(e12.tree.readings)")
}

/// **2.2.** `.combine` makes one static text of its children's text joined
/// `", "` (E3), a declared label replacing the join (E8), nested (E10), and a
/// value-carrying child moving the join to the label (E11: `vol, B` / `5`).
/// Mutations M2b (separator `" "`) and M2b′ (the value arm resolved as a plain
/// text) must redden it.
@Test @MainActor func aCombinedElementJoinsItsChildrenIntoOneStaticText() throws {
    let (_, e3) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityElement(children: .combine)
    })
    try #require(e3.tree.nodes.count == 1, "E3: one node: \(e3.tree.readings)")
    let a = try #require(e3.tree.nodes[e3.tree.roots[0]])
    #expect(a.role == .staticText && a.label == nil && a.value == "A, B" && a.children.isEmpty, "E3: \(a)")

    let (_, e8) = try accessibilityBuild(controlRoot {
        Row { Text("A"); Text("B") }.accessibilityElement(children: .combine).accessibilityLabel("L")
    })
    try #require(e8.tree.nodes.count == 1, "E8: \(e8.tree.readings)")
    let l = try #require(e8.tree.nodes[e8.tree.roots[0]])
    #expect(l.role == .staticText && l.label == nil && l.value == "L", "E8: \(l)")

    let (_, e10) = try accessibilityBuild(controlRoot {
        Column {
            Column { Text("A"); Text("B") }.accessibilityElement(children: .combine)
            Text("C")
        }
    })
    #expect(e10.tree.readings == ["A, B", "C"], "E10: \(e10.tree.readings)")

    let (_, e11) = try accessibilityBuild(controlRoot {
        Column { Text("vol").accessibilityValue("5"); Text("B") }.accessibilityElement(children: .combine)
    })
    try #require(e11.tree.nodes.count == 1, "E11: \(e11.tree.readings)")
    let v = try #require(e11.tree.nodes[e11.tree.roots[0]])
    #expect(v.role == .staticText && v.label == "vol, B" && v.value == "5", "E11: \(v)")
}

/// **2.3.** Over interactive children `.combine` takes the FIRST one's role and
/// press, reads its non-interactive children's text plus the first interactive
/// child's label, and publishes every interactive child as a custom action by
/// label, tree order (E6, E7, E14); the build's redirects name them, first
/// first. Over children of DIFFERENT kinds it merges (`IX-AI`, E15–E19, E18p):
/// the highest-ranked role, the last child's value, the first non-adjustable
/// child's label and press, a slider's increment, and custom actions only for
/// children that press. Mutations M2c (the LAST child leads), M2c′ (redirects
/// empty), M2c-rank (no ranking: the first child's role), M2c-value (the
/// FIRST valued child's value) and M2c-adjust (a slider counts as the lead)
/// must redden it.
@Test @MainActor func aCombinedElementTakesTheFirstInteractiveChildsRoleAndListsEveryOneAsACustomAction() throws {
    let (_, e6) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Button("B") {} }.accessibilityElement(children: .combine)
    })
    try #require(e6.tree.nodes.count == 1, "E6: \(e6.tree.readings)")
    let e6ID = e6.tree.roots[0]
    let b = try #require(e6.tree.nodes[e6ID])
    #expect(b.role == .button && b.label == "A, B" && b.value == nil, "E6: \(b)")
    #expect(b.actions == [.press] && b.customActions == ["B"] && b.children.isEmpty, "E6: \(b)")

    let (_, e7) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Toggle("T", isOn: .constant(true)) }.accessibilityElement(children: .combine)
    })
    try #require(e7.tree.nodes.count == 1, "E7: \(e7.tree.readings)")
    let t = try #require(e7.tree.nodes[e7.tree.roots[0]])
    #expect(t.role == .checkBox && t.label == "A" && t.value == "1" && t.customActions == ["T"], "E7: \(t)")

    // E14 against the same tree uncombined, which names the two buttons' ids.
    @MainActor func e14(_ combined: Bool) -> some Element {
        controlRoot {
            Column { Button("A") {}; Button("B") {} }
                .accessibilityElement(children: combined ? .combine : .contain)
        }
    }
    let (_, control) = try accessibilityBuild(e14(false))
    let aID = try #require(control.tree.one("A").id.base as? GlobalElementID)
    let bID = try #require(control.tree.one("B").id.base as? GlobalElementID)
    let (_, combined) = try accessibilityBuild(e14(true))
    try #require(combined.tree.nodes.count == 1, "E14: \(combined.tree.readings)")
    let e14ID = combined.tree.roots[0]
    let node = try #require(combined.tree.nodes[e14ID])
    #expect(node.role == .button && node.label == "A" && node.customActions == ["A", "B"], "E14: \(node)")
    let key = try #require(e14ID.base as? GlobalElementID)
    #expect(combined.redirects[key] == [aID, bID], "E14: the redirects, first first: \(combined.redirects)")

    // E15–E19 (probe revision 2): interactive children of DIFFERENT kinds, so
    // the first and the last child disagree. SwiftUI MERGES rather than copying
    // one lead (`IX-AI`): the role is the highest-ranked (slider over checkbox
    // over button, whatever the order), the value is the LAST child's that
    // carries one, the press is still the first child's, and an adjustable
    // child is no custom action.
    let e15 = try combinedMixed("E15") { Button("A") {}; Toggle("T", isOn: .constant(true)) }
    #expect(e15.role == .checkBox && e15.label == "A" && e15.value == "1" && e15.custom == ["A", "T"], "E15: \(e15)")
    let e16 = try combinedMixed("E16") { Toggle("T", isOn: .constant(true)); Button("A") {} }
    #expect(e16.role == .checkBox && e16.label == nil && e16.value == "1" && e16.custom == ["T", "A"], "E16: \(e16)")
    let e17 = try combinedMixed("E17") { Button("A") {}; Slider(value: .constant(0.5)) }
    #expect(e17.role == .slider && e17.label == "A" && e17.value == "0.5" && e17.custom == ["A"], "E17: \(e17)")
    let e18 = try combinedMixed("E18") { Slider(value: .constant(0.5)); Toggle("T", isOn: .constant(true)) }
    #expect(e18.role == .slider && e18.label == nil && e18.value == "1" && e18.custom == ["T"], "E18: \(e18)")
    let e19 = try combinedMixed("E19") { Toggle("T", isOn: .constant(true)); Slider(value: .constant(0.5)) }
    #expect(e19.role == .slider && e19.label == nil && e19.value == "0.5" && e19.custom == ["T"], "E19: \(e19)")
    // E18p: a slider is skipped for the label too — the first child that
    // presses gives it, as in E17 — and its increment joins the lead's press.
    let e18p = try combinedMixed("E18p") { Slider(value: .constant(0.5)); Button("A") {} }
    #expect(e18p.role == .slider && e18p.label == "A" && e18p.value == "0.5" && e18p.custom == ["A"], "E18p: \(e18p)")
    #expect(e17.actions.isSuperset(of: [.press, .increment, .decrement]), "E17: \(e17)")
    #expect(e18p.actions.isSuperset(of: [.press, .increment, .decrement]), "E18p: \(e18p)")
    // E20/E21: a text field (focusable, carrying a value, no press) beside a
    // button — the button ranks over it, gives the label and takes the press
    // in either order; the value is the field's. SwiftUI's own custom actions
    // on a text field ("show menu", "confirm") have no MetalUI counterpart
    // anywhere (`IX-AI` item 4), so only the button is a custom action here.
    let e20 = try combinedMixed("E20") { TextField("F", text: .constant("x")); Button("A") {} }
    #expect(e20.role == .button && e20.label == "A" && e20.value == "x" && e20.custom == ["A"], "E20: \(e20)")
    #expect(e20.actions.contains(.press), "E20: \(e20)")
    let e21 = try combinedMixed("E21") { Button("A") {}; TextField("F", text: .constant("x")) }
    #expect(e21.role == .button && e21.label == "A" && e21.value == "x" && e21.custom == ["A"], "E21: \(e21)")
    #expect(e21.actions.contains(.press), "E21: \(e21)")
}

/// What one `.combine` node over `content` publishes (2.3's mixed arms).
struct CombinedMixed { let role: AccessibilityRole; let label: String?; let value: String?; let custom: [String]; let actions: AccessibilityActions }
@MainActor func combinedMixed<C: ElementGroup>(_ name: String, @ElementBuilder _ content: () -> C) throws -> CombinedMixed {
    let (_, build) = try accessibilityBuild(controlRoot {
        Column { content() }.accessibilityElement(children: .combine)
    })
    try #require(build.tree.nodes.count == 1, "\(name): \(build.tree.readings)")
    let n = try #require(build.tree.nodes[build.tree.roots[0]])
    return CombinedMixed(role: n.role, label: n.label, value: n.value, custom: n.customActions, actions: n.actions)
}

/// **2.4.** `.contain` is a real group that keeps its children (E4), keeps its
/// declared label without handing it down (E5), and is a group even over a
/// text leaf — whose text becomes one synthesized static-text child no request
/// resolves (E9). Mutation M2d (`.contain` distributes its label) must redden it.
@Test @MainActor func aContainingElementIsAGroupThatKeepsItsLabelAndItsChildren() throws {
    let (_, e4) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityElement(children: .contain)
    })
    try #require(e4.tree.roots.count == 1, "E4: \(e4.tree.readings)")
    let group = try #require(e4.tree.nodes[e4.tree.roots[0]])
    #expect(group.role == .group && group.label == nil && group.children.count == 2, "E4: \(group)")
    #expect(group.children.compactMap(e4.tree.reading) == ["A", "B"], "E4")

    let (_, e5) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityElement(children: .contain).accessibilityLabel("L")
    })
    let labelled = try e5.tree.one("L").node
    #expect(labelled.role == .group && labelled.children.count == 2, "E5: \(labelled)")
    #expect(labelled.children.compactMap(e5.tree.reading) == ["A", "B"], "E5: the label is not distributed")

    let (_, e9) = try accessibilityBuild(controlRoot { Text("A").accessibilityElement(children: .contain) })
    try #require(e9.tree.roots.count == 1, "E9: \(e9.tree.readings)")
    let leaf = try #require(e9.tree.nodes[e9.tree.roots[0]])
    #expect(leaf.role == .group && leaf.label == nil && leaf.value == nil && leaf.children.count == 1, "E9: \(leaf)")
    let child = try #require(leaf.children.first)
    #expect(e9.tree.nodes[child]?.role == .staticText && e9.tree.nodes[child]?.value == "A", "E9: the text child")
    #expect(child.base as? GlobalElementID == nil, "E9: its key is not an element's")
    #expect(e9.tree.nodes[child]?.actions == [], "E9: no actions")
}

// MARK: - 2.5–2.6 hidden, hint, identifier (`IX-W`)

/// **2.5.** `accessibilityHidden(true)` removes its subtree (H1, H2), contributes
/// nothing to a button's label (H3), loses to a later outer `(false)` on the
/// same element (H4), and an inner `(false)` cannot un-hide (H5). Mutation M2e
/// (the scope wraps the element's own registration only) must redden it.
@Test @MainActor func anAccessibilityHiddenSubtreePublishesNothing() throws {
    let (_, h1) = try accessibilityBuild(controlRoot {
        Column { Text("A").accessibilityHidden(true); Text("B") }
    })
    #expect(h1.tree.readings == ["B"], "H1: \(h1.tree.readings)")

    let (_, h2) = try accessibilityBuild(controlRoot {
        Column { Column { Text("A"); Text("B") }.accessibilityHidden(true); Text("C") }
    })
    #expect(h2.tree.readings == ["C"], "H2: \(h2.tree.readings)")

    let (_, h3) = try accessibilityBuild(controlRoot {
        Button(action: {}) {
            Row { Box().frame(width: 10, height: 10).accessibilityLabel("Icon").accessibilityHidden(true); Text("Go") }
        }
    })
    #expect(h3.tree.readings == ["Go"], "H3: \(h3.tree.readings)")
    #expect(try h3.tree.one("Go").node.role == .button, "H3")

    let (_, h4) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityHidden(true).accessibilityHidden(false)
    })
    #expect(h4.tree.readings == ["A", "B"] && h4.tree.roots.count == 2, "H4: \(h4.tree.readings)")

    let (_, h5) = try accessibilityBuild(controlRoot {
        Column { Column { Text("A").accessibilityHidden(false) }.accessibilityHidden(true); Text("C") }
    })
    #expect(h5.tree.readings == ["C"], "H5: \(h5.tree.readings)")
}

/// **2.6.** A hint publishes as `hint` (N1 on a button, N3 on a text) and an
/// identifier as `identifier` (N2); both distribute from a plain container as a
/// label does (N4, N5). Mutation M2f (both left out of distribution) must
/// redden it.
@Test @MainActor func aHintAndAnIdentifierPublishAndDistributeLikeALabel() throws {
    let (_, n1) = try accessibilityBuild(controlRoot { Button("B") {}.accessibilityHint("Does X") })
    #expect(try n1.tree.one("B").node.hint == "Does X", "N1")
    let (_, n2) = try accessibilityBuild(controlRoot { Text("A").accessibilityIdentifier("id1") })
    #expect(try n2.tree.one("A").node.identifier == "id1", "N2")
    let (_, n3) = try accessibilityBuild(controlRoot { Text("A").accessibilityHint("H") })
    #expect(try n3.tree.one("A").node.hint == "H", "N3")
    let (_, n4) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityHint("H")
    })
    #expect(n4.tree.roots.count == 2, "N4: distributed, the column is gone: \(n4.tree.readings)")
    #expect(try n4.tree.one("A").node.hint == "H" && n4.tree.one("B").node.hint == "H", "N4")
    let (_, n5) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityIdentifier("g")
    })
    #expect(n5.tree.roots.count == 2, "N5: \(n5.tree.readings)")
    #expect(try n5.tree.one("A").node.identifier == "g" && n5.tree.one("B").node.identifier == "g", "N5")
}

// MARK: - 2.7–2.10 traits and modal isolation (`IX-X`)

/// **2.7.** `.isHeader` makes a heading labelled by its text (T1: label
/// `Title`, value nil), distributed from a container (T9), never over a button
/// (T11). Mutation M2g (a heading's text to its value) must redden it.
@Test @MainActor func aHeaderTraitMakesAHeadingLabelledByItsText() throws {
    let (_, t1) = try accessibilityBuild(controlRoot { Text("Title").accessibilityAddTraits(.isHeader) })
    let title = try t1.tree.one("Title").node
    #expect(title.role == .heading && title.label == "Title" && title.value == nil, "T1: \(title)")

    let (_, t9) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityAddTraits(.isHeader)
    })
    #expect(t9.tree.roots.count == 2, "T9: \(t9.tree.readings)")
    for text in ["A", "B"] {
        let node = try t9.tree.one(text).node
        #expect(node.role == .heading && node.label == text, "T9 \(text): \(node)")
    }

    let (_, t11) = try accessibilityBuild(controlRoot { Button("B") {}.accessibilityAddTraits(.isHeader) })
    #expect(try t11.tree.one("B").node.role == .button, "T11")
}

/// **2.8.** The role traits set the role only: `.isButton` a button with NO
/// press (T2), `.isImage` an image (T5), `.isLink` a link (T6), `.isStaticText`
/// on a clickable a text that keeps its press, and a removed `.isButton` a
/// group that keeps its folded label and press (T3p). Mutations M2h (`.isButton`
/// advertises `.press`) and M2h′ (the removal before the fold) must redden it.
@Test @MainActor func theButtonLinkImageAndStaticTextTraitsSetOnlyTheRole() throws {
    let (_, t2) = try accessibilityBuild(controlRoot { Text("Go").accessibilityAddTraits(.isButton) })
    let go = try t2.tree.one("Go").node
    #expect(go.role == .button && go.label == "Go" && go.actions == [], "T2: \(go)")

    let (_, t5) = try accessibilityBuild(controlRoot {
        Box().frame(width: 20, height: 20).accessibilityLabel("Pic").accessibilityAddTraits(.isImage)
    })
    #expect(try t5.tree.one("Pic").node.role == .image, "T5")

    let (_, t6) = try accessibilityBuild(controlRoot { Text("Home").accessibilityAddTraits(.isLink) })
    let home = try t6.tree.one("Home").node
    #expect(home.role == .link && home.label == "Home", "T6: \(home)")

    let (_, text) = try accessibilityBuild(controlRoot {
        Text("Tap").onClick {}.accessibilityAddTraits(.isStaticText)
    })
    let tap = try text.tree.one("Tap").node
    #expect(tap.role == .staticText && tap.actions == [.press], ".isStaticText on a clickable: \(tap)")

    let (_, t3p) = try accessibilityBuild(controlRoot { Button("B") {}.accessibilityRemoveTraits(.isButton) })
    try #require(t3p.tree.nodes.count == 1, "T3p: \(t3p.tree.readings)")
    let b = try #require(t3p.tree.nodes[t3p.tree.roots[0]])
    #expect(b.role == .group && b.label == "B" && b.actions == [.press] && b.children.isEmpty, "T3p: \(b)")
}

/// **2.9.** `.isSelected` publishes `isSelected` on any role (T4 a text, T7 a
/// button); the control without it reads `false`. Mutation M2i (read only on a
/// generic node) must redden it.
@Test @MainActor func aSelectedTraitPublishesSelectedOnAnyRole() throws {
    let (_, t4) = try accessibilityBuild(controlRoot { Text("S").accessibilityAddTraits(.isSelected) })
    let s = try t4.tree.one("S").node
    #expect(s.isSelected && s.role == .staticText, "T4: \(s)")
    let (_, t7) = try accessibilityBuild(controlRoot { Button("B") {}.accessibilityAddTraits(.isSelected) })
    let b = try t7.tree.one("B").node
    #expect(b.isSelected && b.role == .button, "T7: \(b)")
    let (_, control) = try accessibilityBuild(controlRoot { Text("S") })
    #expect(try !control.tree.one("S").node.isSelected, "control")
}

/// **2.10.** A subtree declaring `.isModal` is the only thing published (M1 over
/// a `Stack`, M3 a modal sibling; M0 the control publishes both); of two, the
/// higher `(layer, order)` wins; a focus outside it publishes no `focused`; the
/// build reports `isolatedOut`. Mutations M2j (isolation skipped) and M2j′ (the
/// FIRST modal wins) must redden it.
@Test @MainActor func aModalSubtreeIsTheOnlyThingPublished() throws {
    @MainActor func m1(_ modal: Bool) -> some Element {
        controlRoot {
            Stack {
                Button("Under") {}
                Column { Button("Top") {} }.accessibilityAddTraits(modal ? .isModal : [])
            }
        }
    }
    let (_, m0) = try accessibilityBuild(m1(false))
    #expect(Set(m0.tree.readings) == ["Under", "Top"] && !m0.isolatedOut, "M0: both: \(m0.tree.readings)")
    let underID = try #require(m0.tree.one("Under").id.base as? GlobalElementID)
    let topID = try #require(m0.tree.one("Top").id.base as? GlobalElementID)

    let (_, isolated) = try accessibilityBuild(m1(true), focused: underID)
    #expect(isolated.tree.readings == ["Top"], "M1: only the modal's subtree: \(isolated.tree.readings)")
    #expect(isolated.tree.roots.count == 1 && isolated.isolatedOut, "M1")
    #expect(isolated.tree.focused == nil, "a focus outside the modal publishes nothing")
    let (_, focusedInside) = try accessibilityBuild(m1(true), focused: topID)
    #expect(focusedInside.tree.focused == AccessibilityNodeID(topID), "control: a focus inside publishes")

    let (_, m3) = try accessibilityBuild(controlRoot {
        Column { Button("Top") {}.accessibilityAddTraits(.isModal); Button("Under") {} }
    })
    #expect(m3.tree.readings == ["Top"] && m3.isolatedOut, "M3: \(m3.tree.readings)")

    let (_, two) = try accessibilityBuild(controlRoot {
        Stack {
            Button("One") {}.accessibilityAddTraits(.isModal)
            Button("Two") {}.accessibilityAddTraits(.isModal)
        }
    })
    #expect(two.tree.readings == ["Two"], "two modals: the later-registered wins: \(two.tree.readings)")
}

// MARK: - 2.11–2.12 declared and named actions (`IX-Y`)

/// **2.11.** `accessibilityAction {}` makes a pressable button (A1), distributed
/// to each child of a plain container (A5); disabled, it is still a button but
/// advertises no press (A7). Mutation M2k (the handler not counted as a press)
/// must redden it.
@Test @MainActor func aDeclaredActionMakesAPressableButtonAndADisabledOneNone() throws {
    let (_, a1) = try accessibilityBuild(controlRoot { Text("T").accessibilityAction {} })
    let t = try a1.tree.one("T").node
    #expect(t.role == .button && t.label == "T" && t.actions == [.press], "A1: \(t)")

    let (_, a5) = try accessibilityBuild(controlRoot {
        Column { Text("A"); Text("B") }.accessibilityAction {}
    })
    #expect(a5.tree.roots.count == 2, "A5: distributed: \(a5.tree.readings)")
    for text in ["A", "B"] {
        let node = try a5.tree.one(text).node
        #expect(node.role == .button && node.label == text && node.actions == [.press], "A5 \(text): \(node)")
    }

    let (_, a7) = try accessibilityBuild(controlRoot { Text("T").accessibilityAction {}.disabled(true) })
    let disabled = try a7.tree.one("T").node
    #expect(disabled.role == .button && disabled.actions == [] && !disabled.isEnabled, "A7: \(disabled)")
}

/// **2.12.** `accessibilityAction(named:)` publishes a custom action (A2), keeps
/// a button's own press (A3), and lists the LATER-written first (A6). Mutation
/// M2l (names appended) must redden it.
@Test @MainActor func aNamedActionPublishesACustomActionLaterWrittenFirst() throws {
    let (_, a2) = try accessibilityBuild(controlRoot { Text("T").accessibilityAction(named: "Delete") {} })
    let t = try a2.tree.one("T").node
    #expect(t.role == .staticText && t.customActions == ["Delete"] && t.actions == [], "A2: \(t)")

    let (_, a3) = try accessibilityBuild(controlRoot { Button("B") {}.accessibilityAction(named: "Archive") {} })
    let b = try a3.tree.one("B").node
    #expect(b.role == .button && b.actions == [.press] && b.customActions == ["Archive"], "A3: \(b)")

    let (_, a6) = try accessibilityBuild(controlRoot {
        Text("T").accessibilityAction(named: "One") {}.accessibilityAction(named: "Two") {}
    })
    #expect(try a6.tree.one("T").node.customActions == ["Two", "One"], "A6")
}

// MARK: - 2.14 gestures (`IX-Y` item 3), both spellings

/// **2.14.** No gesture publishes a press — a tap, `.gesture(TapGesture())`, a
/// long press, a drag, a count-2 tap (G1–G4, G7) — and `accessibilityAction`
/// over a tap adds one (G6), **each on both spellings**: `StyledElement`'s
/// modifiers returning `Self`, and the proposal `GestureModifier`/`OnTapModifier`
/// (a copy of a pinned rule is unpinned). Mutations M2n (a proposal tap
/// synthesizes) and M2n′ (the declared-action term back inside the synthesize
/// gate: the non-synthesizing arm at the end, `IX-AH` item 1 — not G6's proposal
/// arm, which registers synthesizing) must redden it.
@Test @MainActor func aGestureOrTapPublishesNoPressAndAnAccessibilityActionAddsOne() throws {
    let legacy: [(String, @MainActor () throws -> AccessibilityBuild)] = [
        ("G1", { try accessibilityBuild(controlRoot { Text("Tap").onTapGesture {} }).1 }),
        ("G2", { try accessibilityBuild(controlRoot { Text("Tap").gesture(TapGesture().onEnded {}) }).1 }),
        ("G3", { try accessibilityBuild(controlRoot { Text("Tap").onLongPressGesture(perform: {}) }).1 }),
        ("G4", { try accessibilityBuild(controlRoot {
            Box().frame(width: 40, height: 40).accessibilityLabel("Tap").gesture(DragGesture())
        }).1 }),
        ("G7", { try accessibilityBuild(controlRoot { Text("Tap").onTapGesture(count: 2) {} }).1 }),
    ]
    for (arm, make) in legacy {
        let build = try make()
        #expect(try build.tree.one("Tap").node.actions == [], "\(arm) legacy: no press")
    }
    let proposal: [(String, @MainActor () throws -> AccessibilityBuild)] = [
        ("G1", { try accessibilityBuild(HStack { ProposalText("Tap").onTapGesture {} }).1 }),
        ("G2", { try accessibilityBuild(HStack { ProposalText("Tap").gesture(TapGesture().onEnded {}) }).1 }),
        ("G3", { try accessibilityBuild(HStack { ProposalText("Tap").onLongPressGesture(perform: {}) }).1 }),
        ("G4", { try accessibilityBuild(HStack {
            Rectangle().frame(width: 40, height: 40).accessibilityLabel("Tap").gesture(DragGesture())
        }).1 }),
        ("G7", { try accessibilityBuild(HStack { ProposalText("Tap").onTapGesture(count: 2) {} }).1 }),
        ("onTap", { try accessibilityBuild(HStack { ProposalText("Tap").onTap {} }).1 }),
    ]
    for (arm, make) in proposal {
        let build = try make()
        #expect(try build.tree.one("Tap").node.actions == [], "\(arm) proposal: no press")
    }

    let (_, g6) = try accessibilityBuild(controlRoot { Text("Tap").onTapGesture {}.accessibilityAction {} })
    let legacyG6 = try g6.tree.one("Tap").node
    #expect(legacyG6.role == .button && legacyG6.actions == [.press], "G6 legacy: \(legacyG6)")
    let (_, pg6) = try accessibilityBuild(HStack { ProposalText("Tap").onTapGesture {}.accessibilityAction {} })
    let proposalG6 = try pg6.tree.one("Tap").node
    #expect(proposalG6.role == .button && proposalG6.actions == [.press], "G6 proposal: \(proposalG6)")

    // `IX-AF` item 3 / `IX-AH` item 1: a declared action is a declaration, not
    // a synthesis — recorded through a NON-synthesizing registration too.
    // `AccessibilityModifier` registers synthesizing, so G6's arms above cannot
    // see the term's place (M2n′ left them green); this arm registers a
    // declared action with `synthesizesAccessibility: false`, as
    // `OnTapModifier`/`GestureModifier` register, and must still publish it.
    let (_, quiet) = try accessibilityBuild(HStack {
        NonSynthesizingDeclarer(content: Rectangle(width: Pixels(40), height: Pixels(40)))
    })
    // Nothing else declared — a label would record the node on its own.
    let pressable = quiet.tree.nodes.values.filter { $0.actions == [.press] }
    #expect(pressable.count == 1 && pressable.first?.role == .button,
            "a declared action through a non-synthesizing registration: \(quiet.tree.nodes.values)")
}

/// A wrapper shaped like `GestureModifier` that registers an unlabelled, declared
/// `accessibilityAction(_:)` with `synthesizesAccessibility: false` (2.14's
/// `IX-AH` item 1 arm).
private struct NonSynthesizingDeclarer<Content: ProposalElementGroup>: Element, ProposalElement {
    var content: Content
    struct Layout { var content: Content.GroupLayout }

    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        precondition(children.count == 1)
        return (children[0], Layout(content: contentLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var handlers = Handlers()
        handlers.declareDefaultAction {}
        pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil,
                              synthesizesAccessibility: false)
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                        prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

// MARK: - 2.19 the cost (`IX-Y`, `IX-N`)

/// **2.19.** The seven declarations cost `AXNode` — and so `Handlers`, which
/// holds one inline — at most one pointer: 113 and 440 bytes at `31d3565`
/// (measured 2026-09-29, arm64 debug), so at most 121 and 448. Mutation M2s
/// (the fields stored inline) must redden it.
///
/// **T row (drag and drop, ruling `DN-P`)**: `Handlers` gained one more
/// reference since, `dropDestination` (a class box, `IX-N`'s budget), so its
/// bound is 448 + 8 — measured 456 at lane 1 (2026-10-01, arm64 debug). The
/// `AXNode` bound and this test's answer for the seven declarations are
/// unchanged.
@Test func theNewDeclarationsCostHandlersAtMostOnePointer() {
    #expect(MemoryLayout<AXNode>.size <= 113 + 8, "AXNode: \(MemoryLayout<AXNode>.size)")
    #expect(MemoryLayout<Handlers>.size <= 440 + 8 + 8, "Handlers: \(MemoryLayout<Handlers>.size)")
}
