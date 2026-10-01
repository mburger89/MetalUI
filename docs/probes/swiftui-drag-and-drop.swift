// SwiftUI probe: drag and drop (user request 2026-10-01, not a plan task) —
// `Transferable` content types and encoding, drop-callback sequencing,
// precedence of `.draggable` against taps, clicks, `Button`, `DragGesture`,
// `List` selection, `ScrollView`, `TextField` and `Slider`, drop-target
// selection (nested, siblings, covered, disabled, `allowsHitTesting(false)`),
// Escape, leaving the window, the default and custom preview, and what
// accessibility publishes. Evidence for rulings DN-A… in
// docs/superpowers/2026-10-01-drag-and-drop-decisions.md; spec
// docs/superpowers/specs/2026-10-01-drag-and-drop-design.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-drag-and-drop.swift -o /tmp/dnd-probe
//   /tmp/dnd-probe                              # groups T, R, A (headless)
//   METALUI_DND_POINTER=1 /tmp/dnd-probe        # + group P (moves YOUR pointer)
//   METALUI_DND_POINTER=1 METALUI_DND_ONLY=P0,P13a /tmp/dnd-probe   # chosen P arms
//
// Group P needs an unlocked screen (lock probe: no CGSSessionScreenIsLocked
// line, `displayAsleep main: 0`) and event-posting access for the terminal
// (`CGPreflightPostEventAccess()` true). It posts real CGEvents at the HID
// event tap — the pointer really moves for ~3 minutes — and restores the
// pointer's position at the end. Do not touch the mouse while it runs.
//
// THE INSTRUMENTS.
// - T: CoreTransferable's own `exportedContentTypes`/`importedContentTypes`/
//   `exported(as:)`/`init(importing:contentType:)`, headless.
// - R: SwiftUI's destination view (`_PlatformDraggingDestinationView`, found
//   by `registeredDraggedTypes`) driven with a fake `NSDraggingInfo` over a
//   private pasteboard. **Trusted for type filtering, callback ORDER and the
//   action's arguments only.** Its spatial readings are wrong: SwiftUI picks
//   the destination from the live pointer, not `draggingLocation` — R2b
//   targets a 100x100 destination from outside it, R6/R6c never reach the
//   inner destination, R8 delivers B's drop to A, R5/R7 deliver everywhere.
//   Every spatial ruling rests on a P arm instead.
// - A: the NSAccessibility walk of swiftui-accessibility-part2.swift (KVC on
//   the modern selectors after AXEnhancedUserInterface), plus perform
//   selectors, attribute and action names.
// - P: a 400x200 floating window at (300,300); source at (100,100) (left
//   half), String target the right half. A background thread posts
//   move/down/20 dragged steps/4 small wiggles/up; the main thread pumps
//   NSApp events (a drag session tracks inside sendEvent). `phase=` lines
//   come from `.onDragSessionUpdated` on the source. P18 samples a 40x40-pt
//   screen square with /usr/sbin/screencapture mid-drag.
//
// POSITIVE CONTROLS AND SEPARATING ARMS. P0 (a draggable dropped on the
// target: T=true,T=false,drop) against P0b (the same drag from a plain colour:
// `-`). P1a/P3a/P22a (clicks) against P1b/P3b/P22b (drags). P17z (zero
// distance, tap) against P17 1pt (session). P18c (no drag) against P18/P18b.
// R0a (no destination: none) against R0b. A0 (no modifiers) against A1-A4.
// T7d (URL from url data) against T7c (from plain text).
//
// RECORDED 2026-10-01 by the drag-and-drop design session, macOS 27.0,
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen UNLOCKED (no
// CGSSessionScreenIsLocked line, displayAsleep main: 0), AXIsProcessTrusted
// and CGPreflightPostEventAccess both true. Compiled form, run twice with
// METALUI_DND_POINTER=1: stdout byte-identical (134 lines), exit 0, stderr
// empty both times. Earlier development runs of every arm read the same
// values. Output, verbatim:
//
//   --- T: Transferable (CoreTransferable, headless)
//     T1 String exported: public.utf8-plain-text imported: public.utf8-plain-text
//     T2 URL exported: public.url,public.file-url imported: public.url,public.file-url
//     T3 Data exported: public.data imported: public.data
//     T3b AttributedString exported: com.apple.flat-rtfd,public.rtf,public.utf8-plain-text
//     T4 web URL instance exported: public.url; file URL instance: public.url,public.file-url
//     T5 "héllo" exported as utf8PlainText: "héllo" (6 bytes)
//     T5b "héllo" exported as plainText: "héllo" (6 bytes)
//     T5c "héllo" exported as nil: "héllo" (6 bytes)
//     T6 web URL exported as url: "https://example.com/a" (21 bytes)
//     T6b file URL exported as fileURL: "file:///tmp/metalui-probe.txt" (29 bytes)
//     T6c web URL exported as plainText: throws
//     T7 String imported from utf8 'x': x
//     T7b String imported from url data: nil
//     T7c URL imported from plainText 'https://e.com': nil
//     T7d URL imported from url data: https://e.com
//     T7e Data imported from png content type: nil
//   --- R: drop sequencing through a fake NSDraggingInfo (200x200 window, centre (100,100), top-left points)
//     R0a registered dragged types, plain Color (control): none
//     R0b registered, dropDestination(for: String.self): _PlatformDraggingDestinationView:public.data|public.item
//     R0c registered, dropDestination(for: URL.self): _PlatformDraggingDestinationView:public.data|public.item
//     R0d registered, dropDestination(for: Data.self): _PlatformDraggingDestinationView:public.data|public.item
//     R0e registered, onDrop(of: [.plainText]): _PlatformDraggingDestinationView:public.data|public.item
//     R0f registered, draggable only: none
//     R1 String dest, String drop: enter, update, update, exit: e=copy [dT=true] u=copy u=copy x [dT=false]
//     R1b String dest, String drop: enter, update, perform: e=copy [dT=true] u=copy prep=true perf=true [dT=false,d:["hello"] at (30,40)]
//     R1c String dest, String drop: perform then draggingEnded: e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)] end
//     R2 location space: 100x100 dest centred, drop at window (60,70): e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (60,70)]
//     R2b 100x100 dest centred: enter OUTSIDE it (20,20), update inside, update outside: e=copy [dT=true] u=copy u=copy prep=true perf=true [dT=false,d:["hello"] at (20,20)]
//     R3 String dest, file-URL drop: e=none prep=true perf=true [dT=false,d:[] at (100,100)]
//     R3b String dest, web-URL drop: e=none prep=true perf=true [dT=false,d:[] at (100,100)]
//     R3c URL dest, String 'https://example.com/s' drop: e=none prep=true perf=true [dT=false,d:[] at (100,100)]
//     R3d URL dest, file-URL drop: e=copy [dT=true] prep=true perf=true [dT=false,d:["file:///tmp/metalui-probe.txt"] at (100,100)]
//     R3e URL dest, web-URL drop: e=copy [dT=true] prep=true perf=true [dT=false,d:["https://example.com/a"] at (100,100)]
//     R3f String dest, two strings: e=copy [dT=true] prep=true perf=true [dT=false,d:["one", "two"] at (100,100)]
//     R3g Data dest, String drop: e=copy [dT=true] prep=true perf=true [dT=false,d:["5 bytes"] at (100,100)]
//     R4 action returns false: e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R5 dest .disabled(true): e=copy [dT=true] u=copy prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R5b dest inside .disabled(true) VStack: e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R5c dest .allowsHitTesting(false): e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R5d dest .hidden(): e=none prep=true perf=false
//     R5e dest .opacity(0): e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R6 nested String/String: drop on inner: e=copy [outerT=true] prep=true perf=true [outerT=false,outer:["hello"] at (100,100)]
//     R6b nested String/String: drop outside inner: e=copy [outerT=true] prep=true perf=true [outerT=false,outer:["hello"] at (20,20)]
//     R6c nested String/String: enter outer, move into inner, move out, drop outer: e=copy [outerT=true] u=copy u=copy prep=true perf=true [outerT=false,outer:["hello"] at (20,20)]
//     R6d outer String, inner URL: String drop on inner: e=copy [outerT=true] prep=true perf=true [outerT=false,outer:["hello"] at (100,100)]
//     R6e two dropDestinations chained on one view: e=copy [chainedT=true] prep=true perf=true [chainedT=false,chained:["hello"]]
//     R7 dest covered by a plain Color: drop on the Color: e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R7b dest covered by a tappable Color: drop on it: e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R7c dest covered by a non-hit-testable Color: e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R7d dest covered by a Button: drop on it: e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//     R8 sibling A then B: enter A, move to B, drop B: e=copy [AT=true] u=copy prep=true perf=true [AT=false,A:["hello"] at (150,100)]
//     R9 onDrop(of: [.plainText]) String drop: e=copy prep=true perf=true [onDrop:1 at (100,100)]
//     R10 drop from a source with no copy in its mask (move only): e=copy [dT=true] prep=true perf=true [dT=false,d:["hello"] at (100,100)]
//   --- A: what NSHostingView publishes to accessibility (AXEnhancedUserInterface on)
//     A0 control: VStack { Text src; Text dst }
//     FirstMouseHost role=AXGroup label=nil value=nil performs=["Press", "ShowMenu", "Pick"] attrs=11 actionNames=[] kids=2
//       AccessibilityNode role=AXStaticText label=nil value=src performs=["Press", "ShowMenu"] attrs=0 actionNames=[] kids=0
//       AccessibilityNode role=AXStaticText label=nil value=dst performs=["Press", "ShowMenu"] attrs=0 actionNames=[] kids=0
//     A1 Text src .draggable; Text dst .dropDestination
//     FirstMouseHost role=AXGroup label=nil value=nil performs=["Press", "ShowMenu", "Pick"] attrs=11 actionNames=[] kids=2
//       AccessibilityNode role=AXStaticText label=nil value=src performs=["Press", "ShowMenu"] attrs=0 actionNames=[] kids=0
//       AccessibilityNode role=AXStaticText label=nil value=dst performs=["Press", "ShowMenu"] attrs=0 actionNames=[] kids=0
//     A2 Button .draggable
//     FirstMouseHost role=AXGroup label=nil value=nil performs=["Press", "ShowMenu", "Pick"] attrs=11 actionNames=[] kids=1
//       AccessibilityNode role=AXButton label=btn value=nil performs=["Press", "ShowMenu"] attrs=1 actionNames=[] kids=0
//     A3 Color .dropDestination labelled
//     FirstMouseHost role=AXGroup label=nil value=nil performs=["Press", "ShowMenu", "Pick"] attrs=11 actionNames=[] kids=0
//     A4 Text .onDrag / .onDrop
//     FirstMouseHost role=AXGroup label=nil value=nil performs=["Press", "ShowMenu", "Pick"] attrs=11 actionNames=[] kids=2
//       AccessibilityNode role=AXStaticText label=nil value=src performs=["Press", "ShowMenu"] attrs=0 actionNames=[] kids=0
//       AccessibilityNode role=AXStaticText label=nil value=dst performs=["Press", "ShowMenu"] attrs=0 actionNames=[] kids=0
//   --- P: real pointer drags (CGEvent at the HID tap; 400x200 window, source centre (100,100), target the right half)
//     P0 control: Color.draggable("p0") dragged onto target: T=true,T=false,drop["p0"]
//     P0b control: plain Color (no draggable) dragged onto target: -
//     P1a draggable + onTapGesture: click: tap
//     P1b draggable + onTapGesture: drag: T=true,T=false,drop["p1"]
//     P1c onTapGesture then draggable (other order): drag: T=true,T=false,drop["p1"]
//     P2a draggable then .gesture(DragGesture): drag: T=true,T=false,drop["p2"]
//     P2b .gesture(DragGesture) then draggable: drag: chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,dEnd
//     P2c draggable child, parent .gesture(DragGesture): drag: T=true,T=false,drop["p2"]
//     P2d draggable + highPriorityGesture(DragGesture): drag: chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,dEnd
//     P2e draggable + simultaneousGesture(DragGesture): drag: chg,T=true,T=false,drop["p2"]
//     P2f draggable + onLongPressGesture: drag: T=true,T=false,drop["p2"]
//     P3a plain Button.draggable: click: button
//     P3b plain Button.draggable: drag: T=true,T=false,drop["p3"]
//     P3c bordered Button("Go").draggable: drag from its centre: T=true,T=false,drop["p3"]
//     P4a List(selection:) draggable rows: click row 1: sel=1
//     P4b List(selection:) draggable rows: drag row 1 to target: T=true,T=false,drop["row1"]
//     P5a ScrollView of draggable rows: vertical drag inside (row 1 down 100): off=0
//     P5b ScrollView of draggable rows: drag row 1 to target: off=0,T=true,T=false,drop["row1"]
//     P6 session phases, drag 2pt and release: phase=initial,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=ended with operation cancel
//     P6 session phases, drag 3pt and release: phase=initial,phase=completed data transfer,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=ended with operation cancel
//     P6 session phases, drag 4pt and release: phase=initial,phase=completed data transfer,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=ended with operation cancel
//     P6 session phases, drag 5pt and release: phase=initial,phase=completed data transfer,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=ended with operation cancel
//     P6 session phases, drag 6pt and release: phase=initial,phase=completed data transfer,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=ended with operation cancel
//     P6 session phases, drag 8pt and release: phase=initial,phase=completed data transfer,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=ended with operation cancel
//     P6b session phases, drag onto target: phase=initial,phase=completed data transfer,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,T=true,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,T=false,phase=completed data transfer,drop["p6"],phase=ended with operation copy
//     P6c session phases, drag out of the window (300pt below): phase=initial,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=ended with operation cancel
//     P7 Escape held over target, then release: phase=initial,phase=completed data transfer,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,T=true,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,phase=active,T=false,phase=ended with operation cancel
//     P8 target .disabled(true): phase=completed data transfer,T=true,T=false,drop["p8"]
//     P9 source .disabled(true) (after draggable): T=true,T=false,drop["p9"]
//     P10 enter target, leave, re-enter, drop: T=true,T=false,T=true,T=false,drop["p10"]
//     P11 drop back onto the source itself (source is also a destination): self["p11"]
//     P12a location space: drop at window (330,140) on a right-half target: dT=true,dT=false,d["s"] at (130,140)
//     P13a nested String/String: drop on inner: outerT=true,outerT=false,innerT=true,innerT=false,inner["s"] at (40,40)
//     P13b nested String/String: drop on outer outside inner: outerT=true,outerT=false,outer["s"] at (20,20)
//     P13c outer String, inner URL: String dropped on inner: outerT=true,outerT=false
//     P14 siblings: enter A (250,100), move to B (350,100), drop: AT=true,AT=false,BT=true,BT=false,B["s"] at (50,100)
//     P15a target covered by a plain Color: drop on the Color: dT=true,dT=false,d["s"] at (100,100)
//     P15b target covered by a tappable Color: drop on it: dT=true,dT=false,d["s"] at (100,100)
//     P15c target covered by a non-hit-testable Color: drop on it: dT=true,dT=false,d["s"] at (100,100)
//     P15d target covered by a Button: drop on it: dT=true,dT=false,d["s"] at (100,100)
//     P15e target .allowsHitTesting(false): dT=true,dT=false,d["s"] at (100,100)
//     P16 URL payload onto a String target: -
//     P16b String payload onto a Data target: dataT=true,dataT=false,data[1 bytes]
//     P17 exact move of 1pt, no wiggle, release (draggable + onTapGesture): phase=initial,phase=active,phase=ended with operation cancel
//     P17 exact move of 2pt, no wiggle, release (draggable + onTapGesture): phase=initial,phase=completed data transfer,phase=active,phase=ended with operation cancel
//     P17 exact move of 3pt, no wiggle, release (draggable + onTapGesture): phase=initial,phase=completed data transfer,phase=active,phase=ended with operation cancel
//     P17 exact move of 4pt, no wiggle, release (draggable + onTapGesture): phase=initial,phase=completed data transfer,phase=active,phase=ended with operation cancel
//     P18 default preview: capture around the pointer mid-drag over empty canvas, and the source: phase=completed data transfer {atPointer=orange 0% blue 0% green 0% mean (246,176,108); source=orange 0% blue 0% green 0% mean (244,167,89)}
//     P18b preview: closure (a 60x60 blue square): capture mid-drag: - {atPointer=orange 0% blue 0% green 0% mean (98,172,249); source=orange 0% blue 0% green 0% mean (244,167,89)}
//     P18c preview control: no drag, capture the same points after a click: - {atPointer=orange 0% blue 0% green 0% mean (255,254,255); source=orange 0% blue 0% green 0% mean (244,167,89)}
//     P19 isTargeted while hovering without moving after entry (hold 0.5s): T=true,T=false,drop["s"]
//     P17z a zero-distance dragged event, then release (draggable + onTapGesture): tap
//     P20 TextField.draggable: drag from the field's text onto target: -
//     P20b Slider.draggable: drag from the slider's centre onto target: v=0.56,v=0.61,v=0.67,v=0.72,v=0.78,v=0.83,v=0.89,v=0.94,v=1.0
//     P22a draggable parent, plain Button child: click the child: button
//     P22b draggable parent, plain Button child: drag from the child: T=true,T=false,drop["parent"]
//     P22c draggable parent, onTapGesture child: drag from the child: T=true,T=false,drop["parent"]
//     P22d draggable parent, DragGesture child: drag from the child: chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,chg,dEnd
//     P22e draggable parent, draggable child: drag from the child: T=true,T=false,drop["child"]
//     P22f draggable parent, plain Color child: drag from the child: T=true,T=false,drop["parent"]
//     P21 draggable + onTapGesture(count: 2): drag: T=true,T=false,drop["s"]
//
// READING (each ruling cites its arms):
// - T: String <-> public.utf8-plain-text only (T1, T5-T5c, T7, T7b); URL
//   imports url/file-url, a web URL exports [url], a file URL both (T2, T4,
//   T6, T6b); URL does not take plain text (T6c, T7c); Data <-> public.data.
// - R: registration (R0*); isTargeted true on enter, false on exit and BEFORE
//   the action (R1, R1b); wrong types answer `none` (R3-R3c); two items
//   arrive as two (R3f); Data takes a String (R3g); an action returning false
//   still answers perform=true (R4); hidden refuses (R5d); of two chained
//   destinations the outer receives (R6e).
// - P: see the decisions doc, DN-D (precedence), DN-F (target selection),
//   DN-G (disabled), DN-H (sequencing, location), DN-I (Escape), DN-J
//   (preview), DN-K (leaving the window).
// - A: A1-A4 publish exactly A0's tree: no drag/drop action or attribute.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ApplicationServices

setvbuf(stdout, nil, _IOLBF, 0)

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String { defer { lines = [] }; return lines.isEmpty ? "-" : lines.joined(separator: ",") }
}
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
@MainActor func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - fake dragging info (group R)

