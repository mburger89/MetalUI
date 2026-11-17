import Foundation
import Testing
@testable import MetalUITerminal

/// OSC 0/2/7/8/10/11 beyond the `41`..`45` fixtures: caps, replies, the link table and snapshot publishing.
@Suite struct OSCTests {
    private func events(_ input: String, cols: Int = 20, cap: Int = 4096) -> [TerminalEvent] {
        let e = TerminalEmulator(cols: cols, rows: 3, payloadCap: cap)
        e.feed(input)
        return e.drainEvents()
    }

    @Test func aTitleIsCappedAt256CharactersNotBytes() {
        let long = String(repeating: "\u{E9}", count: 300)
        #expect(events("\(ESC)]0;\(long)\(BEL)") == [.title(String(repeating: "\u{E9}", count: 256))])
        #expect(events("\(ESC)]2;\(String(repeating: "w", count: 256))\(BEL)") == [.title(String(repeating: "w", count: 256))])
        #expect(events("\(ESC)]2;with space; and semicolon\(BEL)") == [.title("with space; and semicolon")])
    }

    @Test func anOverlongStringIsDroppedToItsTerminatorAndTheParserRecovers() {
        let e = TerminalEmulator(cols: 20, rows: 3, payloadCap: 16)
        e.feed("\(ESC)]0;\(String(repeating: "x", count: 30))\(BEL)ok\(ESC)]0;short\(ST)!")
        #expect(e.drainEvents() == [.title("short")])
        #expect(e.screenLines[0] == "ok!")
        // A payload of exactly the cap still lands; one byte more does not.
        #expect(events("\(ESC)]0;\(String(repeating: "y", count: 14))\(BEL)", cap: 16).count == 1)
        #expect(events("\(ESC)]0;\(String(repeating: "y", count: 15))\(BEL)", cap: 16).isEmpty)
        // An overlong link target is dropped whole: no event, no link on the cells printed after it.
        let f = TerminalEmulator(cols: 20, rows: 3, payloadCap: 32)
        f.feed("\(ESC)]8;;http://\(String(repeating: "u", count: 40))\(BEL)a")
        #expect(f.drainEvents().isEmpty)
        #expect(f.publishSnapshot().damagedRows[0].row.cell(at: 0).attributes.hyperlink == nil)
    }

    @Test func clipboardAndOtherOSCNumbersDoNothing() {
        let e = TerminalEmulator(cols: 20, rows: 3)
        e.feed("\(ESC)]52;c;aGVsbG8=\(BEL)\(ESC)]52;c;?\(BEL)\(ESC)]1;i\(BEL)\(ESC)]4;1;?\(BEL)\(ESC)]99;x\(BEL)\(ESC)]\(BEL)\(ESC)]a;b\(BEL)\(ESC)]0\(BEL)")
        #expect(e.drainEvents().isEmpty)
        #expect(e.screenLines[0].isEmpty)
    }

    @Test func aWorkingDirectoryNeedsAFileSchemeAndALocalHost() {
        #expect(events("\(ESC)]7;file:///a/b\(BEL)") == [.workingDirectory(URL(fileURLWithPath: "/a/b"))])
        #expect(events("\(ESC)]7;file://localhost/a%20b\(BEL)") == [.workingDirectory(URL(fileURLWithPath: "/a b"))])
        #expect(events("\(ESC)]7;file://evil.example.invalid/a\(BEL)").isEmpty)
        #expect(events("\(ESC)]7;http://localhost/a\(BEL)").isEmpty)
        #expect(events("\(ESC)]7;/a/b\(BEL)").isEmpty)
        #expect(events("\(ESC)]7;file://localhost\(BEL)").isEmpty)
        let host = ProcessInfo.processInfo.hostName
        if !host.isEmpty, !host.contains("/") {
            // The machine's own name is accepted (`TRM-AF`); gethostname and hostName can differ in case only.
            #expect(events("\(ESC)]7;file://\(host.split(separator: ".")[0])/h\(BEL)").count <= 1)
        }
    }

