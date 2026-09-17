// SwiftUI probe: what an NSHostingView exposes through NSAccessibility, read
// in-process with no Accessibility permission. Evidence for the AB- rulings in
// docs/superpowers/2026-09-15-accessibility-bridge-decisions.md.
//
// HOW TO RUN (Apple's toolchain; swiftly's swift.org JIT cannot load SwiftUI,
// see docs/probes/swiftui-layout-protocol-contract.swift's header):
//
//   /usr/bin/swift docs/probes/swiftui-accessibility-bridge.swift 2>&1 \
//     | grep -v 'Connection\]\|ntents\|warning:\|deprecated\|^ *[0-9]* |\|^ *|\|note:\|WARNING: Application performed a reentrant'
//
// The filter strips the deprecation warnings the informal accessibility API
// produces (used only for the AppKit control), XPC noise, and one AppKit log
// line NSTableView prints while arm 14a's List builds (a reentrant-delegate
// warning from SwiftUI's own table, not from this file).
//
// HOW IT READS. SwiftUI's `AccessibilityNode` objects do not conform to
// `NSAccessibilityProtocol` as far as a Swift `as?` cast can see, and answer
// nil to the informal `accessibilityAttributeValue(_:)` API. They DO answer
// the modern selectors through KVC (`value(forKey: "accessibilityRole")`),
// which is what `kv` below does, and a typed IMP call for the perform methods.
// `responds(to:)` is not evidence: every NSObject subclass here answers yes.
//
// POSITIVE CONTROLS.
//   1. arm 0: an AppKit NSButton read by the same walker reports AXButton,
//      title "Native" — so a nil/unknown elsewhere is SwiftUI's answer, not a
//      broken walker.
//   2. arm 1 vs arm 2: the same hosted Text read before and after the process
//      sets AXEnhancedUserInterface on NSApp. Children 0 before, 1 after.
//   3. every perform arm prints its closure's side-effect counter, so "true"
//      is checked against a closure that actually ran.
//
// RECORDED 2026-09-15 by the accessibility-bridge design session, macOS 26.6.2
// (25G83), /usr/bin/swift = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0.
// Screen coordinates below are AppKit's: origin at the bottom-left of the
// main screen, so a 16pt Text at the top of a 300pt content rect whose origin
// is y = 100 reads y = 100 + 300 - 16 = 384. One run's filtered output,
// verbatim except that leading and trailing blank lines are dropped:
//
//   === 0 control: NSButton
//   NSButton role=AXUnknown sub=nil label=Native value=nil frame=(99.0, 99.0, 202.0, 102.0) kids=1 parent=NSWindow
//     NSButtonCell role=AXButton sub=nil label=Native value=nil frame=(99.0, 99.0, 202.0, 102.0) kids=0 parent=NSWindow
//   === 1 Text before any activation
//   children on ask: 0
//   children after a second ask and a spin: 0
//   === 2 the same Text after AXEnhancedUserInterface = true
//   children on ask: 1
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 384.0, 31.0, 16.0) kids=1 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Hello frame=(100.0, 384.0, 31.0, 16.0) kids=0 parent=NSHostingView
//   === 3 VStack { Text A; Text B }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 368.0, 9.0, 32.0) kids=2 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A frame=(100.0, 384.0, 9.0, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B frame=(100.25, 368.0, 8.5, 16.0) kids=0 parent=NSHostingView
//   === 4 ZStack { Text Under; Text Over }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 384.0, 38.0, 16.0) kids=2 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Over frame=(104.5, 384.0, 29.0, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Under frame=(100.25, 384.0, 37.5, 16.0) kids=0 parent=NSHostingView
//   === 5 Button("Go")
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 376.0, 42.0, 24.0) kids=1 parent=NSWindow
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil frame=(100.5, 376.0, 41.5, 24.0) kids=0 parent=NSHostingView
//   press -> true, closure ran 1 time(s)
//   === 6 Button { HStack { Text A; Text B } }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 376.0, 50.0, 24.0) kids=1 parent=NSWindow
//     AccessibilityNode role=AXButton sub=nil label=A, B value=nil frame=(100.5, 376.0, 49.5, 24.0) kids=0 parent=NSHostingView
//   === 7 Text("Tap").onTapGesture
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 384.0, 22.0, 16.0) kids=1 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Tap frame=(100.0, 384.0, 22.0, 16.0) kids=0 parent=NSHostingView
//   press -> false, closure ran 0 time(s)
//   === 8 Text("Tap").onTapGesture.accessibilityAddTraits(.isButton)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 384.0, 22.0, 16.0) kids=1 parent=NSWindow
//     AccessibilityNode role=AXButton sub=nil label=Tap value=nil frame=(100.0, 384.0, 22.0, 16.0) kids=0 parent=NSHostingView
//   press -> false, closure ran 0 time(s)
//   === 9 VStack { Text A; Text B }.onTapGesture
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 368.0, 9.0, 32.0) kids=2 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A frame=(100.0, 384.0, 9.0, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B frame=(100.25, 368.0, 8.5, 16.0) kids=0 parent=NSHostingView
//   === 10a Text("Hello").accessibilityLabel("Greeting")
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 384.0, 31.0, 16.0) kids=1 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Greeting frame=(100.0, 384.0, 31.0, 16.0) kids=0 parent=NSHostingView
//   === 10b Color.frame(20).accessibilityLabel("Swatch")
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 380.0, 20.0, 20.0) kids=1 parent=NSWindow
//     AccessibilityNode role=AXUnknown sub=nil label=Swatch value=nil frame=(100.0, 380.0, 20.0, 20.0) kids=0 parent=NSHostingView
//   === 10c Color.frame(20), nothing declared
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 380.0, 20.0, 20.0) kids=0 parent=NSWindow
//   === 11 Text("vol").accessibilityValue("5").accessibilityAdjustableAction
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 384.0, 18.0, 16.0) kids=1 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=vol value=5 frame=(100.0, 384.0, 18.0, 16.0) kids=0 parent=NSHostingView
//   increment -> true, decrement -> true, closure saw ["increment", "decrement"]
//   === 12 identity: VStack { if show { Text Conditional }; Text Count n; Text Trailing }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 352.0, 69.0, 48.0) kids=3 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Conditional frame=(100.0, 384.0, 69.0, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Count 0 frame=(110.25, 368.0, 48.5, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Trailing frame=(112.25, 352.0, 44.5, 16.0) kids=0 parent=NSHostingView
//   after n = 1: count 3; same objects by position: [true, true, true]
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 352.0, 69.0, 48.0) kids=3 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Conditional frame=(100.0, 384.0, 69.0, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Count 1 frame=(111.25, 368.0, 46.5, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Trailing frame=(112.25, 352.0, 44.5, 16.0) kids=0 parent=NSHostingView
//   after show = false: count 2; Count-node same object as before: true, Trailing same: true
//   removed node now reads: AccessibilityNode role=AXStaticText sub=nil label=nil value=Conditional frame=(100.0, 384.0, 69.0, 16.0) kids=0 parent=nil
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 368.0, 47.0, 32.0) kids=2 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Count 1 frame=(100.25, 384.0, 46.5, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Trailing frame=(101.25, 368.0, 44.5, 16.0) kids=0 parent=NSHostingView
//   after show = true again: first node same object as the original Conditional: false
//   === 13 focus: VStack { Text Other .focusable(); Text Focusable .focusable().focused($f) }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 368.0, 62.0, 32.0) kids=2 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Other frame=(113.75, 384.0, 34.5, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Focusable frame=(100.0, 368.0, 62.0, 16.0) kids=0 parent=NSHostingView
//   FocusState changes seen before any AX request: []
//   host accessibilityFocusedUIElement: AccessibilityNode role=AXStaticText sub=nil label=nil value=Other frame=(113.75, 384.0, 34.5, 16.0) kids=0 parent=NSHostingView
//   after setAccessibilityFocused(true) on the Focusable node: FocusState changes seen [true]
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 368.0, 62.0, 32.0) kids=2 parent=NSWindow
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Other frame=(113.75, 384.0, 34.5, 16.0) kids=0 parent=NSHostingView
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Focusable frame=(100.0, 368.0, 62.0, 16.0) kids=0 parent=NSHostingView
//   host accessibilityFocusedUIElement: AccessibilityNode role=AXStaticText sub=nil label=nil value=Focusable frame=(100.0, 368.0, 62.0, 16.0) kids=0 parent=NSHostingView
//   === 14a List(0..<500)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 100.0, 300.0, 200.0) kids=1 parent=NSWindow
//     ListCoreScrollView role=AXScrollArea sub=nil label=nil value=nil frame=(100.0, 100.0, 300.0, 200.0) kids=2 parent=NSHostingView
//       SwiftUIOutlineListView role=AXOutline sub=nil label=nil value=nil frame=(99.0, 99.0, 302.0, 202.0) kids=501 rows=500 parent=ListCoreScrollView
//       NSScroller role=AXScrollBar sub=nil label=nil value=0 frame=(382.0, 106.5, 19.0, 194.5) kids=5 parent=ListCoreScrollView
//   === 14b ScrollView { LazyVStack { ForEach(0..<500) } }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil frame=(100.0, 100.0, 300.0, 200.0) kids=1 parent=NSWindow
//     HostingScrollView role=AXScrollArea sub=nil label=nil value=nil frame=(100.0, 100.0, 300.0, 200.0) kids=2 parent=NSHostingView
//       AccessibilityLazyLayoutNode role=AXOpaqueProviderGroup sub=AXOpaqueProviderList label=nil value=nil frame=(227.25, -513.0, 45.5, 813.0) kids=25 parent=HostingScrollView
//         AccessibilityNode role=AXStaticText sub=nil label=nil value=Row 0 frame=(231.25, 284.0, 37.5, 16.0) kids=0 parent=AccessibilityLazyLayoutNode
//         AccessibilityNode role=AXStaticText sub=nil label=nil value=Row 1 frame=(232.25, 268.0, 35.5, 16.0) kids=0 parent=AccessibilityLazyLayoutNode
//       NSScroller role=AXScrollBar sub=nil label=nil value=0 frame=(382.0, 106.5, 19.0, 194.5) kids=5 parent=HostingScrollView
//         NSAccessibilityScrollerPart role=AXValueIndicator sub=nil label=nil value=0 frame=(391.0, 271.0, 6.0, 26.0) kids=0 parent=NSScroller
//         NSAccessibilityScrollerPart role=AXButton sub=AXIncrementArrow label=nil value=nil frame=(383.0, 300.0, 0.0, 0.0) kids=0 parent=NSScroller

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)

