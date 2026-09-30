// SwiftUI probe: plan task 12 part 2 — the accessibility half. What an
// NSHostingView publishes through NSAccessibility for every concept part 2
// rules on: `accessibilityElement(children:)`, `accessibilityHidden`, traits,
// hints and identifiers, declared and named actions, modal isolation, button
// roles and keyboard shortcuts, gestures, a truncated `Text`, focus against
// `@FocusState`, a `List`'s rows and selection, images, and proposal-shaped
// stacks and grids. Evidence for the `IX-U`… rulings in
// docs/superpowers/2026-09-29-interaction-decisions.md and spec
// docs/superpowers/specs/2026-09-29-accessibility-design.md.
//
// HOW TO RUN (Apple's toolchain; swiftly's JIT cannot load SwiftUI):
//
//   /usr/bin/swift docs/probes/swiftui-accessibility-part2.swift 2>&1 \
//     | grep -v 'Connection\]\|ntents\|warning:\|deprecated\|^ *[0-9]* |\|^ *|\|note:\|WARNING: Application performed a reentrant'
//
// HOW IT READS. As the three accessibility-bridge probes: KVC on the modern
// selectors after AXEnhancedUserInterface is set on NSApp (SwiftUI's
// `AccessibilityNode`s answer nothing to the informal API and publish no
// children before it), perform methods through a typed IMP, custom actions
// through `NSAccessibilityCustomAction.handler`. Headless: nothing here needs
// an unlocked screen, a key window or VoiceOver — every read is in-process.
//
// POSITIVE CONTROLS.
//   C0  re-runs the first probe's arm 11 / rules R0 and must read
//       `label=vol value=5` before any other arm is believed.
//   C1  a plain VStack { Text A; Text B } publishes two static texts, so an
//       arm that reads one node (E*) is the modifier's effect.
//   C2  an AppKit NSButton with a key equivalent read by the same walker, so
//       a missing shortcut attribute on SwiftUI's button is SwiftUI's answer.
//   Every perform arm prints its closure's side-effect counter; every hidden
//   arm has a published sibling; M0 (no .isModal) publishes both buttons.
//
// RECORDED 2026-09-29 by the plan-task-12-part-2 design session, macOS 27.0
// (26A428), /usr/bin/swift = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Screen
// LOCKED (CGSSessionScreenIsLocked = 1, displayAsleep main: 1) — nothing here
// depends on it except F4, recorded below as non-separating. Run twice, exit 0
// both times, filtered stdout byte-identical (308 lines), filtered stderr
// empty. F2's two FocusState writes arrived in a different ORDER on two
// earlier runs, so the arm prints them sorted. `disabled` on NSHostingView is
// the host's own answer to accessibilityEnabled and is not read by any
// ruling. One run's filtered output, verbatim:
//
//   === C2 control: NSButton keyEquivalent cmd-s
//   NSButton role=AXUnknown sub=nil label=Native value=nil kids=1
//     NSButtonCell role=AXButton sub=nil label=Native value=nil kids=0
//     key/shortcut attribute names on NSButton+cell: []
//   === C0 control: Text(vol).accessibilityValue(5).accessibilityAdjustableAction
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=vol value=5 kids=0
//   === C1 control: VStack { Text A; Text B }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B kids=0
//   === E1 VStack { Text A; Text B }.accessibilityElement()
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXUnknown sub=nil label=nil value=nil kids=0
//   === E2 VStack { Text A; Text B }.accessibilityElement(children: .ignore).accessibilityLabel(L)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXUnknown sub=nil label=L value=nil kids=0
//   === E3 VStack { Text A; Text B }.accessibilityElement(children: .combine)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A, B kids=0
//   === E4 VStack { Text A; Text B }.accessibilityElement(children: .contain)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXGroup sub=nil label=nil value=nil kids=2
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=A kids=0
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=B kids=0
//   === E5 VStack { Text A; Text B }.accessibilityElement(children: .contain).accessibilityLabel(L)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXGroup sub=nil label=L value=nil kids=2
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=A kids=0
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=B kids=0
//   === E6 VStack { Text A; Button B }.accessibilityElement(children: .combine)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=A, B value=nil custom=["B"] kids=0
//     E6 press -> true, ran 1 []
//   === E14 VStack { Button A; Button B }.accessibilityElement(children: .combine): press
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=A value=nil custom=["A", "B"] kids=0
//     E14 press -> true, ran 0 ["A"]
//   === E7 VStack { Text A; Toggle T }.accessibilityElement(children: .combine)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXCheckBox sub=nil label=A value=1 custom=["T"] kids=0
//   === E8 HStack { Text A; Text B }.accessibilityElement(children: .combine).accessibilityLabel(L)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=L kids=0
//   === E9 Text(A).accessibilityElement(children: .contain)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXGroup sub=nil label=nil value=nil kids=1
//       AccessibilityNode role=AXStaticText sub=nil label=nil value=A kids=0
//   === E10 VStack { VStack { Text A; Text B }.combine; Text C }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A, B kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=C kids=0
//   === E11 VStack { Text(vol).accessibilityValue(5); Text B }.combine
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=vol, B value=5 kids=0
//   === E12 VStack { Color.frame(20); Color.frame(20) }.accessibilityElement(children: .ignore)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXUnknown sub=nil label=nil value=nil kids=0
//   === E13 VStack { Text A; Text B }.accessibilityElement(children: .combine).onTapGesture{}
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A, B kids=0
//   === H1 VStack { Text A.accessibilityHidden(true); Text B }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B kids=0
//   === H2 VStack { VStack { Text A; Text B }.accessibilityHidden(true); Text C }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=C kids=0
//   === H3 Button { HStack { Image-like Color.accessibilityLabel(Icon).accessibilityHidden(true); Text Go } }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil kids=0
//   === H4 VStack { Text A; Text B }.accessibilityHidden(true).accessibilityHidden(false)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B kids=0
//   === H5 VStack { Text A.accessibilityHidden(false) }.accessibilityHidden(true); Text C
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=C kids=0
//   === T1 Text(Title).accessibilityAddTraits(.isHeader)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXHeading sub=nil label=Title value=nil kids=0
//   === T2 Text(Go).accessibilityAddTraits(.isButton)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil kids=0
//     T2 press -> false, ran 0 []
//   === T3 Button(B).accessibilityRemoveTraits(.isButton)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXUnknown sub=nil label=B value=nil kids=0
//   === T3p Button(B){count}.accessibilityRemoveTraits(.isButton): press
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXUnknown sub=nil label=B value=nil kids=0
//     T3p press -> true, ran 1 []
//   === T4 Text(S).accessibilityAddTraits(.isSelected)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=S selected kids=0
//   === T5 Color.frame(20).accessibilityLabel(Pic).accessibilityAddTraits(.isImage)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXImage sub=nil label=Pic value=nil kids=0
//   === T6 Text(Home).accessibilityAddTraits(.isLink)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXLink sub=nil label=Home value=nil kids=0
//   === T7 Button(B).accessibilityAddTraits(.isSelected)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=B value=nil selected kids=0
//   === T8 Text(Title).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXHeading sub=nil label=Title value=nil kids=0
//   === T9 VStack { Text A; Text B }.accessibilityAddTraits(.isHeader)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXHeading sub=nil label=A value=nil kids=0
//     AccessibilityNode role=AXHeading sub=nil label=B value=nil kids=0
//   === T10 Text(Clock).accessibilityAddTraits(.updatesFrequently)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Clock kids=0
//   === T11 Button(B).accessibilityAddTraits(.isHeader)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=B value=nil kids=0
//   === M0 control: ZStack { Button Under; Button Top }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXButton sub=nil label=Top value=nil kids=0
//     AccessibilityNode role=AXButton sub=nil label=Under value=nil kids=0
//   === M1 ZStack { Button Under; VStack { Button Top }.accessibilityAddTraits(.isModal) }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Top value=nil kids=0
//   === M2 Button(Under).overlay { VStack { Text Card; Button Close }.accessibilityAddTraits(.isModal) }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Card kids=0
//     AccessibilityNode role=AXButton sub=nil label=Close value=nil kids=0
//   === M3 VStack { Button Top; Button Under }, first .accessibilityAddTraits(.isModal)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Top value=nil kids=0
//   === M4 M1 again, then press Under via its element from M0's shape (occlusion)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Top value=nil kids=0
//     M4 hit test at the window centre -> NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//   === M5 occlusion: hold Under's element, then show an .isModal cover and press it
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Under value=nil kids=0
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Top value=nil kids=0
//     M5 held Under after the cover press -> true, ran 1 []
//   === N1 Button(B).accessibilityHint(Does X)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=B value=nil help=Does X kids=0
//   === N2 Text(A).accessibilityIdentifier(id1)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A id=id1 kids=0
//   === N3 Text(A).accessibilityHint(H)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A help=H kids=0
//   === N4 VStack { Text A; Text B }.accessibilityHint(H)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A help=H kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B help=H kids=0
//   === N5 VStack { Text A; Text B }.accessibilityIdentifier(g)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A id=g kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B id=g kids=0
//   === N6 Text(A).help(Tip)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A help=Tip kids=0
//   === A1 Text(T).accessibilityAction { }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=T value=nil kids=0
//     A1 press -> true, ran 1 []
//   === A2 Text(T).accessibilityAction(named: Delete) { }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=T custom=["Delete"] kids=0
//     A2 custom Delete handler -> true, ran 1
//   === A3 Button(B){log B}.accessibilityAction(named: Archive){log Archive}
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=B value=nil custom=["Archive"] kids=0
//     A3 press -> true, ran 0 ["B"]
//     A3 custom -> true ["B", "Archive"]
//   === A4 Button(B){log B}.accessibilityAction {log Default}
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=B value=nil kids=0
//     A4 press -> true, ran 0 ["Default"]
//   === A5 VStack{Text A; Text B}.accessibilityAction { }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXButton sub=nil label=A value=nil kids=0
//     AccessibilityNode role=AXButton sub=nil label=B value=nil kids=0
//     A5 first child press -> true, ran 1 []
//   === A6 Text(T).accessibilityAction(named: One){}.accessibilityAction(named: Two){}
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=T custom=["Two", "One"] kids=0
//   === A7 Text(T).accessibilityAction {}.disabled(true)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=T value=nil disabled kids=0
//     A7 press -> false, ran 0 []
//   === B1 Button(Delete, role: .destructive)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Delete value=nil kids=0
//   === B2 Button(Cancel, role: .cancel)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Cancel value=nil kids=0
//   === B3 Button(Save).keyboardShortcut(s)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Save value=nil kids=0
//     B3 roleDescription=button
//   === B3c control: Button(Save) plain
//     B3c roleDescription=button
//   === B4 Button(OK).keyboardShortcut(.defaultAction)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=OK value=nil kids=0
//   === B5 Button(P).buttonStyle(.plain)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=P value=nil kids=0
//   === B6 Button(Go).allowsHitTesting(false) (P1 re-run)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil kids=0
//     B6 press -> true, ran 1 []
//   === B7 Button(Go).disabled(true) (P2 re-run)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil disabled kids=0
//     B7 press -> false, ran 0 []
//   === B8 Text(Go).onTapGesture{}.allowsHitTesting(false).accessibilityAddTraits(.isButton)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil kids=0
//     B8 press -> false, ran 0 []
//   === G1 Text(Tap).onTapGesture{} (arm 7 re-run)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Tap kids=0
//     G1 press -> false, ran 0 []
//   === G2 Text(Tap).gesture(TapGesture().onEnded{})
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Tap kids=0
//     G2 press -> false, ran 0 []
//   === G3 Text(Hold).onLongPressGesture{}
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Hold kids=0
//     G3 press -> false, ran 0 []
//   === G4 Color.frame(40).accessibilityLabel(Drag).gesture(DragGesture())
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXUnknown sub=nil label=Drag value=nil kids=0
//     G4 press -> false, ran 0 []
//   === G5 Text(Tap).onTapGesture{}.accessibilityAddTraits(.isButton) (arm 8 re-run)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Tap value=nil kids=0
//     G5 press -> false, ran 0 []
//   === G6 Text(Tap).onTapGesture{}.accessibilityAction{}
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=Tap value=nil kids=0
//     G6 press -> true, ran 0 ["action"]
//   === G7 Text(Tap).onTapGesture(count: 2){}
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Tap kids=0
//     G7 press -> false, ran 0 []
//   === X1 Text(long).lineLimit(1).frame(width: 60)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A very long sentence that cannot fit kids=0
//   === X2 Text(long).lineLimit(1).truncationMode(.head).frame(width: 60)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A very long sentence that cannot fit kids=0
//   === X3 Text(long).lineLimit(2).frame(width: 60)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A very long sentence that cannot fit kids=0
//   === X4 Button(long).lineLimit(1).frame(width: 60)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXButton sub=nil label=A very long sentence that cannot fit value=nil kids=0
//   === F1 FocusState initial .b: host accessibilityFocusedUIElement
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     _SystemTextFieldCell role=AXTextField sub=nil label=nil value= kids=0
//     _SystemTextFieldCell role=AXTextField sub=nil label=nil value= kids=0
//     F1 focused element: AccessibilityNode role=AXTextField sub=nil label=nil value= kids=0 log=["focus=b"]
//   === F2 FocusState nil: set AXFocused on field A
//     F2 text fields found: 2; focused before: NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     F2 after AXFocused=true on A: log (sorted; its order varied run to run)=["focus=a", "focus=nil"] focused=AccessibilityNode role=AXTextField sub=nil label=nil value= kids=0
//   === F3 nothing focused: which element does the host report (divergence 31 re-run)
//     F3 focused element: NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=3
//   === F4 arm 13 re-run: VStack { Text Other.focusable(); Text Focusable.focusable().focused($f) }
//     F4 focused element: NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2 log=["f=true"]
//   === L1 List(0..<500) (R16 re-run): rows, last row's index and frame
//     L1 outline rows=500 visible=8 rowCount=0
//     L1 first row: NSOutlineRow role=AXRow sub=AXOutlineRow index=0 selected=0 frame=nil kids=1 firstKid=NSTableViewCellMockElement role=nil sub=nil label=nil value=nil kids=0
//     L1 last row: NSOutlineRow role=AXRow sub=AXOutlineRow index=499 selected=0 frame=nil kids=1 firstKid=NSTableViewCellMockElement role=nil sub=nil label=nil value=nil kids=0
//   === I1 Image(nsImage:)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXImage sub=nil label=nil value=nil kids=0
//   === I2 Image(decorative: cg, scale: 1)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=0
//   === I3 Image(nsImage:).accessibilityLabel(Logo)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXImage sub=nil label=Logo value=nil kids=0
//   === I4 Image(decorative:).accessibilityLabel(Logo)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=0
//   === I5 Image(decorative:).onTapGesture{}
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=0
//     I5: no node
//   === P1 HStack { Text A; Spacer; Text B }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B kids=0
//   === P2 Grid { GridRow { Text A; Text B }; GridRow { Text C; Text D } }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=4
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=A kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=B kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=C kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=D kids=0
//   === P3 HStack { Text A; Text B }.accessibilityLabel(L)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=2
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=L kids=0
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=L kids=0
//   === P4 ZStack { Rectangle; Text Over }
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Over kids=0
//   === P5 Rectangle().accessibilityLabel(Swatch)
//   NSHostingView role=AXGroup sub=AXHostingView label=nil value=nil disabled kids=1
//     AccessibilityNode role=AXUnknown sub=nil label=Swatch value=nil kids=0
//
// WHAT THE ARMS SETTLE (the IX- rulings cite them; this is a reading aid):
//   E1/E2/E12: .accessibilityElement() (children .ignore, the default) makes
//     ONE node with no role (AXUnknown), no label unless declared, and drops
//     every child — the children's text does NOT become its label.
//   E3/E8/E10/E11: .combine makes ONE node; its children's labels (or a
//     static text's value) join with ", " — into the VALUE of a static-text
//     node, into the LABEL where a child has a value (E11) or the node is a
//     button (E6); a declared label replaces the joined text (E8).
//   E6/E7/E14: .combine over interactive children takes the FIRST one's ROLE
//     (AXButton, AXCheckBox) and its press (E14 runs A, not B); its label is
//     every non-interactive child's text plus the first interactive child's
//     label (E6 "A, B"; E14 "A", B's label left out); and EVERY interactive
//     child is published as a custom action named by its label, in tree
//     order (E6 ["B"], E14 ["A", "B"]).
//   E4/E5/E9: .contain makes a real AXGroup (labelled if declared) holding
//     the children — even over a single leaf (E9).
//   E13: a gesture outside .combine adds no press.
//   H1–H5: accessibilityHidden(true) removes the subtree; an inner (false)
//     cannot un-hide it (H5); a later outer (false) wins over an inner (true)
//     only because the OUTER modifier wins (H4); a hidden child of a button
//     contributes nothing to its label (H3).
//   T1/T8/T9/T11: .isHeader makes AXHeading, whose text is the LABEL (not the
//     value), distributed from a container (T9); a Button keeps AXButton (T11).
//   T2/G5: .isButton makes AXButton with the text as label and NO press.
//   T3/T3p: removing .isButton from a Button leaves AXUnknown with its folded
//     label AND its press (T3p runs the action): the trait changes the role
//     only.
//   T4/T7: .isSelected publishes AXSelected on any role. T5: .isImage makes
//     AXImage. T6: .isLink makes AXLink. T10: .updatesFrequently is invisible.
//   M0–M3: .isModal on a subtree publishes ONLY that subtree (its siblings and
//     their ancestors' other content vanish from the tree, M1, M3); an .isModal
//     overlay hides its primary (M2); M4: the hit test outside it answers the
//     host. M5: an element a client already HOLDS still presses after the
//     cover appears — SwiftUI isolates the tree, not the held handle.
//   N1–N6: a hint publishes as AXHelp (N1, N3), distributed from a container
//     (N4), and .help(_:) publishes the same attribute (N6); an identifier is
//     AXIdentifier, distributed too (N5).
//   A1/A5: accessibilityAction {} makes a Text an AXButton that presses (the
//     action runs), distributed to each child (A5). A4: on a Button the
//     declared action REPLACES the button's own press. A2/A3/A6: a named action
//     publishes as a custom action (NSAccessibilityCustomAction) that runs; on a
//     Button its press stays the button's (A3); two named actions list the
//     LATER-written first (A6). A7: disabled refuses the press.
//   B1/B2/B4/B5: role, a default-action shortcut and a plain style publish
//     nothing different: AXButton with its label. B3/B3c/C2: a keyboard
//     shortcut publishes no attribute (none on AppKit's own NSButton either).
//   B6: a Button under allowsHitTesting(false) STILL presses (P1 re-run,
//     divergence 28). B7: disabled refuses (P2 re-run). B8: a tap gesture under
//     allowsHitTesting(false) with .isButton does not press.
//   G1–G7: no gesture (tap, count-2 tap, long press, drag) publishes a press
//     (arm 7/8 re-run); .accessibilityAction on a tapped text runs the ACTION
//     and not the tap (G6).
//   X1–X4: a truncated or line-limited Text (and a Button's label) publishes
//     its WHOLE string, whatever is drawn.
//   F1: the FocusState-focused field is the host's focused element. F2: an
//     AXFocused write reaches @FocusState (focus=a). F3: nothing focusable
//     focused answers the host. F4: arm 13's shape answered the host this time
//     (arm 13 recorded "Other" with an unlocked screen) — NOT separating; no
//     ruling rests on F4, and divergence 31 is untouched.
//   L1: a 500-row List publishes 500 AXRow/AXOutlineRow rows with indices
//     0…499 through AXRows (only 8 visible) — every row is reachable.
//   I1–I5: Image(nsImage:) is an AXImage (labelled when declared); a
//     decorative image publishes nothing, even labelled (I4) or tapped (I5).
//   P1–P5: stacks and grids publish no container node — their texts are
//     flattened into the host in reading order (P2: row by row); a label on
//     an HStack distributes (P3); a labelled Rectangle is AXUnknown (P5).

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
/// KVC, guarded: AppKit's own row/cell mock elements are not KVC-compliant for
/// the accessibility keys, and an undefined key raises.
func kv(_ o: NSObject, _ key: String) -> Any? {
    let isKey = "is" + key.prefix(1).uppercased() + key.dropFirst()
    guard o.responds(to: Selector(key)) || o.responds(to: Selector(isKey)) else { return nil }
    return o.value(forKey: key)
}
@MainActor func kids(_ o: NSObject) -> [NSObject] { ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject } }
@MainActor func customActions(_ o: NSObject) -> [NSAccessibilityCustomAction] {
    (kv(o, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]) ?? []
}
@MainActor func line(_ o: NSObject) -> String {
    var s = "\(type(of: o))".components(separatedBy: "<").first!
    s += " role=\(str(kv(o, "accessibilityRole"))) sub=\(str(kv(o, "accessibilitySubrole")))"
    s += " label=\(str(kv(o, "accessibilityLabel"))) value=\(str(kv(o, "accessibilityValue")))"
    if let help = kv(o, "accessibilityHelp") as? String, !help.isEmpty { s += " help=\(help)" }
    if let ident = kv(o, "accessibilityIdentifier") as? String, !ident.isEmpty { s += " id=\(ident)" }
    if (kv(o, "accessibilitySelected") as? Bool) == true { s += " selected" }
    if (kv(o, "accessibilityEnabled") as? Bool) == false { s += " disabled" }
    let names = customActions(o).map(\.name)
    if !names.isEmpty { s += " custom=\(names)" }
    if str(kv(o, "accessibilityRole")) == "AXOutline" { s += " rows=\((kv(o, "accessibilityRows") as? [Any])?.count ?? -1)" }
    s += " kids=\(kids(o).count)"
    return s
}
@MainActor func describe(_ o: NSObject, _ d: Int = 0, maxDepth: Int = 4, maxKids: Int = 5) {
    print(String(repeating: "  ", count: d) + line(o))
    if d < maxDepth { for k in kids(o).prefix(maxKids) { describe(k, d + 1, maxDepth: maxDepth, maxKids: maxKids) } }
}
@MainActor func perform(_ e: NSObject, _ sel: String) -> Bool {
    typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(e.method(for: Selector(sel)), to: Fn.self)(e, Selector(sel))
}
/// Depth-first, first node with this role.
@MainActor func find(_ o: NSObject, role: String) -> NSObject? {
    if str(kv(o, "accessibilityRole")) == role { return o }
    for k in kids(o) { if let f = find(k, role: role) { return f } }
    return nil
}
final class Counter: @unchecked Sendable { var n = 0; var log: [String] = [] }

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.5)
    print("=== \(name)"); windows.append(w)
    return h
}
@MainActor func show<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 300)) {
    describe(host(name, v, size: size))
}
@MainActor func press(_ name: String, _ node: NSObject?, _ c: Counter) {
    guard let node else { print("  \(name): no node"); return }
    print("  \(name) press -> \(perform(node, "accessibilityPerformPress")), ran \(c.n) \(c.log)")
}

