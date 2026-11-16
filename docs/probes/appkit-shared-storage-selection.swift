// AppKit probe: two NSTextViews over ONE NSTextStorage (each with its own layout manager and text container) and ONE
// shared NSUndoManager. When view A edits, what happens to view B's selection(s), which view's selection does an
// undo/redo performed by B restore, how many undo steps do two views' typing make, and what happens to B's marked
// text? Settles the open rules of docs/superpowers/specs/2026-11-16-codeview-selection-state-design.md §3 and
// CV-AW (move rule for a non-acting state), CV-AX (undo target and coalescing), CV-AZ (marked text) in
// docs/superpowers/2026-11-07-code-view-decisions.md (record 325).
//
// Every edit goes through the text view's own editing path (`insertText(_:replacementRange:)`, which runs
// shouldChangeText / replaceCharacters / didChangeText), so undo registration and the selection updates are AppKit's.
// The shared undo manager is handed to both views by overriding `undoManager`; `allowsUndo` is on. The run loop is
// spun between steps that a user would make as separate events (undo groups close per event).
//
// HOW TO RUN (compiled form with Apple's toolchain, ruling SA-O; one arm per process, so no state leaks):
//
//   xcrun swiftc docs/probes/appkit-shared-storage-selection.swift -o /tmp/shared-sel
//   for a in $(/tmp/shared-sel --list); do /tmp/shared-sel $a 2>&1 | grep -v 'Connection\]'; done
//   TK=2 /tmp/shared-sel insertAtOtherCaret        # TextKit 2: one NSTextContentStorage, two NSTextLayoutManagers
//
// Document "0123456789" (10 characters). Selections are printed as `A=[{loc,len}] B=[{loc,len}]` (selectedRanges).
// Each arm prints `before`, `after` and arm-specific lines, then exits itself.
//
// RECORDED: see the RECORDED block at the foot of this file (after the code).

import AppKit

nonisolated(unsafe) var sharedUM = UndoManager()

final class Tv: NSTextView {
    override var undoManager: UndoManager? { sharedUM }
}

func spin(_ s: Double = 0.05) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }
func r(_ a: Int, _ b: Int) -> NSValue { NSValue(range: NSRange(location: a, length: b)) }
func fmt(_ v: NSTextView) -> String {
    "[" + v.selectedRanges.map { "{\($0.rangeValue.location),\($0.rangeValue.length)}" }.joined(separator: ",") + "]"
}

struct World {
    let window: NSWindow
    let a: NSTextView, b: NSTextView
    let storageString: () -> String
    let tk2: Bool
    func show(_ tag: String) { print("\(tag): A=\(fmt(a)) B=\(fmt(b)) text='\(storageString())'") }
}

func makeWorld(_ text: String) -> World {
    let tk2 = ProcessInfo.processInfo.environment["TK"] == "2"
    let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    let a: NSTextView, b: NSTextView
    var str: () -> String
    if tk2 {
        let cs = NSTextContentStorage()
        cs.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        func make(_ x: CGFloat) -> NSTextView {
            let lm = NSTextLayoutManager()
            cs.addTextLayoutManager(lm)
            let tc = NSTextContainer(size: NSSize(width: 280, height: 1e6))
            lm.textContainer = tc
            let v = Tv(frame: NSRect(x: x, y: 0, width: 290, height: 200), textContainer: tc)
            return v
        }
        a = make(0); b = make(300)
        let ts = cs.textStorage!
        str = { ts.string }
    } else {
        let ts = NSTextStorage(string: text)
        func make(_ x: CGFloat) -> NSTextView {
            let lm = NSLayoutManager()
            ts.addLayoutManager(lm)
            let tc = NSTextContainer(size: NSSize(width: 280, height: 1e6))
            lm.addTextContainer(tc)
            return Tv(frame: NSRect(x: x, y: 0, width: 290, height: 200), textContainer: tc)
        }
        a = make(0); b = make(300)
        str = { ts.string }
    }
    for v in [a, b] { v.allowsUndo = true; v.isEditable = true; v.isRichText = false }
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    content.addSubview(a); content.addSubview(b)
    win.contentView = content
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    spin(0.2)
    sharedUM.removeAllActions()
    return World(window: win, a: a, b: b, storageString: str, tk2: tk2)
}

