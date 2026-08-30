import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// The public modifier surface: `StyledElement`'s thirty-seven and `Box`'s one.

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
// `minSize.height`, `maxHeight(_:)` writing `maxSize.width`, `width(percent:)`
// writing `size.height`, `flexShrink(_:)` writing `flexGrow`, `flexBasis(_:)`
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
/// **`Handlers` has FIVE members as of the keymap task, and this comment said
/// three until then.** The projection stopped tracking the struct and the
/// comment stopped saying so, in one commit — the reason the two new modifiers
/// escaped this table entirely. When `Handlers` gains a member, it gains a
/// field here in the same change.
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
}

@MainActor
private struct ModifierCase {
    let name: String
    let apply: @MainActor (Box<EmptyGroup>) -> Box<EmptyGroup>
    let effect: @MainActor (inout Style, inout Decoration, inout ElementID?,
                            inout HandlerShape) -> Void
}

/// Every public modifier writes its own field, and only its own field.
///
/// **Every value below is distinct, and none is a default.** Both halves are
/// load-bearing and both are taxonomy shape 1 ("uniform values on both sides of
/// an assertion"), which is the exact trap here:
///
/// - *Distinct* — `padding(19)` and `borderWidth(31)` produce different `Edges`,
///   so `borderWidth(_:)` writing `padding` is a mismatch rather than a
///   coincidence. Uniform `4`s would pass against every transposition in the
///   table. The four-edge and two-axis cases carry four and two distinct
///   components for the same reason: `margin(_ edges:)` rebuilds the `Edges`
///   component by component, which is a transposition site.
/// - *Non-default* — `flexShrink`'s default is `1`, so `flexShrink(1)` would
///   pass against a modifier that writes nothing. Every case moves the field off
///   its `Style()` value, which is what catches the three "wrote nothing"
///   mutations.
///
/// The count check is a tripwire on **this table**, not on `Box.swift`: nothing
/// here can see a modifier added there without a case. Reconcile with
/// `grep -c "public func" Sources/MetalUI/Box.swift`, which is 38 — the 37 on
/// `extension StyledElement` plus `flexDirection` on `extension Box`.
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

        // MARK: Size
        ModifierCase(name: "width(_:)",
                     apply: { $0.width(px(11)) },
                     effect: { s, _, _, _ in s.size.width = .length(.pixels(px(11))) }),
        ModifierCase(name: "height(_:)",
                     apply: { $0.height(px(12)) },
                     effect: { s, _, _, _ in s.size.height = .length(.pixels(px(12))) }),
        ModifierCase(name: "width(percent:)",
                     apply: { $0.width(percent: 13) },
                     effect: { s, _, _, _ in s.size.width = .length(.percent(13)) }),
        ModifierCase(name: "height(percent:)",
                     apply: { $0.height(percent: 14) },
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
                     effect: { s, _, _, _ in s.maxSize.height = .length(.pixels(px(18))) }),

        // MARK: Box model
        ModifierCase(name: "padding(_ points:)",
                     apply: { $0.padding(px(19)) },
                     effect: { s, _, _, _ in s.padding = Edges(all: .pixels(px(19))) }),
        ModifierCase(name: "padding(_ edges:)",
                     apply: { $0.padding(Edges(top: .pixels(px(21)), right: .pixels(px(22)),
                                               bottom: .pixels(px(23)), left: .pixels(px(24)))) },
                     effect: { s, _, _, _ in
                         s.padding = Edges(top: .pixels(px(21)), right: .pixels(px(22)),
                                           bottom: .pixels(px(23)), left: .pixels(px(24)))
                     }),
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
        ModifierCase(name: "borderWidth(_ points:)",
                     apply: { $0.borderWidth(px(31)) },
                     effect: { s, _, _, _ in s.border = Edges(all: .pixels(px(31))) }),
        ModifierCase(name: "borderWidth(_ edges:)",
                     apply: { $0.borderWidth(Edges(top: .pixels(px(32)), right: .pixels(px(33)),
                                                   bottom: .pixels(px(34)), left: .pixels(px(35)))) },
                     effect: { s, _, _, _ in
                         s.border = Edges(top: .pixels(px(32)), right: .pixels(px(33)),
                                          bottom: .pixels(px(34)), left: .pixels(px(35)))
                     }),

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
        ModifierCase(name: "alignContent(_:)",
                     apply: { $0.alignContent(.spaceAround) },
                     effect: { s, _, _, _ in s.alignContent = .spaceAround }),
        ModifierCase(name: "flexWrap(_:)",
                     apply: { $0.flexWrap(.wrapReverse) },
                     effect: { s, _, _, _ in s.flexWrap = .wrapReverse }),

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
        ModifierCase(name: "flexBasis(percent:)",
                     apply: { $0.flexBasis(percent: 44) },
                     effect: { s, _, _, _ in s.flexBasis = .length(.percent(44)) }),
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
        ModifierCase(name: "onKey(_:)",
                     apply: { $0.onKey { _ in true } },
                     effect: { _, _, _, h in h.key = true }),

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

        // MARK: `Box`'s own — deliberately not on `StyledElement`, so that
        // `Column { … }.flexDirection(.row)` cannot compile.
        ModifierCase(name: "flexDirection(_:)",
                     apply: { $0.flexDirection(.columnReverse) },
                     effect: { s, _, _, _ in s.flexDirection = .columnReverse }),
    ]

    #expect(cases.count == 38)

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
        #expect(HandlerShape(click: got.handlers.onClick != nil,
                             key: got.handlers.onKey != nil,
                             focusable: got.handlers.isFocusable,
                             actionCount: got.handlers.actions.count,
                             context: got.handlers.keyContext) == expectedHandlers,
                "\(c.name) wrote the wrong `Handlers` member, or wrote nothing")
    }
}
