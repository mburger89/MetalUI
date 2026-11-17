import Testing
@testable import MetalUITerminal

private let E = "\u{1b}"

private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

private func key(_ k: Character, _ chars: String = "", _ m: TerminalModifiers = []) -> TerminalKey {
    TerminalKey(key: k, characters: chars, modifiers: m)
}

private func modes(cursor: Bool = false, keypad: Bool = false, paste: Bool = false, focus: Bool = false,
                   tracking: MouseTracking = .off, encoding: MouseEncoding = .legacy) -> TerminalModes {
    var m = TerminalModes()
    m.applicationCursorKeys = cursor
    m.applicationKeypad = keypad
    m.bracketedPaste = paste
    m.focusEvents = focus
    m.mouseTracking = tracking
    m.mouseEncoding = encoding
    return m
}

/// The eight shift/option/control combinations with the xterm parameter written out (`1 + shift + 2 alt + 4 ctrl`), not computed.
private let modifierRows: [(TerminalModifiers, String)] = [
    ([], ""), ([.shift], "2"), ([.option], "3"), ([.shift, .option], "4"),
    ([.control], "5"), ([.shift, .control], "6"), ([.option, .control], "7"), ([.shift, .option, .control], "8"),
]

@Suite struct EncoderKeyTests {
    struct Row: Sendable, CustomStringConvertible {
        var name: String
        var key: Character
        var chars: String = ""
        var mods: TerminalModifiers = []
        var cursor = false
        var meta = false
        var expect: String
        var description: String { "\(name) \(mods.rawValue) cursor=\(cursor) meta=\(meta)" }
    }

    static func check(_ rows: [Row]) {
        for r in rows {
            let got = TerminalEncoder.encodeKey(TerminalKey(key: r.key, characters: r.chars, modifiers: r.mods),
                                                modes: modes(cursor: r.cursor), optionAsMeta: r.meta)
            #expect(got == bytes(r.expect), "\(r) got \(got)")
        }
    }

    // The cursor-like keys: letter finals, SS3 only for the unmodified application form.
    static let cursorKeys: [(String, Character, String)] = [
        ("up", "\u{f700}", "A"), ("down", "\u{f701}", "B"), ("right", "\u{f703}", "C"), ("left", "\u{f702}", "D"),
        ("home", "\u{f729}", "H"), ("end", "\u{f72b}", "F"),
    ]

    @Test func cursorKeysInEveryModifierAndMode() {
        var rows: [Row] = []
        for (name, k, f) in Self.cursorKeys {
            for (mods, p) in modifierRows {
                for app in [false, true] {
                    let exp: String
                    if p.isEmpty { exp = app ? "\(E)O\(f)" : "\(E)[\(f)" } else { exp = "\(E)[1;\(p)\(f)" }
                    rows.append(Row(name: name, key: k, mods: mods, cursor: app, expect: exp))
                }
            }
        }
        Self.check(rows)
        #expect(rows.count == 96)
    }

    @Test func tildeKeysInEveryModifier() {
        let keys: [(String, Character, String)] = [("insert", "\u{f727}", "2"), ("delete", "\u{f728}", "3"),
                                                   ("pgup", "\u{f72c}", "5"), ("pgdn", "\u{f72d}", "6")]
        var rows: [Row] = []
        for (name, k, n) in keys {
            for (mods, p) in modifierRows {
                for app in [false, true] {
                    rows.append(Row(name: name, key: k, mods: mods, cursor: app,
                                    expect: p.isEmpty ? "\(E)[\(n)~" : "\(E)[\(n);\(p)~"))
                }
            }
        }
        Self.check(rows)
    }

    @Test func functionKeysOneToFour() {
        var rows: [Row] = []
        for (i, f) in ["P", "Q", "R", "S"].enumerated() {
            let k = Character(UnicodeScalar(0xF704 + UInt32(i))!)
            for (mods, p) in modifierRows {
                for app in [false, true] {
                    rows.append(Row(name: "F\(i + 1)", key: k, mods: mods, cursor: app,
                                    expect: p.isEmpty ? "\(E)O\(f)" : "\(E)[1;\(p)\(f)"))
                }
            }
        }
        Self.check(rows)
    }

