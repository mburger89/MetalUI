import MetalUIPlatform

/// One key press: a set of modifiers and the character the **unmodified**
/// layout reports for the physical key.
///
/// **`charactersIgnoringModifiers`, never a physical key code and never
/// `characters`** — framework spec §8.3's Dvorak and AZERTY rule. Matching on
/// a key code binds a shortcut to a position on a US keyboard; matching on
/// `characters` binds it to whatever the modifier rewrote the key into, which
/// on several layouts is a different letter entirely. Pinned by
/// `matchingUsesCharactersIgnoringModifiersNotCharacters`, whose event reports
/// two *different* spellings so the test cannot pass under both.
public struct Keystroke: Equatable, Sendable {
    /// The character to compare against `KeyEvent.charactersIgnoringModifiers`
    /// — lower-cased for letters, and the literal control character for a named
    /// key such as `space` or `escape`.
    public var key: String
    public var modifiers: Modifiers

    /// Parses one stroke: zero or more `-`-separated modifier names followed by
    /// a key.
    ///
    /// `"cmd-c"`, `"ctrl-shift-k"`, `"space"`, `"cmd-enter"`. Recognised
    /// modifiers are `cmd`/`command`, `ctrl`/`control`, `alt`/`opt`/`option`
    /// and `shift`; the key is either a single character or one of the names in
    /// `namedKeys`.
    ///
    /// **`nil` for anything else, rather than a `Keystroke` that never
    /// matches.** An unknown modifier name, a trailing separator or a
    /// multi-character key that is not a known name are all failures a caller
    /// can see — `KeyBinding("cmd-enterr", …)` would otherwise be a binding that
    /// compiles, parses and silently never fires, which is exactly the shape
    /// CLAUDE.md's declared-but-inert table exists to prevent.
    public init?(_ spelling: String) {
        // `-` is both the separator and a plausible key, so the trailing
        // component is examined before splitting decides anything.
        let components = spelling.split(separator: "-", omittingEmptySubsequences: false)
                                 .map(String.init)
        var names: [String]
        var rawKey: String
        if components.count >= 2, components[components.count - 1].isEmpty,
           components[components.count - 2].isEmpty {
            // "cmd--" and "-": the key IS the separator.
            rawKey = "-"
            names = Array(components.dropLast(2))
        } else if let last = components.last, !last.isEmpty {
            rawKey = last
            names = Array(components.dropLast())
        } else {
            return nil  // "" or a trailing separator such as "cmd-"
        }

        var modifiers: Modifiers = []
        for name in names {
            guard let modifier = Self.modifierNames[name.lowercased()] else { return nil }
            modifiers.insert(modifier)
        }
        if let named = Self.namedKeys[rawKey.lowercased()] {
            rawKey = named
        } else if rawKey.count != 1 {
            return nil
        }
        self.key = rawKey.lowercased()
        self.modifiers = modifiers
    }

    /// Whether `event` is this keystroke.
    ///
    /// **The modifier set must match exactly**, not merely contain: `"c"` does
    /// not match cmd-C, and `"cmd-c"` does not match cmd-shift-C. A subset test
    /// would make every unmodified binding fire under every modifier
    /// combination, and `"cmd-c"` would shadow `"cmd-shift-c"`.
    ///
    /// The key half is compared case-insensitively because
    /// `charactersIgnoringModifiers` folds shift in — the shift-A key reports
    /// `"A"` — so the modifier set is what distinguishes `"a"` from
    /// `"shift-a"`.
    func matches(_ event: KeyEvent) -> Bool {
        event.modifiers == modifiers
            && event.charactersIgnoringModifiers.lowercased() == key
    }

    static let modifierNames: [String: Modifiers] = [
        "cmd": .command, "command": .command,
        "ctrl": .control, "control": .control,
        "alt": .option, "opt": .option, "option": .option,
        "shift": .shift,
    ]