// F: focus against @FocusState.
enum Field: Hashable { case a, b }
final class FocusLog: @unchecked Sendable { var lines: [String] = [] }
let focusLog = FocusLog()
struct FocusHost: View {
    @FocusState var focus: Field?
    @State var a = ""
    @State var b = ""
    let initial: Field?
    var body: some View {
        VStack {
            TextField("A", text: $a).focused($focus, equals: .a)
            TextField("B", text: $b).focused($focus, equals: .b)
        }
        .onAppear { focus = initial }
        .onChange(of: focus) { _, new in focusLog.lines.append("focus=\(str(new))") }
    }
}

final class ModalModel: ObservableObject { @Published var shown = false }
struct ModalHost: View {
    @ObservedObject var m: ModalModel
    let under: Counter
    var body: some View {
        ZStack {
            Button("Under") { under.n += 1 }
            if m.shown { VStack { Button("Top") {} }.frame(width: 200, height: 200).background(.white).accessibilityAddTraits(.isModal) }
        }
    }
}
struct FocusableTexts: View {
    @FocusState var f: Bool
    var body: some View {
        VStack { Text("Other").focusable(); Text("Focusable").focusable().focused($f) }
            .onChange(of: f) { _, new in focusLog.lines.append("f=\(new)") }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    // --- C2 first, before AXEnhancedUserInterface: an AppKit button with a key equivalent.
    let native = NSButton(title: "Native", target: nil, action: nil)
    native.keyEquivalent = "s"
    native.keyEquivalentModifierMask = [.command]
    let nw = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    nw.isReleasedWhenClosed = false
    nw.contentView = native
    nw.orderFrontRegardless(); spin(0.3)
    print("=== C2 control: NSButton keyEquivalent cmd-s")
    describe(native, maxDepth: 1)
    let names = (native.accessibilityAttributeNames() + (native.cell?.accessibilityAttributeNames() ?? []))
        .map(\.rawValue).filter { $0.localizedCaseInsensitiveContains("key") || $0.localizedCaseInsensitiveContains("short") }
    print("  key/shortcut attribute names on NSButton+cell: \(names)")
    nw.orderOut(nil)

    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.5)
    show("C0 control: Text(vol).accessibilityValue(5).accessibilityAdjustableAction", Text("vol").accessibilityValue("5").accessibilityAdjustableAction { _ in })
    show("C1 control: VStack { Text A; Text B }", VStack { Text("A"); Text("B") })

