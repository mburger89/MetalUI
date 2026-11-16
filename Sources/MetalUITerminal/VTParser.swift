/// The numeric arguments of a CSI or DCS sequence.
struct CSIParameters {
    /// The parameters in order; -1 stands for an omitted one (the sequence's own default applies). Values
    /// saturate at 65 535, and at most 32 are kept (`TRM-G`).
    var values: [Int32] = []
    /// `isSub[i]` is true when `values[i]` followed a `:` (a sub-parameter of the previous parameter).
    var isSub: [Bool] = []
    /// A private-use marker (`<`, `=`, `>` or `?`) that led the parameters, or 0.
    var prefix: UInt8 = 0
    /// Intermediate bytes (0x20-0x2F), at most 4; a longer run suppresses the dispatch.
    var intermediates: [UInt8] = []
    /// Set when the intermediates ran past 4.
    var overflow = false

    mutating func clear() {
        values.removeAll(keepingCapacity: true)
        isSub.removeAll(keepingCapacity: true)
        intermediates.removeAll(keepingCapacity: true)
        prefix = 0
        overflow = false
    }
}

/// What a ``VTParser`` calls back with. All calls arrive in stream order.
protocol VTParserHandler: AnyObject {
    /// A run of printable ASCII (0x20-0x7E). Runs depend on how the stream was split into chunks; the
    /// sequence of printed scalars does not.
    func printASCII(_ bytes: UnsafeBufferPointer<UInt8>)
    /// One printable non-ASCII scalar (or U+FFFD for invalid UTF-8).
    func print(_ scalar: Unicode.Scalar)
    /// A C0 control (0x00-0x1F) or a C1 control (0x80-0x9F) other than the ones that begin or end a string.
    func execute(_ code: UInt8)
    /// A complete CSI sequence.
    func csi(_ parameters: CSIParameters, final: UInt8)
    /// A complete escape sequence (ESC, optional intermediates, final).
    func esc(intermediates: [UInt8], final: UInt8)
    /// A terminated OSC string whose payload fit the cap.
    func osc(_ payload: [UInt8])
    /// A terminated DCS string whose payload fit the cap.
    func dcs(_ parameters: CSIParameters, final: UInt8, payload: [UInt8])
    /// A terminated APC string whose payload fit the cap.
    func apc(_ payload: [UInt8])
}

/// The ECMA-48 / DEC control-sequence state machine, with an incremental UTF-8 decoder in front of it.
///
/// Written from the published state descriptions (`TRM-A`). C1 controls are the scalars U+0080-U+009F, which in
/// UTF-8 arrive as two bytes; a lone byte 0x80-0x9F is invalid UTF-8 and prints U+FFFD (`TRM-G`).
struct VTParser {
    enum State: UInt8 {
        case ground, escape, escapeIntermediate
        case csiEntry, csiParam, csiIntermediate, csiIgnore
        case dcsEntry, dcsParam, dcsIntermediate, dcsPassthrough, dcsIgnore
        case oscString, apcString, ignoredString
    }

    private(set) var state: State = .ground
    private var decoder = UTF8Decoder()
    private var params = CSIParameters()
    private var current: Int32 = -1
    private var paramStarted = false
    private var nextIsSub = false
    private var dcsFinal: UInt8 = 0
    private var payload: [UInt8] = []
    private var payloadOverflow = false
    let payloadCap: Int

    init(payloadCap: Int) { self.payloadCap = max(0, payloadCap) }

    /// A description of everything that determines how the next byte is read, for the chunk-split tests.
    var stateDescription: String {
        "\(state) pending=\(decoder.isPending) params=\(params.values)/\(params.isSub) prefix=\(params.prefix) "
            + "inter=\(params.intermediates) cur=\(current) started=\(paramStarted) sub=\(nextIsSub) "
            + "overflow=\(params.overflow) payload=\(payload) payloadOverflow=\(payloadOverflow)"
    }

    mutating func reset() {
        state = .ground
        decoder.reset()
        clearSequence()
        payload.removeAll(keepingCapacity: true)
        payloadOverflow = false
    }

    mutating func feed<H: VTParserHandler>(_ buf: UnsafeBufferPointer<UInt8>, _ handler: H) {
        let n = buf.count
        var i = 0
        while i < n {
            let b = buf[i]
            if !decoder.isPending {
                if state == .ground && b >= 0x20 && b < 0x7F {
                    var j = i + 1
                    while j < n && buf[j] >= 0x20 && buf[j] < 0x7F { j += 1 }
                    handler.printASCII(UnsafeBufferPointer(rebasing: buf[i..<j]))
                    i = j
                    continue
                }
                if b < 0x80 {
                    process(b, handler)
                    i += 1
                    continue
                }
            }
            switch decoder.step(b) {
            case .more:
                i += 1
            case .scalar(let v):
                scalar(v, handler)
                i += 1
            case .invalid(let reprocess):
                scalar(0xFFFD, handler)
                if !reprocess { i += 1 }
            }
        }
    }

