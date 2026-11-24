import Foundation

/// The key of an OSC 8 link that carries an explicit `id=`: the same id and target share one numeric id.
struct LinkKey: Hashable {
    let id: String
    let uri: String
}

/// Operating system commands (`TRM-AE`..`TRM-AH`): titles, the working directory, hyperlinks and the colour
/// queries. OSC 52 (clipboard) and every other number are dropped (spec section 2.1, rule 2).
extension TerminalEmulator {
    /// The most distinct links one emulator remembers; a link past it is not attached to cells.
    static let linkLimit = 65_536
    /// The longest title, in characters.
    static let titleLimit = 256

    func handleOSC(_ payload: [UInt8]) {
        var number = 0
        var index = 0
        while index < payload.count, payload[index] >= 0x30, payload[index] <= 0x39, index < 6 {
            number = number * 10 + Int(payload[index] - 0x30)
            index += 1
        }
        guard index > 0 else { return }
        guard index < payload.count, payload[index] == 0x3B else { return }
        let rest = Array(payload[(index + 1)...])
        switch number {
        case 0, 2: setTitle(rest)
        case 7: setWorkingDirectory(rest)
        case 8: setHyperlink(rest)
        case 10, 11: answerColorQuery(number, rest)
        default: break
        }
    }

    private func setTitle(_ bytes: [UInt8]) {
        let text = String(decoding: bytes, as: UTF8.self)
        emit(.title(String(text.prefix(Self.titleLimit))))
    }

    /// OSC 7: `file://host/path`. The host must be empty, `localhost` or this machine's; any other scheme or
    /// host is dropped (`TRM-AF`).
    private func setWorkingDirectory(_ bytes: [UInt8]) {
        guard let text = String(validatingCString: bytes.map { CChar(bitPattern: $0) } + [0]),
              let components = URLComponents(string: text), components.scheme?.lowercased() == "file" else { return }
        let host = (components.host ?? "").lowercased()
        guard host.isEmpty || host == "localhost" || Self.isThisHost(host) else { return }
        let path = components.path
        guard path.hasPrefix("/"), !path.contains("\u{0}") else { return }
        emit(.workingDirectory(URL(fileURLWithPath: path)))
    }

    private static let hostName: String = {
        #if os(Windows)
        return ProcessInfo.processInfo.hostName.lowercased()
        #else
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count - 1) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).lowercased()
        #endif
    }()

    private static func isThisHost(_ host: String) -> Bool {
        guard !hostName.isEmpty else { return false }
        return host == hostName || host == hostName.split(separator: ".").first.map(String.init)
    }

    /// OSC 8: `params ; uri`. An empty uri ends the link. `id=` in the colon-separated params makes a link
    /// that is reused by id and target; without one every opening is a fresh link.
    private func setHyperlink(_ bytes: [UInt8]) {
        guard let separator = bytes.firstIndex(of: 0x3B) else { return }
        let params = String(decoding: bytes[..<separator], as: UTF8.self)
        let uri = String(decoding: bytes[(separator + 1)...], as: UTF8.self)
        guard !uri.isEmpty else {
            pen.hyperlink = nil
            return
        }
        let explicit = params.split(separator: ":").first { $0.hasPrefix("id=") }.map { String($0.dropFirst(3)) }
        if let explicit, !explicit.isEmpty, let known = linkIDs[LinkKey(id: explicit, uri: uri)] {
            pen.hyperlink = known
            return
        }
        guard links.count < Self.linkLimit, nextLinkID < UInt32.max else {
            pen.hyperlink = nil
            return
        }
        let id = nextLinkID
        nextLinkID += 1
        links[id] = uri
        linksChanged = true
        if let explicit, !explicit.isEmpty { linkIDs[LinkKey(id: explicit, uri: uri)] = id }
        pen.hyperlink = id
        emit(.hyperlink(id: id, uri: uri))
    }

    /// OSC 10 and 11 with a `?` argument answer with the colours the owner set in ``queryColors``
    /// (`rgb:rrrr/gggg/bbbb`, the string terminator the query used is not tracked, so ST answers both); setting
    /// a colour is not supported.
    private func answerColorQuery(_ number: Int, _ rest: [UInt8]) {
        guard rest == [0x3F], let colors = queryColors else { return }
        let c = number == 10 ? colors.foreground : colors.background
        func hex(_ v: UInt8) -> String { let s = String(v, radix: 16); return String(repeating: "0", count: 2 - s.count) + s }
        reply("\u{1B}]\(number);rgb:\(hex(c.0))\(hex(c.0))/\(hex(c.1))\(hex(c.1))/\(hex(c.2))\(hex(c.2))\u{1B}\\")
    }

    /// SGR 0: everything but the OSC 8 link, which only OSC 8 ends.
    func resetPenKeepingLink() {
        let link = pen.hyperlink
        pen = TerminalAttributes()
        pen.hyperlink = link
    }
}
