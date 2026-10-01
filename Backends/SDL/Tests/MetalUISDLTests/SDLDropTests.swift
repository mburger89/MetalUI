import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// Drag and drop on SDL, lane 3, tests 3.1–3.7 (rulings `DN-K` item 4, `DN-M`,
// `DN-U` item 4; spec `docs/superpowers/specs/2026-10-01-drag-and-drop-design.md`
// §6.5). Every drop event goes through SDL's own queue: a raw
// `SDL_EVENT_DROP_*` pushed by `mui_push_raw_drop_event`, its type taken from
// the C-exported `mui_sdl_event_drop_*` constants — never
// `SDL_EVENT_DROP_*.rawValue` in Swift, which is `Int32` on Windows and
// `UInt32` on Apple (`DN-U` item 4) — then `translate` and
// `SDLPlatform.pumpEvents`'s dispatch to `SDLWindow.handle`, the real path.

@MainActor
private func dropWindow() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI drop test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    platform.pumpEvents()   // drain whatever opening the window queued
    return (platform, window)
}

private func pushDrop(_ type: UInt32, _ window: UInt32, _ x: Float = 0, _ y: Float = 0, _ data: String? = nil,
                      sourceLocation: SourceLocation = #_sourceLocation) {
    let pushed = data.map { $0.withCString { mui_push_raw_drop_event(type, window, x, y, $0) } }
        ?? mui_push_raw_drop_event(type, window, x, y, nil)
    #expect(pushed, "push drop type \(type)", sourceLocation: sourceLocation)
}

private func pushPointer(_ kind: Int, _ window: UInt32, _ x: Float, _ y: Float) {
    var event = MUIEvent()
    event.kind = UInt32(kind); event.window_id = window; event.x = x; event.y = y
    #expect(mui_push_event(&event))
}

private func point(_ p: Point<Pixels>) -> String { "(\(Int(p.x.value)),\(Int(p.y.value)))" }

/// One line per event; a performed drop lists each item's types and the bytes
/// its first type loads as text.
@MainActor
private func describe(_ events: [InputEvent]) -> [String] {
    events.map { event in
        switch event {
        case .drop(.entered(let position, let items)):
            return "entered\(point(position)) items=\(items.map { "\($0.count)" } ?? "nil")"
        case .drop(.moved(let position)): return "moved\(point(position))"
        case .drop(.exited): return "exited"
        case .drop(.performed(let position, let items)):
            let described = items.map { item -> String in
                let first = item.types.first?.identifier ?? "none"
                let bytes = item.load(first).map { String(decoding: $0, as: UTF8.self) } ?? "nil"
                return "\(first)=\(bytes)"
            }
            return "performed\(point(position)) \(described)"
        case .mouseMoved(let m): return "move\(point(m.position))"
        case .mouseDragged(let m): return "drag\(point(m.position))"
        default: return "other"
        }
    }
}

/// **3.1** (`DN-M` item 1). `BEGIN, POSITION(10, 20), POSITION(30, 40),
/// FILE(/tmp/a.txt), COMPLETE` is one session: entered at the first position
/// with the items unknown, moved at the second, performed at the last with one
/// file-URL item whose bytes are the URL string. Mutation **M3a** (perform with
/// no items) must redden it.
@MainActor
@Test func sdlDropEventsBecomeOneDropSession() throws {
    let (platform, window) = try dropWindow()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    pushDrop(mui_sdl_event_drop_begin, window.id)
    pushDrop(mui_sdl_event_drop_position, window.id, 10, 20)
    pushDrop(mui_sdl_event_drop_position, window.id, 30, 40)
    pushDrop(mui_sdl_event_drop_file, window.id, 30, 40, "/tmp/a.txt")
    pushDrop(mui_sdl_event_drop_complete, window.id, 30, 40)
    platform.pumpEvents()
    #expect(describe(received) == ["entered(10,20) items=nil", "moved(30,40)",
                                   "performed(30,40) [\"public.file-url=file:///tmp/a.txt\"]"])
    guard case .drop(.performed(_, let items))? = received.last else {
        Issue.record("no performed drop: \(describe(received))"); return
    }
    let item = try #require(items.first)
    #expect(item.types.map(\.identifier) == ["public.file-url"])
    #expect(item.types.first.map { $0.satisfies("public.url") && $0.satisfies("public.data") } == true,
            "a file URL conforms to url and data: \(item.types)")
    #expect(item.load("public.utf8-plain-text") == nil, "a file item is not text")
}

/// **3.2** (`DN-M` item 1). A session whose `COMPLETE` gathered no item is an
/// exit, not an empty drop. Mutation **M3b** (perform an empty drop) must
/// redden it.
@MainActor
@Test func aCompleteWithNoItemsIsAnExit() throws {
    let (platform, window) = try dropWindow()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    pushDrop(mui_sdl_event_drop_begin, window.id)
    pushDrop(mui_sdl_event_drop_position, window.id, 50, 60)
    pushDrop(mui_sdl_event_drop_complete, window.id, 50, 60)
    platform.pumpEvents()
    #expect(describe(received) == ["entered(50,60) items=nil", "exited"])
}

