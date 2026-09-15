/// A named context an element contributes for its whole subtree, with optional
/// string-valued attributes — framework spec §8.3's
/// `.keyContext("Editor", ["mode": "code"])`.
///
/// **Values are `String`s**, by the framework spec, and the predicate language
/// compares them for equality only. That is deliberately less than a scripting
/// language: a keymap is data loaded at runtime, so every operator it gains is
/// an operator whose failure mode has to be designed.
public struct KeyContext: Equatable, Sendable {
    public var name: String
    public var values: [String: String]
    public init(_ name: String, _ values: [String: String] = [:]) {
        self.name = name
        self.values = values
    }
}

/// A parsed context predicate — `identifier`, `key == value`, `&&`, `||`, `!`
/// and parentheses (framework spec §8.3, design spec §4.3).
///
/// **Parsed once into a tree rather than matched as a substring.** Design spec
/// §4.3 calls it "a small pure function with no engine coupling — the most
/// heavily testable unit in the milestone, and worth building properly": a
/// substring match cannot express precedence, cannot express `!`, and answers
/// `true` for `"Editor"` against a context named `"EditorPane"`.
///
/// **`parse` returns `nil` on malformed input and never traps, and evaluation
/// of an unparseable predicate never happens at all.** A keymap is data — a
/// typo in one must not kill the app — but "returns false" is this repo's
/// most-recorded bug shape, so the failure is a value the caller can *see*
/// rather than an answer indistinguishable from a legitimate `false`.
/// `matchKeymap` skips a binding whose predicate does not parse; that binding
/// is inert and its neighbours are unaffected. Pinned by
/// `aMalformedPredicateIsAParseFailureAndAWellFormedOneIsNot`, whose two halves
/// no constant-answer implementation can satisfy together.
///
/// **Precedence is the conventional one**: `!` binds tighter than `&&`, which
/// binds tighter than `||`. Both are pinned with fixtures on which the two
/// readings *disagree* — `andBindsTighterThanOr` and `notBindsTighterThanAnd`.
public struct ContextPredicate {
    /// The parsed expression.
    ///
    /// `indirect` because `not`/`and`/`or` hold `Node`s; the tree is built once
    /// per parse and evaluated per keystroke.
    indirect enum Node: Equatable {
        /// `Editor` — true when some context in the stack has that name.
        case identifier(String)
        /// `mode == code` — true when some context in the stack maps that key
        /// to that value.
        case comparison(key: String, value: String)
        case not(Node)
        case and(Node, Node)
        case or(Node, Node)
    }

    let root: Node

    init(root: Node) { self.root = root }

    /// Parses `source`, or returns `nil` if it is malformed.
    ///
    /// An empty or whitespace-only string is malformed. "No predicate at all"
    /// is spelled by passing no context to a `KeyBinding`, which is a different
    /// thing from a predicate that failed to parse: the first always matches,
    /// the second never does.
    public static func parse(_ source: String) -> ContextPredicate? {
        guard let tokens = Lexer.tokenize(source) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let node = parser.parseOr(), parser.isAtEnd else { return nil }
        return ContextPredicate(root: node)
    }

    /// Whether `stack` satisfies this predicate.
    ///
    /// **Every context in the stack is consulted for every term**, so an
    /// ancestor pane's `mode` is visible to a predicate evaluated for a
    /// descendant. The stack's *order* is irrelevant here and load-bearing one
    /// level up: `matchKeymap` evaluates a predicate against several suffixes
    /// of the focus chain to decide which binding is contributed innermost.
    public func evaluate(against stack: [KeyContext]) -> Bool {
        Self.evaluate(root, stack)
    }

    private static func evaluate(_ node: Node, _ stack: [KeyContext]) -> Bool {
        switch node {
        case .identifier(let name):
            return stack.contains { $0.name == name }
        case .comparison(let key, let value):
            return stack.contains { $0.values[key] == value }
        case .not(let inner):
            return !evaluate(inner, stack)
        case .and(let lhs, let rhs):
            return evaluate(lhs, stack) && evaluate(rhs, stack)
        case .or(let lhs, let rhs):
            return evaluate(lhs, stack) || evaluate(rhs, stack)
        }
    }
}

// MARK: - Lexing