final class FakeDrag: NSObject, NSDraggingInfo {
    let window: NSWindow
    var location: NSPoint
    let pb: NSPasteboard
    var mask: NSDragOperation = .every
    init(window: NSWindow, location: NSPoint, pb: NSPasteboard) { self.window = window; self.location = location; self.pb = pb }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { mask }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pb }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 7 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        Log.add("enumerate")
    }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

nonisolated(unsafe) var pasteboardCounter = 0
func pasteboard(_ fill: (NSPasteboard) -> Void) -> NSPasteboard {
    pasteboardCounter += 1
    let pb = NSPasteboard(name: NSPasteboard.Name("metalui-dnd-probe-\(getpid())-\(pasteboardCounter)"))
    pb.clearContents()
    fill(pb)
    return pb
}
let pbString = { pasteboard { _ = $0.writeObjects(["hello" as NSString]) } }
let pbTwoStrings = { pasteboard { _ = $0.writeObjects(["one" as NSString, "two" as NSString]) } }
let pbFileURL = { pasteboard { _ = $0.writeObjects([NSURL(fileURLWithPath: "/tmp/metalui-probe.txt")]) } }
let pbWebURL = { pasteboard { _ = $0.writeObjects([NSURL(string: "https://example.com/a")!]) } }
let pbURLString = { pasteboard { _ = $0.writeObjects(["https://example.com/s" as NSString]) } }

