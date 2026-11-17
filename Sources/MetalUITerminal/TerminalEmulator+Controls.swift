/// What the parser's callbacks mean (`TRM-Z`..`TRM-AD`): C0 and C1 controls, escape sequences, CSI (including
/// SGR, modes and replies).
extension TerminalEmulator {
    func execute(_ code: UInt8) {
        switch code {
        case 0x07: emit(.bell)
        case 0x08: moveCursor(col: cursorCol - 1)
        case 0x09: moveCursor(col: nextTabStop(from: cursorCol, count: 1))
        case 0x0A, 0x0B, 0x0C, 0x84: lineFeed()
        case 0x0D: moveCursor(col: 0)
        case 0x0E:  // SO
            glSet = 1
            updateTranslation()
        case 0x0F:  // SI
            glSet = 0
            updateTranslation()
        case 0x85:
            moveCursor(col: 0)
            lineFeed()
        case 0x88: tabStops[cursorCol] = true  // HTS
        case 0x8D: reverseIndex()  // RI
        default: break
        }
    }

    func esc(intermediates: [UInt8], final: UInt8) {
        if intermediates.isEmpty {
            switch final {
            case 0x44: lineFeed()  // IND
            case 0x45:  // NEL
                moveCursor(col: 0)
                lineFeed()
            case 0x4D: reverseIndex()  // RI
            case 0x48: tabStops[cursorCol] = true  // HTS
            case 0x37: saveCursor()  // DECSC
            case 0x38: restoreCursor()  // DECRC
            case 0x63: hardReset()  // RIS
            case 0x3D: currentModes.applicationKeypad = true  // DECKPAM
            case 0x3E: currentModes.applicationKeypad = false  // DECKPNM
            default: break
            }
            return
        }
        guard intermediates.count == 1 else { return }
        let marker = intermediates[0]
        if marker == 0x23 && final == 0x38 {  // DECALN
            screenAlignmentPattern()
        } else if marker >= 0x28 && marker <= 0x2B {  // designate G0-G3
            switch final {
            case 0x30: charsets[Int(marker - 0x28)] = .decGraphics
            case 0x41: charsets[Int(marker - 0x28)] = .uk
            default: charsets[Int(marker - 0x28)] = .ascii
            }
            updateTranslation()
        }
    }

    func csi(_ p: CSIParameters, final: UInt8) {
        if p.prefix == 0x3F {
            csiPrivate(p, final: final)
            return
        }
        if p.prefix == 0x3E {
            if final == 0x63 && p.intermediates.isEmpty && parameter(p) == 0 { reply("\u{1B}[>1;0;0c") }  // DA2
            return
        }
        guard p.prefix == 0 else { return }
        if !p.intermediates.isEmpty {
            csiWithIntermediate(p, final: final)
            return
        }
        switch final {
        case 0x41: cursorUp(count(p))  // CUU
        case 0x42, 0x65: cursorDown(count(p))  // CUD, VPR
        case 0x43, 0x61: moveCursor(col: cursorCol + count(p))  // CUF, HPR
        case 0x44: moveCursor(col: cursorCol - count(p))  // CUB
        case 0x45:  // CNL
            cursorDown(count(p))
            moveCursor(col: 0)
        case 0x46:  // CPL
            cursorUp(count(p))
            moveCursor(col: 0)
        case 0x47, 0x60: moveCursor(col: count(p) - 1)  // CHA, HPA
        case 0x64: setRow(oneBased: count(p))  // VPA
        case 0x48, 0x66:  // CUP, HVP
            setRow(oneBased: count(p, 0))
            moveCursor(col: count(p, 1) - 1)
        case 0x49: moveCursor(col: nextTabStop(from: cursorCol, count: count(p)))  // CHT
        case 0x5A: moveCursor(col: previousTabStop(from: cursorCol, count: count(p)))  // CBT
        case 0x67:  // TBC
            switch parameter(p) {
            case 0: tabStops[cursorCol] = false
            case 3: for index in 0..<cols { tabStops[index] = false }
            default: break
            }
        case 0x4A: eraseInDisplay(parameter(p))  // ED
        case 0x4B: eraseInLine(parameter(p))  // EL
        case 0x40: insertCharacters(count(p))  // ICH
        case 0x50: deleteCharacters(count(p))  // DCH
        case 0x58: eraseCharacters(count(p))  // ECH
        case 0x4C: insertLines(count(p))  // IL
        case 0x4D: deleteLines(count(p))  // DL
        case 0x53:  // SU
            scrollRegionUp(count: count(p))
        case 0x54:  // SD
            scrollRegionDown(count: count(p))
        case 0x62: repeatLast(count(p))  // REP
        case 0x72:  // DECSTBM
            let bottom = parameter(p, 1)
            setRegion(top: count(p, 0), bottom: bottom == 0 ? rows : bottom)
        case 0x73: if p.values.isEmpty { saveCursor() }  // SCOSC
        case 0x75: if p.values.isEmpty { restoreCursor() }  // SCORC
        case 0x6D: sgr(p)
        case 0x63: if parameter(p) == 0 { reply("\u{1B}[?62;22c") }  // DA1
        case 0x6E:  // DSR
            switch parameter(p) {
            case 5: reply("\u{1B}[0n")
            case 6: reply("\u{1B}[\(reportedRow);\(cursorCol + 1)R")
            default: break
            }
        case 0x68, 0x6C:  // SM, RM
            for value in p.values where value == 4 { insertMode = final == 0x68 }
        default: break
        }
    }