    /// Keys with no printable spelling, mapped to what
    /// `charactersIgnoringModifiers` actually reports for them — the function
    /// keys and arrows land in Unicode's private-use area, which is AppKit's
    /// long-standing convention (`NSUpArrowFunctionKey` and friends).
    static let namedKeys: [String: String] = [
        "space": " ",
        "tab": "\t",
        "enter": "\r", "return": "\r",
        "escape": "\u{1b}", "esc": "\u{1b}",
        "delete": "\u{7f}", "backspace": "\u{7f}",
        "up": "\u{f700}", "down": "\u{f701}",
        "left": "\u{f702}", "right": "\u{f703}",
        "home": "\u{f729}", "end": "\u{f72b}",
        "pageup": "\u{f72c}", "pagedown": "\u{f72d}",
        "f1": "\u{f704}", "f2": "\u{f705}", "f3": "\u{f706}", "f4": "\u{f707}",
        "f5": "\u{f708}", "f6": "\u{f709}", "f7": "\u{f70a}", "f8": "\u{f70b}",
        "f9": "\u{f70c}", "f10": "\u{f70d}", "f11": "\u{f70e}", "f12": "\u{f70f}",
    ]
}

/// One keystroke sequence bound to one action, optionally scoped by a context
/// predicate (framework spec §8.3).
///
/// ```swift
/// KeyBinding("cmd-c",         Copy(),           context: "Editor")
/// KeyBinding("ctrl-k ctrl-f", FormatDocument(), context: "Editor && mode == code")
/// ```
///
/// **The spelling stays a `String` rather than being parsed in `init`**, so a
/// `KeyBinding` is a plain value with no failable initializer and a keymap can be
/// written as a literal list. A spelling that does not parse makes *that*
/// binding inert and nothing else — same rule as a malformed `context`.
///
/// **Named `KeyBinding`, not `Binding`** (ruling `EV-N`): `Binding` is the
/// SwiftUI value binding (`Binding.swift`, `DD-D`). The deprecated
/// `typealias Binding = KeyBinding` that bridged task 9's rename was deleted
/// with that type's arrival (`DD-D` item 6); `Binding("m", ToggleModal())` no
/// longer compiles (`theKeyBindingAliasIsGoneSoBindingNamesTheValueBinding`).
public struct KeyBinding {
    /// One or two `-`-separated strokes, separated from each other by a space:
    /// `"cmd-c"`, `"ctrl-k ctrl-f"`.
    public var spelling: String
    public var action: any Action
    /// A `ContextPredicate` source, or `nil` for a binding that is in scope
    /// everywhere — including with nothing focused at all.
    public var context: String?

    public init(_ spelling: String, _ action: any Action, context: String? = nil) {
        self.spelling = spelling
        self.action = action
        self.context = context
    }

    /// The parsed strokes, or `nil` when the spelling is malformed or names
    /// more than the two strokes §8.3 supports.
    var strokes: [Keystroke]? {
        let parsed = spelling.split(separator: " ").map { Keystroke(String($0)) }
        guard (1...2).contains(parsed.count), !parsed.contains(where: { $0 == nil }) else {
            return nil
        }
        return parsed.map { $0! }
    }
}

/// A window's key bindings.
///
/// ```swift
/// window.keymap = Keymap {
///     KeyBinding("cmd-i", Increment())
///     KeyBinding("cmd-k", Format(), context: "Editor")
/// }
/// ```
///
/// **A flat list, resolved per keystroke.** There is no trie and no
/// precomputation: a keymap is tens of entries and the resolution runs once per
/// key press, so the cost is not worth a structure that would have to be
/// invalidated whenever the list changed.
public struct Keymap {
    public var bindings: [KeyBinding]
    public init(_ bindings: [KeyBinding] = []) { self.bindings = bindings }
    public init(@KeymapBuilder _ bindings: () -> [KeyBinding]) { self.bindings = bindings() }
}

/// Lets a `Keymap` be written as a block of `KeyBinding`s, which is the spelling
/// framework spec §8.3 uses.
///
/// **`buildBlock` only.** `buildOptional`, `buildEither` and `buildArray` would
/// let a keymap block hold an `if` or a `for`, and each is a method that would
/// ship untested — the declared-and-inert shape CLAUDE.md's own table exists to
/// prevent. A caller who needs a conditional binding today builds the array and
/// uses `Keymap(_:)`; whoever needs the block form adds the method and its test
/// in the same change.
@resultBuilder
public enum KeymapBuilder {
    public static func buildBlock(_ bindings: KeyBinding...) -> [KeyBinding] { bindings }
}

/// The first stroke of a two-stroke sequence, held until the second arrives or
/// the sequence times out.
///
/// The timestamp is the **event's own**, never a clock read when the prefix was
/// stored — see `KeyEvent.timestamp`.
struct PendingStroke: Equatable {
    var stroke: Keystroke
    var timestamp: Double
}