@MainActor func makeWindow<V: View>(_ view: V, width: CGFloat = 200, height: CGFloat = 200,
                                    origin: CGPoint = CGPoint(x: 200, y: 200)) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.level = .floating
    w.makeKeyAndOrderFront(nil)
    w.contentView!.layoutSubtreeIfNeeded()
    spin()
    return w
}

@MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor func registered(_ w: NSWindow) -> String {
    allViews(w.contentView!).filter { !$0.registeredDraggedTypes.isEmpty }
        .map { "\(type(of: $0))".components(separatedBy: "<").first! + ":" + $0.registeredDraggedTypes.map(\.rawValue).sorted().joined(separator: "|") }
        .joined(separator: " ; ")
}
@MainActor func destinationView(_ w: NSWindow) -> NSView {
    allViews(w.contentView!).first { !$0.registeredDraggedTypes.isEmpty } ?? w.contentView!
}
func op(_ o: NSDragOperation) -> String {
    if o.isEmpty { return "none" }
    var s: [String] = []
    if o.contains(.copy) { s.append("copy") }
    if o.contains(.link) { s.append("link") }
    if o.contains(.generic) { s.append("generic") }
    if o.contains(.move) { s.append("move") }
    return s.joined(separator: "+")
}

/// A scripted drag over `w` through the fake info. Steps: e=entered, u=updated,
/// x=exited, p=prepare+perform+conclude. Each step logs its return then the
/// handlers' log since the previous step.
@MainActor func script(_ w: NSWindow, _ pb: NSPasteboard, _ steps: [(Character, CGPoint)], mask: NSDragOperation = .every) -> String {
    let dest = destinationView(w)
    let h = w.contentView!.bounds.height
    let info = FakeDrag(window: w, location: .zero, pb: pb)
    info.mask = mask
    var out: [String] = []
    _ = Log.take()
    for (s, p) in steps {
        info.location = NSPoint(x: p.x, y: h - p.y)
        switch s {
        case "e": out.append("e=\(op(dest.draggingEntered(info)))")
        case "u": out.append("u=\(op(dest.draggingUpdated(info)))")
        case "x": dest.draggingExited(info); out.append("x")
        case "p":
            let prep = dest.prepareForDragOperation(info)
            let perf = dest.performDragOperation(info)
            dest.concludeDragOperation(info)
            out.append("prep=\(prep) perf=\(perf)")
        case "d": dest.draggingEnded(info); out.append("end")
        default: break
        }
        spin(0.25)
        let l = Log.take()
        if l != "-" { out.append("[\(l)]") }
    }
    return out.joined(separator: " ")
}