func type(_ v: NSTextView, _ s: String, at loc: Int, length: Int = 0) {
    v.insertText(s, replacementRange: NSRange(location: loc, length: length))
}

/// Every arm: `setup` places both selections, `act` edits through A (or does the arm's own steps).
struct Arm { let name: String; let run: (World) -> Void }

func oneEdit(_ name: String, bSel: [NSValue], aLoc: Int, aLen: Int, text: String) -> Arm {
    Arm(name: name) { w in
        w.window.makeFirstResponder(w.a)
        w.a.setSelectedRange(NSRange(location: 0, length: 0))
        w.b.selectedRanges = bSel
        w.show("before")
        type(w.a, text, at: aLoc, length: aLen)
        spin()
        w.show("after")
    }
}

func undoArm(_ name: String, redo: Bool) -> Arm {
    Arm(name: name) { w in
        w.a.setSelectedRange(NSRange(location: 0, length: 0))
        w.b.setSelectedRange(NSRange(location: 8, length: 0))
        w.window.makeFirstResponder(w.a)
        w.show("before")
        type(w.a, "XYZ", at: 2, length: 2) // A replaces 2..4 (A's caret stays at 0); B's caret was at 8
        spin()
        w.show("afterEdit")
        w.window.makeFirstResponder(w.b)  // B is first responder and performs the undo
        spin()
        w.show("beforeUndo (B first responder)")
        sharedUM.undo()
        spin()
        w.show("afterUndo")
        if redo {
            sharedUM.redo()
            spin()
            w.show("afterRedo")
        }
        print("firstResponder=\(w.window.firstResponder === w.b ? "B" : (w.window.firstResponder === w.a ? "A" : "other"))")
    }
}