@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }

func kv(_ o: NSObject, _ key: String) -> Any? {
    guard o.responds(to: Selector(key)) else { return "<n/a>" }
    return o.value(forKey: key)
}

@MainActor func line(_ o: NSObject) -> String {
    let kids = (kv(o, "accessibilityChildren") as? [Any]) ?? []
    var extras = ""
    if let rows = kv(o, "accessibilityRows") as? [Any] { extras += " rows=\(rows.count)" }
    if let f = kv(o, "accessibilityFocused") as? Bool, f { extras += " FOCUSED" }
    let frame = (kv(o, "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
    let parent = kv(o, "accessibilityParent").map { "\(type(of: $0))" } ?? "nil"
    let typeName = "\(type(of: o))".components(separatedBy: "<").first!
    return "\(typeName) role=\(str(kv(o, "accessibilityRole"))) sub=\(str(kv(o, "accessibilitySubrole"))) label=\(str(kv(o, "accessibilityLabel"))) value=\(str(kv(o, "accessibilityValue"))) frame=\(frame) kids=\(kids.count)\(extras) parent=\(parent.components(separatedBy: "<").first!)"
}

@MainActor func describe(_ o: Any, depth: Int = 0, maxDepth: Int = 3, maxKids: Int = 4) {
    guard let obj = o as? NSObject else { return }
    print(String(repeating: "  ", count: depth) + line(obj))
    guard depth < maxDepth else { return }
    for k in ((kv(obj, "accessibilityChildren") as? [Any]) ?? []).prefix(maxKids) {
        describe(k, depth: depth + 1, maxDepth: maxDepth, maxKids: maxKids)
    }
}

@MainActor func kids(_ o: NSObject) -> [NSObject] { ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject } }

@MainActor func perform(_ e: NSObject, _ sel: String) -> Bool {
    typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(e.method(for: Selector(sel)), to: Fn.self)(e, Selector(sel))
}

@MainActor func setFocused(_ e: NSObject, _ v: Bool) {
    typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
    let sel = Selector("setAccessibilityFocused:")
    unsafeBitCast(e.method(for: sel), to: Fn.self)(e, sel, v)
}

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless()
    h.layoutSubtreeIfNeeded()
    spin(0.5)
    print("=== \(name)")
    windows.append(w)
    return h
}

