// SwiftUI probe: does a presented view's press join its presenter's gesture
// arena? (plan task 12 part 1, lane 1 fix round, ruling IX-Q in
// docs/superpowers/2026-09-29-interaction-decisions.md.)
//
// The question: a MetalUI `Deferred` presentation hoists its content to a
// higher hit layer, but its id stays under its declarer's. Should a declaring
// ancestor's `highPriorityGesture`/`simultaneousGesture` see a press on the
// presented content? SwiftUI has two shapes that answer it: `.overlay` (the
// content stays in the presenter's tree and layer) and `.sheet`/`.popover`
// (a presentation, in its own window).
//
// HOW TO RUN (SA-O's compiled form, as `swiftui-interaction.swift`):
//
//   xcrun swiftc docs/probes/swiftui-gesture-presentation-arena.swift -o /tmp/ix-pa && /tmp/ix-pa
//
// THE INSTRUMENT is `swiftui-interaction.swift`'s, copied: a `FirstMouseHost`
// window, `NSEvent`s through `NSWindow.sendEvent` with a run-loop spin
// between down and up. A press on a presentation is sent to the window the
// presentation opened (`attachedSheet`, or the popover's own window, found as
// the one new visible window after presenting), at its content's centre.
//
// POSITIVE CONTROLS. P0 (a presenter with no gesture; the overlay's own tap)
// and S0/V0 (a sheet's / popover's own tap with no gesture on the presenter)
// must each read the presented view's tap, or the arm reading "-" or the
// presenter's gesture proves nothing. The "window" line of each presentation
// arm names the window the click went to, so an arm that clicked the
// presenter's own window by mistake is visible.
//
// RECORDED 2026-09-29 by the task 12 part 1 lane 1 fix round, macOS 27.0,
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED (lock probe:
// `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). Compiled form,
// run twice: stdout byte-identical (12 lines), exit 0, stderr empty both
// times. The presentation's hosting view refused the synthesized press until
// its `acceptsFirstMouse(for:)` was replaced (`acceptFirstMouse` below): the
// first run without it read "-" on every S/V arm, controls included, and
// was discarded as a broken instrument, not read as an answer.
//
// RESULT. An overlay is in its presenter's arena (P1: the presenter's high
// priority tap wins; P2: its simultaneous tap runs beside the overlay's). A
// sheet's or a popover's content is NOT (S1/S2, V1/V2 read exactly their
// controls S0/V0): the presenter's high-priority and simultaneous gestures
// never see a press on the presentation.
//
//   --- P: .overlay (in the presenter's tree); click the overlay's centre
//     P0 overlay tap, presenter no gesture (control): modal
//     P1 overlay tap, presenter .highPriorityGesture(Tap): presenter-high
//     P2 overlay tap, presenter .simultaneousGesture(Tap): presenter-sim,modal
//   --- S: .sheet; click the sheet content's centre
//     S0 sheet tap, presenter no gesture (control): modal   window=SheetPresentationWindow presenter=false at=(50.0, 50.0) hit=SheetHostingView<SheetContent>
//     S1 sheet tap, presenter .highPriorityGesture(Tap): modal   window=SheetPresentationWindow presenter=false at=(50.0, 50.0) hit=SheetHostingView<SheetContent>
//     S2 sheet tap, presenter .simultaneousGesture(Tap): modal   window=SheetPresentationWindow presenter=false at=(50.0, 50.0) hit=SheetHostingView<SheetContent>
//   --- V: .popover; click the popover content's centre
//     V0 popover tap, presenter no gesture (control): modal   window=_NSPopoverWindow presenter=false at=(63.0, 63.0) hit=PopoverHostingView<ModifiedContent<AnyView, PopoverRootModifier>>
//     V1 popover tap, presenter .highPriorityGesture(Tap): modal   window=_NSPopoverWindow presenter=false at=(63.0, 63.0) hit=PopoverHostingView<ModifiedContent<AnyView, PopoverRootModifier>>
//     V2 popover tap, presenter .simultaneousGesture(Tap): modal   window=_NSPopoverWindow presenter=false at=(63.0, 63.0) hit=PopoverHostingView<ModifiedContent<AnyView, PopoverRootModifier>>

import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.6)
    return w
}

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint) {
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}

