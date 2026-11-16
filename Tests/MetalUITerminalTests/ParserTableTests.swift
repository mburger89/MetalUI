import Testing
@testable import MetalUITerminal

/// State-machine table: each row is an input and the exact callback sequence it must produce.
@Suite struct ParserTableTests {
    struct Row: Sendable, CustomStringConvertible {
        var input: String
        var expect: [String]
        var description: String { input.debugDescription }
    }

    static let csiRows: [Row] = [
        Row(input: "\(ESC)[H", expect: ["csi H v=[] sub=[] prefix=0 i=[]"]),
        Row(input: "\(ESC)[1;2H", expect: ["csi H v=[1, 2] sub=[0, 0] prefix=0 i=[]"]),
        Row(input: "\(ESC)[;5H", expect: ["csi H v=[-1, 5] sub=[0, 0] prefix=0 i=[]"]),
        Row(input: "\(ESC)[5;H", expect: ["csi H v=[5, -1] sub=[0, 0] prefix=0 i=[]"]),
        Row(input: "\(ESC)[;H", expect: ["csi H v=[-1, -1] sub=[0, 0] prefix=0 i=[]"]),
        Row(input: "\(ESC)[38:2::255:128:0m",
            expect: ["csi m v=[38, 2, -1, 255, 128, 0] sub=[0, 1, 1, 1, 1, 1] prefix=0 i=[]"]),
        Row(input: "\(ESC)[1;38:5:200;4m",
            expect: ["csi m v=[1, 38, 5, 200, 4] sub=[0, 0, 1, 1, 0] prefix=0 i=[]"]),
        Row(input: "\(ESC)[4:3m", expect: ["csi m v=[4, 3] sub=[0, 1] prefix=0 i=[]"]),
        Row(input: "\(ESC)[?25h", expect: ["csi h v=[25] sub=[0] prefix=63 i=[]"]),
        Row(input: "\(ESC)[>0c", expect: ["csi c v=[0] sub=[0] prefix=62 i=[]"]),
        Row(input: "\(ESC)[ q", expect: ["csi q v=[] sub=[] prefix=0 i=[32]"]),
        Row(input: "\(ESC)[2 q", expect: ["csi q v=[2] sub=[0] prefix=0 i=[32]"]),
        Row(input: "\(ESC)[!p", expect: ["csi p v=[] sub=[] prefix=0 i=[33]"]),
        Row(input: "\(ESC)[99999999999H", expect: ["csi H v=[65535] sub=[0] prefix=0 i=[]"]),
        // A private marker after digits, or a digit after an intermediate, poisons the sequence: no dispatch,
        // and the parser is back in ground for the next byte.
        Row(input: "\(ESC)[1?2hX", expect: ["print X"]),
        Row(input: "\(ESC)[ 1qX", expect: ["print X"]),
        Row(input: "\(ESC)[1 2 3 4 5qX", expect: ["print X"]),
        // C0 controls execute inside a CSI without disturbing it.
        Row(input: "\(ESC)[1\u{0A}2H", expect: ["exec 10", "csi H v=[12] sub=[0] prefix=0 i=[]"]),
        // A new ESC restarts; CAN and SUB abort (the final byte then prints).
        Row(input: "\(ESC)[1\(ESC)[2H", expect: ["csi H v=[2] sub=[0] prefix=0 i=[]"]),
        Row(input: "\(ESC)[1\u{18}H", expect: ["exec 24", "print H"]),
        Row(input: "\(ESC)[1\u{1A}H", expect: ["exec 26", "print H"]),
        // DEL is ignored.
        Row(input: "\(ESC)[1\u{7F}2H", expect: ["csi H v=[12] sub=[0] prefix=0 i=[]"]),
    ]