final class Model: ObservableObject {
    @Published var n = 0
    @Published var show = true
    @Published var adjusted: [String] = []
}

struct Counter: View {
    @ObservedObject var m: Model
    var body: some View {
        VStack {
            if m.show { Text("Conditional") }
            Text("Count \(m.n)")
            Text("Trailing")
        }
    }
}

struct FocusProbe: View {
    @FocusState var focused: Bool
    let onChange: (Bool) -> Void
    var body: some View {
        VStack {
            Text("Other").focusable()
            Text("Focusable").focusable().focused($focused)
        }
        .onChange(of: focused) { _, v in onChange(v) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

MainActor.assumeIsolated {
    // --- 0: positive control, AppKit's own button through the same walker.
    let cw = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                      styleMask: [.titled], backing: .buffered, defer: false)
    cw.isReleasedWhenClosed = false
    let b = NSButton(title: "Native", target: nil, action: nil)
    cw.contentView = b
    cw.orderFrontRegardless(); spin(0.1)
    print("=== 0 control: NSButton")
    describe(b)

    // --- 1: activation. No AX client in this process yet.
    let lazyHost = host("1 Text before any activation", Text("Hello"))
    print("children on ask: \(kids(lazyHost).count)")
    spin(0.5)
    print("children after a second ask and a spin: \(kids(lazyHost).count)")

    // --- 2: the same host after the app is told an assistive client is active.
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.5)
    print("=== 2 the same Text after AXEnhancedUserInterface = true")
    print("children on ask: \(kids(lazyHost).count)")
    describe(lazyHost)

    // --- 3: containers flatten; a static text's string is its VALUE.
    describe(host("3 VStack { Text A; Text B }", VStack { Text("A"); Text("B") }))

    // --- 4: ZStack order, last declared paints on top.
    describe(host("4 ZStack { Text Under; Text Over }", ZStack { Text("Under"); Text("Over") }))

    // --- 5: Button, and pressing it.
    var pressed = 0
    let bh = host("5 Button(\"Go\")", Button("Go") { pressed += 1 })
    describe(bh)
    if let n = kids(bh).first { print("press -> \(perform(n, "accessibilityPerformPress")), closure ran \(pressed) time(s)") }

    // --- 6: a Button whose label is two Texts: combined, and how.
    describe(host("6 Button { HStack { Text A; Text B } }", Button {} label: { HStack { Text("A"); Text("B") } }))

    // --- 7: onTapGesture is not a button.
    var tapped = 0
    let th = host("7 Text(\"Tap\").onTapGesture", Text("Tap").onTapGesture { tapped += 1 })
    describe(th)
    if let n = kids(th).first { print("press -> \(perform(n, "accessibilityPerformPress")), closure ran \(tapped) time(s)") }

    // --- 8: onTapGesture plus the isButton trait.
    var tapped2 = 0
    let tbh = host("8 Text(\"Tap\").onTapGesture.accessibilityAddTraits(.isButton)",
                   Text("Tap").onTapGesture { tapped2 += 1 }.accessibilityAddTraits(.isButton))
    describe(tbh)
    if let n = kids(tbh).first { print("press -> \(perform(n, "accessibilityPerformPress")), closure ran \(tapped2) time(s)") }

    // --- 9: a tap gesture on a container of two texts.
    describe(host("9 VStack { Text A; Text B }.onTapGesture", VStack { Text("A"); Text("B") }.onTapGesture {}))

    // --- 10: label on a Text, on a Color; a plain Color.
    describe(host("10a Text(\"Hello\").accessibilityLabel(\"Greeting\")", Text("Hello").accessibilityLabel("Greeting")))
    describe(host("10b Color.frame(20).accessibilityLabel(\"Swatch\")", Color.red.frame(width: 20, height: 20).accessibilityLabel("Swatch")))
    describe(host("10c Color.frame(20), nothing declared", Color.red.frame(width: 20, height: 20)))

    // --- 11: adjustable action.
    let m = Model()
    let ah = host("11 Text(\"vol\").accessibilityValue(\"5\").accessibilityAdjustableAction",
                  Text("vol").accessibilityValue("5").accessibilityAdjustableAction { d in
                      m.adjusted.append(d == .increment ? "increment" : "decrement") })
    describe(ah)
    if let n = kids(ah).first {
        print("increment -> \(perform(n, "accessibilityPerformIncrement")), decrement -> \(perform(n, "accessibilityPerformDecrement")), closure saw \(m.adjusted)")
    }

    // --- 12: identity across an update, and across a vanishing sibling.
    let model = Model()
    let ih = host("12 identity: VStack { if show { Text Conditional }; Text Count n; Text Trailing }", Counter(m: model))
    describe(ih)
    let before = kids(ih)
    model.n = 1; spin(0.5)
    let afterValue = kids(ih)
    print("after n = 1: count \(afterValue.count); same objects by position: \(zip(before, afterValue).map { $0 === $1 })")
    describe(ih)
    model.show = false; spin(0.5)
    let afterRemove = kids(ih)
    print("after show = false: count \(afterRemove.count); Count-node same object as before: \(afterRemove.first === before[1]), Trailing same: \(afterRemove.last === before[2])")
    print("removed node now reads: \(line(before[0]))")
    describe(ih)
    model.show = true; spin(0.5)
    let afterReturn = kids(ih)
    print("after show = true again: first node same object as the original Conditional: \(afterReturn.first === before[0])")

    // --- 13: focus. Programmatic focus, then AX-requested focus.
    var focusLog: [Bool] = []
    let fh = host("13 focus: VStack { Text Other .focusable(); Text Focusable .focusable().focused($f) }",
                  FocusProbe { focusLog.append($0) })
    fh.window?.makeKeyAndOrderFront(nil); spin(0.5)
    describe(fh)
    print("FocusState changes seen before any AX request: \(focusLog)")
    print("host accessibilityFocusedUIElement: \(str((kv(fh, "accessibilityFocusedUIElement") as? NSObject).map { line($0) }))")
    if let target = kids(fh).last {
        setFocused(target, true); spin(0.5)
        print("after setAccessibilityFocused(true) on the Focusable node: FocusState changes seen \(focusLog)")
        describe(fh)
        print("host accessibilityFocusedUIElement: \(str((kv(fh, "accessibilityFocusedUIElement") as? NSObject).map { line($0) }))")
    }

    // --- 14: virtualized content.
    describe(host("14a List(0..<500)", List(0..<500, id: \.self) { Text("Row \($0)") }, size: CGSize(width: 300, height: 200)), maxDepth: 2, maxKids: 2)
    describe(host("14b ScrollView { LazyVStack { ForEach(0..<500) } }", ScrollView { LazyVStack { ForEach(0..<500, id: \.self) { Text("Row \($0)") } } }, size: CGSize(width: 300, height: 200)), maxDepth: 3, maxKids: 2)
}