    @Test func functionKeysFiveToTwenty() {
        let numbers = ["15", "17", "18", "19", "20", "21", "23", "24", "25", "26", "28", "29", "31", "32", "33", "34"]
        var rows: [Row] = []
        for (i, n) in numbers.enumerated() {
            let k = Character(UnicodeScalar(0xF708 + UInt32(i))!)
            for (mods, p) in modifierRows {
                rows.append(Row(name: "F\(i + 5)", key: k, mods: mods,
                                expect: p.isEmpty ? "\(E)[\(n)~" : "\(E)[\(n);\(p)~"))
            }
        }
        Self.check(rows)
        // The unmapped neighbours encode to nothing.
        #expect(TerminalEncoder.encodeKey(key("\u{f718}"), modes: modes(), optionAsMeta: false) == [])
        #expect(TerminalEncoder.encodeKey(key("\u{f739}"), modes: modes(), optionAsMeta: true) == [])
    }

    @Test func controlLetters() {
        var rows: [Row] = []
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            rows.append(Row(name: "ctrl-\(c)", key: c, chars: "", mods: [.control],
                            expect: String(UnicodeScalar(UInt8(i + 1)))))
            rows.append(Row(name: "ctrl-shift-\(c)", key: c, chars: "", mods: [.control, .shift],
                            expect: String(UnicodeScalar(UInt8(i + 1)))))
            rows.append(Row(name: "meta-ctrl-\(c)", key: c, chars: "", mods: [.control, .option], meta: true,
                            expect: E + String(UnicodeScalar(UInt8(i + 1)))))
        }
        Self.check(rows)
    }

    @Test func controlPunctuation() {
        let table: [(Character, UInt8)] = [
            ("@", 0), (" ", 0), ("`", 0), ("2", 0), ("[", 0x1B), ("3", 0x1B), ("\\", 0x1C), ("4", 0x1C),
            ("]", 0x1D), ("5", 0x1D), ("^", 0x1E), ("6", 0x1E), ("_", 0x1F), ("-", 0x1F), ("7", 0x1F),
            ("/", 0x1F), ("?", 0x7F), ("8", 0x7F),
        ]
        var rows: [Row] = []
        for (c, b) in table {
            rows.append(Row(name: "ctrl-\(c)", key: c, chars: String(c), mods: [.control],
                            expect: String(UnicodeScalar(b))))
        }
        // Ctrl+Shift+/ is Ctrl+?.
        rows.append(Row(name: "ctrl-shift-/", key: "/", mods: [.control, .shift], expect: "\u{7f}"))
        // Ctrl with a key that has no C0 spelling sends what it typed.
        rows.append(Row(name: "ctrl-1", key: "1", chars: "1", mods: [.control], expect: "1"))
        Self.check(rows)
    }

    @Test func editingKeys() {
        Self.check([
            Row(name: "backspace", key: "\u{7f}", expect: "\u{7f}"),
            Row(name: "shift-backspace", key: "\u{7f}", mods: [.shift], expect: "\u{7f}"),
            Row(name: "ctrl-backspace", key: "\u{7f}", mods: [.control], expect: "\u{08}"),
            Row(name: "meta-backspace", key: "\u{7f}", mods: [.option], meta: true, expect: "\(E)\u{7f}"),
            Row(name: "meta-ctrl-backspace", key: "\u{7f}", mods: [.option, .control], meta: true, expect: "\(E)\u{08}"),
            Row(name: "option-backspace plain", key: "\u{7f}", mods: [.option], expect: "\u{7f}"),
            Row(name: "tab", key: "\t", expect: "\t"),
            Row(name: "shift-tab", key: "\t", mods: [.shift], expect: "\(E)[Z"),
            Row(name: "ctrl-tab", key: "\t", mods: [.control], expect: "\t"),
            Row(name: "meta-tab", key: "\t", mods: [.option], meta: true, expect: "\(E)\t"),
            Row(name: "meta-shift-tab", key: "\t", mods: [.option, .shift], meta: true, expect: "\(E)\(E)[Z"),
            Row(name: "enter", key: "\r", expect: "\r"),
            Row(name: "shift-enter", key: "\r", mods: [.shift], expect: "\r"),
            Row(name: "meta-enter", key: "\r", mods: [.option], meta: true, expect: "\(E)\r"),
            Row(name: "escape", key: "\u{1b}", expect: E),
            Row(name: "meta-escape", key: "\u{1b}", mods: [.option], meta: true, expect: "\(E)\(E)"),
            Row(name: "space", key: " ", chars: " ", expect: " "),
            Row(name: "ctrl-space", key: " ", chars: " ", mods: [.control], expect: "\u{0}"),
            Row(name: "meta-space", key: " ", chars: " ", mods: [.option], meta: true, expect: "\(E) "),
        ])
    }

    @Test func textAndOptionAsMeta() {
        Self.check([
            Row(name: "a", key: "a", chars: "a", expect: "a"),
            Row(name: "A", key: "a", chars: "A", mods: [.shift], expect: "A"),
            Row(name: "utf8", key: "e", chars: "\u{e9}", expect: "\u{e9}"),
            // Without optionAsMeta, Option composes.
            Row(name: "option-a composes", key: "a", chars: "\u{e5}", mods: [.option], expect: "\u{e5}"),
            // With it, the unmodified character after an ESC.
            Row(name: "meta-a", key: "a", chars: "\u{e5}", mods: [.option], meta: true, expect: "\(E)a"),
            Row(name: "meta-shift-a", key: "a", chars: "\u{c5}", mods: [.option, .shift], meta: true, expect: "\(E)A"),
            Row(name: "meta-1", key: "1", chars: "\u{a1}", mods: [.option], meta: true, expect: "\(E)1"),
            Row(name: "meta-dot", key: ".", chars: "\u{2265}", mods: [.option], meta: true, expect: "\(E)."),
            // optionAsMeta without Option changes nothing.
            Row(name: "a with meta on", key: "a", chars: "a", meta: true, expect: "a"),
            // A key with no characters and no mapping is nothing.
            Row(name: "empty", key: "x", chars: "", expect: ""),
        ])
        let bytesE9 = TerminalEncoder.encodeKey(key("e", "\u{e9}"), modes: modes(), optionAsMeta: false)
        #expect(bytesE9 == [0xC3, 0xA9])
    }

    @Test func optionOnSpecialKeysIsTheAltParameterWithOrWithoutMeta() {
        for meta in [false, true] {
            #expect(TerminalEncoder.encodeKey(key("\u{f703}", "", [.option]), modes: modes(), optionAsMeta: meta) == bytes("\(E)[1;3C"))
        }
    }

    @Test func commandCombinationsEncodeToNothing() {
        let chars: [Character] = ["a", "c", "v", "\r", "\t", "\u{7f}", "\u{f700}", "\u{f704}", "\u{f728}", " ", "1"]
        for c in chars {
            for extra in [TerminalModifiers(), .shift, .control, .option] {
                for meta in [false, true] {
                    let k = key(c, String(c), [.command, extra])
                    #expect(TerminalEncoder.encodeKey(k, modes: modes(cursor: true), optionAsMeta: meta) == [], "\(c) \(extra)")
                }
            }
        }
    }

    @Test func applicationKeypadDoesNotChangeKeys() {
        var m = modes()
        m.applicationKeypad = true
        #expect(TerminalEncoder.encodeKey(key("5", "5"), modes: m, optionAsMeta: false) == bytes("5"))
        #expect(TerminalEncoder.encodeKey(key("\r"), modes: m, optionAsMeta: false) == bytes("\r"))
    }
}