    private var reportedRow: Int { (currentModes.originMode ? cursorRow - regionTop : cursorRow) + 1 }

    private func csiWithIntermediate(_ p: CSIParameters, final: UInt8) {
        guard p.intermediates.count == 1 else { return }
        switch (p.intermediates[0], final) {
        case (0x20, 0x71):  // DECSCUSR
            let value = parameter(p)
            guard value <= 6 else { return }
            let shape: TerminalCursorStyle.Shape = value <= 2 ? .block : value <= 4 ? .underline : .bar
            // 0 and 1 are both the blinking block (xterm ctlseqs, VT520; `TRM-AD`); odd values blink, even are steady.
            currentModes.cursorStyle = TerminalCursorStyle(shape: shape, blinking: value % 2 == 1 || value == 0)
        case (0x21, 0x70):  // DECSTR
            softReset()
        case (0x24, 0x70):  // DECRQM
            let number = parameter(p)
            reply("\u{1B}[\(number);\(ansiModeStatus(number))$y")
        default: break
        }
    }

    private func csiPrivate(_ p: CSIParameters, final: UInt8) {
        if p.intermediates.isEmpty {
            switch final {
            case 0x68, 0x6C: for value in p.values where value >= 0 { setPrivateMode(value, final == 0x68) }
            case 0x4A: eraseInDisplay(parameter(p))  // DECSED
            case 0x4B: eraseInLine(parameter(p))  // DECSEL
            case 0x6E where parameter(p) == 6:  // DECXCPR
                reply("\u{1B}[?\(reportedRow);\(cursorCol + 1);1R")
            default: break
            }
        } else if p.intermediates == [0x24] && final == 0x70 {  // DECRQM
            let number = parameter(p)
            reply("\u{1B}[?\(number);\(privateModeStatus(number))$y")
        }
    }

    // MARK: Modes

    func setPrivateMode(_ number: Int32, _ on: Bool) {
        switch number {
        case 1: currentModes.applicationCursorKeys = on
        case 6:
            currentModes.originMode = on
            home()
        case 7: currentModes.autowrap = on
        case 12: currentModes.cursorStyle.blinking = on
        case 25: currentModes.cursorVisible = on
        case 9: currentModes.mouseTracking = on ? .x10 : .off
        case 1000: currentModes.mouseTracking = on ? .normal : .off
        case 1002: currentModes.mouseTracking = on ? .buttonEvent : .off
        case 1003: currentModes.mouseTracking = on ? .anyEvent : .off
        case 1004: currentModes.focusEvents = on
        case 1005: currentModes.mouseEncoding = on ? .utf8 : .legacy
        case 1006: currentModes.mouseEncoding = on ? .sgr : .legacy
        case 2004: currentModes.bracketedPaste = on
        case 47: on ? enterAlternate(clear: false) : leaveAlternate(clear: false)
        case 1047: on ? enterAlternate(clear: false) : leaveAlternate(clear: true)
        case 1048: on ? saveCursor() : restoreCursor()
        case 1049:
            if on {
                guard !onAlternate else { return }
                saveCursor()
                enterAlternate(clear: true)
            } else {
                guard onAlternate else { return }
                leaveAlternate(clear: false)
                restoreCursor()
            }
        default: break
        }
    }