@MainActor func armR<V: View>(_ label: String, _ view: V, _ pb: NSPasteboard, _ steps: [(Character, CGPoint)],
                              mask: NSDragOperation = .every) {
    let w = makeWindow(view)
    print("  \(label): \(script(w, pb, steps, mask: mask))")
    w.orderOut(nil)
}

let C = CGPoint(x: 100, y: 100)

func dest<T: Transferable>(_ name: String, _ t: T.Type, ret: Bool = true) -> some View {
    Color.blue.dropDestination(for: t) { items, loc in
        Log.add("\(name):\(items.map { "\($0)" }) at (\(Int(loc.x)),\(Int(loc.y)))"); return ret
    } isTargeted: { Log.add("\(name)T=\($0)") }
}

@MainActor func groupR() {
    print("--- R: drop sequencing through a fake NSDraggingInfo (200x200 window, centre (100,100), top-left points)")
    let w0 = makeWindow(Color.blue)
    print("  R0a registered dragged types, plain Color (control): \(registered(w0).isEmpty ? "none" : registered(w0))"); w0.orderOut(nil)
    let w1 = makeWindow(dest("d", String.self))
    print("  R0b registered, dropDestination(for: String.self): \(registered(w1))"); w1.orderOut(nil)
    let w2 = makeWindow(dest("d", URL.self))
    print("  R0c registered, dropDestination(for: URL.self): \(registered(w2))"); w2.orderOut(nil)
    let w3 = makeWindow(dest("d", Data.self))
    print("  R0d registered, dropDestination(for: Data.self): \(registered(w3))"); w3.orderOut(nil)
    let w4 = makeWindow(Color.blue.onDrop(of: [.plainText], isTargeted: nil) { _ in true })
    print("  R0e registered, onDrop(of: [.plainText]): \(registered(w4))"); w4.orderOut(nil)
    let w5 = makeWindow(Text("s").draggable("x"))
    print("  R0f registered, draggable only: \(registered(w5).isEmpty ? "none" : registered(w5))"); w5.orderOut(nil)

    armR("R1 String dest, String drop: enter, update, update, exit", dest("d", String.self), pbString(),
         [("e", C), ("u", C), ("u", CGPoint(x: 110, y: 100)), ("x", C)])
    armR("R1b String dest, String drop: enter, update, perform", dest("d", String.self), pbString(),
         [("e", C), ("u", C), ("p", CGPoint(x: 30, y: 40))])
    armR("R1c String dest, String drop: perform then draggingEnded", dest("d", String.self), pbString(),
         [("e", C), ("p", C), ("d", C)])
    armR("R2 location space: 100x100 dest centred, drop at window (60,70)",
         dest("d", String.self).frame(width: 100, height: 100), pbString(),
         [("e", CGPoint(x: 60, y: 70)), ("p", CGPoint(x: 60, y: 70))])
    armR("R2b 100x100 dest centred: enter OUTSIDE it (20,20), update inside, update outside",
         dest("d", String.self).frame(width: 100, height: 100), pbString(),
         [("e", CGPoint(x: 20, y: 20)), ("u", C), ("u", CGPoint(x: 20, y: 20)), ("p", CGPoint(x: 20, y: 20))])
    armR("R3 String dest, file-URL drop", dest("d", String.self), pbFileURL(), [("e", C), ("p", C)])
    armR("R3b String dest, web-URL drop", dest("d", String.self), pbWebURL(), [("e", C), ("p", C)])
    armR("R3c URL dest, String 'https://example.com/s' drop", dest("d", URL.self), pbURLString(), [("e", C), ("p", C)])
    armR("R3d URL dest, file-URL drop", dest("d", URL.self), pbFileURL(), [("e", C), ("p", C)])
    armR("R3e URL dest, web-URL drop", dest("d", URL.self), pbWebURL(), [("e", C), ("p", C)])
    armR("R3f String dest, two strings", dest("d", String.self), pbTwoStrings(), [("e", C), ("p", C)])
    armR("R3g Data dest, String drop", dest("d", Data.self), pbString(), [("e", C), ("p", C)])
    armR("R4 action returns false", dest("d", String.self, ret: false), pbString(), [("e", C), ("p", C)])
    armR("R5 dest .disabled(true)", dest("d", String.self).disabled(true), pbString(), [("e", C), ("u", C), ("p", C)])
    armR("R5b dest inside .disabled(true) VStack", VStack { dest("d", String.self) }.disabled(true), pbString(), [("e", C), ("p", C)])
    armR("R5c dest .allowsHitTesting(false)", dest("d", String.self).allowsHitTesting(false), pbString(), [("e", C), ("p", C)])
    armR("R5d dest .hidden()", dest("d", String.self).hidden(), pbString(), [("e", C), ("p", C)])
    armR("R5e dest .opacity(0)", dest("d", String.self).opacity(0), pbString(), [("e", C), ("p", C)])
    let nested = ZStack { dest("outer", String.self); dest("inner", String.self).frame(width: 80, height: 80) }
    armR("R6 nested String/String: drop on inner", nested, pbString(), [("e", C), ("p", C)])
    armR("R6b nested String/String: drop outside inner", nested, pbString(), [("e", CGPoint(x: 20, y: 20)), ("p", CGPoint(x: 20, y: 20))])
    armR("R6c nested String/String: enter outer, move into inner, move out, drop outer", nested, pbString(),
         [("e", CGPoint(x: 20, y: 20)), ("u", C), ("u", CGPoint(x: 20, y: 20)), ("p", CGPoint(x: 20, y: 20))])
    let mixed = ZStack { dest("outer", String.self); dest("inner", URL.self).frame(width: 80, height: 80) }
    armR("R6d outer String, inner URL: String drop on inner", mixed, pbString(), [("e", C), ("p", C)])
    let modifierNested = dest("outer", String.self).padding(0).dropDestination(for: String.self) { i, _ in Log.add("chained:\(i)"); return true } isTargeted: { Log.add("chainedT=\($0)") }
    armR("R6e two dropDestinations chained on one view", modifierNested, pbString(), [("e", C), ("p", C)])
    let covered = ZStack { dest("d", String.self); Color.red.frame(width: 80, height: 80) }
    armR("R7 dest covered by a plain Color: drop on the Color", covered, pbString(), [("e", C), ("p", C)])
    let coveredTap = ZStack { dest("d", String.self); Color.red.frame(width: 80, height: 80).onTapGesture { Log.add("tap") } }
    armR("R7b dest covered by a tappable Color: drop on it", coveredTap, pbString(), [("e", C), ("p", C)])
    let coveredOff = ZStack { dest("d", String.self); Color.red.frame(width: 80, height: 80).allowsHitTesting(false) }
    armR("R7c dest covered by a non-hit-testable Color", coveredOff, pbString(), [("e", C), ("p", C)])
    let coveredButton = ZStack { dest("d", String.self); Button("B") { Log.add("button") }.frame(width: 80, height: 80) }
    armR("R7d dest covered by a Button: drop on it", coveredButton, pbString(), [("e", C), ("p", C)])
    let siblings = HStack(spacing: 0) { dest("A", String.self); dest("B", String.self) }
    armR("R8 sibling A then B: enter A, move to B, drop B", siblings, pbString(),
         [("e", CGPoint(x: 50, y: 100)), ("u", CGPoint(x: 150, y: 100)), ("p", CGPoint(x: 150, y: 100))])
    armR("R9 onDrop(of: [.plainText]) String drop", Color.blue.onDrop(of: [.plainText], isTargeted: nil) { providers, loc in
        Log.add("onDrop:\(providers.count) at (\(Int(loc.x)),\(Int(loc.y)))"); return true }, pbString(), [("e", C), ("p", C)])
    armR("R10 drop from a source with no copy in its mask (move only)", dest("d", String.self), pbString(), [("e", C), ("p", C)], mask: .move)
}