    // MARK: Scalars above ASCII

    private mutating func scalar<H: VTParserHandler>(_ v: UInt32, _ handler: H) {
        if v < 0x80 {
            process(UInt8(v), handler)
        } else if v < 0xA0 {
            c1(UInt8(v), handler)
        } else {
            switch state {
            case .ground:
                handler.print(Unicode.Scalar(v) ?? "\u{FFFD}")
            case .oscString, .apcString, .dcsPassthrough:
                var encoded: [UInt8] = []
                for byte in String(Character(Unicode.Scalar(v) ?? "\u{FFFD}")).utf8 { encoded.append(byte) }
                for byte in encoded { collectPayload(byte) }
            case .csiIgnore, .dcsIgnore, .ignoredString:
                break
            case .escape, .escapeIntermediate, .csiEntry, .csiParam, .csiIntermediate, .dcsEntry, .dcsParam,
                 .dcsIntermediate:
                state = .ground
                handler.print(Unicode.Scalar(v) ?? "\u{FFFD}")
            }
        }
    }

    private mutating func c1<H: VTParserHandler>(_ code: UInt8, _ handler: H) {
        switch code {
        case 0x90:
            abortString()
            enter(.dcsEntry)
        case 0x98, 0x9E:
            abortString()
            enter(.ignoredString)
        case 0x9B:
            abortString()
            enter(.csiEntry)
        case 0x9D:
            abortString()
            enter(.oscString)
        case 0x9F:
            abortString()
            enter(.apcString)
        case 0x9C:
            endString(handler, dispatch: true)
            state = .ground
        default:
            switch state {
            case .oscString, .apcString, .dcsPassthrough, .dcsIgnore, .ignoredString, .dcsEntry, .dcsParam,
                 .dcsIntermediate:
                break
            default:
                handler.execute(code)
            }
        }
    }

    // MARK: Bytes below 0x80

    private mutating func process<H: VTParserHandler>(_ b: UInt8, _ handler: H) {
        if b == 0x18 || b == 0x1A {
            abortString()
            state = .ground
            handler.execute(b)
            return
        }
        if b == 0x1B {
            endString(handler, dispatch: true)
            enter(.escape)
            return
        }
        switch state {
        case .ground:
            if b < 0x20 { handler.execute(b) } else if b < 0x7F { handler.print(Unicode.Scalar(b)) }

        case .escape:
            if b < 0x20 {
                handler.execute(b)
            } else if b < 0x30 {
                collect(b)
                state = .escapeIntermediate
            } else if b == 0x5B {
                enter(.csiEntry)
            } else if b == 0x5D {
                enter(.oscString)
            } else if b == 0x50 {
                enter(.dcsEntry)
            } else if b == 0x58 || b == 0x5E {
                enter(.ignoredString)
            } else if b == 0x5F {
                enter(.apcString)
            } else if b < 0x7F {
                handler.esc(intermediates: params.intermediates, final: b)
                state = .ground
            }

        case .escapeIntermediate:
            if b < 0x20 {
                handler.execute(b)
            } else if b < 0x30 {
                collect(b)
            } else if b < 0x7F {
                if !params.overflow { handler.esc(intermediates: params.intermediates, final: b) }
                state = .ground
            }

        case .csiEntry, .csiParam, .csiIntermediate, .csiIgnore:
            csiByte(b, handler)

        case .dcsEntry, .dcsParam, .dcsIntermediate, .dcsIgnore:
            dcsByte(b)

        case .dcsPassthrough:
            if b != 0x7F { collectPayload(b) }

        case .oscString:
            if b == 0x07 {
                endString(handler, dispatch: true)
                state = .ground
            } else if b >= 0x20 && b != 0x7F {
                collectPayload(b)
            }

        case .apcString:
            if b >= 0x20 && b != 0x7F { collectPayload(b) }

        case .ignoredString:
            break
        }
    }

