import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// MARK: - Helpers

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func ctx(_ name: String, _ values: [String: String] = [:]) -> KeyContext {
    KeyContext(name, values)
}

/// Parses `source` and evaluates it, failing the test if it does not parse.
///
/// `try #require` rather than `#expect` on purpose: a `nil` here would
/// otherwise be reported as a *false* predicate, which is exactly the
/// distinction ruling "a malformed predicate must be distinguishable from a
/// legitimate false" exists to keep visible.
private func evaluate(_ source: String, _ stack: [KeyContext]) throws -> Bool {
    let predicate = try #require(ContextPredicate.parse(source),
                                 "`\(source)` is well-formed and must parse")
    return predicate.evaluate(against: stack)
}

// MARK: - The predicate parser (design spec §4.3)

@Test func aBareIdentifierMatchesAContextOfThatName() throws {
    #expect(try evaluate("Editor", [ctx("Editor")]))
}

@Test func aBareIdentifierIsFalseWhenNoContextCarriesThatName() throws {
    #expect(try evaluate("Editor", [ctx("Terminal")]) == false)
}

/// An identifier nobody contributed is **false, not a parse error** — the
/// brief's own wording. The `#require` inside `evaluate` is what asserts the
/// second half.
@Test func anUnknownIdentifierIsFalseRatherThanAParseFailure() throws {
    #expect(try evaluate("NobodyContributedThis", []) == false)
}

@Test func aKeyValueComparisonMatchesAContextsValue() throws {
    #expect(try evaluate("mode == code", [ctx("Editor", ["mode": "code"])]))
}

@Test func aKeyValueComparisonIsFalseWhenTheValueDiffers() throws {
    #expect(try evaluate("mode == code", [ctx("Editor", ["mode": "prose"])]) == false)
}

/// A key the stack does not carry at all is false — distinct from a key whose
/// value differs, and the same answer.
@Test func aKeyValueComparisonIsFalseWhenTheKeyIsAbsent() throws {
    #expect(try evaluate("mode == code", [ctx("Editor")]) == false)
}

/// Values are read from **every** context in the stack, not only the innermost
/// one: an ancestor pane's `mode` is visible to a binding predicated on a leaf.
@Test func aValueIsVisibleFromAnyContextInTheStack() throws {
    let stack = [ctx("Leaf"), ctx("Editor", ["mode": "code"])]
    #expect(try evaluate("mode == code", stack))
    #expect(try evaluate("Editor && Leaf", stack))
}

@Test func andRequiresBothSides() throws {
    #expect(try evaluate("Editor && Focused", [ctx("Editor"), ctx("Focused")]))
    #expect(try evaluate("Editor && Focused", [ctx("Editor")]) == false)
    #expect(try evaluate("Editor && Focused", [ctx("Focused")]) == false)
}

@Test func orRequiresEitherSide() throws {
    #expect(try evaluate("Editor || Terminal", [ctx("Editor")]))
    #expect(try evaluate("Editor || Terminal", [ctx("Terminal")]))
    #expect(try evaluate("Editor || Terminal", [ctx("Pane")]) == false)
}

@Test func notInvertsItsOperand() throws {
    #expect(try evaluate("!Modal", [ctx("Editor")]))
    #expect(try evaluate("!Modal", [ctx("Modal")]) == false)
}

/// `&&` binds tighter than `||`, and the fixture is chosen so the two readings
/// **disagree**: with `A` present and `B`/`C` absent, `A || (B && C)` is true
/// and `(A || B) && C` is false. A test whose fixture both readings satisfy
/// pins nothing (taxonomy shape 1).
@Test func andBindsTighterThanOr() throws {
    let stack = [ctx("A")]
    #expect(try evaluate("A || B && C", stack),
            "parsed as A || (B && C); the other associativity gives false")
    #expect(try evaluate("B && C || A", stack),
            "and the same on the other side of the operator")
}

/// `!` binds tighter than `&&`, and the fixture is the one on which the two
/// readings disagree: with `A` present and `B` absent, `(!A) && B` is **false**
/// and `!(A && B)` is **true**.
///
/// **The obvious fixture does not work, and this test had it first.** With both
/// `A` and `B` present, `(!A) && B` and `!(A && B)` are both false; with both
/// absent, both are true. Only the mixed case separates them — measured, by a
/// mutation (`!` parsing its operand at the `&&` level) that reddened nothing
/// until this fixture was fixed.
@Test func notBindsTighterThanAnd() throws {
    #expect(try evaluate("!A && B", [ctx("A")]) == false,
            "parsed as (!A) && B; !(A && B) would give true")
    #expect(try evaluate("!A && B", [ctx("A"), ctx("B")]) == false,
            "both present: both readings give false, so this line pins nothing on its own")
}

@Test func parenthesesOverridePrecedence() throws {
    #expect(try evaluate("(A || B) && C", [ctx("A")]) == false)
    #expect(try evaluate("(A || B) && C", [ctx("A"), ctx("C")]))
    #expect(try evaluate("!(A && B)", [ctx("A"), ctx("B")]) == false)
    #expect(try evaluate("!(A && B)", [ctx("A")]))
}