    // --- E: accessibilityElement(children:)
    show("E1 VStack { Text A; Text B }.accessibilityElement()", VStack { Text("A"); Text("B") }.accessibilityElement())
    show("E2 VStack { Text A; Text B }.accessibilityElement(children: .ignore).accessibilityLabel(L)",
         VStack { Text("A"); Text("B") }.accessibilityElement(children: .ignore).accessibilityLabel("L"))
    show("E3 VStack { Text A; Text B }.accessibilityElement(children: .combine)",
         VStack { Text("A"); Text("B") }.accessibilityElement(children: .combine))
    show("E4 VStack { Text A; Text B }.accessibilityElement(children: .contain)",
         VStack { Text("A"); Text("B") }.accessibilityElement(children: .contain))
    show("E5 VStack { Text A; Text B }.accessibilityElement(children: .contain).accessibilityLabel(L)",
         VStack { Text("A"); Text("B") }.accessibilityElement(children: .contain).accessibilityLabel("L"))
    let e6 = Counter()
    let h6 = host("E6 VStack { Text A; Button B }.accessibilityElement(children: .combine)",
                  VStack { Text("A"); Button("B") { e6.n += 1 } }.accessibilityElement(children: .combine))
    describe(h6)
    press("E6", kids(h6).first, e6)
    let e14 = Counter()
    let h14 = host("E14 VStack { Button A; Button B }.accessibilityElement(children: .combine): press",
                   VStack { Button("A") { e14.log.append("A") }; Button("B") { e14.log.append("B") } }.accessibilityElement(children: .combine))
    describe(h14); press("E14", kids(h14).first, e14)
    show("E7 VStack { Text A; Toggle T }.accessibilityElement(children: .combine)",
         VStack { Text("A"); Toggle("T", isOn: .constant(true)) }.accessibilityElement(children: .combine))
    show("E8 HStack { Text A; Text B }.accessibilityElement(children: .combine).accessibilityLabel(L)",
         HStack { Text("A"); Text("B") }.accessibilityElement(children: .combine).accessibilityLabel("L"))
    show("E9 Text(A).accessibilityElement(children: .contain)", Text("A").accessibilityElement(children: .contain))
    show("E10 VStack { VStack { Text A; Text B }.combine; Text C }",
         VStack { VStack { Text("A"); Text("B") }.accessibilityElement(children: .combine); Text("C") })
    show("E11 VStack { Text(vol).accessibilityValue(5); Text B }.combine",
         VStack { Text("vol").accessibilityValue("5"); Text("B") }.accessibilityElement(children: .combine))
    show("E12 VStack { Color.frame(20); Color.frame(20) }.accessibilityElement(children: .ignore)",
         VStack { Color.red.frame(width: 20, height: 20); Color.blue.frame(width: 20, height: 20) }.accessibilityElement(children: .ignore))
    show("E13 VStack { Text A; Text B }.accessibilityElement(children: .combine).onTapGesture{}",
         VStack { Text("A"); Text("B") }.accessibilityElement(children: .combine).onTapGesture {})