@Suite struct EncoderMouseTests {
    private func enc(_ kind: TerminalMouseEvent.Kind, _ button: TerminalMouseEvent.Button = .none,
                     _ mods: TerminalModifiers = [], row: Int = 4, col: Int = 9,
                     _ t: MouseTracking, _ e: MouseEncoding = .sgr) -> [UInt8] {
        TerminalEncoder.encodeMouse(TerminalMouseEvent(kind: kind, button: button, modifiers: mods),
                                    at: TerminalPosition(row: row, col: col), modes: modes(tracking: t, encoding: e))
    }

    @Test func trackingOffReportsNothing() {
        for k: TerminalMouseEvent.Kind in [.press, .release, .move, .wheelUp, .wheelDown] {
            #expect(enc(k, .left, [], .off) == [])
        }
    }

    @Test func whichEventsEachTrackingModeReports() {
        // (kind, button, x10, normal, buttonEvent, anyEvent) -> reported?
        let rows: [(TerminalMouseEvent.Kind, TerminalMouseEvent.Button, Bool, Bool, Bool, Bool)] = [
            (.press, .left, true, true, true, true),
            (.press, .middle, true, true, true, true),
            (.press, .right, true, true, true, true),
            (.press, .none, false, false, false, false),
            (.release, .left, false, true, true, true),
            (.release, .none, false, false, false, false),
            (.move, .left, false, false, true, true),
            (.move, .none, false, false, false, true),
            (.wheelUp, .none, false, true, true, true),
            (.wheelDown, .none, false, true, true, true),
        ]
        for (k, b, x10, normal, button, any) in rows {
            for (t, expected) in [(MouseTracking.x10, x10), (.normal, normal), (.buttonEvent, button), (.anyEvent, any)] {
                #expect((enc(k, b, [], t) != []) == expected, "\(k) \(b) \(t)")
            }
        }
    }

