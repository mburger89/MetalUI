import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// The direct-style modifier surface: `StyledElement`'s forty-five and `Box`'s
// one. The table below holds 44 of the 46: `padding(_:)`'s two overloads are
// deliberately absent, being wrapper modifiers that return a `ModifiedElement`
// rather than writing their receiver's `Style`.

/// An `Action` for the `onAction(_:_:)` row below. Its identity is all that
/// matters — the row asserts that exactly one entry landed in
/// `Handlers.actions`, not which closure it holds.
private struct TableAction: Action {}
//
// **Nothing else in the repo can see a modifier write the wrong field.** The 81
// browser fixtures build a `Style` directly and never call a modifier; the
// element tests call a handful of them and assert on the *rect* that comes out,
// so they cover the few they use and say nothing about the rest. Measured before
// this file existed: nine mutations applied **at once** — `minWidth(_:)` writing
// `minSize.height`, `maxHeight(_:)` writing `maxSize.width`, `width(percent:)` (now
// `width(fraction:)`, ruling CN-O) writing `size.height`, `flexShrink(_:)` writing `flexGrow`, `flexBasis(_:)`
// treating points as a percentage, `borderWidth(_:)` writing `padding`, and
// `justifyContent(_:)`, `flexWrap(_:)`, `alignContent(_:)` each writing nothing
// at all — left the whole 302-test suite green.
//
// That inverts `StyledElement`'s own argument (Box.swift): a modifier for an
// inert property is worse than none "because from outside it is
// indistinguishable from an implemented one". A modifier that writes the wrong
// live field is indistinguishable in exactly the same way.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// One modifier, and the whole of what it is expected to change.
///
/// `effect` is written against the **four** stored values a `StyledElement`
/// owns, so a modifier that writes a field `effect` does not — or writes
/// nothing — fails on whole-value equality. That is what makes "assert the
/// fields it should not have touched" free rather than a second list to
/// maintain.
///
/// **`handlers` is the fourth and it is carried as a PROJECTION, not as a
/// value.** `Handlers` holds closures, so it is not `Equatable` and cannot be
/// compared the way the other three are; what a case declares instead is what
/// each of its members should look like afterwards — present or absent for the
/// closures, the whole value for the ones that are comparable. That is weaker
/// than whole-value equality on exactly one axis — two different closures
/// compare equal here — and it is strong enough for what this table exists to
/// catch: a modifier writing `handlers` when it should not, or `onClick(_:)`
/// writing nothing. `InputDispatchTests`, `FocusTests` and `KeymapTests` are
/// what check that the closure stored is the one that runs.
///
/// **One member per `Handlers` member, because a single flag could not tell
/// them apart.** `focusable()`, `onKey(_:)`, `onAction(_:_:)` and
/// `keyContext(_:_:)` are deliberately separate modifiers writing separate
/// fields (see `Handlers`), and each pair has a plausible mistake this
/// separation catches: an `onKey(_:)` that also set `isFocusable`, a
/// `keyContext(_:_:)` that made its element focusable, an `onAction(_:_:)` that
/// also registered a pointer hitbox by writing `onClick`.
///
/// **`Handlers` has EIGHT members as of plan task 5's lane 3 (`allowsHitTesting`
/// and `contentShapeInset`, ruling `OM-T`/`OM-J`); it had SIX as of the
/// tombstones-and-AX milestone's Task 5, and this comment said five (before
/// that, three) until that milestone's fix round.**
/// The projection stopped tracking the struct and the comment stopped saying
/// so, in one commit — the reason the two keymap-task modifiers escaped this
/// table entirely, back when it happened the first time. It has now happened
/// a SECOND time, to the same projection, for the same reason: `axNode` was
/// added to `Handlers` at Task 5 and this struct was not updated in the same
/// change. CLAUDE.md names this exact failure shape in advance and records
/// this as its second occurrence. There is no modifier that writes `axNode`
/// yet (`List.requestLayout` sets it directly, not through
/// `StyledElement`'s modifier surface — see `AXNode.swift`'s own doc), so no
/// `ModifierCase` below sets `axNode` in its `effect`; the field exists here
/// so a FUTURE modifier — or a bug in an EXISTING one — that writes `axNode`
/// is caught rather than silently absent from every case's comparison, on
/// `context`'s own footing. When `Handlers` gains a member, it gains a field
/// here in the same change.
private struct HandlerShape: Equatable {
    var click = false
    var key = false
    var focusable = false
    /// A count rather than a flag: `onAction(_:_:)` writes into a dictionary
    /// keyed by action type, so "wrote one entry" and "wrote two" are different
    /// answers a flag would collapse.
    var actionCount = 0
    /// The whole value, not a flag — `KeyContext` is `Equatable`, so a
    /// `keyContext(_:_:)` that dropped its `values` argument is a mismatch here
    /// rather than a coincidence.
    var context: KeyContext?
    /// The whole value, not a flag — `AXNode` is `Equatable` (unlike the four
    /// closure-carrying members above, which is why this one CAN be a whole
    /// value at all), so a future `axNode`-writing modifier that wrote the
    /// wrong role/label is a mismatch here rather than a coincidence. Every
    /// case below leaves this at the default `AXNode()`, matching
    /// `Handlers.axNode`'s own default — nothing today writes it.
    var axNode = AXNode()
    /// Plan task 5's lane 3. The default is `true`, so the one case that writes
    /// it must write `false` — a modifier that wrote nothing would otherwise
    /// pass. `contentShapeInset` is the whole `Edges` value, not a flag, so the
    /// per-edge overload's four distinct components catch a transposition.
    var allowsHitTesting = true
    var contentShapeInset: Edges<Pixels>?
    /// Roadmap item 14 (TI-B): internal, set only by `TextField`, so no
    /// modifier case writes it — a modifier that did is a mismatch here.
    var textInput = false
    /// Plan task 10 part 2 (`DD-W` item 5): internal, set only by `Slider`, so
    /// no modifier case writes it either.
    var valueTrack = false
    /// Plan task 12 part 1 (`IX-B`): a count rather than a flag, because the
    /// five gesture modifiers APPEND — "wrote one" and "replaced with one" are
    /// different answers only a count tells apart.
    var gestureCount = 0
    /// Plan task 12 part 1, lane 2: the shortcut is internal, set only by
    /// `Button` (`IX-F`), so no modifier case writes it; `contentShape(_:)`
    /// writes the boxed shape (`IX-L`).
    var keyboardShortcut = false
    var contentShape = false
    /// Plan task 12 part 1, lane 3 (`IX-J`): the `.focused` binding. No case
    /// below writes it — a `FocusState` box needs a body to bind in — so a
    /// modifier that wrote it by accident is a mismatch here.
    var focusBinding = false
    /// Drag and drop (ruling `DN-P`): the fifteenth member, the destination,
    /// and — because `.draggable` appends to `gestures` — how many of the
    /// gestures are draggables, so a `.draggable` that appended some other
    /// gesture (or a gesture modifier that appended a draggable) is a mismatch
    /// rather than a coincidence of `gestureCount`.
    var dropDestination = false
    var draggableCount = 0
    /// Menus (ruling `MN-Q`): the sixteenth member, the context-menu/help
    /// attachment.
    var contextual = false