/// A value may be quoted, which is the only way to write one containing a
/// space or an operator character.
@Test func aQuotedValueMayContainSpacesAndOperators() throws {
    #expect(try evaluate("mode == \"read only\"", [ctx("E", ["mode": "read only"])]))
    #expect(try evaluate("mode == \"a && b\"", [ctx("E", ["mode": "a && b"])]))
    #expect(try evaluate("mode == \"read only\"", [ctx("E", ["mode": "read"])]) == false)
}

/// **The test the "returns false for everything" parser cannot pass.**
///
/// A stub that answers `false` to every predicate satisfies every assertion
/// above that expects `false`, and satisfies a bare
/// `#expect(evaluate("&& ||") == false)` too. What it cannot do is answer
/// `nil` for the malformed half and non-`nil` for the well-formed half of this
/// pair — which is the whole of ruling "a malformed predicate never matches,
/// never traps, and must be DISTINGUISHABLE from one that legitimately
/// evaluated false".
@Test func aMalformedPredicateIsAParseFailureAndAWellFormedOneIsNot() throws {
    let malformed = ["&& ||", "Editor &&", "|| Editor", "mode ==", "== code",
                     "(Editor", "Editor)", "!", "Editor Terminal", "", "   ",
                     "mode = code", "\"unterminated"]
    for source in malformed {
        #expect(ContextPredicate.parse(source) == nil,
                "`\(source)` is malformed and must fail to parse")
    }
    // The differential: a well-formed predicate over an empty stack parses and
    // evaluates false. A parser that returned `nil` for everything would fail
    // here; one that returned a predicate for everything would fail above.
    let wellFormed = try #require(ContextPredicate.parse("Editor"))
    #expect(wellFormed.evaluate(against: []) == false)
}

/// Whitespace is not significant, and an operator needs no space around it.
@Test func whitespaceAroundOperatorsIsOptional() throws {
    #expect(try evaluate("Editor&&mode==code", [ctx("Editor", ["mode": "code"])]))
    #expect(try evaluate("  Editor   ", [ctx("Editor")]))
}

// MARK: - Keystroke parsing (framework spec §8.3)

@Test func aKeystrokeParsesItsModifiersAndItsKey() throws {
    let stroke = try #require(Keystroke("cmd-c"))
    #expect(stroke.key == "c")
    #expect(stroke.modifiers == .command)

    let two = try #require(Keystroke("ctrl-shift-k"))
    #expect(two.key == "k")
    #expect(two.modifiers == [.control, .shift])
}

/// A spelling that does not parse is `nil` rather than a `Keystroke` that never
/// matches — and the positive control is what keeps this from being satisfied
/// by an initializer that returns `nil` for everything (taxonomy shape 1).
@Test func aMalformedSpellingFailsToParseAndAWellFormedOneDoesNot() {
    #expect(Keystroke("meta-c") == nil, "unknown modifier name")
    #expect(Keystroke("") == nil, "empty")
    #expect(Keystroke("cmd-") == nil, "trailing separator with no key")
    #expect(Keystroke("cmd-enterr") == nil, "a multi-character key that names nothing")
    #expect(Keystroke("cmd-c") != nil, "the differential: a well-formed spelling parses")
}

/// `-` is both the separator and a plausible key, and the parser has a branch
/// for exactly that — untested, it is a composition living in the code and in
/// no test.
@Test func theSeparatorIsAlsoASpellableKey() throws {
    let bare = try #require(Keystroke("-"))
    #expect(bare.key == "-")
    #expect(bare.modifiers == [])

    let modified = try #require(Keystroke("cmd--"))
    #expect(modified.key == "-")
    #expect(modified.modifiers == .command)
}

/// The block spelling framework spec §8.3 uses, which is what Task 11's demo
/// will write.
@Test func aKeymapCanBeWrittenAsABlockOfBindings() throws {
    let keymap = Keymap {
        KeyBinding("cmd-i", Increment())
        KeyBinding("cmd-d", Decrement(), context: "Editor")
    }
    // `try #require`, not `#expect` — taxonomy shape 13. `#expect` records and
    // continues, so a `buildBlock` that dropped a binding would send the two
    // subscripts below past the end of the array and kill the whole run with
    // `Index out of range` and no summary line. Measured: `buildBlock`
    // returning `Array(bindings.prefix(1))` truncated the suite at 519 of 725
    // tests started.
    try #require(keymap.bindings.count == 2)
    #expect(keymap.bindings[0].spelling == "cmd-i")
    #expect(keymap.bindings[1].context == "Editor")
}

/// A named key resolves to the character `charactersIgnoringModifiers` actually
/// reports for it — otherwise `KeyBinding("cmd-enter", …)` would be an API that
/// compiles and never fires.
@Test func aNamedKeyResolvesToItsCharacter() throws {
    #expect(try #require(Keystroke("space")).key == " ")
    #expect(try #require(Keystroke("cmd-enter")).key == "\r")
    #expect(try #require(Keystroke("escape")).key == "\u{1b}")
    #expect(try #require(Keystroke("tab")).key == "\t")
}