    @Test func sgrCodes() {
        let r = 4, c = 9   // reported 1-based as 10;5
        let rows: [(TerminalMouseEvent.Kind, TerminalMouseEvent.Button, TerminalModifiers, String)] = [
            (.press, .left, [], "0;10;5M"), (.press, .middle, [], "1;10;5M"), (.press, .right, [], "2;10;5M"),
            (.release, .left, [], "0;10;5m"), (.release, .middle, [], "1;10;5m"), (.release, .right, [], "2;10;5m"),
            (.move, .left, [], "32;10;5M"), (.move, .right, [], "34;10;5M"), (.move, .none, [], "35;10;5M"),
            (.wheelUp, .none, [], "64;10;5M"), (.wheelDown, .none, [], "65;10;5M"),
            (.press, .left, [.shift], "4;10;5M"), (.press, .left, [.option], "8;10;5M"), (.press, .left, [.control], "16;10;5M"),
            (.press, .left, [.shift, .option, .control], "28;10;5M"), (.press, .left, [.command], "0;10;5M"),
            (.release, .right, [.control], "18;10;5m"), (.wheelUp, .none, [.shift], "68;10;5M"),
            (.move, .none, [.option], "43;10;5M"), (.wheelDown, .none, [.control, .option], "89;10;5M"),
        ]
        for (k, b, m, s) in rows {
            #expect(enc(k, b, m, row: r, col: c, .anyEvent) == bytes("\(E)[<\(s)"), "\(k) \(b) \(m)")
        }
        // Large coordinates are fine in SGR.
        #expect(enc(.press, .left, row: 999, col: 4999, .normal) == bytes("\(E)[<0;5000;1000M"))
    }

    @Test func legacyBytes() {
        // Cb = 32 + code, Cx = 32 + col + 1, Cy = 32 + row + 1.
        func legacy(_ k: TerminalMouseEvent.Kind, _ b: TerminalMouseEvent.Button, _ m: TerminalModifiers = [],
                    _ t: MouseTracking = .anyEvent) -> [UInt8] { enc(k, b, m, row: 4, col: 9, t, .legacy) }
        let tail: [UInt8] = [32 + 10, 32 + 5]
        #expect(legacy(.press, .left) == [0x1B, 0x5B, 0x4D, 32] + tail)
        #expect(legacy(.press, .middle) == [0x1B, 0x5B, 0x4D, 33] + tail)
        #expect(legacy(.press, .right) == [0x1B, 0x5B, 0x4D, 34] + tail)
        #expect(legacy(.release, .left) == [0x1B, 0x5B, 0x4D, 35] + tail)
        #expect(legacy(.release, .right, [.control]) == [0x1B, 0x5B, 0x4D, 35 + 16] + tail)
        #expect(legacy(.move, .left) == [0x1B, 0x5B, 0x4D, 64] + tail)
        #expect(legacy(.move, .none) == [0x1B, 0x5B, 0x4D, 67] + tail)
        #expect(legacy(.wheelUp, .none) == [0x1B, 0x5B, 0x4D, 96] + tail)
        #expect(legacy(.wheelDown, .none, [.shift]) == [0x1B, 0x5B, 0x4D, 32 + 65 + 4] + tail)
        #expect(legacy(.press, .left, [.shift, .option, .control]) == [0x1B, 0x5B, 0x4D, 32 + 28] + tail)
        // X10 reports presses only and carries no modifiers.
        #expect(legacy(.press, .left, [.shift, .control], .x10) == [0x1B, 0x5B, 0x4D, 32] + tail)
    }