    /// The projection of one element's `Handlers` — every member, one field
    /// each. The table below and the chain test after it read through this
    /// one function, so a member added here is compared everywhere at once.
    @MainActor init(_ h: Handlers) {
        self.init(click: h.onClick != nil,
                  key: h.onKey != nil,
                  focusable: h.isFocusable,
                  actionCount: h.actions.count,
                  context: h.keyContext,
                  axNode: h.axNode,
                  allowsHitTesting: h.allowsHitTesting,
                  contentShapeInset: h.contentShapeInset,
                  textInput: h.textInput != nil,
                  valueTrack: h.valueTrack != nil,
                  gestureCount: h.gestures.count,
                  keyboardShortcut: h.keyboardShortcut != nil,
                  contentShape: h.contentShape != nil,
                  focusBinding: h.focusBinding != nil,
                  dropDestination: h.dropDestination != nil,
                  draggableCount: h.gestures.filter(\.isDraggable).count,
                  contextual: h.contextual != nil)
    }

    init(click: Bool = false, key: Bool = false, focusable: Bool = false, actionCount: Int = 0,
         context: KeyContext? = nil, axNode: AXNode = AXNode(), allowsHitTesting: Bool = true,
         contentShapeInset: Edges<Pixels>? = nil, textInput: Bool = false, valueTrack: Bool = false,
         gestureCount: Int = 0, keyboardShortcut: Bool = false, contentShape: Bool = false,
         focusBinding: Bool = false, dropDestination: Bool = false, draggableCount: Int = 0,
         contextual: Bool = false) {
        self.click = click; self.key = key; self.focusable = focusable
        self.actionCount = actionCount; self.context = context; self.axNode = axNode
        self.allowsHitTesting = allowsHitTesting; self.contentShapeInset = contentShapeInset
        self.textInput = textInput; self.valueTrack = valueTrack; self.gestureCount = gestureCount
        self.keyboardShortcut = keyboardShortcut; self.contentShape = contentShape
        self.focusBinding = focusBinding; self.dropDestination = dropDestination
        self.draggableCount = draggableCount
        self.contextual = contextual
    }
}