/// **§8.3's Dvorak rule, pinned with an event whose two spellings differ.**
///
/// A test using an event where `characters == charactersIgnoringModifiers`
/// passes under either spelling and pins nothing. Here the layout reports `c`
/// for the unmodified key and `j` for the modified one, so matching on
/// `characters` fires the wrong binding and matching on
/// `charactersIgnoringModifiers` fires the right one.
@Test func matchingUsesCharactersIgnoringModifiersNotCharacters() throws {
    let event = KeyEvent(charactersIgnoringModifiers: "c", characters: "j",
                         modifiers: .command, timestamp: 0)
    #expect(try #require(Keystroke("cmd-c")).matches(event),
            "the binding is written against the unmodified layout character")
    #expect(try #require(Keystroke("cmd-j")).matches(event) == false,
            "and NOT against `characters`, which the modifier rewrote")
}

@Test func modifiersMustMatchExactly() throws {
    let plain = KeyEvent(charactersIgnoringModifiers: "c", characters: "c", timestamp: 0)
    let withCommand = KeyEvent(charactersIgnoringModifiers: "c", characters: "c",
                               modifiers: .command, timestamp: 0)
    let both = KeyEvent(charactersIgnoringModifiers: "c", characters: "c",
                        modifiers: [.command, .shift], timestamp: 0)
    #expect(try #require(Keystroke("c")).matches(plain))
    #expect(try #require(Keystroke("c")).matches(withCommand) == false)
    #expect(try #require(Keystroke("cmd-c")).matches(withCommand))
    #expect(try #require(Keystroke("cmd-c")).matches(both) == false,
            "a superset of the bound modifiers is not a match")
}

/// The key half is matched case-insensitively, because
/// `charactersIgnoringModifiers` folds shift in: shift-A reports `"A"`.
@Test func theKeyHalfIsMatchedCaseInsensitively() throws {
    let shifted = KeyEvent(charactersIgnoringModifiers: "A", characters: "A",
                           modifiers: .shift, timestamp: 0)
    #expect(try #require(Keystroke("shift-a")).matches(shifted))
    #expect(try #require(Keystroke("a")).matches(shifted) == false,
            "the modifier set still has to match")
}

// MARK: - Keymap matching

private struct Increment: Action, Equatable {}
private struct Decrement: Action, Equatable {}
private struct Outer: Action, Equatable {}
private struct Inner: Action, Equatable {}

/// Drives `matchKeymap` with no window, on the same footing as
/// `dispatchKey(_:along:in:)`: the interesting part is the rule, and a test
/// should not need a device to reach it.
private func match(_ keymap: Keymap, _ spelling: String, at timestamp: Double,
                   contexts: [KeyContext?] = [], pending: inout PendingStroke?) throws
    -> KeymapMatch
{
    let stroke = try #require(Keystroke(spelling))
    let event = KeyEvent(charactersIgnoringModifiers: stroke.key,
                         characters: stroke.key,
                         modifiers: stroke.modifiers,
                         timestamp: timestamp)
    return matchKeymap(event, in: keymap, contextsByLevel: contexts, pending: &pending)
}

@Test func aOneStrokeBindingResolvesToItsAction() throws {
    let keymap = Keymap([KeyBinding("cmd-i", Increment())])
    var pending: PendingStroke?
    guard case .action(let action) = try match(keymap, "cmd-i", at: 0, pending: &pending) else {
        Issue.record("expected an action"); return
    }
    #expect(action is Increment)
    #expect(pending == nil)
}

/// A keystroke nothing is bound to resolves to nothing — which is what lets it
/// fall through to the raw `onKey` bubble.
@Test func anUnboundKeystrokeMatchesNothing() throws {
    let keymap = Keymap([KeyBinding("cmd-i", Increment())])
    var pending: PendingStroke?
    guard case .none = try match(keymap, "cmd-x", at: 0, pending: &pending) else {
        Issue.record("expected no match"); return
    }
    // The differential: the same keymap and the bound keystroke do match, so
    // this is about `cmd-x` and not about a matcher that answers nothing.
    guard case .action = try match(keymap, "cmd-i", at: 0, pending: &pending) else {
        Issue.record("the bound keystroke still matches"); return
    }
}

/// **A binding with no context fires with nothing focused** — the empty chain
/// case, and the one the counter demo relies on.
@Test func aContextFreeBindingFiresWithAnEmptyFocusChain() throws {
    let keymap = Keymap([KeyBinding("cmd-i", Increment())])
    var pending: PendingStroke?
    guard case .action = try match(keymap, "cmd-i", at: 0, contexts: [], pending: &pending) else {
        Issue.record("a context-free binding must fire with nothing focused"); return
    }
}