/// What resolving a keystroke against a keymap produced.
enum KeymapMatch {
    /// A binding fired. The keystroke is claimed **only if something handles
    /// the action** — see `Window.dispatchAction(_:)`.
    case action(any Action)
    /// The first stroke of a two-stroke sequence was recorded. The keystroke is
    /// claimed unconditionally: a `ctrl-k` in flight must not also reach a raw
    /// `onKey` handler.
    case pending
    /// Nothing matched. The keystroke falls through to the raw key bubble.
    case none
}

/// Framework spec §8.3's pending-prefix timeout, in seconds.
///
/// **Pinned on both sides of the boundary and ON it**, by
/// `theTimeoutIsExactlyOneSecondOnBothSidesOfTheBoundary` — a gap of 0.999
/// completes, one of 1.001 does not, and one of exactly 1.0 completes. The two
/// ordinary two-stroke tests bracket this only to `[0.5, 1.49]`, measured, so
/// without that test a build shipping a half-second chord window would have
/// been green.
///
/// **The comparison below is `>` rather than `>=`, and only the exactly-1.0
/// assertion can see the difference** — measured: `>=` leaves 729 tests green
/// when the boundary case is absent. §8.3 drops a prefix "older than" one
/// second, and a gap of exactly one second is not older than one second.
let twoStrokeTimeout: Double = 1

/// Resolves `event` against `keymap`, given the key contexts along the focus
/// chain, and updates the pending two-stroke prefix.
///
/// `contextsByLevel` is **innermost first** — one entry per focus-chain level,
/// `nil` where that element contributed no context. An empty array means
/// nothing is focused, which is a supported case rather than a degenerate one:
/// a context-free binding still fires.
///
/// **Four steps, in this order, and each ordering choice is load-bearing.**
///
/// 1. **A prefix older than `twoStrokeTimeout` is dropped** (§8.3: dropped, not
///    dispatched), measured against `event.timestamp` — the arriving event's
///    own clock, never a clock read here.
/// 2. **A live prefix is offered the completion first.** If some binding's two
///    strokes are the held prefix followed by this event, it fires.
/// 3. **An exact one-stroke binding beats a prefix.** Reversing 3 and 4 makes
///    `KeyBinding("ctrl-k", …)` unreachable whenever any `"ctrl-k …"` sequence
///    exists.
/// 4. **Otherwise a first stroke is recorded** and the keystroke is claimed.
///
/// **A prefix that completes nothing does not swallow the arriving keystroke.**
/// Steps 3 and 4 run whether or not step 2 found anything, so an expired or
/// unmatched prefix is discarded and the new key is processed as a fresh first
/// stroke — what every editor does, and the alternative silently eats a
/// keypress. Two tests, because they are two assertions:
/// `aPrefixOlderThanOneSecondIsDroppedNotDispatched` says the prefix is gone,
/// and `aStalePrefixLetsTheArrivingKeystrokeActAsAFreshFirstStroke` says the
/// keystroke still works.
///
/// **A context that vanishes between the two strokes drops the sequence**, and
/// clears the prefix — measured, correct, and deliberately not pinned by a test
/// of its own: it is `bestBinding` finding no in-scope completion, which is the
/// same path `aSecondStrokeThatCompletesNothingIsProcessedAsAFreshFirstStroke`
/// already covers with a different reason for the miss. Recorded here so the
/// composition is written down somewhere.
///
/// **A pending prefix survives a mouse click**, and that is a decision rather
/// than an oversight. Nothing outside this function touches `pending`, so
/// `ctrl-k`, a click, then `ctrl-f` within the second still completes the
/// sequence — measured. Most editors cancel a chord on a click; this one does
/// not, because the only thing that would make that possible is `Window`
/// reaching into the prefix from its pointer path, and the 1-second timeout
/// already bounds how long a forgotten prefix can surprise anybody. Revisit it
/// when there is a text field to lose focus from, not before.
///
/// A free function over explicit state, on `dispatchKey(_:along:in:)`'s
/// footing: every test above drives this without a window or a device.
func matchKeymap(_ event: KeyEvent, in keymap: Keymap,
                 contextsByLevel: [KeyContext?],
                 pending: inout PendingStroke?) -> KeymapMatch {
    let stacks = contextStacks(contextsByLevel)

    var prefix = pending
    if let held = prefix, event.timestamp - held.timestamp > twoStrokeTimeout {
        prefix = nil
    }
    // Cleared unconditionally: whatever happens below either completes the
    // sequence or starts a new one, and neither leaves the old prefix standing.
    pending = nil

    if let held = prefix,
       let completion = bestBinding(keymap, stacks: stacks, where: { strokes in
           strokes.count == 2 && strokes[0] == held.stroke && strokes[1].matches(event)
       }) {
        return .action(completion.binding.action)
    }

    if let exact = bestBinding(keymap, stacks: stacks, where: { strokes in
        strokes.count == 1 && strokes[0].matches(event)
    }) {
        return .action(exact.binding.action)
    }

    if let opening = bestBinding(keymap, stacks: stacks, where: { strokes in
        strokes.count == 2 && strokes[0].matches(event)
    }) {
        pending = PendingStroke(stroke: opening.strokes[0], timestamp: event.timestamp)
        return .pending
    }

    return .none
}