    // --- H: accessibilityHidden
    show("H1 VStack { Text A.accessibilityHidden(true); Text B }", VStack { Text("A").accessibilityHidden(true); Text("B") })
    show("H2 VStack { VStack { Text A; Text B }.accessibilityHidden(true); Text C }",
         VStack { VStack { Text("A"); Text("B") }.accessibilityHidden(true); Text("C") })
    show("H3 Button { HStack { Image-like Color.accessibilityLabel(Icon).accessibilityHidden(true); Text Go } }",
         Button {} label: { HStack { Color.red.frame(width: 10, height: 10).accessibilityLabel("Icon").accessibilityHidden(true); Text("Go") } })
    show("H4 VStack { Text A; Text B }.accessibilityHidden(true).accessibilityHidden(false)",
         VStack { Text("A"); Text("B") }.accessibilityHidden(true).accessibilityHidden(false))
    show("H5 VStack { Text A.accessibilityHidden(false) }.accessibilityHidden(true); Text C",
         VStack { VStack { Text("A").accessibilityHidden(false) }.accessibilityHidden(true); Text("C") })

    // --- T: traits
    show("T1 Text(Title).accessibilityAddTraits(.isHeader)", Text("Title").accessibilityAddTraits(.isHeader))
    let t2 = Counter()
    let ht2 = host("T2 Text(Go).accessibilityAddTraits(.isButton)", Text("Go").accessibilityAddTraits(.isButton))
    describe(ht2); press("T2", kids(ht2).first, t2)
    show("T3 Button(B).accessibilityRemoveTraits(.isButton)", Button("B") {}.accessibilityRemoveTraits(.isButton))
    let t3p = Counter()
    let ht3p = host("T3p Button(B){count}.accessibilityRemoveTraits(.isButton): press",
                    Button("B") { t3p.n += 1 }.accessibilityRemoveTraits(.isButton))
    describe(ht3p); press("T3p", kids(ht3p).first, t3p)
    show("T4 Text(S).accessibilityAddTraits(.isSelected)", Text("S").accessibilityAddTraits(.isSelected))
    show("T5 Color.frame(20).accessibilityLabel(Pic).accessibilityAddTraits(.isImage)",
         Color.red.frame(width: 20, height: 20).accessibilityLabel("Pic").accessibilityAddTraits(.isImage))
    show("T6 Text(Home).accessibilityAddTraits(.isLink)", Text("Home").accessibilityAddTraits(.isLink))
    show("T7 Button(B).accessibilityAddTraits(.isSelected)", Button("B") {}.accessibilityAddTraits(.isSelected))
    show("T8 Text(Title).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)",
         Text("Title").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2))
    show("T9 VStack { Text A; Text B }.accessibilityAddTraits(.isHeader)",
         VStack { Text("A"); Text("B") }.accessibilityAddTraits(.isHeader))
    show("T10 Text(Clock).accessibilityAddTraits(.updatesFrequently)", Text("Clock").accessibilityAddTraits(.updatesFrequently))
    show("T11 Button(B).accessibilityAddTraits(.isHeader)", Button("B") {}.accessibilityAddTraits(.isHeader))

    // --- M: modal isolation
    show("M0 control: ZStack { Button Under; Button Top }", ZStack { Button("Under") {}; Button("Top") {} })
    show("M1 ZStack { Button Under; VStack { Button Top }.accessibilityAddTraits(.isModal) }",
         ZStack { Button("Under") {}; VStack { Button("Top") {} }.accessibilityAddTraits(.isModal) })
    show("M2 Button(Under).overlay { VStack { Text Card; Button Close }.accessibilityAddTraits(.isModal) }",
         Button("Under") {}.frame(width: 200, height: 200).overlay { VStack { Text("Card"); Button("Close") {} }.accessibilityAddTraits(.isModal) })
    show("M3 VStack { Button Top; Button Under }, first .accessibilityAddTraits(.isModal)",
         VStack { Button("Top") {}.accessibilityAddTraits(.isModal); Button("Under") {} })
    let m4 = Counter()
    let hm4 = host("M4 M1 again, then press Under via its element from M0's shape (occlusion)",
                   ZStack { Button("Under") { m4.n += 1 }; VStack { Button("Top") {} }.accessibilityAddTraits(.isModal) })
    describe(hm4)
    print("  M4 hit test at the window centre -> \(str((hm4.accessibilityHitTest(NSPoint(x: 250, y: 250)) as? NSObject).map { line($0) }))")

    let m5 = Counter()
    let model = ModalModel()
    let hm5 = host("M5 occlusion: hold Under's element, then show an .isModal cover and press it", ModalHost(m: model, under: m5))
    describe(hm5)
    let heldUnder = find(hm5, role: "AXButton")
    model.shown = true
    spin(0.5)
    describe(hm5)
    press("M5 held Under after the cover", heldUnder, m5)

    // --- N: hint and identifier
    show("N1 Button(B).accessibilityHint(Does X)", Button("B") {}.accessibilityHint("Does X"))
    show("N2 Text(A).accessibilityIdentifier(id1)", Text("A").accessibilityIdentifier("id1"))
    show("N3 Text(A).accessibilityHint(H)", Text("A").accessibilityHint("H"))
    show("N4 VStack { Text A; Text B }.accessibilityHint(H)", VStack { Text("A"); Text("B") }.accessibilityHint("H"))
    show("N5 VStack { Text A; Text B }.accessibilityIdentifier(g)", VStack { Text("A"); Text("B") }.accessibilityIdentifier("g"))
    show("N6 Text(A).help(Tip)", Text("A").help("Tip"))

    // --- A: declared actions
    let a1 = Counter()
    let ha1 = host("A1 Text(T).accessibilityAction { }", Text("T").accessibilityAction { a1.n += 1 })
    describe(ha1); press("A1", kids(ha1).first, a1)
    let a2 = Counter()
    let ha2 = host("A2 Text(T).accessibilityAction(named: Delete) { }", Text("T").accessibilityAction(named: "Delete") { a2.n += 1 })
    describe(ha2)
    if let n = kids(ha2).first, let act = customActions(n).first {
        print("  A2 custom \(act.name) handler -> \(str(act.handler?())), ran \(a2.n)")
    }
    let a3 = Counter()
    let ha3 = host("A3 Button(B){log B}.accessibilityAction(named: Archive){log Archive}",
                   Button("B") { a3.log.append("B") }.accessibilityAction(named: "Archive") { a3.log.append("Archive") })
    describe(ha3); press("A3", kids(ha3).first, a3)
    if let n = kids(ha3).first, let act = customActions(n).first { print("  A3 custom -> \(str(act.handler?())) \(a3.log)") }
    let a4 = Counter()
    let ha4 = host("A4 Button(B){log B}.accessibilityAction {log Default}",
                   Button("B") { a4.log.append("B") }.accessibilityAction { a4.log.append("Default") })
    describe(ha4); press("A4", kids(ha4).first, a4)
    let a5 = Counter()
    let ha5 = host("A5 VStack{Text A; Text B}.accessibilityAction { }", VStack { Text("A"); Text("B") }.accessibilityAction { a5.n += 1 })
    describe(ha5); press("A5 first child", kids(ha5).first, a5)
    let a6 = Counter()
    let ha6 = host("A6 Text(T).accessibilityAction(named: One){}.accessibilityAction(named: Two){}",
                   Text("T").accessibilityAction(named: "One") { a6.log.append("One") }.accessibilityAction(named: "Two") { a6.log.append("Two") })
    describe(ha6)
    let a7 = Counter()
    let ha7 = host("A7 Text(T).accessibilityAction {}.disabled(true)", Text("T").accessibilityAction { a7.n += 1 }.disabled(true))
    describe(ha7); press("A7", kids(ha7).first, a7)

    // --- B: buttons — role, shortcut, style, hit testing
    show("B1 Button(Delete, role: .destructive)", Button("Delete", role: .destructive) {})
    show("B2 Button(Cancel, role: .cancel)", Button("Cancel", role: .cancel) {})
    let hb3 = host("B3 Button(Save).keyboardShortcut(s)", Button("Save") {}.keyboardShortcut("s"))
    describe(hb3)
    if let n = kids(hb3).first {
        print("  B3 roleDescription=\(str(kv(n, "accessibilityRoleDescription")))")
    }
    let hb3c = host("B3c control: Button(Save) plain", Button("Save") {})
    if let n = kids(hb3c).first { print("  B3c roleDescription=\(str(kv(n, "accessibilityRoleDescription")))") }
    show("B4 Button(OK).keyboardShortcut(.defaultAction)", Button("OK") {}.keyboardShortcut(.defaultAction))
    show("B5 Button(P).buttonStyle(.plain)", Button("P") {}.buttonStyle(.plain))
    let b6 = Counter()
    let hb6 = host("B6 Button(Go).allowsHitTesting(false) (P1 re-run)", Button("Go") { b6.n += 1 }.allowsHitTesting(false))
    describe(hb6); press("B6", kids(hb6).first, b6)
    let b7 = Counter()
    let hb7 = host("B7 Button(Go).disabled(true) (P2 re-run)", Button("Go") { b7.n += 1 }.disabled(true))
    describe(hb7); press("B7", kids(hb7).first, b7)
    let b8 = Counter()
    let hb8 = host("B8 Text(Go).onTapGesture{}.allowsHitTesting(false).accessibilityAddTraits(.isButton)",
                   Text("Go").onTapGesture { b8.n += 1 }.allowsHitTesting(false).accessibilityAddTraits(.isButton))
    describe(hb8); press("B8", kids(hb8).first, b8)

    // --- G: gestures
    let g1 = Counter()
    let hg1 = host("G1 Text(Tap).onTapGesture{} (arm 7 re-run)", Text("Tap").onTapGesture { g1.n += 1 })
    describe(hg1); press("G1", kids(hg1).first, g1)
    let g2 = Counter()
    let hg2 = host("G2 Text(Tap).gesture(TapGesture().onEnded{})", Text("Tap").gesture(TapGesture().onEnded { g2.n += 1 }))
    describe(hg2); press("G2", kids(hg2).first, g2)
    let g3 = Counter()
    let hg3 = host("G3 Text(Hold).onLongPressGesture{}", Text("Hold").onLongPressGesture { g3.n += 1 })
    describe(hg3); press("G3", kids(hg3).first, g3)
    let g4 = Counter()
    let hg4 = host("G4 Color.frame(40).accessibilityLabel(Drag).gesture(DragGesture())",
                   Color.red.frame(width: 40, height: 40).accessibilityLabel("Drag").gesture(DragGesture().onEnded { _ in g4.n += 1 }))
    describe(hg4); press("G4", kids(hg4).first, g4)
    let g5 = Counter()
    let hg5 = host("G5 Text(Tap).onTapGesture{}.accessibilityAddTraits(.isButton) (arm 8 re-run)",
                   Text("Tap").onTapGesture { g5.n += 1 }.accessibilityAddTraits(.isButton))
    describe(hg5); press("G5", kids(hg5).first, g5)
    let g6 = Counter()
    let hg6 = host("G6 Text(Tap).onTapGesture{}.accessibilityAction{}",
                   Text("Tap").onTapGesture { g6.log.append("tap") }.accessibilityAction { g6.log.append("action") })
    describe(hg6); press("G6", kids(hg6).first, g6)
    let g7 = Counter()
    let hg7 = host("G7 Text(Tap).onTapGesture(count: 2){}", Text("Tap").onTapGesture(count: 2) { g7.n += 1 })
    describe(hg7); press("G7", kids(hg7).first, g7)

    // --- X: a truncated Text
    show("X1 Text(long).lineLimit(1).frame(width: 60)",
         Text("A very long sentence that cannot fit").lineLimit(1).frame(width: 60))
    show("X2 Text(long).lineLimit(1).truncationMode(.head).frame(width: 60)",
         Text("A very long sentence that cannot fit").lineLimit(1).truncationMode(.head).frame(width: 60))
    show("X3 Text(long).lineLimit(2).frame(width: 60)",
         Text("A very long sentence that cannot fit").lineLimit(2).frame(width: 60))
    show("X4 Button(long).lineLimit(1).frame(width: 60)",
         Button("A very long sentence that cannot fit") {}.lineLimit(1).frame(width: 60))

    // --- F: focus and @FocusState
    focusLog.lines = []
    let hf1 = host("F1 FocusState initial .b: host accessibilityFocusedUIElement", FocusHost(initial: .b))
    describe(hf1)
    print("  F1 focused element: \(str((hf1.accessibilityFocusedUIElement as? NSObject).map { line($0) })) log=\(focusLog.lines)")
    focusLog.lines = []
    let hf2 = host("F2 FocusState nil: set AXFocused on field A", FocusHost(initial: nil))
    let fields = kids(hf2).flatMap { kids($0).isEmpty ? [$0] : kids($0) }.filter { str(kv($0, "accessibilityRole")) == "AXTextField" }
    print("  F2 text fields found: \(fields.count); focused before: \(str((hf2.accessibilityFocusedUIElement as? NSObject).map { line($0) }))")
    if let a = fields.first {
        a.setValue(true, forKey: "accessibilityFocused")
        spin(0.4)
        print("  F2 after AXFocused=true on A: log (sorted; its order varied run to run)=\(focusLog.lines.sorted()) focused=\(str((hf2.accessibilityFocusedUIElement as? NSObject).map { line($0) }))")
    }
    focusLog.lines = []
    let hf3 = host("F3 nothing focused: which element does the host report (divergence 31 re-run)",
                   VStack { Text("A"); Button("B") {}; TextField("C", text: .constant("")) })
    print("  F3 focused element: \(str((hf3.accessibilityFocusedUIElement as? NSObject).map { line($0) }))")

    focusLog.lines = []
    let hf4 = host("F4 arm 13 re-run: VStack { Text Other.focusable(); Text Focusable.focusable().focused($f) }", FocusableTexts())
    spin(0.3)
    print("  F4 focused element: \(str((hf4.accessibilityFocusedUIElement as? NSObject).map { line($0) })) log=\(focusLog.lines)")

    // --- L: List rows and reach
    let hl1 = host("L1 List(0..<500) (R16 re-run): rows, last row's index and frame",
                   List(0..<500, id: \.self) { Text("Row \($0)") }, size: CGSize(width: 300, height: 200))
    if let outline = find(hl1, role: "AXOutline") {
        let rows = (kv(outline, "accessibilityRows") as? [Any]) ?? []
        let visible = (kv(outline, "accessibilityVisibleRows") as? [Any]) ?? []
        print("  L1 outline rows=\(rows.count) visible=\(visible.count) rowCount=\(str(kv(outline, "accessibilityRowCount")))")
        // Rows are AppKit's NSOutlineRow, which is not KVC-compliant for the
        // accessibility keys: read them through NSAccessibilityProtocol.
        @MainActor func rowLine(_ r: Any) -> String {
            guard let o = r as? NSObject else { return "\(type(of: r))" }
            func attr(_ n: NSAccessibility.Attribute) -> Any? { o.accessibilityAttributeValue(n) }
            let children = (attr(.children) as? [Any]) ?? []
            let firstKid = (children.first as? NSObject).map { line($0) } ?? "nil"
            return "\(type(of: r)) role=\(str(attr(.role))) sub=\(str(attr(.subrole))) index=\(str(attr(.index))) selected=\(str(attr(.selected))) frame=\(str(attr(NSAccessibility.Attribute(rawValue: "AXFrame")))) kids=\(children.count) firstKid=\(firstKid)"
        }
        if let first = rows.first { print("  L1 first row: \(rowLine(first))") }
        if let last = rows.last { print("  L1 last row: \(rowLine(last))") }
    } else { print("  L1 no AXOutline found"); describe(hl1) }

    // --- I: images
    let bitmap = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
    show("I1 Image(nsImage:)", Image(nsImage: bitmap))
    let cg = bitmap.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    show("I2 Image(decorative: cg, scale: 1)", Image(decorative: cg, scale: 1))
    show("I3 Image(nsImage:).accessibilityLabel(Logo)", Image(nsImage: bitmap).accessibilityLabel("Logo"))
    show("I4 Image(decorative:).accessibilityLabel(Logo)", Image(decorative: cg, scale: 1).accessibilityLabel("Logo"))
    let i5 = Counter()
    let hi5 = host("I5 Image(decorative:).onTapGesture{}", Image(decorative: cg, scale: 1).onTapGesture { i5.n += 1 })
    describe(hi5); press("I5", kids(hi5).first, i5)

    // --- P: proposal-shaped containers
    show("P1 HStack { Text A; Spacer; Text B }", HStack { Text("A"); Spacer(); Text("B") })
    show("P2 Grid { GridRow { Text A; Text B }; GridRow { Text C; Text D } }",
         Grid { GridRow { Text("A"); Text("B") }; GridRow { Text("C"); Text("D") } })
    show("P3 HStack { Text A; Text B }.accessibilityLabel(L)", HStack { Text("A"); Text("B") }.accessibilityLabel("L"))
    show("P4 ZStack { Rectangle; Text Over }", ZStack { Rectangle().fill(.red).frame(width: 40, height: 40); Text("Over") })
    show("P5 Rectangle().accessibilityLabel(Swatch)", Rectangle().fill(.red).frame(width: 20, height: 20).accessibilityLabel("Swatch"))
    spin(0.2)
}