@Test func aBindingWhoseContextIsAbsentDoesNotFire() throws {
    let keymap = Keymap([KeyBinding("cmd-i", Increment(), context: "Editor")])
    var pending: PendingStroke?
    guard case .none = try match(keymap, "cmd-i", at: 0,
                                 contexts: [ctx("Terminal")], pending: &pending) else {
        Issue.record("the context is absent, so the binding must not fire"); return
    }
    // The positive control: the same binding fires once the context is there.
    guard case .action = try match(keymap, "cmd-i", at: 0,
                                   contexts: [ctx("Editor")], pending: &pending) else {
        Issue.record("and fires when it is present"); return
    }
}

/// **The innermost context wins**, and the declaration order is deliberately
/// the *opposite* of the expected winner: a matcher that took the last (or the
/// first) declared binding would pass one of these two halves and fail the
/// other, so neither ordering rule can satisfy both.
@Test func theInnermostContextWins() throws {
    // Chain, innermost first: a leaf with no context, an `Editor` pane, a
    // `Pane` workspace.
    let chain: [KeyContext?] = [nil, ctx("Editor"), ctx("Pane")]

    let innerLast = Keymap([KeyBinding("cmd-k", Outer(), context: "Pane"),
                            KeyBinding("cmd-k", Inner(), context: "Editor")])
    var pending: PendingStroke?
    guard case .action(let a) = try match(innerLast, "cmd-k", at: 0,
                                          contexts: chain, pending: &pending) else {
        Issue.record("expected an action"); return
    }
    #expect(a is Inner, "the Editor binding is contributed innermost")

    let innerFirst = Keymap([KeyBinding("cmd-k", Inner(), context: "Editor"),
                             KeyBinding("cmd-k", Outer(), context: "Pane")])
    guard case .action(let b) = try match(innerFirst, "cmd-k", at: 0,
                                          contexts: chain, pending: &pending) else {
        Issue.record("expected an action"); return
    }
    #expect(b is Inner, "and still wins when it is declared first")
}

/// A context-free binding is the **outermost** of all, so a contextual one
/// beats it — otherwise a global fallback would shadow every specialisation.
@Test func aContextualBindingBeatsAContextFreeOne() throws {
    let keymap = Keymap([KeyBinding("cmd-k", Inner(), context: "Editor"),
                         KeyBinding("cmd-k", Outer())])
    var pending: PendingStroke?
    guard case .action(let a) = try match(keymap, "cmd-k", at: 0,
                                          contexts: [ctx("Editor")], pending: &pending) else {
        Issue.record("expected an action"); return
    }
    #expect(a is Inner)
}

/// **A negated predicate does not fire while the context it excludes is on
/// screen — and this is the only shape that reaches `contextDepth`'s scope
/// guard.**
///
/// Every other binding in this file has a *monotone* predicate: it holds on the
/// full stack and stops holding as the walk moves outward, so "the outermost
/// level at which it holds" already implies "it holds at all". A `!` predicate
/// is the reverse — `!Modal` is true at the empty outermost level *because* the
/// stack is empty there — so without the separate `evaluate(against: stacks[0])`
/// check a `!Modal` binding fires with a `Modal` in the chain. Measured:
/// deleting that guard leaves all 725 tests green, and this is the test that
/// stopped being true.
@Test func aNegatedPredicateDoesNotFireWhileItsExcludedContextIsInTheChain() throws {
    let keymap = Keymap([KeyBinding("cmd-i", Increment(), context: "!Modal")])
    var pending: PendingStroke?

    guard case .none = try match(keymap, "cmd-i", at: 0,
                                 contexts: [nil, ctx("Modal")], pending: &pending) else {
        Issue.record("`!Modal` must not fire while a Modal context is in the chain"); return
    }
    // The differential: the identical binding and keystroke against a chain
    // with no `Modal` in it.
    guard case .action = try match(keymap, "cmd-i", at: 0,
                                   contexts: [nil, ctx("Editor")], pending: &pending) else {
        Issue.record("and fires once the excluded context is gone"); return
    }
}

/// A malformed predicate never matches and never traps — and the binding it
/// sits on is simply inert, while its neighbours keep working.
@Test func aBindingWithAMalformedPredicateIsInertRatherThanFatal() throws {
    let keymap = Keymap([KeyBinding("cmd-i", Increment(), context: "&& ||"),
                         KeyBinding("cmd-d", Decrement())])
    var pending: PendingStroke?
    guard case .none = try match(keymap, "cmd-i", at: 0,
                                 contexts: [ctx("Editor")], pending: &pending) else {
        Issue.record("a binding whose predicate does not parse must not fire"); return
    }
    guard case .action = try match(keymap, "cmd-d", at: 0,
                                   contexts: [ctx("Editor")], pending: &pending) else {
        Issue.record("and it must not take its neighbours with it"); return
    }
}

// MARK: - Two-stroke sequences (framework spec §8.3)

@Test func aTwoStrokeSequenceFiresOnTheSecondStroke() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment())])
    var pending: PendingStroke?

    guard case .pending = try match(keymap, "ctrl-k", at: 10, pending: &pending) else {
        Issue.record("the first stroke records a prefix and claims the keystroke"); return
    }
    #expect(pending != nil, "the prefix is held")

    guard case .action(let action) = try match(keymap, "ctrl-f", at: 10.5,
                                               pending: &pending) else {
        Issue.record("the second stroke completes the sequence"); return
    }
    #expect(action is Increment)
    #expect(pending == nil, "and the prefix is cleared")
}