/// The context stacks visible at each level of the focus chain, **plus one**:
/// `stacks[i]` holds every context contributed at level `i` or outward, and
/// `stacks[count]` is empty.
///
/// The extra empty level is not padding — it is where a context-free binding
/// sits, which is what makes "a contextual binding beats a global one" fall out
/// of the same comparison rather than needing a special case.
private func contextStacks(_ levels: [KeyContext?]) -> [[KeyContext]] {
    var stacks: [[KeyContext]] = Array(repeating: [], count: levels.count + 1)
    for i in stride(from: levels.count - 1, through: 0, by: -1) {
        var stack = stacks[i + 1]
        if let context = levels[i] { stack.insert(context, at: 0) }
        stacks[i] = stack
    }
    return stacks
}

/// The binding accepted by `isCandidate` whose context is contributed
/// **innermost**, or `nil` if none is in scope.
///
/// Ties — two bindings in scope at the same depth — go to the one declared
/// **last**, the conventional "a later keymap overrides an earlier one".
private func bestBinding(_ keymap: Keymap, stacks: [[KeyContext]],
                         where isCandidate: ([Keystroke]) -> Bool)
    -> (binding: KeyBinding, strokes: [Keystroke])?
{
    var best: (binding: KeyBinding, strokes: [Keystroke])?
    var bestDepth = Int.max
    for binding in keymap.bindings {
        guard let strokes = binding.strokes, isCandidate(strokes) else { continue }
        guard let depth = contextDepth(binding.context, stacks) else { continue }
        if depth <= bestDepth {
            bestDepth = depth
            best = (binding, strokes)
        }
    }
    return best
}

/// How deep in the focus chain the innermost context this predicate needs was
/// contributed — smaller is more deeply nested — or `nil` when the predicate is
/// not satisfied at all, or does not parse.
///
/// **Two questions, and separating them is the whole of "innermost wins".**
/// Whether the binding is *in scope* is asked once, against the full stack the
/// focused element sees (`stacks[0]`). Its *depth* is then the outermost level
/// at which it still holds: a predicate naming `Editor` stops holding as soon
/// as the walk passes the element that contributed `Editor`, so the level where
/// it last held is that element's own.
///
/// **The scope question is redundant for every predicate WITHOUT a `!`, and
/// that is why it is easy to delete.** A monotone predicate that holds anywhere
/// holds on the full stack, so "the outermost level at which it holds" already
/// implies "it is in scope". A negated one is the reverse: `!Modal` is true at
/// the empty outermost level precisely *because* the stack is empty there, so
/// dropping the guard makes a `!Modal` binding fire with a `Modal` in the
/// chain. Measured — deleting it leaves 725 tests green — which is why
/// `aNegatedPredicateDoesNotFireWhileItsExcludedContextIsInTheChain` exists and
/// is the only test that reaches this line.
///
/// A binding with no context has depth `stacks.count - 1`, the empty outermost
/// level — outside everything, so any contextual binding beats it.
private func contextDepth(_ source: String?, _ stacks: [[KeyContext]]) -> Int? {
    guard let source else { return stacks.count - 1 }
    // A malformed predicate makes its own binding inert and nothing else: it
    // is skipped here rather than trapping or evaluating to `false`, so that
    // "did not parse" and "evaluated false" stay distinguishable at the one
    // place that can tell them apart. See `ContextPredicate.parse`.
    guard let predicate = ContextPredicate.parse(source) else { return nil }
    guard predicate.evaluate(against: stacks[0]) else { return nil }
    var depth = 0
    for level in stacks.indices where predicate.evaluate(against: stacks[level]) {
        depth = level
    }
    return depth
}