    private mutating func csiByte<H: VTParserHandler>(_ b: UInt8, _ handler: H) {
        if b < 0x20 {
            handler.execute(b)
            return
        }
        if b == 0x7F { return }
        switch state {
        case .csiEntry:
            if b >= 0x30 && b <= 0x3B {
                state = .csiParam
                paramByte(b)
            } else if b >= 0x3C && b <= 0x3F {
                params.prefix = b
                state = .csiParam
            } else if b < 0x30 {
                collect(b)
                state = .csiIntermediate
            } else {
                dispatchCSI(b, handler)
            }
        case .csiParam:
            if b >= 0x30 && b <= 0x3B {
                paramByte(b)
            } else if b >= 0x3C && b <= 0x3F {
                state = .csiIgnore
            } else if b < 0x30 {
                collect(b)
                state = .csiIntermediate
            } else {
                dispatchCSI(b, handler)
            }
        case .csiIntermediate:
            if b < 0x30 {
                collect(b)
            } else if b <= 0x3F {
                state = .csiIgnore
            } else {
                dispatchCSI(b, handler)
            }
        default:
            if b >= 0x40 { state = .ground }
        }
    }

    private mutating func dcsByte(_ b: UInt8) {
        if b < 0x20 || b == 0x7F { return }
        switch state {
        case .dcsEntry:
            if b >= 0x30 && b <= 0x3B {
                state = .dcsParam
                paramByte(b)
            } else if b >= 0x3C && b <= 0x3F {
                params.prefix = b
                state = .dcsParam
            } else if b < 0x30 {
                collect(b)
                state = .dcsIntermediate
            } else {
                beginPassthrough(b)
            }
        case .dcsParam:
            if b >= 0x30 && b <= 0x3B {
                paramByte(b)
            } else if b >= 0x3C && b <= 0x3F {
                state = .dcsIgnore
            } else if b < 0x30 {
                collect(b)
                state = .dcsIntermediate
            } else {
                beginPassthrough(b)
            }
        case .dcsIntermediate:
            if b < 0x30 {
                collect(b)
            } else if b <= 0x3F {
                state = .dcsIgnore
            } else {
                beginPassthrough(b)
            }
        default:
            break
        }
    }

    // MARK: Pieces

    private mutating func enter(_ next: State) {
        clearSequence()
        payload.removeAll(keepingCapacity: true)
        payloadOverflow = false
        state = next
    }

    private mutating func clearSequence() {
        params.clear()
        current = -1
        paramStarted = false
        nextIsSub = false
    }

    private mutating func collect(_ b: UInt8) {
        if params.intermediates.count < 4 { params.intermediates.append(b) } else { params.overflow = true }
    }

    private mutating func paramByte(_ b: UInt8) {
        paramStarted = true
        switch b {
        case 0x30...0x39:
            current = min((current < 0 ? 0 : current) * 10 + Int32(b - 0x30), 65_535)
        case 0x3B:
            pushParam()
            nextIsSub = false
        default:  // ':'
            pushParam()
            nextIsSub = true
        }
    }

    private mutating func pushParam() {
        if params.values.count < 32 {
            params.values.append(current)
            params.isSub.append(nextIsSub)
        }
        current = -1
    }

    private mutating func dispatchCSI<H: VTParserHandler>(_ final: UInt8, _ handler: H) {
        if paramStarted { pushParam() }
        if !params.overflow { handler.csi(params, final: final) }
        state = .ground
    }

    private mutating func beginPassthrough(_ final: UInt8) {
        if paramStarted { pushParam() }
        dcsFinal = final
        payload.removeAll(keepingCapacity: true)
        payloadOverflow = params.overflow
        state = .dcsPassthrough
    }

    private mutating func collectPayload(_ b: UInt8) {
        if payloadOverflow { return }
        if payload.count >= payloadCap {
            payloadOverflow = true
            payload.removeAll(keepingCapacity: true)
            return
        }
        payload.append(b)
    }

    /// Leaves a string state, handing its payload over unless it overflowed the cap.
    private mutating func endString<H: VTParserHandler>(_ handler: H, dispatch: Bool) {
        switch state {
        case .oscString:
            if dispatch && !payloadOverflow { handler.osc(payload) }
        case .apcString:
            if dispatch && !payloadOverflow { handler.apc(payload) }
        case .dcsPassthrough:
            if dispatch && !payloadOverflow { handler.dcs(params, final: dcsFinal, payload: payload) }
        default:
            return
        }
        payload.removeAll(keepingCapacity: true)
        payloadOverflow = false
    }

    /// Drops a string in progress without dispatching it.
    private mutating func abortString() {
        switch state {
        case .oscString, .apcString, .dcsPassthrough:
            payload.removeAll(keepingCapacity: true)
            payloadOverflow = false
        default:
            break
        }
    }
}
