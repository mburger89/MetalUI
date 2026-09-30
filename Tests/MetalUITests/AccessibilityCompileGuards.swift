import Testing
import MetalUITestSupport

// Plan task 12 part 2, lane 2, guards G2.1–G2.3 (rulings `IX-V`…`IX-Y`,
// `IX-AF` items 2 and 5). Whole-file Swift 6 against a PLAIN import
// (`typecheckFile`, ruling SA-P): what an external module may write.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `AX GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1 — every new spelling compiles outside the module, and each resolves
/// to the overload it must.** Every §4 modifier on a `Box`, a `Text` and an
/// `HStack`; `Image(_:scale:label:)`; and the static types: a `StyledElement`
/// chain stays `Self` (`ModifiedContent<Box<EmptyGroup>, ModifierLayer>`, no
/// new identity level), a proposal one is `AccessibilityModifier<…>` (`IX-AF`
/// item 5). The control asks the styled chain for the wrapper type, which must
/// not typecheck; the two arms are `#require`d to disagree first.
///
/// Mutation that must redden it: one modifier made `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theAccessibilityModifiersCompileFromAPlainImport() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings(bitmap: ImageBitmap) {
            _ = Box().accessibilityElement().accessibilityElement(children: .combine)
                .accessibilityElement(children: .contain).accessibilityHidden(true)
                .accessibilityHint("h").accessibilityIdentifier("i")
                .accessibilityAddTraits([.isButton, .isHeader, .isSelected, .isLink])
                .accessibilityAddTraits([.isImage, .isStaticText, .isModal, .updatesFrequently])
                .accessibilityRemoveTraits(.isButton)
                .accessibilityAction {}.accessibilityAction(named: "n") {}
            _ = Text("t").accessibilityElement(children: .ignore).accessibilityHidden(false)
                .accessibilityHint("h").accessibilityIdentifier("i").accessibilityAddTraits(.isHeader)
                .accessibilityRemoveTraits(.isButton).accessibilityAction {}.accessibilityAction(named: "n") {}
            _ = HStack { ProposalText("a") }.accessibilityElement(children: .combine)
                .accessibilityHidden(true).accessibilityHint("h").accessibilityIdentifier("i")
                .accessibilityAddTraits(.isHeader).accessibilityRemoveTraits(.isButton)
                .accessibilityAction {}.accessibilityAction(named: "n") {}
                .accessibilityLabel("l").accessibilityValue("v").accessibilityAdjustableAction { _ in }
            _ = Image(bitmap, scale: 2, label: Text("Logo"))
            let _: ModifiedContent<Box<EmptyGroup>, ModifierLayer> = Box().padding(1).accessibilityLabel("x")
            let _: AccessibilityModifier<HStack<ProposalText>> = HStack { ProposalText("a") }.accessibilityLabel("x")
        }
        """, importing: "MetalUI")
    print("AX GUARD G2.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let control = try typecheckFile("""
        @MainActor public func bad() {
            let _: AccessibilityModifier<ModifiedContent<Box<EmptyGroup>, ModifierLayer>> =
                Box().padding(1).accessibilityLabel("x")
        }
        """, importing: "MetalUI")
    print("AX GUARD G2.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "every spelling must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "a styled chain must stay Self:\n\(control.output)")
}

/// **G2.2 — `AXNode.actions` is deprecated toward `accessibilityAction`.**
/// Reading or writing the field and `AXNode(…, actions:)` warn, the message
/// naming `accessibilityAction` (`IX-Y` item 4); the control,
/// `AXNode(role:label:)`, warns nothing — and resolves unambiguously, which a
/// default on the deprecated overload's `actions:` would break (`IX-AF` item 2).
///
/// Mutation that must redden it: the attribute dropped.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anAXNodesActionsAreDeprecatedTowardAccessibilityAction() throws {
    let deprecated = try typecheckFile("""
        public func old() {
            var node = AXNode(role: .button, actions: [.activate])
            node.actions = []
            _ = node.actions
        }
        """, importing: "MetalUI")
    print("AX GUARD G2.2 deprecated: succeeded=\(deprecated.succeeded)\n\(deprecated.messages)")
    let warnings = deprecated.messages.split(separator: "\n").filter { $0.contains("is deprecated") }

    let control = try typecheckFile("""
        public func new() {
            let node = AXNode(role: .button, label: "x")
            _ = node.label
        }
        """, importing: "MetalUI")
    print("AX GUARD G2.2 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(deprecated.succeeded, "the old spelling still compiles:\n\(deprecated.output)")
    try #require(control.succeeded, "the control compiles, unambiguously:\n\(control.output)")
    #expect(warnings.count >= 3, "the initialiser, the write and the read each warn:\n\(deprecated.messages)")
    #expect(warnings.allSatisfy { $0.contains("accessibilityAction") },
            "each message names accessibilityAction:\n\(deprecated.messages)")
    #expect(!control.messages.contains("deprecated"), "the control warns nothing:\n\(control.messages)")
}

/// **G2.3 — an unoffered trait or action kind does not compile.**
/// `.isSearchField`, `.isToggle` and `accessibilityAction(.escape) {}` are not
/// offered (`IX-X` item 1; spec §4); the control, `.isHeader`, compiles. Each
/// negative is its own file, so one cannot hide another.
///
/// Mutation that must redden it: `static let isToggle` added.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anUnofferedTraitOrActionKindDoesNotCompile() throws {
    let control = try typecheckFile("""
        @MainActor public func good() { _ = Text("t").accessibilityAddTraits(.isHeader) }
        """, importing: "MetalUI")
    print("AX GUARD G2.3 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(control.succeeded, "the control compiles:\n\(control.output)")

    for (name, body) in [("isSearchField", "_ = Text(\"t\").accessibilityAddTraits(.isSearchField)"),
                         ("isToggle", "_ = Text(\"t\").accessibilityAddTraits(.isToggle)"),
                         ("escape", "_ = Text(\"t\").accessibilityAction(.escape) {}")] {
        let negative = try typecheckFile("""
            @MainActor public func bad() { \(body) }
            """, importing: "MetalUI")
        print("AX GUARD G2.3 \(name): succeeded=\(negative.succeeded)\n\(negative.messages)")
        #expect(!negative.succeeded, "\(name) must not be offered:\n\(negative.output)")
        #expect(negative.messages.contains(name) || negative.messages.contains("accessibilityAction"),
                "rejected FOR \(name):\n\(negative.messages)")
    }
}