let arms: [Arm] = [
    // (A types at B's caret offset; B's caret = 5)
    oneEdit("insertAtOtherCaret", bSel: [r(5, 0)], aLoc: 5, aLen: 0, text: "XY"),
    oneEdit("insertBefore", bSel: [r(5, 2)], aLoc: 1, aLen: 0, text: "XY"),
    oneEdit("insertAfter", bSel: [r(5, 2)], aLoc: 8, aLen: 0, text: "XY"),
    oneEdit("insertAtOtherSelectionStart", bSel: [r(5, 2)], aLoc: 5, aLen: 0, text: "XY"),
    oneEdit("insertAtOtherSelectionEnd", bSel: [r(5, 2)], aLoc: 7, aLen: 0, text: "XY"),
    oneEdit("insertInsideOtherSelection", bSel: [r(3, 5)], aLoc: 5, aLen: 0, text: "XY"),
    oneEdit("deleteContainingOtherSelection", bSel: [r(4, 2)], aLoc: 2, aLen: 6, text: ""),
    oneEdit("deleteContainingOtherCaret", bSel: [r(5, 0)], aLoc: 2, aLen: 6, text: ""),
    oneEdit("deletePartialOverlap", bSel: [r(4, 4)], aLoc: 2, aLen: 4, text: ""),
    oneEdit("replaceContainingOtherCaret", bSel: [r(5, 0)], aLoc: 2, aLen: 6, text: "ZZ"),
    oneEdit("replaceContainingOtherSelectionLonger", bSel: [r(4, 2)], aLoc: 2, aLen: 6, text: "ZZZZZZZZ"),
    oneEdit("multiRangeOtherAcrossEdit", bSel: [r(1, 1), r(4, 2), r(8, 1)], aLoc: 3, aLen: 3, text: "Q"),
    oneEdit("replaceContainingOtherCaretLonger", bSel: [r(5, 0)], aLoc: 2, aLen: 6, text: "ZZZZZZZZ"),
    oneEdit("multiRangeOtherEditAfterAll", bSel: [r(1, 1), r(4, 2)], aLoc: 8, aLen: 0, text: "Q"),
    oneEdit("multiRangeOtherEditBeforeAll", bSel: [r(4, 1), r(7, 2)], aLoc: 1, aLen: 0, text: "Q"),
    undoArm("undoFromOtherView", redo: false),
    undoArm("redoFromOtherView", redo: true),
    Arm(name: "typingInTwoViewsCoalescing") { w in
        w.a.setSelectedRange(NSRange(location: 0, length: 0))
        w.b.setSelectedRange(NSRange(location: 10, length: 0))
        w.window.makeFirstResponder(w.a)
        w.show("before")
        // Same run-loop event: all typing is one AppKit undo group by event grouping, so use separate
        // events (spin between keystrokes) the way a user types, and count steps by undoing until empty.
        w.a.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)); spin()
        w.a.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0)); spin()
        w.window.makeFirstResponder(w.b); spin()
        w.b.insertText("c", replacementRange: NSRange(location: NSNotFound, length: 0)); spin()
        w.show("afterTyping")
        var steps = 0
        while sharedUM.canUndo && steps < 10 { sharedUM.undo(); spin(); steps += 1; w.show("undo#\(steps)") }
        print("undoSteps=\(steps)")
    },
    Arm(name: "typingInOneViewCoalescingControl") { w in
        w.a.setSelectedRange(NSRange(location: 0, length: 0))
        w.window.makeFirstResponder(w.a)
        w.a.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)); spin()
        w.a.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0)); spin()
        w.a.insertText("c", replacementRange: NSRange(location: NSNotFound, length: 0)); spin()
        var steps = 0
        while sharedUM.canUndo && steps < 10 { sharedUM.undo(); spin(); steps += 1 }
        print("undoSteps=\(steps) text='\(w.storageString())'")
    },
    markedArm("markedTextInBWhileAEdits-awayBefore", aLoc: 0, aLen: 0, text: "XY"),
    markedArm("markedTextInBWhileAEdits-awayAfter", aLoc: 9, aLen: 0, text: "XY"),
    markedArm("markedTextInBWhileAEdits-atMarkStart", aLoc: 5, aLen: 0, text: "XY"),
    markedArm("markedTextInBWhileAEdits-atMarkEnd", aLoc: 7, aLen: 0, text: "XY"),
    markedArm("markedTextInBWhileAEdits-insideMark", aLoc: 6, aLen: 0, text: "XY"),
    markedArm("markedTextInBWhileAEdits-deleteOverlapsMark", aLoc: 4, aLen: 2, text: ""),
]