@MainActor
private struct ModifierCase {
    let name: String
    let apply: @MainActor (Box<EmptyGroup>) -> Box<EmptyGroup>
    let effect: @MainActor (inout Style, inout Decoration, inout ElementID?,
                            inout HandlerShape) -> Void
}

/// **Class D** (plan task 7, stage 8; `LR-EW`, spec §5.2): the eight sizing
/// modifiers are deprecated (`LR-EU`), and they are this table's subject — each
/// row pins the field its modifier writes. The rows are unchanged; they are
/// built inside a deprecated protocol witness reached through its requirement
/// (`oldSpelling(_:)`, `CSSSizing.swift`), which warns nothing
/// (`docs/probes/swift-deprecated-witness-silence.sh`), and spliced back into
/// the table at the place they stood.
private struct DeprecatedSizingCases: DeprecatedSpelling {
    @available(*, deprecated, message: "calls the deprecated sizing modifiers on purpose: they are the subject of everyPublicModifierWritesItsOwnFieldAndOnlyThatField's Size rows (stage 8, LR-EW class D)")
    func spelled() -> [ModifierCase] {
        [
            ModifierCase(name: "width(_:)",
                         apply: { $0.width(px(11)) },
                         effect: { s, _, _, _ in s.size.width = .length(.pixels(px(11))) }),
            ModifierCase(name: "height(_:)",
                         apply: { $0.height(px(12)) },
                         effect: { s, _, _, _ in s.size.height = .length(.pixels(px(12))) }),
            ModifierCase(name: "width(fraction:)",
                         apply: { $0.width(fraction: 13) },
                         effect: { s, _, _, _ in s.size.width = .length(.percent(13)) }),
            ModifierCase(name: "height(fraction:)",
                         apply: { $0.height(fraction: 14) },
                         effect: { s, _, _, _ in s.size.height = .length(.percent(14)) }),
            ModifierCase(name: "minWidth(_:)",
                         apply: { $0.minWidth(px(15)) },
                         effect: { s, _, _, _ in s.minSize.width = .length(.pixels(px(15))) }),
            ModifierCase(name: "minHeight(_:)",
                         apply: { $0.minHeight(px(16)) },
                         effect: { s, _, _, _ in s.minSize.height = .length(.pixels(px(16))) }),
            ModifierCase(name: "maxWidth(_:)",
                         apply: { $0.maxWidth(px(17)) },
                         effect: { s, _, _, _ in s.maxSize.width = .length(.pixels(px(17))) }),
            ModifierCase(name: "maxHeight(_:)",
                         apply: { $0.maxHeight(px(18)) },
                         effect: { s, _, _, _ in s.maxSize.height = .length(.pixels(px(18))) })
        ]
    }
}

/// **Class D, plan task 15** (`CX-C` item 2): `flexBasis(fraction:)` is
/// deprecated, so its row is built in a deprecated witness too and spliced back
/// where it stood.
private struct DeprecatedFlexBasisCase: DeprecatedSpelling {
    @available(*, deprecated, message: "calls flexBasis(fraction:) and flexBasis(percent:) on purpose: they are the subjects of everyPublicModifierWritesItsOwnFieldAndOnlyThatField's rows (plan task 15, CX-C)")
    func spelled() -> [ModifierCase] {
        [ModifierCase(name: "flexBasis(fraction:)",
                      apply: { $0.flexBasis(fraction: 44) },
                      effect: { s, _, _, _ in s.flexBasis = .length(.percent(44)) }),
         // `flexBasis(percent:)` holds its own copy of the body since plan
         // task 15 (it no longer forwards to a non-deprecated spelling), so
         // the copy gets its own row (lane-1 fix round, mutation V-PERCENT).
         ModifierCase(name: "flexBasis(percent:)",
                      apply: { $0.flexBasis(percent: 45) },
                      effect: { s, _, _, _ in s.flexBasis = .length(.percent(45)) })]
    }
}