/// The first stroke of a sequence is **claimed**, not passed on — otherwise
/// `ctrl-k` would also reach the raw `onKey` bubble while the sequence is
/// still in flight.
@Test func aPrefixStrokeClaimsTheKeystroke() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment())])
    var pending: PendingStroke?
    guard case .pending = try match(keymap, "ctrl-k", at: 0, pending: &pending) else {
        Issue.record("expected .pending"); return
    }
}

/// **On expiry the prefix is DROPPED, not dispatched** (§8.3) — the half that
/// is easy to get backwards.
///
/// The second stroke arrives 1.5 s after the first *on the event's own clock*,
/// so the sequence must not complete.
@Test func aPrefixOlderThanOneSecondIsDroppedNotDispatched() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment())])
    var pending: PendingStroke?
    guard case .pending = try match(keymap, "ctrl-k", at: 100, pending: &pending) else {
        Issue.record("expected .pending"); return
    }
    let result = try match(keymap, "ctrl-f", at: 101.5, pending: &pending)
    if case .action = result {
        Issue.record("the stale prefix was dispatched; §8.3 says it is dropped")
    }
    #expect(pending == nil, "the stale prefix is gone either way")
}

/// **The timeout is ONE second, and this sits on the boundary.**
///
/// The two tests above bracket it only loosely: they pass for any timeout in
/// `[0.5, 1.49]`, measured — `twoStrokeTimeout = 0.5` and `= 1.49` both leave
/// the suite green, so a build shipping a half-second chord window would have
/// shipped. These two gaps are a thousandth of a second either side of the
/// figure §8.3 names, so only a one-second timeout satisfies both.
///
/// **The third assertion pins the COMPARISON, and the first two do not** — that
/// claim was in this comment before it was measured, and was false: `>` and
/// `>=` agree at 0.999 and at 1.001, so changing the operator left all 729
/// green. Only a gap of *exactly* the timeout separates them. §8.3's rule is
/// that a prefix "older than one second" is dropped, and a gap of exactly one
/// second is not older than one second, so the sequence completes. `1.0 - 0.0`
/// is exact in binary floating point, so the boundary case is deterministic
/// rather than a near-miss.
@Test func theTimeoutIsExactlyOneSecondOnBothSidesOfTheBoundary() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment())])
    var pending: PendingStroke?

    _ = try match(keymap, "ctrl-k", at: 0, pending: &pending)
    guard case .action = try match(keymap, "ctrl-f", at: 0.999, pending: &pending) else {
        Issue.record("a gap under one second must still complete the sequence"); return
    }

    pending = nil
    _ = try match(keymap, "ctrl-k", at: 0, pending: &pending)
    if case .action = try match(keymap, "ctrl-f", at: 1.001, pending: &pending) {
        Issue.record("a gap over one second must not complete the sequence")
    }

    pending = nil
    _ = try match(keymap, "ctrl-k", at: 0, pending: &pending)
    guard case .action = try match(keymap, "ctrl-f", at: 1, pending: &pending) else {
        Issue.record("exactly one second is not yet 'older than' one second: `>`, not `>=`")
        return
    }
}

/// **And the arriving keystroke is processed as a fresh first stroke.** Two
/// assertions, and this is the one that fails quietly: an implementation that
/// swallows the second stroke along with the stale prefix passes the test
/// above and eats a keypress.
@Test func aStalePrefixLetsTheArrivingKeystrokeActAsAFreshFirstStroke() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment()),
                         KeyBinding("ctrl-f", Decrement())])
    var pending: PendingStroke?
    guard case .pending = try match(keymap, "ctrl-k", at: 100, pending: &pending) else {
        Issue.record("expected .pending"); return
    }
    guard case .action(let action) = try match(keymap, "ctrl-f", at: 101.5,
                                               pending: &pending) else {
        Issue.record("the arriving keystroke must still be processed"); return
    }
    #expect(action is Decrement,
            "as a fresh FIRST stroke — not as the tail of the expired sequence")
}

/// **The timeout reads the event's own timestamp, not a wall clock.**
///
/// Both events below are dispatched back to back, so real elapsed time is
/// microseconds; only their stated timestamps are 5 s apart. An implementation
/// timing the gap with `Date()` or a display-link tick sees ~0 and completes
/// the sequence.
@Test func theTimeoutReadsTheEventsTimestampNotElapsedRealTime() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment())])
    var pending: PendingStroke?
    _ = try match(keymap, "ctrl-k", at: 0, pending: &pending)
    let result = try match(keymap, "ctrl-f", at: 5, pending: &pending)
    if case .action = result {
        Issue.record("timed against a real clock rather than the event's timestamp")
    }

    // The differential, on the same instrument: identical code, timestamps
    // 0.5 s apart, and the sequence completes. So the assertion above is about
    // the *timestamp* and not about two-stroke matching being broken.
    pending = nil
    _ = try match(keymap, "ctrl-k", at: 0, pending: &pending)
    guard case .action = try match(keymap, "ctrl-f", at: 0.5, pending: &pending) else {
        Issue.record("within the timeout, the same sequence completes"); return
    }
}