// MARK: - T: Transferable

final class Done: @unchecked Sendable { var flag = false; var lines: [String] = [] }

func groupT(_ d: Done) async {
    func ids(_ t: [UTType]) -> String { t.map(\.identifier).joined(separator: ",") }
    d.lines.append("--- T: Transferable (CoreTransferable, headless)")
    d.lines.append("  T1 String exported: \(ids(String.exportedContentTypes())) imported: \(ids(String.importedContentTypes()))")
    d.lines.append("  T2 URL exported: \(ids(URL.exportedContentTypes())) imported: \(ids(URL.importedContentTypes()))")
    d.lines.append("  T3 Data exported: \(ids(Data.exportedContentTypes())) imported: \(ids(Data.importedContentTypes()))")
    d.lines.append("  T3b AttributedString exported: \(ids(AttributedString.exportedContentTypes()))")
    let web = URL(string: "https://example.com/a")!, file = URL(fileURLWithPath: "/tmp/metalui-probe.txt")
    d.lines.append("  T4 web URL instance exported: \(ids(web.exportedContentTypes())); file URL instance: \(ids(file.exportedContentTypes()))")
    func show(_ data: Data?) -> String { data.map { String(decoding: $0, as: UTF8.self).debugDescription + " (\($0.count) bytes)" } ?? "throws" }
    d.lines.append("  T5 \"héllo\" exported as utf8PlainText: \(show(try? await "héllo".exported(as: .utf8PlainText)))")
    d.lines.append("  T5b \"héllo\" exported as plainText: \(show(try? await "héllo".exported(as: .plainText)))")
    d.lines.append("  T5c \"héllo\" exported as nil: \(show(try? await "héllo".exported(as: nil)))")
    d.lines.append("  T6 web URL exported as url: \(show(try? await web.exported(as: .url)))")
    d.lines.append("  T6b file URL exported as fileURL: \(show(try? await file.exported(as: .fileURL)))")
    d.lines.append("  T6c web URL exported as plainText: \(show(try? await web.exported(as: .plainText)))")
    d.lines.append("  T7 String imported from utf8 'x': \(str(try? await String(importing: Data("x".utf8), contentType: .utf8PlainText)))")
    d.lines.append("  T7b String imported from url data: \(str(try? await String(importing: Data("https://e.com".utf8), contentType: .url)))")
    d.lines.append("  T7c URL imported from plainText 'https://e.com': \(str(try? await URL(importing: Data("https://e.com".utf8), contentType: .plainText)))")
    d.lines.append("  T7d URL imported from url data: \(str(try? await URL(importing: Data("https://e.com".utf8), contentType: .url)))")
    d.lines.append("  T7e Data imported from png content type: \(str(try? await Data(importing: Data([1, 2]), contentType: .png)))")
    d.flag = true
}

// MARK: - A: accessibility

func kv(_ o: NSObject, _ key: String) -> Any? {
    let isKey = "is" + key.prefix(1).uppercased() + key.dropFirst()
    guard o.responds(to: Selector(key)) || o.responds(to: Selector(isKey)) else { return nil }
    return o.value(forKey: key)
}
@MainActor func kids(_ o: NSObject) -> [NSObject] { ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject } }
@MainActor func line(_ o: NSObject) -> String {
    var s = "\(type(of: o))".components(separatedBy: "<").first!
    s += " role=\(str(kv(o, "accessibilityRole"))) label=\(str(kv(o, "accessibilityLabel"))) value=\(str(kv(o, "accessibilityValue")))"
    let custom = ((kv(o, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]) ?? []).map(\.name)
    if !custom.isEmpty { s += " custom=\(custom)" }
    let sels = ["accessibilityPerformPress", "accessibilityPerformShowMenu", "accessibilityPerformPick"]
        .filter { o.responds(to: Selector($0)) }
    s += " performs=\(sels.map { $0.replacingOccurrences(of: "accessibilityPerform", with: "") })"
    let names = (o.accessibilityAttributeNames()).map(\.rawValue).sorted()
    s += " attrs=\(names.count)"
    let dragNames = names.filter { $0.localizedCaseInsensitiveContains("drag") || $0.localizedCaseInsensitiveContains("drop") }
    if !dragNames.isEmpty { s += " dragAttrs=\(dragNames)" }
    let actions = (o.accessibilityActionNames()).map(\.rawValue).sorted()
    s += " actionNames=\(actions)"
    s += " kids=\(kids(o).count)"
    return s
}
@MainActor func describe(_ o: NSObject, _ d: Int = 1) {
    print(String(repeating: "  ", count: d) + line(o))
    if d < 4 { for k in kids(o).prefix(5) { describe(k, d + 1) } }
}
@MainActor func groupA() {
    print("--- A: what NSHostingView publishes to accessibility (AXEnhancedUserInterface on)")
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.5)
    func show<V: View>(_ name: String, _ v: V) {
        let w = makeWindow(v); spin(0.3)
        print("  \(name)"); describe(w.contentView!); w.orderOut(nil)
    }
    show("A0 control: VStack { Text src; Text dst }", VStack { Text("src"); Text("dst") })
    show("A1 Text src .draggable; Text dst .dropDestination", VStack {
        Text("src").draggable("x")
        Text("dst").dropDestination(for: String.self) { _, _ in true } isTargeted: { _ in }
    })
    show("A2 Button .draggable", Button("btn") {}.draggable("x"))
    show("A3 Color .dropDestination labelled", Color.blue.dropDestination(for: String.self) { _, _ in true } isTargeted: { _ in }.accessibilityLabel("well"))
    show("A4 Text .onDrag / .onDrop", VStack {
        Text("src").onDrag { NSItemProvider(object: "x" as NSString) }
        Text("dst").onDrop(of: [.plainText], isTargeted: nil) { _ in true }
    })
}

// MARK: - P: real pointer (CGEvent), gated

final class Script: @unchecked Sendable { var done = false }
nonisolated(unsafe) var captureLog: [String] = []
/// The share of orange, blue and green pixels, and the mean colour, in a 40x40-point screen square centred on `c` (CG coordinates).
func sampleScreen(around c: CGPoint) -> String {
    let file = NSTemporaryDirectory() + "metalui-dnd-capture-\(getpid()).png"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-R", "\(Int(c.x) - 20),\(Int(c.y) - 20),40,40", file]
    do { try task.run() } catch { return "nocapture" }
    task.waitUntilExit()
    guard let data = FileManager.default.contents(atPath: file), let rep = NSBitmapImageRep(data: data) else { return "nocapture" }
    try? FileManager.default.removeItem(atPath: file)
    var o = 0, b = 0, g = 0, n = 0, r = 0, gg = 0, bb = 0
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
        guard let col = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let R = Int(col.redComponent * 255), G = Int(col.greenComponent * 255), B = Int(col.blueComponent * 255)
        n += 1; r += R; gg += G; bb += B
        if R > 200 && G > 100 && G < 190 && B < 80 { o += 1 }
        if B > 180 && R < 80 && G < 140 { b += 1 }
        if G > 150 && R < 120 && B < 120 { g += 1 }
    } }
    guard n > 0 else { return "empty" }
    return "orange \(o * 100 / n)% blue \(b * 100 / n)% green \(g * 100 / n)% mean (\(r / n),\(gg / n),\(bb / n))"
}
enum Step { case move(CGPoint), down(CGPoint), drag(CGPoint), up(CGPoint), wait(Double), key(UInt16), capture(String, CGPoint) }