extension ContextPredicate {
    enum Token: Equatable {
        case identifier(String)
        /// A double-quoted literal — the only way to write a value containing a
        /// space or an operator character.
        case string(String)
        case equals
        case and
        case or
        case not
        case leftParen
        case rightParen
    }

    enum Lexer {
        /// `nil` for any character the language does not contain, for a lone
        /// `&`, `|` or `=`, and for an unterminated string.
        ///
        /// **A lone `&` is a failure rather than an `and`.** Accepting it would
        /// make `Editor & mode == code` silently mean something, and a keymap
        /// author's typo would then produce a working-but-different binding
        /// instead of an inert one.
        static func tokenize(_ source: String) -> [Token]? {
            var tokens: [Token] = []
            var i = source.startIndex
            while i < source.endIndex {
                let c = source[i]
                if c.isWhitespace { i = source.index(after: i); continue }
                switch c {
                case "&", "|", "=":
                    let next = source.index(after: i)
                    guard next < source.endIndex, source[next] == c else { return nil }
                    tokens.append(c == "&" ? .and : (c == "|" ? .or : .equals))
                    i = source.index(after: next)
                case "!":
                    tokens.append(.not)
                    i = source.index(after: i)
                case "(":
                    tokens.append(.leftParen)
                    i = source.index(after: i)
                case ")":
                    tokens.append(.rightParen)
                    i = source.index(after: i)
                case "\"":
                    var j = source.index(after: i)
                    var literal = ""
                    while j < source.endIndex, source[j] != "\"" {
                        literal.append(source[j])
                        j = source.index(after: j)
                    }
                    guard j < source.endIndex else { return nil }  // unterminated
                    tokens.append(.string(literal))
                    i = source.index(after: j)
                default:
                    guard isIdentifierStart(c) else { return nil }
                    var j = i
                    var name = ""
                    while j < source.endIndex, isIdentifierBody(source[j]) {
                        name.append(source[j])
                        j = source.index(after: j)
                    }
                    tokens.append(.identifier(name))
                    i = j
                }
            }
            return tokens.isEmpty ? nil : tokens
        }

        static func isIdentifierStart(_ c: Character) -> Bool {
            c.isLetter || c.isNumber || c == "_"
        }

        /// `.` and `-` are allowed inside a name so `mode == read-only` and
        /// dotted context names work without quoting.
        static func isIdentifierBody(_ c: Character) -> Bool {
            isIdentifierStart(c) || c == "." || c == "-"
        }
    }
}

// MARK: - Parsing

extension ContextPredicate {
    /// Recursive descent, one method per precedence level:
    ///
    /// ```
    /// or      := and ("||" and)*
    /// and     := unary ("&&" unary)*
    /// unary   := "!" unary | primary
    /// primary := "(" or ")" | identifier ("==" value)?
    /// value   := identifier | string
    /// ```
    ///
    /// **`nil` propagates rather than throwing**, and the caller additionally
    /// requires `isAtEnd` — which is what makes `Editor Terminal` a failure
    /// instead of a silently truncated `Editor`.
    struct Parser {
        let tokens: [Token]
        var cursor = 0

        var isAtEnd: Bool { cursor >= tokens.count }

        mutating func match(_ token: Token) -> Bool {
            guard cursor < tokens.count, tokens[cursor] == token else { return false }
            cursor += 1
            return true
        }

        mutating func parseOr() -> Node? {
            guard var node = parseAnd() else { return nil }
            while match(.or) {
                guard let rhs = parseAnd() else { return nil }
                node = .or(node, rhs)
            }
            return node
        }

        mutating func parseAnd() -> Node? {
            guard var node = parseUnary() else { return nil }
            while match(.and) {
                guard let rhs = parseUnary() else { return nil }
                node = .and(node, rhs)
            }
            return node
        }

        mutating func parseUnary() -> Node? {
            if match(.not) {
                guard let inner = parseUnary() else { return nil }
                return .not(inner)
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> Node? {
            if match(.leftParen) {
                guard let inner = parseOr(), match(.rightParen) else { return nil }
                return inner
            }
            guard cursor < tokens.count,
                  case .identifier(let name) = tokens[cursor] else { return nil }
            cursor += 1
            guard match(.equals) else { return .identifier(name) }
            guard cursor < tokens.count else { return nil }
            switch tokens[cursor] {
            case .identifier(let value), .string(let value):
                cursor += 1
                return .comparison(key: name, value: value)
            default:
                return nil
            }
        }
    }
}