    /// The DECRQM answer for a private mode: 0 unknown, 1 set, 2 reset, 4 permanently reset.
    private func privateModeStatus(_ number: Int) -> Int {
        func state(_ on: Bool) -> Int { on ? 1 : 2 }
        let m = currentModes
        switch number {
        case 1: return state(m.applicationCursorKeys)
        case 6: return state(m.originMode)
        case 7: return state(m.autowrap)
        case 9: return state(m.mouseTracking == .x10)
        case 12: return state(m.cursorStyle.blinking)
        case 25: return state(m.cursorVisible)
        case 47, 1047, 1049: return state(onAlternate)
        case 1000: return state(m.mouseTracking == .normal)
        case 1002: return state(m.mouseTracking == .buttonEvent)
        case 1003: return state(m.mouseTracking == .anyEvent)
        case 1004: return state(m.focusEvents)
        case 1005: return state(m.mouseEncoding == .utf8)
        case 1006: return state(m.mouseEncoding == .sgr)
        case 1048: return 2
        case 2004: return state(m.bracketedPaste)
        case 69: return 4
        default: return 0
        }
    }

    private func ansiModeStatus(_ number: Int) -> Int {
        switch number {
        case 4: return insertMode ? 1 : 2
        case 20: return 4
        default: return 0
        }
    }

    // MARK: SGR

    /// SGR (`TRM-AD`): `;` and `:` forms, 16, 256 and 24-bit colours, underline styles. A malformed extended
    /// colour ends the sequence there; what came before it applies.
    func sgr(_ p: CSIParameters) {
        let values = p.values
        if values.isEmpty {
            resetPenKeepingLink()
            return
        }
        var index = 0
        while index < values.count {
            // A group is one parameter and the `:` sub-parameters that follow it.
            var groupEnd = index + 1
            while groupEnd < values.count && p.isSub[groupEnd] { groupEnd += 1 }
            let code = Int(max(values[index], 0))
            let subs = Array(values[(index + 1)..<groupEnd])
            index = groupEnd
            switch code {
            case 0: resetPenKeepingLink()
            case 1: pen.bold = true
            case 2: pen.dim = true
            case 3: pen.italic = true
            case 4:
                if let style = subs.first {
                    switch style {
                    case 0: pen.underlineStyle = .none
                    case 2: pen.underlineStyle = .double
                    case 3: pen.underlineStyle = .curly
                    case 4: pen.underlineStyle = .dotted
                    case 5: pen.underlineStyle = .dashed
                    default: pen.underlineStyle = .single
                    }
                } else {
                    pen.underlineStyle = .single
                }
            case 5, 6: pen.blink = true
            case 7: pen.inverse = true
            case 8: pen.hidden = true
            case 9: pen.strikethrough = true
            case 21: pen.underlineStyle = .double
            case 22:
                pen.bold = false
                pen.dim = false
            case 23: pen.italic = false
            case 24: pen.underlineStyle = .none
            case 25: pen.blink = false
            case 27: pen.inverse = false
            case 28: pen.hidden = false
            case 29: pen.strikethrough = false
            case 30...37: pen.foreground = .indexed(UInt8(code - 30))
            case 39: pen.foreground = .default
            case 40...47: pen.background = .indexed(UInt8(code - 40))
            case 49: pen.background = .default
            case 59: pen.underlineColor = .default
            case 90...97: pen.foreground = .indexed(UInt8(code - 90 + 8))
            case 100...107: pen.background = .indexed(UInt8(code - 100 + 8))
            case 38, 48, 58:
                var color: TerminalColor?
                if !subs.isEmpty {
                    color = Self.colon(subs)
                } else {
                    // Semicolon form: the colour's parameters are the next parameters.
                    let mode = index < values.count ? values[index] : -1
                    let need = mode == 5 ? 1 : mode == 2 ? 3 : 0
                    guard need > 0, index + need < values.count else { return }
                    color = Self.colon(Array(values[index...(index + need)]))
                    index += need + 1
                }
                guard let color else { return }
                if code == 38 { pen.foreground = color } else if code == 48 { pen.background = color } else { pen.underlineColor = color }
            default: break
            }
        }
    }

    /// The colour described by `5;n` or `2;r;g;b` (with an optional colour-space id before the channels in the
    /// colon form: `2::r:g:b`); nil when it is malformed or a channel is out of range.
    private static func colon(_ list: [Int32]) -> TerminalColor? {
        func channel(_ v: Int32) -> UInt8? { v >= 0 && v <= 255 ? UInt8(v) : (v < 0 ? 0 : nil) }
        switch list.first {
        case 5:
            guard list.count >= 2, let n = channel(list[1]) else { return nil }
            return .indexed(n)
        case 2:
            let channels: ArraySlice<Int32>
            if list.count >= 5 {
                channels = list[2..<5]
            } else if list.count == 4 {
                channels = list[1..<4]
            } else {
                return nil
            }
            let c = channels.compactMap(channel)
            guard c.count == 3 else { return nil }
            return .rgb(c[0], c[1], c[2])
        default:
            return nil
        }
    }
}