@MainActor func toScreen(_ w: NSWindow, _ p: CGPoint) -> CGPoint {
    let h = w.contentView!.bounds.height
    let s = w.convertPoint(toScreen: NSPoint(x: p.x, y: h - p.y))
    return CGPoint(x: s.x, y: NSScreen.screens[0].frame.height - s.y)
}
func post(_ steps: [Step], _ script: Script) {
    Thread.detachNewThread {
        for step in steps {
            switch step {
            case .move(let p): CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            case .down(let p): CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            case .drag(let p): CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            case .up(let p): CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            case .wait(let s): Thread.sleep(forTimeInterval: s)
            case .capture(let label, let c): captureLog.append("\(label)=\(sampleScreen(around: c))")
            case .key(let k):
                CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: true)?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.03)
                CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: false)?.post(tap: .cghidEventTap)
            }
            if case .wait = step {} else { Thread.sleep(forTimeInterval: 0.016) }
        }
        Thread.sleep(forTimeInterval: 0.5)
        script.done = true
    }
}
@MainActor func pump(_ script: Script) {
    let end = Date().addingTimeInterval(15)
    while !script.done && Date() < end {
        if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) {
            NSApp.sendEvent(e)
        }
    }
}
/// A press at `from`, `n` dragged moves to `to`, a hold with small wiggles, a release at `to`.
@MainActor func dragSteps(_ w: NSWindow, from: CGPoint, to: CGPoint, n: Int = 20, escapeAtEnd: Bool = false) -> [Step] {
    let a = toScreen(w, from), b = toScreen(w, to)
    var s: [Step] = [.move(a), .wait(0.15), .down(a), .wait(0.12)]
    for i in 1...n {
        let f = CGFloat(i) / CGFloat(n)
        s.append(.drag(CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)))
    }
    for dx in [1.0, -1.0, 1.0, 0.0] { s.append(.drag(CGPoint(x: b.x + dx, y: b.y))); s.append(.wait(0.05)) }
    if escapeAtEnd { s.append(.key(53)); s.append(.wait(0.3)); s.append(.drag(b)) }
    s.append(.wait(0.1)); s.append(.up(b))
    return s
}
@MainActor func clickSteps(_ w: NSWindow, at p: CGPoint) -> [Step] {
    let a = toScreen(w, p)
    return [.move(a), .wait(0.15), .down(a), .wait(0.06), .up(a), .wait(0.4)]
}
@MainActor func armP<V: View>(_ label: String, _ view: V, width: CGFloat = 400, _ steps: (NSWindow) -> [Step]) {
    if let only = ProcessInfo.processInfo.environment["METALUI_DND_ONLY"],
       !only.split(separator: ",").contains(where: { label.hasPrefix($0 + " ") }) { return }
    _ = Log.take()
    let w = makeWindow(view, width: width, height: 200, origin: CGPoint(x: 300, y: 300))
    NSApp.activate(ignoringOtherApps: true)
    spin(0.3)
    let script = Script()
    post(steps(w), script)
    pump(script)
    spin(0.3)
    let caps = captureLog.isEmpty ? "" : " {" + captureLog.joined(separator: "; ") + "}"
    captureLog = []
    print("  \(label): \(Log.take())\(caps)")
    w.orderOut(nil)
}
let S = CGPoint(x: 100, y: 100), D = CGPoint(x: 300, y: 100)
func target() -> some View {
    Color.green.frame(width: 200, height: 200).dropDestination(for: String.self) { items, _ in
        Log.add("drop\(items)"); return true } isTargeted: { Log.add("T=\($0)") }
}
func pair<Src: View>(_ src: Src) -> some View {
    HStack(spacing: 0) { src.frame(width: 200, height: 200); target() }
}
struct SessionLog: ViewModifier {
    func body(content: Content) -> some View {
        content.onDragSessionUpdated { s in Log.add("phase=\(s.phase)") }
    }
}
struct ScrollProbe: View {
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<10) { i in
                        Color(white: Double(i) / 10).frame(height: 60).overlay(Text("\(i)")).draggable("row\(i)")
                    }
                }
            }
            .onScrollGeometryChange(for: Int.self) { Int($0.contentOffset.y) } action: { _, n in Log.add("off=\(n)") }
            .frame(width: 200, height: 200)
            target()
        }
    }
}
struct ListProbe: View {
    @State var sel: Int? = nil
    var body: some View {
        HStack(spacing: 0) {
            List(0..<5, id: \.self, selection: $sel) { i in Text("row \(i)").draggable("row\(i)") }
                .frame(width: 200, height: 200)
                .onChange(of: sel) { _, n in Log.add("sel=\(str(n))") }
            target()
        }
    }
}
@MainActor func groupP() {
    print("--- P: real pointer drags (CGEvent at the HID tap; 400x200 window, source centre (100,100), target the right half)")
    armP("P0 control: Color.draggable(\"p0\") dragged onto target", pair(Color.orange.draggable("p0"))) { dragSteps($0, from: S, to: D) }
    armP("P0b control: plain Color (no draggable) dragged onto target", pair(Color.orange)) { dragSteps($0, from: S, to: D) }
    armP("P1a draggable + onTapGesture: click", pair(Color.orange.draggable("p1").onTapGesture { Log.add("tap") })) { clickSteps($0, at: S) }
    armP("P1b draggable + onTapGesture: drag", pair(Color.orange.draggable("p1").onTapGesture { Log.add("tap") })) { dragSteps($0, from: S, to: D) }
    armP("P1c onTapGesture then draggable (other order): drag", pair(Color.orange.onTapGesture { Log.add("tap") }.draggable("p1"))) { dragSteps($0, from: S, to: D) }
    let withDrag = Color.orange.draggable("p2").gesture(DragGesture().onChanged { _ in Log.add("chg") }.onEnded { _ in Log.add("dEnd") })
    armP("P2a draggable then .gesture(DragGesture): drag", pair(withDrag)) { dragSteps($0, from: S, to: D) }
    let dragFirst = Color.orange.gesture(DragGesture().onChanged { _ in Log.add("chg") }.onEnded { _ in Log.add("dEnd") }).draggable("p2")
    armP("P2b .gesture(DragGesture) then draggable: drag", pair(dragFirst)) { dragSteps($0, from: S, to: D) }
    let parentDrag = pair(Color.orange.draggable("p2")).gesture(DragGesture().onChanged { _ in Log.add("chg") }.onEnded { _ in Log.add("dEnd") })
    armP("P2c draggable child, parent .gesture(DragGesture): drag", parentDrag) { dragSteps($0, from: S, to: D) }
    let hp = Color.orange.draggable("p2").highPriorityGesture(DragGesture().onChanged { _ in Log.add("chg") }.onEnded { _ in Log.add("dEnd") })
    armP("P2d draggable + highPriorityGesture(DragGesture): drag", pair(hp)) { dragSteps($0, from: S, to: D) }
    let sim = Color.orange.draggable("p2").simultaneousGesture(DragGesture().onChanged { _ in Log.add("chg") }.onEnded { _ in Log.add("dEnd") })
    armP("P2e draggable + simultaneousGesture(DragGesture): drag", pair(sim)) { dragSteps($0, from: S, to: D) }
    let lp = Color.orange.draggable("p2").onLongPressGesture { Log.add("long") }
    armP("P2f draggable + onLongPressGesture: drag", pair(lp)) { dragSteps($0, from: S, to: D) }
    let button = Button { Log.add("button") } label: { Color.orange }.buttonStyle(.plain).draggable("p3")
    armP("P3a plain Button.draggable: click", pair(button)) { clickSteps($0, at: S) }
    armP("P3b plain Button.draggable: drag", pair(button)) { dragSteps($0, from: S, to: D) }
    let bordered = Button("Go") { Log.add("button") }.draggable("p3")
    armP("P3c bordered Button(\"Go\").draggable: drag from its centre", pair(bordered)) { dragSteps($0, from: S, to: D) }
    armP("P4a List(selection:) draggable rows: click row 1", ListProbe()) { clickSteps($0, at: CGPoint(x: 60, y: 50)) }
    armP("P4b List(selection:) draggable rows: drag row 1 to target", ListProbe()) { dragSteps($0, from: CGPoint(x: 60, y: 50), to: D) }
    armP("P5a ScrollView of draggable rows: vertical drag inside (row 1 down 100)", ScrollProbe()) { dragSteps($0, from: CGPoint(x: 100, y: 90), to: CGPoint(x: 100, y: 190)) }
    armP("P5b ScrollView of draggable rows: drag row 1 to target", ScrollProbe()) { dragSteps($0, from: CGPoint(x: 100, y: 90), to: D) }
    for d in [2.0, 3.0, 4.0, 5.0, 6.0, 8.0] {
        armP("P6 session phases, drag \(Int(d))pt and release", pair(Color.orange.draggable("p6").modifier(SessionLog()))) { w in
            dragSteps(w, from: S, to: CGPoint(x: S.x + d, y: S.y), n: 4)
        }
    }
    armP("P6b session phases, drag onto target", pair(Color.orange.draggable("p6").modifier(SessionLog()))) { dragSteps($0, from: S, to: D) }
    armP("P6c session phases, drag out of the window (300pt below)", pair(Color.orange.draggable("p6").modifier(SessionLog()))) {
        dragSteps($0, from: S, to: CGPoint(x: 100, y: 500))
    }
    armP("P7 Escape held over target, then release", pair(Color.orange.draggable("p7").modifier(SessionLog()))) {
        dragSteps($0, from: S, to: D, escapeAtEnd: true)
    }
    let disabledTarget = HStack(spacing: 0) { Color.orange.draggable("p8").frame(width: 200, height: 200); target().disabled(true) }
    armP("P8 target .disabled(true)", disabledTarget) { dragSteps($0, from: S, to: D) }
    armP("P9 source .disabled(true) (after draggable)", pair(Color.orange.draggable("p9").disabled(true))) { dragSteps($0, from: S, to: D) }
    armP("P10 enter target, leave, re-enter, drop", pair(Color.orange.draggable("p10"))) { w in
        var s = dragSteps(w, from: S, to: D)
        let up = s.removeLast()
        let b = toScreen(w, D), out = toScreen(w, CGPoint(x: 150, y: 100))
        s += [.drag(out), .wait(0.1), .drag(CGPoint(x: out.x - 1, y: out.y)), .wait(0.1), .drag(b), .wait(0.1),
              .drag(CGPoint(x: b.x + 1, y: b.y)), .wait(0.1), up]
        return s
    }
    armP("P11 drop back onto the source itself (source is also a destination)", HStack(spacing: 0) {
        Color.orange.draggable("p11").dropDestination(for: String.self) { i, _ in Log.add("self\(i)"); return true }
            .frame(width: 200, height: 200)
        target()
    }) { w in dragSteps(w, from: S, to: CGPoint(x: 150, y: 150)) }

    // --- revision 2: spatial questions the fake NSDraggingInfo cannot answer (group R reads every
    // destination at the window's whole extent), and the default preview.
    func tdest(_ name: String) -> some View {
        Color.green.dropDestination(for: String.self) { items, loc in
            Log.add("\(name)\(items) at (\(Int(loc.x)),\(Int(loc.y)))"); return true } isTargeted: { Log.add("\(name)T=\($0)") }
    }
    func src() -> some View { Color.orange.draggable("s").frame(width: 200, height: 200) }
    armP("P12a location space: drop at window (330,140) on a right-half target", HStack(spacing: 0) { src(); tdest("d").frame(width: 200, height: 200) }) {
        dragSteps($0, from: S, to: CGPoint(x: 330, y: 140)) }
    let nested = HStack(spacing: 0) { src(); ZStack { tdest("outer"); tdest("inner").frame(width: 80, height: 80) }.frame(width: 200, height: 200) }
    armP("P13a nested String/String: drop on inner", nested) { dragSteps($0, from: S, to: D) }
    armP("P13b nested String/String: drop on outer outside inner", nested) { dragSteps($0, from: S, to: CGPoint(x: 220, y: 20)) }
    let mixed = HStack(spacing: 0) { src(); ZStack { tdest("outer"); Color.blue.frame(width: 80, height: 80).dropDestination(for: URL.self) { i, _ in Log.add("innerURL\(i)"); return true } isTargeted: { Log.add("innerURLT=\($0)") } }.frame(width: 200, height: 200) }
    armP("P13c outer String, inner URL: String dropped on inner", mixed) { dragSteps($0, from: S, to: D) }
    let sibs = HStack(spacing: 0) { src(); HStack(spacing: 0) { tdest("A"); tdest("B") }.frame(width: 200, height: 200) }
    armP("P14 siblings: enter A (250,100), move to B (350,100), drop", sibs) { w in
        var s = dragSteps(w, from: S, to: CGPoint(x: 250, y: 100)); let up = s.removeLast()
        let b = toScreen(w, CGPoint(x: 350, y: 100))
        s += [.drag(CGPoint(x: b.x - 20, y: b.y)), .wait(0.1), .drag(b), .wait(0.1), .drag(CGPoint(x: b.x + 1, y: b.y)), .wait(0.1), .up(b)]
        return s }
    let coverPlain = HStack(spacing: 0) { src(); ZStack { tdest("d"); Color.red.frame(width: 80, height: 80) }.frame(width: 200, height: 200) }
    armP("P15a target covered by a plain Color: drop on the Color", coverPlain) { dragSteps($0, from: S, to: D) }
    let coverTap = HStack(spacing: 0) { src(); ZStack { tdest("d"); Color.red.frame(width: 80, height: 80).onTapGesture { Log.add("tap") } }.frame(width: 200, height: 200) }
    armP("P15b target covered by a tappable Color: drop on it", coverTap) { dragSteps($0, from: S, to: D) }
    let coverOff = HStack(spacing: 0) { src(); ZStack { tdest("d"); Color.red.frame(width: 80, height: 80).allowsHitTesting(false) }.frame(width: 200, height: 200) }
    armP("P15c target covered by a non-hit-testable Color: drop on it", coverOff) { dragSteps($0, from: S, to: D) }
    let coverButton = HStack(spacing: 0) { src(); ZStack { tdest("d"); Button("B") { Log.add("button") }.frame(width: 80, height: 80) }.frame(width: 200, height: 200) }
    armP("P15d target covered by a Button: drop on it", coverButton) { dragSteps($0, from: S, to: D) }
    let offTarget = HStack(spacing: 0) { src(); tdest("d").allowsHitTesting(false).frame(width: 200, height: 200) }
    armP("P15e target .allowsHitTesting(false)", offTarget) { dragSteps($0, from: S, to: D) }
    let urlSrc = HStack(spacing: 0) { Color.orange.draggable(URL(string: "https://example.com")!).frame(width: 200, height: 200); tdest("d").frame(width: 200, height: 200) }
    armP("P16 URL payload onto a String target", urlSrc) { dragSteps($0, from: S, to: D) }
    let dataTarget = HStack(spacing: 0) { src(); Color.green.dropDestination(for: Data.self) { i, _ in Log.add("data\(i)"); return true } isTargeted: { Log.add("dataT=\($0)") }.frame(width: 200, height: 200) }
    armP("P16b String payload onto a Data target", dataTarget) { dragSteps($0, from: S, to: D) }
    for d in [1.0, 2.0, 3.0, 4.0] {
        armP("P17 exact move of \(Int(d))pt, no wiggle, release (draggable + onTapGesture)",
             pair(Color.orange.draggable("s").onTapGesture { Log.add("tap") }.modifier(SessionLog()))) { w in
            let a = toScreen(w, S)
            return [.move(a), .wait(0.15), .down(a), .wait(0.12), .drag(CGPoint(x: a.x + d, y: a.y)), .wait(0.3), .up(CGPoint(x: a.x + d, y: a.y)), .wait(0.4)]
        }
    }
    armP("P18 default preview: capture around the pointer mid-drag over empty canvas, and the source", HStack(spacing: 0) {
        Color.orange.draggable("s").frame(width: 100, height: 100).frame(width: 200, height: 200); Color.white.frame(width: 200, height: 200) }) { w in
        var s = dragSteps(w, from: S, to: CGPoint(x: 300, y: 100)); let up = s.removeLast()
        s += [.wait(0.3), .capture("atPointer", toScreen(w, CGPoint(x: 300, y: 100))), .capture("source", toScreen(w, S)), up]
        return s }
    armP("P18b preview: closure (a 60x60 blue square): capture mid-drag", HStack(spacing: 0) {
        Color.orange.draggable("s") { Color.blue.frame(width: 60, height: 60) }.frame(width: 100, height: 100).frame(width: 200, height: 200); Color.white.frame(width: 200, height: 200) }) { w in
        var s = dragSteps(w, from: S, to: CGPoint(x: 300, y: 100)); let up = s.removeLast()
        s += [.wait(0.3), .capture("atPointer", toScreen(w, CGPoint(x: 300, y: 100))), .capture("source", toScreen(w, S)), up]
        return s }
    armP("P18c preview control: no drag, capture the same points after a click", HStack(spacing: 0) {
        Color.orange.frame(width: 100, height: 100).frame(width: 200, height: 200); Color.white.frame(width: 200, height: 200) }) { w in
        clickSteps(w, at: S) + [.capture("atPointer", toScreen(w, CGPoint(x: 300, y: 100))), .capture("source", toScreen(w, S))] }
    armP("P19 isTargeted while hovering without moving after entry (hold 0.5s)", pair(Color.orange.draggable("s"))) { w in
        var s = dragSteps(w, from: S, to: D); let up = s.removeLast(); s += [.wait(0.5), up]; return s }
    armP("P17z a zero-distance dragged event, then release (draggable + onTapGesture)",
         pair(Color.orange.draggable("s").onTapGesture { Log.add("tap") }.modifier(SessionLog()))) { w in
        let a = toScreen(w, S)
        return [.move(a), .wait(0.15), .down(a), .wait(0.12), .drag(a), .wait(0.3), .up(a), .wait(0.4)]
    }
    armP("P20 TextField.draggable: drag from the field's text onto target", FieldProbe()) { dragSteps($0, from: CGPoint(x: 40, y: 100), to: D) }
    armP("P20b Slider.draggable: drag from the slider's centre onto target", SliderProbe()) { dragSteps($0, from: S, to: D) }
    func child<C: View>(_ c: C) -> some View { ZStack { Color.orange; c.frame(width: 100, height: 100) }.draggable("parent") }
    armP("P22a draggable parent, plain Button child: click the child", pair(child(Button { Log.add("button") } label: { Color.purple }.buttonStyle(.plain)))) { clickSteps($0, at: S) }
    armP("P22b draggable parent, plain Button child: drag from the child", pair(child(Button { Log.add("button") } label: { Color.purple }.buttonStyle(.plain)))) { dragSteps($0, from: S, to: D) }
    armP("P22c draggable parent, onTapGesture child: drag from the child", pair(child(Color.purple.onTapGesture { Log.add("tap") }))) { dragSteps($0, from: S, to: D) }
    armP("P22d draggable parent, DragGesture child: drag from the child", pair(child(Color.purple.gesture(DragGesture().onChanged { _ in Log.add("chg") }.onEnded { _ in Log.add("dEnd") })))) { dragSteps($0, from: S, to: D) }
    armP("P22e draggable parent, draggable child: drag from the child", pair(child(Color.purple.draggable("child")))) { dragSteps($0, from: S, to: D) }
    armP("P22f draggable parent, plain Color child: drag from the child", pair(child(Color.purple))) { dragSteps($0, from: S, to: D) }
    armP("P21 draggable + onTapGesture(count: 2): drag", pair(Color.orange.draggable("s").onTapGesture(count: 2) { Log.add("double") })) { dragSteps($0, from: S, to: D) }
}
struct FieldProbe: View {
    @State var text = "hello world"
    var body: some View {
        HStack(spacing: 0) {
            TextField("f", text: $text).draggable("field").frame(width: 200)
                .onChange(of: text) { _, n in Log.add("text=\(n)") }
            target()
        }
    }
}
struct SliderProbe: View {
    @State var v = 0.5
    var body: some View {
        HStack(spacing: 0) {
            Slider(value: $v).draggable("slider").frame(width: 200)
                .onChange(of: v) { _, n in Log.add("v=\((n * 100).rounded() / 100)") }
            target()
        }
    }
}


// MARK: - main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    app.activate(ignoringOtherApps: true)
    let done = Done()
    Task.detached { await groupT(done) }
    while !done.flag { spin(0.05) }
    done.lines.forEach { print($0) }
    groupR()
    groupA()
    if ProcessInfo.processInfo.environment["METALUI_DND_POINTER"] == "1" {
        let saved = NSEvent.mouseLocation
        groupP()
        CGWarpMouseCursorPosition(CGPoint(x: saved.x, y: NSScreen.screens[0].frame.height - saved.y))
    } else {
        print("--- P: skipped (set METALUI_DND_POINTER=1 with an unlocked screen and event-posting access)")
    }
}
exit(0)