/// **3.3** (`DN-M` item 1). A dropped path becomes a `file://` URL string:
/// RFC 3986's unreserved characters and `/` kept, everything else
/// percent-encoded as UTF-8, a Windows drive path `file:///C:/…` with its
/// backslashes as slashes. Mutation **M3c** (no percent-encoding) must redden
/// it.
@Test func aDroppedPathBecomesAFileURLString() {
    #expect(SDLWindow.fileURLString(fromPath: "/tmp/a b.txt") == "file:///tmp/a%20b.txt")
    #expect(SDLWindow.fileURLString(fromPath: #"C:\Users\x y.txt"#) == "file:///C:/Users/x%20y.txt")
    #expect(SDLWindow.fileURLString(fromPath: "/tmp/é.txt") == "file:///tmp/%C3%A9.txt")
    #expect(SDLWindow.fileURLString(fromPath: "/a/b-c_d.e~f") == "file:///a/b-c_d.e~f")
    #expect(SDLWindow.fileURLString(fromPath: "/a/100%#?.txt") == "file:///a/100%25%23%3F.txt")
}

/// **3.4** (`DN-M` item 1). Dropped text is one UTF-8 plain-text item,
/// conforming to plain text, text and data. Mutation **M3d** (type
/// `public.text`) must redden it.
@MainActor
@Test func droppedTextIsUTF8PlainText() throws {
    let (platform, window) = try dropWindow()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    pushDrop(mui_sdl_event_drop_begin, window.id)
    pushDrop(mui_sdl_event_drop_text, window.id, 5, 6, "hi")
    pushDrop(mui_sdl_event_drop_complete, window.id, 5, 6)
    platform.pumpEvents()
    #expect(describe(received) == ["entered(5,6) items=nil",
                                   "performed(5,6) [\"public.utf8-plain-text=hi\"]"],
            "with no position the first item's position enters (DN-M item 1)")
    guard case .drop(.performed(_, let items))? = received.last else {
        Issue.record("no performed drop: \(describe(received))"); return
    }
    try #require(items.count == 1)
    let type = try #require(items[0].types.first)
    #expect(items[0].types.count == 1)
    #expect(type.identifier == "public.utf8-plain-text")
    #expect(type.satisfies("public.plain-text") && type.satisfies("public.text") && type.satisfies("public.data"),
            "\(type)")
    #expect(!type.satisfies("public.url"))
}

/// **3.5** (`DN-K` item 4). An SDL window cannot hand a drag to the operating
/// system: SDL3 has no outgoing drag API. Mutation **M3e** (`true`) must
/// redden it. (Green on arrival — lane 1 wrote the member, `DN-T`.)
@MainActor
@Test func anSDLWindowCannotBeginAnExternalDrag() throws {
    let (_, window) = try dropWindow()
    let text = DragRepresentation(type: PasteboardType(identifier: "public.utf8-plain-text"), bytes: Array("s".utf8))
    #expect(window.beginExternalDrag([text], at: Point(x: Pixels(400), y: Pixels(10))) == false)
}

/// **3.6** (`DN-M` item 1). An ordinary pointer motion while a session is open
/// ends it with an exit (a backend that sends no `COMPLETE` on leaving), then
/// the motion is delivered. Mutation **M3f** (ignore motion) must redden it.
@MainActor
@Test func ordinaryPointerMotionEndsAnOpenDropSession() throws {
    let (platform, window) = try dropWindow()
    var received: [InputEvent] = []
    window.onInput = { received.append($0); return true }
    pushDrop(mui_sdl_event_drop_begin, window.id)
    pushDrop(mui_sdl_event_drop_position, window.id, 10, 20)
    pushPointer(MUI_EVENT_MOUSE_MOVE, window.id, 70, 80)
    // The session is closed: a later COMPLETE belongs to no session.
    pushDrop(mui_sdl_event_drop_complete, window.id, 70, 80)
    platform.pumpEvents()
    #expect(describe(received) == ["entered(10,20) items=nil", "exited", "move(70,80)"])
}

/// **3.7** (`DN-M` item 1, `DN-U` item 4). The bridge translates each of the
/// five `SDL_EVENT_DROP_*` kinds into its `MUI_EVENT_DROP_*`, carrying `x`,
/// `y` and `text`; each text is copied at once (SDL owns it until the next
/// poll). Mutation **M3g** (drop `POSITION` from the switch) must redden it.
@MainActor
@Test func theBridgeTranslatesEverySDLDropEvent() throws {
    let (_, window) = try dropWindow()
    pushDrop(mui_sdl_event_drop_begin, window.id)
    pushDrop(mui_sdl_event_drop_position, window.id, 1.5, 2.5)
    pushDrop(mui_sdl_event_drop_file, window.id, 3, 4, "/tmp/f")
    pushDrop(mui_sdl_event_drop_text, window.id, 5, 6, "text é")
    pushDrop(mui_sdl_event_drop_complete, window.id, 7, 8)
    var seen: [String] = []
    var event = MUIEvent()
    while mui_poll_event(&event) {
        let text = event.text.map { String(cString: $0) } ?? "nil"
        let name: String
        switch Int(event.kind) {
        case Int(MUI_EVENT_DROP_BEGIN): name = "BEGIN"
        case Int(MUI_EVENT_DROP_POSITION): name = "POSITION"
        case Int(MUI_EVENT_DROP_FILE): name = "FILE"
        case Int(MUI_EVENT_DROP_TEXT): name = "TEXT"
        case Int(MUI_EVENT_DROP_COMPLETE): name = "COMPLETE"
        default: continue
        }
        #expect(event.window_id == window.id, "\(name)")
        seen.append("\(name)(\(event.x),\(event.y),\(text))")
    }
    #expect(seen == ["BEGIN(0.0,0.0,nil)", "POSITION(1.5,2.5,nil)", "FILE(3.0,4.0,/tmp/f)",
                     "TEXT(5.0,6.0,text é)", "COMPLETE(7.0,8.0,nil)"])
}