    @Test func legacyLimitDropsInsteadOfWrapping() {
        func at(row: Int, col: Int) -> [UInt8] { enc(.press, .left, row: row, col: col, .normal, .legacy) }
        #expect(at(row: 0, col: 222) == [0x1B, 0x5B, 0x4D, 32, 255, 33])   // column 223 is the last
        #expect(at(row: 222, col: 0) == [0x1B, 0x5B, 0x4D, 32, 33, 255])
        #expect(at(row: 0, col: 223) == [])
        #expect(at(row: 223, col: 0) == [])
        #expect(at(row: 500, col: 500) == [])
    }

    @Test func utf8Encoding() {
        func u(row: Int, col: Int, _ k: TerminalMouseEvent.Kind = .press) -> [UInt8] {
            enc(k, .left, row: row, col: col, .normal, .utf8)
        }
        #expect(u(row: 4, col: 9) == [0x1B, 0x5B, 0x4D, 32, 42, 37])
        // 223 -> 32 + 224 = 256 = U+0100 -> C4 80.
        #expect(u(row: 0, col: 223) == [0x1B, 0x5B, 0x4D, 32, 0xC4, 0x80, 33])
        // 127 + 32 is the last one-byte value: col 95 -> 32 + 96 = 128 -> C2 80.
        #expect(u(row: 0, col: 94) == [0x1B, 0x5B, 0x4D, 32, 127, 33])
        #expect(u(row: 0, col: 95) == [0x1B, 0x5B, 0x4D, 32, 0xC2, 0x80, 33])
        // The last representable column is 2015 (U+07FF).
        #expect(u(row: 0, col: 2014) == [0x1B, 0x5B, 0x4D, 32, 0xDF, 0xBF, 33])
        #expect(u(row: 0, col: 2015) == [])
        #expect(u(row: 2015, col: 0) == [])
        #expect(u(row: 0, col: 0, .release) == [0x1B, 0x5B, 0x4D, 35, 33, 33])
    }

    @Test func negativeCellsAreDropped() {
        #expect(enc(.press, .left, row: -1, col: 0, .normal) == [])
        #expect(enc(.press, .left, row: 0, col: -1, .normal, .legacy) == [])
    }
}

@Suite struct EncoderPasteFocusTests {
    @Test func plainPasteKeepsTabCRLFAndText() {
        let out = TerminalEncoder.encodePaste("a\tb\r\nc\n\u{e9}\u{1F600}", modes: modes())
        #expect(out == bytes("a\tb\r\nc\n\u{e9}\u{1F600}"))
    }

    @Test func bracketedPasteWraps() {
        let out = TerminalEncoder.encodePaste("hi", modes: modes(paste: true))
        #expect(out == bytes("\(E)[200~hi\(E)[201~"))
        #expect(TerminalEncoder.encodePaste("", modes: modes(paste: true)) == bytes("\(E)[200~\(E)[201~"))
    }

    @Test func everyC0ExceptTabCRLFIsStripped() {
        for b in 0..<0x20 where b != 9 && b != 10 && b != 13 {
            let s = "x" + String(UnicodeScalar(UInt8(b))) + "y"
            #expect(TerminalEncoder.encodePaste(s, modes: modes()) == bytes("xy"), "byte \(b)")
            #expect(TerminalEncoder.encodePaste(s, modes: modes(paste: true)) == bytes("\(E)[200~xy\(E)[201~"), "byte \(b)")
        }
    }

    @Test func embeddedBracketEndCannotEndThePaste() {
        let evil = "a\(E)[201~; rm -rf ~\n"
        let out = TerminalEncoder.encodePaste(evil, modes: modes(paste: true))
        #expect(out == bytes("\(E)[200~a[201~; rm -rf ~\n\(E)[201~"))
        // Exactly one ESC in the output other than the pair we wrote: the two wrapper ESCs.
        #expect(out.filter { $0 == 0x1B }.count == 2)
        #expect(TerminalEncoder.encodePaste("\(E)[200~x", modes: modes(paste: true)) == bytes("\(E)[200~[200~x\(E)[201~"))
    }

    @Test func focus() {
        #expect(TerminalEncoder.encodeFocus(true, modes: modes(focus: true)) == bytes("\(E)[I"))
        #expect(TerminalEncoder.encodeFocus(false, modes: modes(focus: true)) == bytes("\(E)[O"))
        #expect(TerminalEncoder.encodeFocus(true, modes: modes()) == [])
        #expect(TerminalEncoder.encodeFocus(false, modes: modes()) == [])
    }
}