    @Test(arguments: csiRows) func csi(_ row: Row) { #expect(parse(row.input) == row.expect) }

    @Test func thirtyTwoParametersAreKeptAndTheRestDropped() {
        let input = "\(ESC)[" + (1...40).map(String.init).joined(separator: ";") + "m"
        let events = parse(input)
        #expect(events.count == 1)
        let expected = "csi m v=\((1...32).map { $0 }) sub=\(Array(repeating: 0, count: 32)) prefix=0 i=[]"
        #expect(events == [expected])
    }

    static let escRows: [Row] = [
        Row(input: "\(ESC)7", expect: ["esc 7 i=[]"]),
        Row(input: "\(ESC)(0", expect: ["esc 0 i=[40]"]),
        Row(input: "\(ESC)#8", expect: ["esc 8 i=[35]"]),
        Row(input: "\(ESC)=\(ESC)>", expect: ["esc = i=[]", "esc > i=[]"]),
        Row(input: "\(ESC)\n7", expect: ["exec 10", "esc 7 i=[]"]),
        Row(input: "\(ESC)(\u{18}A", expect: ["exec 24", "print A"]),
        Row(input: "\(ESC)\(ESC)M", expect: ["esc M i=[]"]),
    ]

    @Test(arguments: escRows) func escape(_ row: Row) { #expect(parse(row.input) == row.expect) }

    static let stringRows: [Row] = [
        Row(input: "\(ESC)]0;title\(BEL)x", expect: ["osc 0;title", "print x"]),
        Row(input: "\(ESC)]0;title\(ST)x", expect: ["osc 0;title", "esc \\ i=[]", "print x"]),
        Row(input: "\(ESC)]2;h\u{E9}llo\(BEL)", expect: ["osc 2;h\u{E9}llo"]),
        Row(input: "\(ESC)]2;a\u{0B}b\(BEL)", expect: ["osc 2;ab"]),  // C0 other than BEL is ignored in OSC
        Row(input: "\(ESC)]1;a\u{18}bc", expect: ["exec 24", "print b", "print c"]),  // CAN aborts, nothing dispatched
        Row(input: "\(ESC)]1;a\u{1A}bc", expect: ["exec 26", "print b", "print c"]),
        Row(input: "\(ESC)P1;2$qm\(ST)", expect: ["dcs q v=[1, 2] i=[36] m", "esc \\ i=[]"]),
        Row(input: "\(ESC)Pqa\nb\(ST)", expect: ["dcs q v=[] i=[] a\nb", "esc \\ i=[]"]),  // C0 kept in a DCS payload
        Row(input: "\(ESC)P1:2;3 pxyz\(BEL)Q", expect: []),  // BEL does not end a DCS, ST never came
        Row(input: "\(ESC)P\u{18}ok", expect: ["exec 24", "print o", "print k"]),
        Row(input: "\(ESC)_Gabc\(ST)", expect: ["apc Gabc", "esc \\ i=[]"]),
        Row(input: "\(ESC)_a\u{18}z", expect: ["exec 24", "print z"]),
        Row(input: "\(ESC)Xjunk\(ST)after", expect: ["esc \\ i=[]"] + "after".map { "print \($0)" }),
        Row(input: "\(ESC)^junk\(ST)", expect: ["esc \\ i=[]"]),
        // ESC inside a string ends it as ST does and starts a new sequence.
        Row(input: "\(ESC)]0;t\(ESC)[2H", expect: ["osc 0;t", "csi H v=[2] sub=[0] prefix=0 i=[]"]),
        // A DCS with a private marker after digits is ignored to its terminator.
        Row(input: "\(ESC)P1?2qZZ\(ST)W", expect: ["esc \\ i=[]", "print W"]),
    ]

    @Test(arguments: stringRows) func strings(_ row: Row) { #expect(parse(row.input) == row.expect) }

    @Test func payloadCapDropsOverlongStringsAndTheParserRecovers() {
        // Exactly the cap is kept; one more is dropped to the terminator.
        #expect(parse("\(ESC)]12345678\(BEL)", cap: 8) == ["osc 12345678"])
        #expect(parse("\(ESC)]123456789\(BEL)ok", cap: 8) == ["print o", "print k"])
        #expect(parse("\(ESC)_12345678\(ST)", cap: 8) == ["apc 12345678", "esc \\ i=[]"])
        #expect(parse("\(ESC)_123456789\(ST)ok", cap: 8) == ["esc \\ i=[]", "print o", "print k"])
        #expect(parse("\(ESC)Pq12345678\(ST)", cap: 8) == ["dcs q v=[] i=[] 12345678", "esc \\ i=[]"])
        #expect(parse("\(ESC)Pq123456789\(ST)", cap: 8) == ["esc \\ i=[]"])
        // A multibyte payload counts in bytes.
        #expect(parse("\(ESC)]\u{E9}\u{E9}\u{E9}\u{E9}\u{E9}\(BEL)", cap: 8) == [])
        // After an overflow the next string is whole again.
        #expect(parse("\(ESC)]123456789\(BEL)\(ESC)]1\(BEL)", cap: 8) == ["osc 1"])
        // A long payload never grows the buffer past the cap.
        var parser = VTParser(payloadCap: 16)
        let recorder = Recorder()
        let long = Array("\(ESC)]".utf8) + Array(repeating: UInt8(ascii: "x"), count: 1_000_000)
        long.withUnsafeBufferPointer { parser.feed($0, recorder) }
        #expect(recorder.events.isEmpty)
        #expect(parser.stateDescription.count < 400)
    }

    @Test func c1ControlsAsTwoByteUTF8() {
        // U+009B is CSI, U+009D OSC, U+009C ST, U+0090 DCS, U+009F APC, U+0085 NEL, U+008D RI, U+0088 HTS.
        let csi: [UInt8] = [0xC2, 0x9B, 0x31, 0x3B, 0x32, 0x48]
        #expect(parse(csi) == ["csi H v=[1, 2] sub=[0, 0] prefix=0 i=[]"])
        let osc: [UInt8] = [0xC2, 0x9D, 0x30, 0x3B, 0x74, 0xC2, 0x9C]
        #expect(parse(osc) == ["osc 0;t"])
        let dcs: [UInt8] = [0xC2, 0x90, 0x71, 0x61, 0xC2, 0x9C]
        #expect(parse(dcs) == ["dcs q v=[] i=[] a"])
        let apc: [UInt8] = [0xC2, 0x9F, 0x61, 0xC2, 0x9C]
        #expect(parse(apc) == ["apc a"])
        #expect(parse([0xC2, 0x85, 0xC2, 0x8D, 0xC2, 0x88]) == ["exec 133", "exec 141", "exec 136"])
        // ST outside a string does nothing; a C1 introducer inside a string drops the string.
        #expect(parse([0xC2, 0x9C, 0x41]) == ["print A"])
        #expect(parse([0x1B, 0x5D, 0x31, 0xC2, 0x9B, 0x48]) == ["csi H v=[] sub=[] prefix=0 i=[]"])
    }

    @Test func aLoneC1ByteIsInvalidUTF8NotACommand() {
        #expect(parse([0x9B, 0x31, 0x48]) == ["print \u{FFFD}", "print 1", "print H"])
        #expect(parse([0x90]) == ["print \u{FFFD}"])
    }

    @Test func nonASCIIInsideAnEscapeOrCSICancelsItAndPrints() {
        #expect(parse("\(ESC)[1\u{E9}H") == ["print \u{E9}", "print H"])
        #expect(parse("\(ESC)\u{E9}") == ["print \u{E9}"])
        #expect(parse("\(ESC)(\u{E9}") == ["print \u{E9}"])
        // An ignored CSI swallows it silently.
        #expect(parse("\(ESC)[1?\u{E9}2hX") == ["print X"])
    }
}