/// A second stroke that completes nothing is likewise processed as a fresh
/// first stroke rather than swallowed.
@Test func aSecondStrokeThatCompletesNothingIsProcessedAsAFreshFirstStroke() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment()),
                         KeyBinding("cmd-d", Decrement())])
    var pending: PendingStroke?
    _ = try match(keymap, "ctrl-k", at: 0, pending: &pending)
    guard case .action(let action) = try match(keymap, "cmd-d", at: 0.1,
                                               pending: &pending) else {
        Issue.record("expected the arriving keystroke to be processed"); return
    }
    #expect(action is Decrement)
    #expect(pending == nil)
}

/// An exact one-stroke binding wins over a prefix of the same spelling —
/// otherwise the one-stroke binding would be unreachable.
@Test func anExactOneStrokeMatchWinsOverAPrefix() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment()),
                         KeyBinding("ctrl-k", Decrement())])
    var pending: PendingStroke?
    guard case .action(let action) = try match(keymap, "ctrl-k", at: 0, pending: &pending) else {
        Issue.record("the exact binding must fire"); return
    }
    #expect(action is Decrement)
    #expect(pending == nil, "and no prefix is left pending")
}

/// §8.3 supports one- and two-stroke sequences, so a three-stroke spelling is
/// **inert** — the same answer as a malformed one, and it takes no neighbour
/// with it.
@Test func aSequenceOfMoreThanTwoStrokesIsInert() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f ctrl-g", Increment()),
                         KeyBinding("ctrl-k", Decrement())])
    var pending: PendingStroke?
    guard case .action(let action) = try match(keymap, "ctrl-k", at: 0, pending: &pending) else {
        Issue.record("the two-stroke-or-fewer neighbour still fires"); return
    }
    #expect(action is Decrement)
    #expect(pending == nil, "and the three-stroke binding recorded no prefix")
}

/// **A live prefix's completion beats a single-stroke binding on the second
/// stroke** — the exact inverse of `anExactOneStrokeMatchWinsOverAPrefix`, and
/// the assertion that pins step 2 ahead of step 3 in `matchKeymap`.
///
/// Without it, swapping those two steps is a plausible refactor that no test
/// notices: `"ctrl-f"` alone would fire and the sequence the user was halfway
/// through would be unreachable.
@Test func aCompletionBeatsASingleStrokeBindingOnTheSecondStroke() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment()),
                         KeyBinding("ctrl-f", Decrement())])
    var pending: PendingStroke?
    _ = try match(keymap, "ctrl-k", at: 0, pending: &pending)
    guard case .action(let action) = try match(keymap, "ctrl-f", at: 0.1,
                                               pending: &pending) else {
        Issue.record("expected an action"); return
    }
    #expect(action is Increment, "the sequence completes rather than `ctrl-f` firing alone")

    // The differential: the same `ctrl-f` with no prefix in flight fires the
    // single-stroke binding, so this is about the prefix and not about
    // `"ctrl-f"` being unreachable.
    guard case .action(let alone) = try match(keymap, "ctrl-f", at: 5,
                                              pending: &pending) else {
        Issue.record("expected an action"); return
    }
    #expect(alone is Decrement)
}

/// A two-stroke binding's context is evaluated on the **second** stroke, and a
/// sequence whose context is absent completes into nothing.
@Test func aTwoStrokeBindingHonoursItsContext() throws {
    let keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment(), context: "Editor")])
    var pending: PendingStroke?
    guard case .pending = try match(keymap, "ctrl-k", at: 0,
                                    contexts: [ctx("Editor")], pending: &pending) else {
        Issue.record("expected .pending"); return
    }
    guard case .action = try match(keymap, "ctrl-f", at: 0.1,
                                   contexts: [ctx("Editor")], pending: &pending) else {
        Issue.record("expected the sequence to complete in context"); return
    }
    // And out of context the same first stroke records no prefix at all.
    guard case .none = try match(keymap, "ctrl-k", at: 1,
                                 contexts: [ctx("Terminal")], pending: &pending) else {
        Issue.record("out of context, the prefix must not even be recorded"); return
    }
}

// MARK: - Dispatch through a real Window

/// Records which handlers ran, in order. A reference type for `KeyLog`'s
/// reason: the content closure rebuilds the element every frame.
private final class ActionLog {
    var names: [String] = []
}

private func rootID(_ name: String) -> GlobalElementID {
    GlobalElementID.child(of: nil, at: 0, name: ElementID(name))
}

private func keyDown(_ characters: String, _ modifiers: Modifiers = [],
                     at timestamp: Double = 0) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                      modifiers: modifiers, timestamp: timestamp))
}

private func keyUp(_ characters: String, _ modifiers: Modifiers = [],
                   at timestamp: Double = 0) -> InputEvent {
    .keyUp(KeyEvent(charactersIgnoringModifiers: characters, characters: characters,
                    modifiers: modifiers, timestamp: timestamp))
}