func markedArm(_ name: String, aLoc: Int, aLen: Int, text: String) -> Arm {
    Arm(name: name) { w in
        w.window.makeFirstResponder(w.b)
        w.b.setSelectedRange(NSRange(location: 5, length: 0))
        w.b.setMarkedText("ab", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        spin()
        w.show("before")
        print("B before: hasMarked=\(w.b.hasMarkedText()) marked=\(w.b.markedRange())")
        w.a.setSelectedRange(NSRange(location: 0, length: 0))
        type(w.a, text, at: aLoc, length: aLen)
        spin()
        w.show("after")
        print("B after: hasMarked=\(w.b.hasMarkedText()) marked=\(w.b.markedRange())")
    }
}

let args = CommandLine.arguments
if args.count > 1 && args[1] == "--list" { for a in arms { print(a.name) }; exit(0) }
guard args.count > 1, let arm = arms.first(where: { $0.name == args[1] }) else { print("usage: --list | <arm>"); exit(2) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let sess = CGSessionCopyCurrentDictionary() as? [String: Any]
print("arm=\(arm.name) TK=\(ProcessInfo.processInfo.environment["TK"] ?? "1") screenLocked=\(sess?["CGSSessionScreenIsLocked"] ?? "absent")")
let w = makeWorld("0123456789")
arm.run(w)
exit(0)

// ====================================================================================================
// RECORDED 2026-11-15 (record 325, lane 1), macOS 27.2.1 (26B131), Apple Swift 6.4.2, compiled form, every arm its own
// process, run twice, stdout byte-identical both times (TextKit 1 run: 121 lines; TextKit 2 subset: 10 arms). The
// screen was LOCKED (CGSSessionScreenIsLocked=1) and no input was sent: windows open, edits are method calls, so
// nothing needs a visible screen. Arm blocks below are the first TextKit 1 run; `TK=2` rows follow.
//
// TextKit 1, run 1 (run 2 byte-identical):
//   arm=insertAtOtherCaret TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{5,0}] text='0123456789'
//   after: A=[{0,0}] B=[{7,0}] text='01234XY56789'
//   ---
//   arm=insertBefore TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{5,2}] text='0123456789'
//   after: A=[{0,0}] B=[{7,2}] text='0XY123456789'
//   ---
//   arm=insertAfter TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{5,2}] text='0123456789'
//   after: A=[{0,0}] B=[{5,2}] text='01234567XY89'
//   ---
//   arm=insertAtOtherSelectionStart TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{5,2}] text='0123456789'
//   after: A=[{0,0}] B=[{7,2}] text='01234XY56789'
//   ---
//   arm=insertAtOtherSelectionEnd TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{5,2}] text='0123456789'
//   after: A=[{0,0}] B=[{5,2}] text='0123456XY789'
//   ---
//   arm=insertInsideOtherSelection TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{3,5}] text='0123456789'
//   after: A=[{0,0}] B=[{7,0}] text='01234XY56789'
//   ---
//   arm=deleteContainingOtherSelection TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{4,2}] text='0123456789'
//   after: A=[{0,0}] B=[{2,0}] text='0189'
//   ---
//   arm=deleteContainingOtherCaret TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{5,0}] text='0123456789'
//   after: A=[{0,0}] B=[{2,0}] text='0189'
//   ---
//   arm=deletePartialOverlap TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{4,4}] text='0123456789'
//   after: A=[{0,0}] B=[{2,0}] text='016789'
//   ---
//   arm=replaceContainingOtherCaret TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{5,0}] text='0123456789'
//   after: A=[{0,0}] B=[{4,0}] text='01ZZ89'
//   ---
//   arm=replaceContainingOtherSelectionLonger TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{4,2}] text='0123456789'
//   after: A=[{0,0}] B=[{10,0}] text='01ZZZZZZZZ89'
//   ---
//   arm=multiRangeOtherAcrossEdit TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{1,1},{4,2},{8,1}] text='0123456789'
//   after: A=[{0,0}] B=[{4,0}] text='012Q6789'
//   ---
//   arm=replaceContainingOtherCaretLonger TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{5,0}] text='0123456789'
//   after: A=[{0,0}] B=[{10,0}] text='01ZZZZZZZZ89'
//   ---
//   arm=multiRangeOtherEditAfterAll TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{1,1},{4,2}] text='0123456789'
//   after: A=[{0,0}] B=[{1,1},{4,2}] text='01234567Q89'
//   ---
//   arm=multiRangeOtherEditBeforeAll TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{4,1},{7,2}] text='0123456789'
//   after: A=[{0,0}] B=[{5,1},{8,2}] text='0Q123456789'
//   ---
//   arm=undoFromOtherView TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{8,0}] text='0123456789'
//   afterEdit: A=[{0,0}] B=[{9,0}] text='01XYZ456789'
//   beforeUndo (B first responder): A=[{0,0}] B=[{9,0}] text='01XYZ456789'
//   afterUndo: A=[{2,2}] B=[{8,0}] text='0123456789'
//   firstResponder=B
//   ---
//   arm=redoFromOtherView TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{8,0}] text='0123456789'
//   afterEdit: A=[{0,0}] B=[{9,0}] text='01XYZ456789'
//   beforeUndo (B first responder): A=[{0,0}] B=[{9,0}] text='01XYZ456789'
//   afterUndo: A=[{2,2}] B=[{8,0}] text='0123456789'
//   afterRedo: A=[{5,0}] B=[{9,0}] text='01XYZ456789'
//   firstResponder=B
//   ---
//   arm=typingInTwoViewsCoalescing TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{10,0}] text='0123456789'
//   afterTyping: A=[{2,0}] B=[{13,0}] text='ab0123456789c'
//   undo#1: A=[{12,0}] B=[{12,0}] text='ab0123456789'
//   undo#2: A=[{0,0}] B=[{10,0}] text='0123456789'
//   undoSteps=2
//   ---
//   arm=typingInOneViewCoalescingControl TK=1 screenLocked=1
//   undoSteps=1 text='0123456789'
//   ---
//   arm=markedTextInBWhileAEdits-awayBefore TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{7,0}] text='01234ab56789'
//   B before: hasMarked=true marked={5, 2}
//   after: A=[{2,0}] B=[{9,0}] text='XY01234ab56789'
//   B after: hasMarked=false marked={14, 0}
//   ---
//   arm=markedTextInBWhileAEdits-awayAfter TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{7,0}] text='01234ab56789'
//   B before: hasMarked=true marked={5, 2}
//   after: A=[{0,0}] B=[{7,0}] text='01234ab56XY789'
//   B after: hasMarked=false marked={14, 0}
//   ---
//   arm=markedTextInBWhileAEdits-atMarkStart TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{7,0}] text='01234ab56789'
//   B before: hasMarked=true marked={5, 2}
//   after: A=[{0,0}] B=[{9,0}] text='01234XYab56789'
//   B after: hasMarked=false marked={14, 0}
//   ---
//   arm=markedTextInBWhileAEdits-atMarkEnd TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{7,0}] text='01234ab56789'
//   B before: hasMarked=true marked={5, 2}
//   after: A=[{0,0}] B=[{9,0}] text='01234abXY56789'
//   B after: hasMarked=false marked={14, 0}
//   ---
//   arm=markedTextInBWhileAEdits-insideMark TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{7,0}] text='01234ab56789'
//   B before: hasMarked=true marked={5, 2}
//   after: A=[{0,0}] B=[{9,0}] text='01234aXYb56789'
//   B after: hasMarked=false marked={14, 0}
//   ---
//   arm=markedTextInBWhileAEdits-deleteOverlapsMark TK=1 screenLocked=1
//   before: A=[{0,0}] B=[{7,0}] text='01234ab56789'
//   B before: hasMarked=true marked={5, 2}
//   after: A=[{0,0}] B=[{5,0}] text='0123b56789'
//   B after: hasMarked=false marked={10, 0}
//   ---
//
// TextKit 2 (TK=2, one NSTextContentStorage, two NSTextLayoutManagers; run 1, run 2 byte-identical):
//   arm=insertAtOtherCaret TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{5,0}] text='0123456789'
//   after: A=[{0,0}] B=[{7,0}] text='01234XY56789'
//   ---
//   arm=insertBefore TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{5,2}] text='0123456789'
//   after: A=[{0,0}] B=[{7,2}] text='0XY123456789'
//   ---
//   arm=insertInsideOtherSelection TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{3,5}] text='0123456789'
//   after: A=[{0,0}] B=[{7,0}] text='01234XY56789'
//   ---
//   arm=deleteContainingOtherCaret TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{5,0}] text='0123456789'
//   after: A=[{0,0}] B=[{2,0}] text='0189'
//   ---
//   arm=replaceContainingOtherCaretLonger TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{5,0}] text='0123456789'
//   after: A=[{0,0}] B=[{10,0}] text='01ZZZZZZZZ89'
//   ---
//   arm=multiRangeOtherAcrossEdit TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{1,1},{4,2},{8,1}] text='0123456789'
//   after: A=[{0,0}] B=[{4,0}] text='012Q6789'
//   ---
//   arm=undoFromOtherView TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{8,0}] text='0123456789'
//   afterEdit: A=[{0,0}] B=[{9,0}] text='01XYZ456789'
//   beforeUndo (B first responder): A=[{0,0}] B=[{9,0}] text='01XYZ456789'
//   afterUndo: A=[{0,0}] B=[{8,0}] text='0123456789'
//   firstResponder=B
//   ---
//   arm=typingInTwoViewsCoalescing TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{10,0}] text='0123456789'
//   afterTyping: A=[{2,0}] B=[{13,0}] text='ab0123456789c'
//   undo#1: A=[{2,0}] B=[{12,0}] text='ab0123456789'
//   undo#2: A=[{0,0}] B=[{10,0}] text='0123456789'
//   undoSteps=2
//   ---
//   arm=markedTextInBWhileAEdits-awayAfter TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{7,0}] text='01234ab56789'
//   B before: hasMarked=true marked={5, 2}
//   after: A=[{0,0}] B=[{5,0}] text='01234ab56XY789'
//   B after: hasMarked=false marked={14, 0}
//   ---
//   arm=markedTextInBWhileAEdits-atMarkEnd TK=2 screenLocked=1
//   before: A=[{0,0}] B=[{7,0}] text='01234ab56789'
//   B before: hasMarked=true marked={5, 2}
//   after: A=[{0,0}] B=[{9,0}] text='01234abXY56789'
//   B after: hasMarked=false marked={14, 0}
//   ---

// RESULT (TextKit 1; TextKit 2 agrees except where noted). The edit is made in A at a place other than A's own caret
// (A's caret stays at 0), so every change shown is to B.
//   MOVE RULE for a NON-ACTING view's selection (CV-AW): an insertion strictly BEFORE B's range shifts it; an insertion AT
//   B's caret or at B's range START moves B AFTER the insertion (caret 5, XY at 5 -> 7; range {5,2} -> {7,2}); an insertion at
//   B's range END or after it leaves it. An insertion strictly inside a range collapses it to a caret at the END of the
//   insertion. A deletion that contains the caret/range collapses to the deletion's START; a partial overlap collapses to the
//   start too. A replacement that contains the caret/range puts the caret at the END of the replacement text (caret 5,
//   2..8 -> 'ZZ' gives 4 = end; -> 'ZZZZZZZZ' gives 10 = end), NOT start+min(offset-start, newLength) (that rule would give 5).
//   MULTI-RANGE: ranges wholly before or after the edit shift/stay and all survive; an edit that overlaps ANY range collapses
//   the whole selection to a SINGLE caret (here {4,0}), losing the ranges that were untouched.
//   UNDO (CV-AX): B is first responder and undoes A's edit. The selection restored to the change goes to the view that MADE
//   the edit (A: {2,2}, the replaced span), never to the undoing view B, whose caret only follows the text ({9,0} -> {8,0}). On
//   redo A gets {5,0} (after the reinserted text). TextKit 2: undo restores NO selection to A ({0,0}); B follows the text.
//   COALESCING: A types 'a','b' (separate events), then B types 'c' -> 2 undo steps ('ab' then 'c'); one view typing a,b,c -> 1.
//   MARKED TEXT (CV-AZ): ANY edit by A, even far from B's mark (before or after it, and at its start, end or inside it) ENDS B's
//   composition (hasMarkedText false, marked range {14,0} i.e. none); the composed text stays in the storage, committed. B's
//   caret moves like any non-acting caret. TextKit 2 matches (B's caret differs: awayAfter {5,0}; the mark's commit moved it).