@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .leftMouseDown, p); spin(0.05)
    mouse(w, .leftMouseUp, p); spin(0.6)
}

/// The presentation's own hosting view is SwiftUI's, not a `FirstMouseHost`,
/// and this unbundled script's windows are never key-active, so its
/// `acceptsFirstMouse(for:)` is replaced with `true` for the probe — what
/// `FirstMouseHost` does for the presenter's window.
@MainActor func acceptFirstMouse(_ cls: AnyClass) {
    let sel = #selector(NSView.acceptsFirstMouse(for:))
    let block: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
    let imp = imp_implementationWithBlock(block)
    if let m = class_getInstanceMethod(cls, sel), class_getInstanceMethod(class_getSuperclass(cls), sel) != m {
        method_setImplementation(m, imp)
    } else {
        class_addMethod(cls, sel, imp, "c@:@")
    }
}

@MainActor func centreOf(_ w: NSWindow) -> CGPoint {
    let f = w.contentView?.frame ?? .zero
    return CGPoint(x: f.midX, y: f.midY)
}

/// A 60x60 tappable that logs `modal`.
@MainActor func presented() -> some View {
    Color.green.frame(width: 60, height: 60).onTapGesture { Log.add("modal") }
}

enum Attach { case none, high, simultaneous }

extension View {
    @ViewBuilder func attach(_ a: Attach) -> some View {
        switch a {
        case .none: self
        case .high: self.highPriorityGesture(TapGesture().onEnded { Log.add("presenter-high") })
        case .simultaneous: self.simultaneousGesture(TapGesture().onEnded { Log.add("presenter-sim") })
        }
    }
}

@MainActor func overlayArm(_ label: String, _ a: Attach) {
    _ = Log.take()
    let w = makeWindow(Color.gray.overlay { presented() }.attach(a))
    click(w, at: CGPoint(x: 100, y: 100))
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
}

@MainActor func presentationArm(_ label: String, _ a: Attach, popover: Bool) {
    _ = Log.take()
    let before = Set(NSApp.windows.map(ObjectIdentifier.init))
    let host: AnyView = popover
        ? AnyView(Color.gray.frame(width: 200, height: 200)
            .popover(isPresented: .constant(true)) { presented().padding(20) }.attach(a))
        : AnyView(Color.gray.frame(width: 200, height: 200)
            .sheet(isPresented: .constant(true)) { presented().padding(20) }.attach(a))
    let w = makeWindow(host)
    spin(0.6)
    let target = w.attachedSheet
        ?? NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0 !== w && $0.isVisible }
    guard let target else {
        print("  \(label): NO PRESENTATION WINDOW")
        w.orderOut(nil)
        return
    }
    target.makeKey()
    spin(0.3)
    if let hit = target.contentView?.hitTest(centreOf(target)) { acceptFirstMouse(type(of: hit)) }
    let where_ = centreOf(target)
    click(target, at: where_)
    print("  \(label): \(Log.take())   window=\(type(of: target)) presenter=\(target === w) at=\(where_) hit=\(target.contentView?.hitTest(where_).map { String(describing: type(of: $0)) } ?? "nil")")
    target.orderOut(nil)
    w.orderOut(nil)
    spin(0.3)
}

@MainActor func run() {
    print("--- P: .overlay (in the presenter's tree); click the overlay's centre")
    overlayArm("P0 overlay tap, presenter no gesture (control)", .none)
    overlayArm("P1 overlay tap, presenter .highPriorityGesture(Tap)", .high)
    overlayArm("P2 overlay tap, presenter .simultaneousGesture(Tap)", .simultaneous)
    print("--- S: .sheet; click the sheet content's centre")
    presentationArm("S0 sheet tap, presenter no gesture (control)", .none, popover: false)
    presentationArm("S1 sheet tap, presenter .highPriorityGesture(Tap)", .high, popover: false)
    presentationArm("S2 sheet tap, presenter .simultaneousGesture(Tap)", .simultaneous, popover: false)
    print("--- V: .popover; click the popover content's centre")
    presentationArm("V0 popover tap, presenter no gesture (control)", .none, popover: true)
    presentationArm("V1 popover tap, presenter .highPriorityGesture(Tap)", .high, popover: true)
    presentationArm("V2 popover tap, presenter .simultaneousGesture(Tap)", .simultaneous, popover: true)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    run()
}
exit(0)