@Test @MainActor func aBoundActionReachesAnElementHandlerAlongTheFocusChain() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().cssWidth(px(40)).cssHeight(px(40)).id("a")
            .focusable()
            .onAction(Increment.self) { _ in log.names.append("element") }
    }
    window.keymap = Keymap([KeyBinding("cmd-i", Increment())])
    window.drawFrameIfNeeded()
    window.focus(rootID("a"))

    platformWindow.simulateInput(keyDown("i", .command))
    #expect(log.names == ["element"])
}

/// The action bubbles the focus chain, skipping an element that registered a
/// handler for a **different** action type — dispatch is by type identity
/// (§4.1), not "the first element with any handler".
@Test @MainActor func anActionBubblesPastAnElementThatDoesNotHandleIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box {
            Box().frame(width: px(20), height: px(20)).id("leaf")
                .focusable()
                .onAction(Decrement.self) { _ in log.names.append("leaf-decrement") }
        }
        .id("root")
        .onAction(Increment.self) { _ in log.names.append("root-increment") }
    }
    window.keymap = Keymap([KeyBinding("cmd-i", Increment())])
    window.drawFrameIfNeeded()
    let root = rootID("root")
    window.focus(GlobalElementID.child(of: root, at: 0, name: ElementID("leaf")))

    platformWindow.simulateInput(keyDown("i", .command))
    #expect(log.names == ["root-increment"],
            "the leaf handles a different type, so the action bubbled past it")
}

/// **The ordering pin: a bound action runs BEFORE the raw `onKey` bubble, and
/// claims the keystroke.**
///
/// Both bubbles walk the same chain, so a dispatcher that ran `onKey` first
/// would log `raw` and never reach the action. Reversing the two lines in
/// `Window.onInput` reddens exactly this.
@Test @MainActor func aBoundActionRunsBeforeARawOnKeyHandler() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().cssWidth(px(40)).cssHeight(px(40)).id("a")
            .focusable()
            .onKey { _ in log.names.append("raw"); return true }
            .onAction(Increment.self) { _ in log.names.append("action") }
    }
    window.keymap = Keymap([KeyBinding("cmd-i", Increment())])
    window.drawFrameIfNeeded()
    window.focus(rootID("a"))

    platformWindow.simulateInput(keyDown("i", .command))
    #expect(log.names == ["action"],
            "the keymap is the declaration of intent; the raw handler is the escape hatch")

    // The differential: the same element, an unbound keystroke, and the raw
    // handler is the one that runs — so the two bubbles have not collapsed
    // into each other.
    platformWindow.simulateInput(keyDown("x"))
    #expect(log.names == ["action", "raw"])
}

/// A bound action nobody handles is **not** a swallow: it falls through to the
/// raw key bubble, so a binding to an action with no handler behaves as if
/// unbound rather than eating the keystroke silently.
@Test @MainActor func anUnhandledActionFallsThroughToTheRawKeyBubble() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().cssWidth(px(40)).cssHeight(px(40)).id("a")
            .focusable()
            .onKey { _ in log.names.append("raw"); return true }
    }
    window.keymap = Keymap([KeyBinding("cmd-i", Increment())])
    window.drawFrameIfNeeded()
    window.focus(rootID("a"))

    platformWindow.simulateInput(keyDown("i", .command))
    #expect(log.names == ["raw"])

    // **The differential, and without it this test also passes against a
    // keymap that was never implemented at all.** Give the action a handler —
    // at the window, since the element has none — and the same keystroke stops
    // reaching the raw bubble. So the assertion above is about an *unhandled*
    // action falling through, not about the keymap doing nothing.
    window.onAction = { _ in log.names.append("window"); return true }
    platformWindow.simulateInput(keyDown("i", .command))
    #expect(log.names == ["raw", "window"])
}

/// Unhandled along the chain, an action reaches the **window** — which is what
/// makes a binding work with nothing focused at all.
@Test @MainActor func anActionUnhandledInTheChainReachesTheWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().frame(width: px(40), height: px(40)).id("a")
    }
    window.keymap = Keymap([KeyBinding("cmd-i", Increment())])
    window.onAction = { action in
        guard action is Increment else { return false }
        log.names.append("window")
        return true
    }
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "nothing is focused")

    platformWindow.simulateInput(keyDown("i", .command))
    #expect(log.names == ["window"])
}

/// **A key context is contributed by any element, focusable or not** — the
/// ancestor pane names the context and the focused leaf knows nothing about
/// it.
@Test @MainActor func aKeyContextIsContributedByANonFocusableAncestor() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box {
            Box().frame(width: px(20), height: px(20)).id("leaf")
                .focusable()
                .onAction(Increment.self) { _ in log.names.append("leaf") }
        }
        .id("pane")
        .keyContext("Editor", ["mode": "code"])
    }
    window.keymap = Keymap([KeyBinding("cmd-i", Increment(),
                                    context: "Editor && mode == code")])
    window.drawFrameIfNeeded()
    let pane = rootID("pane")
    window.focus(GlobalElementID.child(of: pane, at: 0, name: ElementID("leaf")))

    platformWindow.simulateInput(keyDown("i", .command))
    #expect(log.names == ["leaf"],
            "the pane is neither focusable nor a key handler and still contributes")
}

