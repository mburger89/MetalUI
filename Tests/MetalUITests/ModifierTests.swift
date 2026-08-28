import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// The public modifier surface: `StyledElement`'s twenty-nine and `Box`'s one.
//
// **Nothing else in the repo can see a modifier write the wrong field.** The 76
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
/// `effect` is written against the three stored values a `StyledElement` owns,
/// so a modifier that writes a field `effect` does not — or writes nothing —
/// fails on whole-value equality. That is what makes "assert the fields it
/// should not have touched" free rather than a second list to maintain.
@MainActor
private struct ModifierCase {
    let name: String
    let apply: @MainActor (Box<EmptyGroup>) -> Box<EmptyGroup>
    let effect: @MainActor (inout Style, inout Decoration, inout ElementID?) -> Void
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
/// `grep -c "public func" Sources/MetalUI/Box.swift`, which is 30 — the 29 on
/// `extension StyledElement` plus `flexDirection` on `extension Box`.
@MainActor
@Test func everyPublicModifierWritesItsOwnFieldAndOnlyThatField() {
    let cases: [ModifierCase] = [
        // MARK: Identity and paint
        ModifierCase(name: "id(_:)",
                     apply: { $0.id("beacon") },
                     effect: { _, _, id in id = ElementID("beacon") }),
        ModifierCase(name: "background(_:)",
                     apply: { $0.background(.accent) },
                     effect: { _, d, _ in d.background = .accent }),
        ModifierCase(name: "cornerRadius(_:)",
                     apply: { $0.cornerRadius(px(3)) },
                     effect: { _, d, _ in d.cornerRadius = px(3) }),

        // MARK: Size
        ModifierCase(name: "width(_:)",
                     apply: { $0.width(px(11)) },
                     effect: { s, _, _ in s.size.width = .length(.pixels(px(11))) }),
        ModifierCase(name: "height(_:)",
                     apply: { $0.height(px(12)) },
                     effect: { s, _, _ in s.size.height = .length(.pixels(px(12))) }),
        ModifierCase(name: "width(percent:)",
                     apply: { $0.width(percent: 13) },
                     effect: { s, _, _ in s.size.width = .length(.percent(13)) }),
        ModifierCase(name: "height(percent:)",
                     apply: { $0.height(percent: 14) },
                     effect: { s, _, _ in s.size.height = .length(.percent(14)) }),
        ModifierCase(name: "minWidth(_:)",
                     apply: { $0.minWidth(px(15)) },
                     effect: { s, _, _ in s.minSize.width = .length(.pixels(px(15))) }),
        ModifierCase(name: "minHeight(_:)",
                     apply: { $0.minHeight(px(16)) },
                     effect: { s, _, _ in s.minSize.height = .length(.pixels(px(16))) }),
        ModifierCase(name: "maxWidth(_:)",
                     apply: { $0.maxWidth(px(17)) },
                     effect: { s, _, _ in s.maxSize.width = .length(.pixels(px(17))) }),
        ModifierCase(name: "maxHeight(_:)",
                     apply: { $0.maxHeight(px(18)) },
                     effect: { s, _, _ in s.maxSize.height = .length(.pixels(px(18))) }),

        // MARK: Box model
        ModifierCase(name: "padding(_ points:)",
                     apply: { $0.padding(px(19)) },
                     effect: { s, _, _ in s.padding = Edges(all: .pixels(px(19))) }),
        ModifierCase(name: "padding(_ edges:)",
                     apply: { $0.padding(Edges(top: .pixels(px(21)), right: .pixels(px(22)),
                                               bottom: .pixels(px(23)), left: .pixels(px(24)))) },
                     effect: { s, _, _ in
                         s.padding = Edges(top: .pixels(px(21)), right: .pixels(px(22)),
                                           bottom: .pixels(px(23)), left: .pixels(px(24)))
                     }),
        ModifierCase(name: "margin(_ points:)",
                     apply: { $0.margin(px(25)) },
                     effect: { s, _, _ in s.margin = Edges(all: .length(.pixels(px(25)))) }),
        ModifierCase(name: "margin(_ edges:)",
                     apply: { $0.margin(Edges(top: .pixels(px(26)), right: .pixels(px(27)),
                                              bottom: .pixels(px(28)), left: .pixels(px(29)))) },
                     effect: { s, _, _ in
                         s.margin = Edges(top: .length(.pixels(px(26))), right: .length(.pixels(px(27))),
                                          bottom: .length(.pixels(px(28))), left: .length(.pixels(px(29))))
                     }),
        ModifierCase(name: "borderWidth(_ points:)",
                     apply: { $0.borderWidth(px(31)) },
                     effect: { s, _, _ in s.border = Edges(all: .pixels(px(31))) }),
        ModifierCase(name: "borderWidth(_ edges:)",
                     apply: { $0.borderWidth(Edges(top: .pixels(px(32)), right: .pixels(px(33)),
                                                   bottom: .pixels(px(34)), left: .pixels(px(35)))) },
                     effect: { s, _, _ in
                         s.border = Edges(top: .pixels(px(32)), right: .pixels(px(33)),
                                          bottom: .pixels(px(34)), left: .pixels(px(35)))
                     }),

        // MARK: As a flex container
        ModifierCase(name: "gap(_ points:)",
                     apply: { $0.gap(px(36)) },
                     effect: { s, _, _ in s.gap = Axes(both: .pixels(px(36))) }),
        ModifierCase(name: "gap(horizontal:vertical:)",
                     apply: { $0.gap(horizontal: px(37), vertical: px(38)) },
                     effect: { s, _, _ in
                         s.gap = Axes(horizontal: .pixels(px(37)), vertical: .pixels(px(38)))
                     }),
        ModifierCase(name: "justifyContent(_:)",
                     apply: { $0.justifyContent(.spaceEvenly) },
                     effect: { s, _, _ in s.justifyContent = .spaceEvenly }),
        ModifierCase(name: "alignItems(_:)",
                     apply: { $0.alignItems(.center) },
                     effect: { s, _, _ in s.alignItems = .center }),
        ModifierCase(name: "alignContent(_:)",
                     apply: { $0.alignContent(.spaceAround) },
                     effect: { s, _, _ in s.alignContent = .spaceAround }),
        ModifierCase(name: "flexWrap(_:)",
                     apply: { $0.flexWrap(.wrapReverse) },
                     effect: { s, _, _ in s.flexWrap = .wrapReverse }),

        // MARK: As a flex item
        ModifierCase(name: "flexGrow(_:)",
                     apply: { $0.flexGrow(41) },
                     effect: { s, _, _ in s.flexGrow = 41 }),
        ModifierCase(name: "flexShrink(_:)",
                     apply: { $0.flexShrink(42) },
                     effect: { s, _, _ in s.flexShrink = 42 }),
        ModifierCase(name: "flexBasis(_ points:)",
                     apply: { $0.flexBasis(px(43)) },
                     effect: { s, _, _ in s.flexBasis = .length(.pixels(px(43))) }),
        ModifierCase(name: "flexBasis(percent:)",
                     apply: { $0.flexBasis(percent: 44) },
                     effect: { s, _, _ in s.flexBasis = .length(.percent(44)) }),
        ModifierCase(name: "alignSelf(_:)",
                     apply: { $0.alignSelf(.flexEnd) },
                     effect: { s, _, _ in s.alignSelf = .flexEnd }),

        // MARK: Participation
        ModifierCase(name: "hidden()",
                     apply: { $0.hidden() },
                     effect: { s, _, _ in s.display = .none }),

        // MARK: `Box`'s own — deliberately not on `StyledElement`, so that
        // `Column { … }.flexDirection(.row)` cannot compile.
        ModifierCase(name: "flexDirection(_:)",
                     apply: { $0.flexDirection(.columnReverse) },
                     effect: { s, _, _ in s.flexDirection = .columnReverse }),
    ]

    #expect(cases.count == 30)

    for c in cases {
        var expectedStyle = Style()
        var expectedDecoration = Decoration()
        var expectedID: ElementID?
        c.effect(&expectedStyle, &expectedDecoration, &expectedID)

        // Sanity on the table itself: a case whose value equals the default
        // cannot fail against a modifier that writes nothing.
        #expect(expectedStyle != Style() || expectedDecoration != Decoration()
                    || expectedID != nil,
                "\(c.name) expects no change at all — it cannot catch a no-op")

        let got = c.apply(Box())
        #expect(got.style == expectedStyle, "\(c.name) wrote the wrong `Style` field")
        #expect(got.decoration == expectedDecoration, "\(c.name) wrote the wrong `Decoration` field")
        #expect(got.elementID == expectedID, "\(c.name) wrote the wrong `elementID`")
    }
}