/// Every direct-style modifier writes its own field, and only its own field.
///
/// **Every value below is distinct, and none is a default.** Both halves are
/// load-bearing and both are taxonomy shape 1 ("uniform values on both sides of
/// an assertion"), which is the exact trap here:
///
/// - *Distinct* — `margin(25)` and `border(…, width: 51)` carry different
///   numbers, so a border modifier writing `Style.margin` — or writing
///   `Style.border`, the field its deleted `borderWidth(_:)` predecessor wrote
///   — is a mismatch rather than a coincidence. Uniform `4`s would pass against
///   every transposition in the table. The four-edge and two-axis cases carry four and two distinct
///   components for the same reason: `margin(_ edges:)` rebuilds the `Edges`
///   component by component, which is a transposition site.
/// - *Non-default* — `flexShrink`'s default is `1`, so `flexShrink(1)` would
///   pass against a modifier that writes nothing. Every case moves the field off
///   its `Style()` value, which is what catches the three "wrote nothing"
///   mutations.
///
/// The count check is a tripwire on **this table**, not on `Box.swift`: nothing
/// here can see a modifier added there without a case. Reconcile with
/// `grep -c "public func" Sources/MetalUI/Box.swift`, which is **50** as of
/// plan task 5's lane 3: 40 before, minus the two deleted `borderWidth`
/// overloads (`OM-M`), plus the eight paint-only decoration modifiers (lane
/// 2), plus lane 3's three hit-testing modifiers, plus
/// `BorderStyle.withWidths(_:)` — which grep counts and which is not a
/// modifier. `Decoration.setOpacity(_:)` is `public mutating func` and this
/// grep does not see it, which is worth knowing before anyone re-derives the
/// number and lands on 48.
@MainActor
@Test func everyPublicModifierWritesItsOwnFieldAndOnlyThatField() {
    let cases: [ModifierCase] = [
        // MARK: Identity and paint
        ModifierCase(name: "id(_:)",
                     apply: { $0.id("beacon") },
                     effect: { _, _, id, _ in id = ElementID("beacon") }),
        ModifierCase(name: "background(_:)",
                     apply: { $0.background(.accent) },
                     effect: { _, d, _, _ in d.background = .accent }),
        ModifierCase(name: "cornerRadius(_:)",
                     apply: { $0.cornerRadius(px(3)) },
                     effect: { _, d, _, _ in d.cornerRadius = px(3) }),
        // A token distinct from `background(_:)`'s and from each other's, so a
        // `hoverBackground(_:)` that wrote `background` — or wrote the focus
        // field — is a mismatch rather than a coincidence. `Theme` asserts no
        // two tokens share a value, which is the same rule one level down.
        ModifierCase(name: "hoverBackground(_:)",
                     apply: { $0.hoverBackground(.separator) },
                     effect: { _, d, _, _ in d.hoverBackground = .separator }),
        ModifierCase(name: "focusBackground(_:)",
                     apply: { $0.focusBackground(.scrim) },
                     effect: { _, d, _, _ in d.focusBackground = .scrim }),

        // MARK: Size — the eight deprecated sizing rows, unchanged, built in a
        // class-D witness (`DeprecatedSizingCases`, below the table's type).
    ] + oldSpelling(DeprecatedSizingCases()) + [
        // MARK: Box model
        // `padding` deliberately does not appear here: it is a SwiftUI-style
        // wrapper modifier now, not a direct write into its receiver's Style.
        ModifierCase(name: "margin(_ points:)",
                     apply: { $0.margin(px(25)) },
                     effect: { s, _, _, _ in s.margin = Edges(all: .length(.pixels(px(25)))) }),
        ModifierCase(name: "margin(_ edges:)",
                     apply: { $0.margin(Edges(top: .pixels(px(26)), right: .pixels(px(27)),
                                              bottom: .pixels(px(28)), left: .pixels(px(29)))) },
                     effect: { s, _, _, _ in
                         s.margin = Edges(top: .length(.pixels(px(26))), right: .length(.pixels(px(27))),
                                          bottom: .length(.pixels(px(28))), left: .length(.pixels(px(29))))
                     }),
        // The two `borderWidth(_:)` rows lived here and are GONE with the
        // modifier (ruling `OM-M`). They wrote `Style.border`, which the engine
        // consumed inside `contentBox` and discarded — the layout moved and
        // nothing painted. `borderWidthIsNoLongerSpellable`
        // (`DecorationCompileGuards.swift`) pins the removal against a plain
        // import, which a `@testable` test cannot do (taxonomy shape 16). The
        // paint-only replacements are under "Paint-only decoration" below.

        // MARK: As a flex container
        ModifierCase(name: "gap(_ points:)",
                     apply: { $0.gap(px(36)) },
                     effect: { s, _, _, _ in s.gap = Axes(both: .pixels(px(36))) }),
        ModifierCase(name: "gap(horizontal:vertical:)",
                     apply: { $0.gap(horizontal: px(37), vertical: px(38)) },
                     effect: { s, _, _, _ in
                         s.gap = Axes(horizontal: .pixels(px(37)), vertical: .pixels(px(38)))
                     }),
        ModifierCase(name: "justifyContent(_:)",
                     apply: { $0.justifyContent(.spaceEvenly) },
                     effect: { s, _, _, _ in s.justifyContent = .spaceEvenly }),
        ModifierCase(name: "alignItems(_:)",
                     apply: { $0.alignItems(.center) },
                     effect: { s, _, _, _ in s.alignItems = .center }),

        // MARK: As a flex item
        ModifierCase(name: "flexGrow(_:)",
                     apply: { $0.flexGrow(41) },
                     effect: { s, _, _, _ in s.flexGrow = 41 }),
        ModifierCase(name: "flexShrink(_:)",
                     apply: { $0.flexShrink(42) },
                     effect: { s, _, _, _ in s.flexShrink = 42 }),
        ModifierCase(name: "flexBasis(_ points:)",
                     apply: { $0.flexBasis(px(43)) },
                     effect: { s, _, _, _ in s.flexBasis = .length(.pixels(px(43))) }),
        // `flexBasis(fraction:)`'s row, unchanged, in a class-D witness since
        // plan task 15 deprecated it (`CX-C` item 2; `DeprecatedFlexBasisCase`).
    ] + oldSpelling(DeprecatedFlexBasisCase()) + [
        ModifierCase(name: "alignSelf(_:)",
                     apply: { $0.alignSelf(.flexEnd) },
                     effect: { s, _, _, _ in s.alignSelf = .flexEnd }),

        // MARK: Out of flow
        ModifierCase(name: "position(_:)",
                     apply: { $0.position(.absolute) },
                     effect: { s, _, _, _ in s.position = .absolute }),
        ModifierCase(name: "inset(_ edges:)",
                     apply: { $0.inset(Edges(top: .length(.pixels(px(45))),
                                             right: .length(.pixels(px(46))),
                                             bottom: .length(.pixels(px(47))),
                                             left: .length(.pixels(px(48))))) },
                     effect: { s, _, _, _ in
                         s.inset = Edges(top: .length(.pixels(px(45))), right: .length(.pixels(px(46))),
                                         bottom: .length(.pixels(px(47))), left: .length(.pixels(px(48))))
                     }),
        ModifierCase(name: "inset(_ points:)",
                     apply: { $0.inset(px(49)) },
                     effect: { s, _, _, _ in s.inset = Edges(all: .length(.pixels(px(49)))) }),

        // MARK: Participation
        ModifierCase(name: "hidden()",
                     apply: { $0.hidden() },
                     effect: { s, _, _, _ in s.display = .none }),

        // MARK: Input
        ModifierCase(name: "onClick(_:)",
                     apply: { $0.onClick {} },
                     effect: { _, _, _, h in h.click = true }),
        // Plan task 12 part 1 (`IX-B`): the five gesture attachment modifiers,
        // each appending one gesture.
        ModifierCase(name: "onTapGesture(count:perform:)",
                     apply: { $0.onTapGesture {} },
                     effect: { _, _, _, h in h.gestureCount = 1 }),
        ModifierCase(name: "onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)",
                     apply: { $0.onLongPressGesture {} },
                     effect: { _, _, _, h in h.gestureCount = 1 }),
        ModifierCase(name: "gesture(_:)",
                     apply: { $0.gesture(TapGesture()) },
                     effect: { _, _, _, h in h.gestureCount = 1 }),
        ModifierCase(name: "simultaneousGesture(_:)",
                     apply: { $0.simultaneousGesture(TapGesture()) },
                     effect: { _, _, _, h in h.gestureCount = 1 }),
        ModifierCase(name: "highPriorityGesture(_:)",
                     apply: { $0.highPriorityGesture(TapGesture()) },
                     effect: { _, _, _, h in h.gestureCount = 1 }),
        ModifierCase(name: "onKey(_:)",
                     apply: { $0.onKey { _ in true } },
                     effect: { _, _, _, h in h.key = true }),

        // MARK: Drag and drop (ruling `DN-P`)
        //
        // `.draggable` appends one gesture, a draggable; `.dropDestination`
        // sets the fifteenth member.
        ModifierCase(name: "draggable(_:)",
                     apply: { $0.draggable("payload") },
                     effect: { _, _, _, h in h.gestureCount = 1; h.draggableCount = 1 }),
        ModifierCase(name: "dropDestination(for:action:isTargeted:)",
                     apply: { $0.dropDestination(for: String.self, action: { _, _ in true }) },
                     effect: { _, _, _, h in h.dropDestination = true }),

        // MARK: Menus (ruling `MN-Q`)
        //
        // `.contextMenu` sets the sixteenth member and nothing else.
        ModifierCase(name: "contextMenu(menuItems:)",
                     apply: { $0.contextMenu { Button("Copy") {} } },
                     effect: { _, _, _, h in h.contextual = true }),

        // MARK: Focus
        ModifierCase(name: "focusable()",
                     apply: { $0.focusable() },
                     effect: { _, _, _, h in h.focusable = true }),

        // MARK: Actions and key contexts
        ModifierCase(name: "onAction(_:_:)",
                     apply: { $0.onAction(TableAction.self) { _ in } },
                     effect: { _, _, _, h in h.actionCount = 1 }),
        ModifierCase(name: "keyContext(_:_:)",
                     apply: { $0.keyContext("Editor", ["mode": "code"]) },
                     effect: { _, _, _, h in
                         h.context = KeyContext("Editor", ["mode": "code"])
                     }),

        // MARK: Paint-only decoration (plan task 5, lane 2)
        //
        // Eight rows for the eight modifiers appended at the end of
        // `extension StyledElement`. Every value is distinct from every other
        // in this table and from each other's: `.scrollIndicator` and
        // `.background` are two more tokens `Theme`'s
        // `noTwoTokensCollideWithinAVariant` keeps apart, and the widths run
        // 51…59, clear of the `Length`-valued 25…35 range above, so a border
        // modifier writing `Style.border` — the field its deleted predecessor
        // wrote — is a mismatch rather than a coincidence.
        ModifierCase(name: "border(_:width:)",
                     apply: { $0.border(.accent, width: px(51)) },
                     effect: { _, d, _, _ in d.border = BorderStyle(.accent, width: px(51)) }),
        ModifierCase(name: "border(_:widths:)",
                     apply: { $0.border(.separator, widths: Edges(top: px(52), right: px(53),
                                                                  bottom: px(54), left: px(55))) },
                     effect: { _, d, _, _ in
                         d.border = BorderStyle(.separator, widths: Edges(top: px(52), right: px(53),
                                                                          bottom: px(54), left: px(55)))
                     }),
        ModifierCase(name: "hoverBorder(_:width:)",
                     apply: { $0.hoverBorder(.scrim, width: px(56)) },
                     effect: { _, d, _, _ in d.hoverBorder = BorderStyle(.scrim, width: px(56)) }),
        ModifierCase(name: "hoverBorder(_:widths:)",
                     apply: { $0.hoverBorder(.surface, widths: Edges(top: px(57), right: px(58),
                                                                     bottom: px(59), left: px(60))) },
                     effect: { _, d, _, _ in
                         d.hoverBorder = BorderStyle(.surface, widths: Edges(top: px(57), right: px(58),
                                                                             bottom: px(59), left: px(60)))
                     }),
        ModifierCase(name: "focusBorder(_:width:)",
                     apply: { $0.focusBorder(.textPrimary, width: px(61)) },
                     effect: { _, d, _, _ in d.focusBorder = BorderStyle(.textPrimary, width: px(61)) }),
        ModifierCase(name: "focusBorder(_:widths:)",
                     apply: { $0.focusBorder(.scrollIndicator,
                                             widths: Edges(top: px(62), right: px(63),
                                                           bottom: px(64), left: px(65))) },
                     effect: { _, d, _, _ in
                         d.focusBorder = BorderStyle(.scrollIndicator,
                                                     widths: Edges(top: px(62), right: px(63),
                                                                   bottom: px(64), left: px(65)))
                     }),
        // `Decoration.opacity` defaults to 1, so this value must be neither 1
        // nor 0 — 0 would also be non-default, but a modifier that wrote
        // `clipsContent` instead would then be caught only by luck.
        ModifierCase(name: "opacity(_:)",
                     apply: { $0.opacity(0.25) },
                     effect: { _, d, _, _ in d.setOpacity(0.25) }),
        ModifierCase(name: "clipped()",
                     apply: { $0.clipped() },
                     effect: { _, d, _, _ in d.clipsContent = true }),

        // MARK: Hit testing (plan task 5, lane 3)
        //
        // Three rows for the three modifiers appended after lane 2's eight.
        // `allowsHitTesting` defaults to `true`, so the row writes `false` — the
        // only non-default value a `Bool` has. The insets run 66…70, clear of
        // lane 2's 51…65 and of every `Length`-valued number above, and the
        // per-edge row's four components are distinct so that `contentShape(
        // inset: Edges)` rebuilding the value component by component is a
        // transposition site this table can see.
        ModifierCase(name: "allowsHitTesting(_:)",
                     apply: { $0.allowsHitTesting(false) },
                     effect: { _, _, _, h in h.allowsHitTesting = false }),
        ModifierCase(name: "contentShape(inset: Pixels)",
                     apply: { $0.contentShape(inset: px(66)) },
                     effect: { _, _, _, h in h.contentShapeInset = Edges(all: px(66)) }),
        ModifierCase(name: "contentShape(inset: Edges)",
                     apply: { $0.contentShape(inset: Edges(top: px(67), right: px(68),
                                                            bottom: px(69), left: px(70))) },
                     effect: { _, _, _, h in
                         h.contentShapeInset = Edges(top: px(67), right: px(68),
                                                     bottom: px(69), left: px(70))
                     }),
        // Plan task 12 part 1, lane 2 (`IX-L`): a shape, not an inset.
        ModifierCase(name: "contentShape(_ shape:)",
                     apply: { $0.contentShape(Circle()) },
                     effect: { _, _, _, h in h.contentShape = true }),

        // MARK: `Box`'s own — deliberately not on `StyledElement`, so that
        // `Column { … }.flexDirection(.row)` cannot compile.
        ModifierCase(name: "flexDirection(_:)",
                     apply: { $0.flexDirection(.columnReverse) },
                     effect: { s, _, _, _ in s.flexDirection = .columnReverse }),
    ]

    // 38 − 2 (`borderWidth` ×2, ruling `OM-M`) + 8 (lane 2's paint-only
    // decoration) + 3 (lane 3's `allowsHitTesting` and `contentShape` ×2) =
    // **47**, this track's pre-agreed number — stated in the spec's lane 3
    // table so the parallel frame/sizing track adds to it rather than
    // colliding with it (spec §8 risk (c)). − 2 at stage 10 (`alignContent(_:)`
    // and `flexWrap(_:)`, removed with their fields, `LR-FM` item 1, `LR-FN`) =
    // **45**. + 5 at plan task 12 part 1 (the gesture attachment modifiers,
    // `IX-B`) = **50**. + 1 at lane 2 (`contentShape(_:)`, `IX-L`) = **51**.
    // + 1 at plan task 15's lane-1 fix round (`flexBasis(percent:)`'s own
    // class-D row, `CX-C`) = **52**. + 2 for drag and drop (`draggable(_:)`,
    // `dropDestination(for:action:isTargeted:)`, `DN-P`) = **54**. + 1 for
    // menus (`contextMenu(menuItems:)`, `MN-Q`) = **55**.
    #expect(cases.count == 55)

    for c in cases {
        var expectedStyle = Style()
        var expectedDecoration = Decoration()
        var expectedID: ElementID?
        var expectedHandlers = HandlerShape()
        c.effect(&expectedStyle, &expectedDecoration, &expectedID, &expectedHandlers)

        // Sanity on the table itself: a case whose value equals the default
        // cannot fail against a modifier that writes nothing.
        #expect(expectedStyle != Style() || expectedDecoration != Decoration()
                    || expectedID != nil || expectedHandlers != HandlerShape(),
                "\(c.name) expects no change at all — it cannot catch a no-op")

        let got = c.apply(Box())
        #expect(got.style == expectedStyle, "\(c.name) wrote the wrong `Style` field")
        #expect(got.decoration == expectedDecoration, "\(c.name) wrote the wrong `Decoration` field")
        #expect(got.elementID == expectedID, "\(c.name) wrote the wrong `elementID`")
        #expect(HandlerShape(got.handlers) == expectedHandlers,
                "\(c.name) wrote the wrong `Handlers` member, or wrote nothing")
    }
}