/// The context registration is not a hitbox: a `.keyContext` element stays
/// transparent to the pointer, exactly as `.focusable()` does.
@Test @MainActor func aKeyContextRegistersNoPointerHitbox() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device, size: 100) {
        Box().cssWidth(px(40)).cssHeight(px(40)).id("a").keyContext("Editor")
    }
    window.drawFrameIfNeeded()
    #expect(window.lastHitboxes.isEmpty,
            "contributing a context must not make an element opaque to the pointer")
    // The positive control: the context really was registered, so the line
    // above is about the *pointer* gate rather than about `.keyContext(_:_:)`
    // being inert.
    #expect(window.lastFocusRegistry.context(for: rootID("a")) == KeyContext("Editor"))
}

/// **A `keyUp` dispatches no action, and does not disturb a pending prefix.**
///
/// Two assertions and both were unpinned. Without the first, every bound action
/// fires **twice per keypress** — measured, `fired == 2` for one press-and-release
/// of `cmd-i`. Without the second, the release of a sequence's own first stroke
/// would consume the prefix and no two-stroke binding could ever complete.
///
/// `dispatchKey` is `keyDown`-only for its own reason (a `KeyEvent` carries no
/// down/up discriminator, so an `onKey` handed both could not tell them apart);
/// this is a second, independent reason for the same guard on the same event.
@Test @MainActor func aKeyUpDispatchesNoActionAndLeavesAPendingPrefixAlone() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().frame(width: px(40), height: px(40)).id("a")
    }
    window.onAction = { action in
        log.names.append(action is Increment ? "increment" : "decrement")
        return true
    }
    window.keymap = Keymap([KeyBinding("cmd-i", Decrement()),
                            KeyBinding("ctrl-k ctrl-f", Increment())])
    window.drawFrameIfNeeded()

    // One press and one release of a bound keystroke is ONE action.
    platformWindow.simulateInput(keyDown("i", .command, at: 0))
    platformWindow.simulateInput(keyUp("i", .command, at: 0.05))
    #expect(log.names == ["decrement"], "the release must not fire the binding a second time")

    // And a release between the two strokes of a sequence does not eat the
    // prefix.
    platformWindow.simulateInput(keyDown("k", .control, at: 1))
    platformWindow.simulateInput(keyUp("k", .control, at: 1.05))
    platformWindow.simulateInput(keyDown("f", .control, at: 1.1))
    #expect(log.names == ["decrement", "increment"],
            "the sequence completed across its own key releases")
}

/// Assigning a new keymap drops a pending prefix: a `ctrl-k` recorded against
/// the old bindings means nothing under the new ones.
@Test @MainActor func replacingTheKeymapDropsAPendingPrefix() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().frame(width: px(40), height: px(40)).id("a")
    }
    window.onAction = { action in
        log.names.append(action is Increment ? "increment" : "decrement")
        return true
    }
    window.keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment()),
                            KeyBinding("ctrl-f", Decrement())])
    window.drawFrameIfNeeded()

    platformWindow.simulateInput(keyDown("k", .control, at: 0))
    window.keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment()),
                            KeyBinding("ctrl-f", Decrement())])
    platformWindow.simulateInput(keyDown("f", .control, at: 0.1))
    #expect(log.names == ["decrement"],
            "the prefix was dropped, so the second stroke is a fresh first one")

    // The differential on the same instrument: without the reassignment the
    // identical pair completes the sequence.
    platformWindow.simulateInput(keyDown("k", .control, at: 1))
    platformWindow.simulateInput(keyDown("f", .control, at: 1.1))
    #expect(log.names == ["decrement", "increment"])
}

/// A two-stroke sequence driven through a real `Window`, with the timestamps
/// carried by the events themselves.
@Test @MainActor func aTwoStrokeSequenceDispatchesThroughTheWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = ActionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Box().cssWidth(px(40)).cssHeight(px(40)).id("a")
            .focusable()
            .onKey { _ in log.names.append("raw"); return true }
            .onAction(Increment.self) { _ in log.names.append("action") }
    }
    window.keymap = Keymap([KeyBinding("ctrl-k ctrl-f", Increment())])
    window.drawFrameIfNeeded()
    window.focus(rootID("a"))

    platformWindow.simulateInput(keyDown("k", .control, at: 100))
    #expect(log.names.isEmpty, "the prefix fires nothing and is claimed")
    platformWindow.simulateInput(keyDown("f", .control, at: 100.4))
    #expect(log.names == ["action"])

    // And with the second stroke late, the prefix is dropped and the arriving
    // keystroke falls through to the raw handler instead.
    platformWindow.simulateInput(keyDown("k", .control, at: 200))
    platformWindow.simulateInput(keyDown("f", .control, at: 201.5))
    #expect(log.names == ["action", "raw"])
}