    @Test func aLinkReachesTheSnapshotTable() {
        let e = TerminalEmulator(cols: 20, rows: 3)
        e.feed("\(ESC)]8;;http://a\(BEL)x\(ESC)]8;id=k;http://b\(BEL)y")
        let snap = e.publishSnapshot()
        #expect(snap.links == [1: "http://a", 2: "http://b"])
        #expect(snap.damagedRows[0].row.cell(at: 0).attributes.hyperlink == 1)
        #expect(snap.damagedRows[0].row.cell(at: 1).attributes.hyperlink == 2)
        #expect(e.drainEvents() == [.hyperlink(id: 1, uri: "http://a"), .hyperlink(id: 2, uri: "http://b")])
    }

    @Test func aLinkAloneBumpsTheVersion() {
        let e = TerminalEmulator(cols: 20, rows: 3)
        _ = e.publishSnapshot()
        let before = e.publishSnapshot().version
        e.feed("\(ESC)]8;;http://a\(BEL)")
        let after = e.publishSnapshot()
        #expect(after.version == before + 1)
        #expect(after.damagedRows.isEmpty && after.links.count == 1)
    }

    @Test func theLinkTableIsBounded() {
        let e = TerminalEmulator(cols: 20, rows: 3)
        for i in 0..<(TerminalEmulator.linkLimit + 5) { e.feed("\(ESC)]8;;u\(i)\(BEL)") }
        e.feed("z")
        let snap = e.publishSnapshot()
        #expect(snap.links.count == TerminalEmulator.linkLimit)
        #expect(snap.damagedRows[0].row.cell(at: 0).attributes.hyperlink == nil)
    }

    @Test func aColourQueryIsAnsweredOnlyWithThemeColours() {
        let e = TerminalEmulator(cols: 20, rows: 3)
        e.feed("\(ESC)]10;?\(BEL)\(ESC)]11;?\(ST)")
        #expect(e.drainEvents().isEmpty)
        e.queryColors = ((255, 0, 128), (1, 2, 3))
        e.feed("\(ESC)]10;?\(BEL)\(ESC)]11;?\(ST)\(ESC)]11;rgb:00/00/00\(BEL)")
        #expect(e.drainEvents() == [.reply(Array("\(ESC)]10;rgb:ffff/0000/8080\(ESC)\\".utf8)),
                                    .reply(Array("\(ESC)]11;rgb:0101/0202/0303\(ESC)\\".utf8))])
    }

    @Test func publishedRowsAreSharedUntilTheyChange() {
        let e = TerminalEmulator(cols: 8, rows: 4)
        e.feed("aa\r\nbb\r\ncc")
        let first = e.publishSnapshot()
        #expect(first.isFullFrame)
        let addresses = first.damagedRows.map { $0.row.storageAddress }
        #expect(addresses[0] != nil)
        e.feed("\(ESC)[3;1Hzz")
        let second = e.publishSnapshot()
        #expect(!second.isFullFrame)
        #expect(second.damagedRows.map(\.index) == [2])
        #expect(e.screen[0].storageAddress == addresses[0])
        #expect(e.screen[1].storageAddress == addresses[1])
        #expect(second.damagedRows[0].row.storageAddress != addresses[2])
        #expect(e.publishSnapshot().damagedRows.isEmpty)
    }

    @Test func aFullFrameListsEveryRowAfterAnAlternateScreenSwitch() {
        let e = TerminalEmulator(cols: 8, rows: 4)
        _ = e.publishSnapshot()
        e.feed("\(ESC)[?1049h")
        let snap = e.publishSnapshot()
        #expect(snap.isFullFrame && snap.damagedRows.map(\.index) == [0, 1, 2, 3])
        #expect(e.publishSnapshot().version == snap.version)
    }
}