/// **A drop destination and a draggable survive every later handler modifier
/// and a wrapper** (drag and drop, `DN-P`; the review round's mutation I).
///
/// The table above applies each modifier to a fresh `Box`, so a later modifier
/// that clobbered `Handlers.dropDestination` or dropped the draggable from
/// `gestures` would pass it — the member was already empty. Here each later
/// modifier is applied **after** `.dropDestination` and `.draggable`, and the
/// projection must keep both, alongside the later modifier's own field.
///
/// The wrapper arms pin the per-layer path (`MC-A`): written before
/// `.padding(8)`, the destination stays on the wrapped content while a later
/// `.onKey` configures the new outermost layer; written after it and then
/// wrapped again, it moves into the chain's `inner` layers with the rest of
/// that layer's handlers.
@MainActor
@Test func aDropDestinationAndADraggableSurviveEveryLaterHandlerModifierAndAWrapper() throws {
    func source() -> Box<EmptyGroup> {
        Box().dropDestination(for: String.self, action: { _, _ in true }).draggable("payload")
    }
    let later: [(String, @MainActor (Box<EmptyGroup>) -> Box<EmptyGroup>)] = [
        ("onClick", { $0.onClick {} }),
        ("onKey", { $0.onKey { _ in true } }),
        ("focusable", { $0.focusable() }),
        ("onAction", { $0.onAction(TableAction.self) { _ in } }),
        ("keyContext", { $0.keyContext("Editor", ["mode": "code"]) }),
        ("onTapGesture", { $0.onTapGesture {} }),
        ("onLongPressGesture", { $0.onLongPressGesture {} }),
        ("gesture", { $0.gesture(TapGesture()) }),
        ("simultaneousGesture", { $0.simultaneousGesture(TapGesture()) }),
        ("highPriorityGesture", { $0.highPriorityGesture(TapGesture()) }),
        ("allowsHitTesting", { $0.allowsHitTesting(false) }),
        ("contentShape(inset:)", { $0.contentShape(inset: px(3)) }),
        ("contentShape(_:)", { $0.contentShape(Circle()) }),
        ("background", { $0.background(.accent) }),
        ("id", { $0.id("kept") }),
    ]
    try #require(later.count == 15)
    for (name, apply) in later {
        let shape = HandlerShape(apply(source()).handlers)
        #expect(shape.dropDestination, "`.\(name)` after `.dropDestination` dropped the destination")
        #expect(shape.draggableCount == 1, "`.\(name)` after `.draggable` dropped the draggable")
    }

    // Before a wrapper: the destination stays on the content, the later
    // `.onKey` lands on the new outermost layer.
    let wrapped = source().padding(px(8)).onKey { _ in true }
    #expect(HandlerShape(wrapped.content.handlers).dropDestination,
            "`.padding(8)` after `.dropDestination` lost the content's destination")
    #expect(HandlerShape(wrapped.content.handlers).draggableCount == 1)
    #expect(!HandlerShape(wrapped.handlers).dropDestination && HandlerShape(wrapped.handlers).key,
            "the later `.onKey` configures the padding layer, which has no destination of its own")

    // On a layer, then wrapped again: the destination rides that layer into
    // `inner`, and a later handler modifier on the outermost does not reach it.
    let layered = Box().padding(px(8)).dropDestination(for: String.self, action: { _, _ in true })
        .onKey { _ in true }
    #expect(HandlerShape(layered.handlers).dropDestination && HandlerShape(layered.handlers).key,
            "a destination written on a layer, then `.onKey`, must keep both on that layer")
    let rewrapped = layered.padding(px(4)).onClick {}
    try #require(rewrapped.inner.count == 1)
    #expect(HandlerShape(rewrapped.inner[0].handlers).dropDestination,
            "wrapping a destination-carrying layer lost the destination from `inner`")
    #expect(!HandlerShape(rewrapped.handlers).dropDestination)
}
