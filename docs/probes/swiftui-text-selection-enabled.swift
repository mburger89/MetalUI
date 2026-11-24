// SwiftUI probe: `View.textSelection(.enabled)` on `Text` (macOS). Rulings `TXS-` in
// docs/superpowers/2026-11-23-text-selectability-decisions.md; design docs/superpowers/specs/2026-11-23-text-selectability-design.md
// (Alloy's request: a stderr log shown as a `Text` that users select and copy).
//
// HOW TO RUN (SA-O's compiled form; no JIT shim; needs no screen-recording grant, no Accessibility grant, no computer use;
// it opens its own 200 x 200 windows for about 80 s, so it takes the foreground briefly):
//
//   xcrun swiftc -swift-version 5 docs/probes/swiftui-text-selection-enabled.swift -o /tmp/txs-probe
//   /tmp/txs-probe > /tmp/txs-1.txt; /tmp/txs-probe > /tmp/txs-2.txt; cmp /tmp/txs-1.txt /tmp/txs-2.txt
//   /tmp/txs-probe E0        # one arm group by id prefix (E, D, F, C, M, S, T, G, L, X); "~S1x" is the child-process arm
//
// INSTRUMENT. `swiftui-text-links.swift`'s: a `FirstMouseHost` (an `NSHostingView`) in a `KeyWindow`, laid out and shown
// before the first event, events sent with a run-loop spin between them, a 200 x 200 window with the origin at the BOTTOM
// left, AX switched on with `AXEnhancedUserInterface` / `AXManualAccessibility`. Four things differ, and each one is a finding:
//   1. A selectable `Text` is NOT drawn by SwiftUI: it owns an AppKit view, `SwiftUI.AppKitTextInteractionView` (a
//      subclass of `NSCoreInteractionView<NSTextInteraction>`), one per selectable `Text`, 119 x 17 pt for a one-line
//      string, a real first responder (`acceptsFirstResponder` true). Every arm finds its Texts through it.
//   2. The app cannot be activated from a command-line process (`NSApp.isActive` stays false), and the responder-chain
//      commands (`copy:`, `selectAll:`, menu validation) look at `NSApp.keyWindow`. The probe therefore runs a
//      `FakeApp: NSApplication` whose `isActive` is true and whose `keyWindow` is the window under test, and installs an
//      Edit menu (Cut, Copy, Paste, Select All, as a SwiftUI app has) so the REAL `⌘C` / `⌘A` key events (through
//      `NSApp.sendEvent`, which runs the menu's key-equivalent search) reach the focused Text. Plain keys (Tab) go to
//      `NSWindow.sendEvent`.
//   3. Mouse events are `NSEvent(cgEvent:)` built from a `CGEvent` with the window number (field 51) and the window-local
//      location (`CGEventSetWindowLocation`, found with `dlsym`) written by hand, posted with `NSApp.postEvent` and
//      dequeued with `nextEvent` (so `NSApp.currentEvent` is set). A control, a plain `NSView` with an
//      `NSClickGestureRecognizer` and an `NSPanGestureRecognizer`, fires both for events sent through `NSWindow.sendEvent`
//      or `NSApplication.sendEvent`, built with `NSEvent.mouseEvent(...)` or from a `CGEvent`, so the instrument drives
//      AppKit gesture recognisers in general.
//   4. **THE LIMIT.** None of these events makes the selectable `Text` select, on any route tried (window or app
//      `sendEvent`, plain or CGEvent-backed events, `postEvent`, a mouse-moved first, the real cursor warped over the
//      text, `mouseDown:` called on the selection view itself, an `NSClickGestureRecognizer` added to it). The hit test
//      does return the selection view (G3), the events reach its `mouseDown:`, and `NSTextInteraction`'s gesture
//      recognisers (a press, a drag, a click, `_NSTextSelectionTouchTracker`) never act on them; posting real events
//      (`CGEventPost`) delivers nothing to this process without a grant. So **every arm that needs a pointer to select
//      (drag, double click, triple click, right-click on a word, click-to-focus, click-to-clear) prints
//      `ptr=NO-SELECTION(not measurable here)` and is a human check (HC-TXS-1..8, listed at the end of docs/superpowers/2026-11-23-text-selectability-decisions.md).**
//      What the probe CAN do is what an assistive client does: set the selection with
//      `setAccessibilitySelectedTextRange:` on the Text's element, move first responder with `makeFirstResponder`, and
//      then drive everything downstream with real keys, the real Edit menu and the real pasteboard. Those arms are
//      labelled PROXY and read as the answer to "given a selection exists, what does SwiftUI do", never as "what a drag does".
//
// ARM IDS. The ids are the task's table (E0 E1 D1 D2 D3 A1 F1 F2 C1 C2 C3 M1 S1 T1 G1 G2 L1 X1); a suffix (E0c, D1p, F1q...)
// is an added arm, `c` a control without the feature, `p`/`q` a proxy (AX-set selection). Every arm prints one line.
// Pasteboard readings start from the sentinel `'<untouched>'`: that value means nothing was copied.
//
// NOT MEASURED (human checks HC-TXS-1..8): the pointer arms above (drag, double and triple click, word/line/paragraph unit, select by
// right-click, click-to-focus, click-to-clear, drag-extend after a double click, a drag outside the Text); the I-beam
// cursor (a synthetic mouse move does not change `NSCursor.current`); the highlight colour, active versus inactive
// (the highlight is not drawn through a view the probe can read); what happens when the app (not just the window)
// resigns; VoiceOver; Full Keyboard Access on (F2 ran with it off, `fka=false`).
//
// RECORDED 2026-11-23, macOS 27.2.1, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), compiled with -swift-version 5, screen unlocked.
// Compiled form, run twice: stdout byte-identical (87 lines, shasum 897e7b3cc1b6d5f4889d35d455acc7bc5ebacc5b), exit 0, stderr
// empty (the S1x / S1y child processes abort by design and are reported by their parent). The window server could not
// activate the process (see INSTRUMENT 2). Every line below is the probe's stdout, verbatim.
//
//   --- E: inheritance and an inner .disabled (a Text is selectable iff it owns an AppKitTextInteractionView; each is focused, given an AX range 0+3, copied with the real ⌘C key)
//     E0 .textSelection(.enabled) on a VStack: staticTexts=9 selectionViews=9,'t1 direct'->copy 't1 ','t2 hstack'->copy 't2 ','t3 group'->copy 't3 ','t4 zstack'->copy 't4 ','t5 scroll'->copy 't5 ','t7 label'->copy 't7 ','t8 styled'->copy 't8 ','t9 link md'->copy 't9 ','t10 concat'->copy 't10'
//     E0c CONTROL no modifier: staticTexts=2 selectionViews=0
//     E0e containers: List row, Form row, a text in .overlay and .background: staticTexts=4 selectionViews=5,'l1 list row'->copy 'l1 ','f1 form row'->copy 'f1 ','b1 background'->copy 'b1 ','o1 base'->copy 'o1 ','o2 overlay'->copy 'o2 '
//     E1 enabled ancestor, inner .disabled on the middle Text: staticTexts=3 selectionViews=2,'outer one'->copy 'out','outer two'->copy 'out'
//     E1b disabled ancestor, inner .enabled on the second Text: staticTexts=2 selectionViews=1,'inner on'->copy 'inn'
//     E1c .enabled on an ancestor, .disabled(true) (the view modifier) on the Text: staticTexts=1 selectionViews=1,'view-disabled'->copy 'vie'
//     E1d .enabled with .allowsHitTesting(false) on the Text: staticTexts=1 selectionViews=1,'no-hit'->copy 'no-'
//     E1e .textSelection(.enabled) on a Text that is then .opacity(0): staticTexts=0 selectionViews=1,'hidden'->copy 'hid'
//   --- D: drag, double click, triple click, select all
//     D1 synthetic drag from the start 59 pt along the line, then ⌘C: ptr=NO-SELECTION(not measurable here),pb='<untouched>'
//     D1p PROXY: AX range 0+9 set, the Text is first responder: Edit>Copy before/after, ⌘C: copy(no range)=Copy=off/Select All=on,copy(range)=Copy=on/Select All=on range=0+9,pb='alpha bet'
//     D1q PROXY: AX range set but the Text is NOT first responder, ⌘C: range=0+9 resp=window copy=Copy=off/Select All=off,pb='<untouched>'
//     D2 synthetic double-click mid-word on visual line 1 of a wrapped text, ⌘C: ptr=NO-SELECTION(not measurable here),pb='<untouched>'
//     D3 synthetic triple-click on visual line 1, ⌘C: ptr=NO-SELECTION(not measurable here),pb='<untouched>'
//     A1 PROXY: A is first responder, ⌘A, ⌘C (the whole of A only?): resp=AppKitTextInteractionView,ranges=0+12/none,pb='first text A',editMenu=Copy=on/Select All=on
//     A1b nothing focused: ⌘A, ⌘C: ranges=none/none resp=window,pb='<untouched>'
//     A1c B has a range and focus, ⌘A: does A also select: ranges=none/0+13,pb='second text B'
//     A1d synthetic click on A, then ⌘A, ⌘C: resp=window,ranges=none/none,pb='<untouched>'
//   --- F: focus
//     F0 the selection view's focus answers: field=true,acceptsFirstResponder=true canBecomeKeyView=true needsPanelToBecomeKey=true
//     F1 synthetic: field focused (click), click the selectable Text: who is first responder, did the field lose @FocusState: field=true,|fieldClicked resp=_SystemTextFieldFieldEditor,|textClicked resp=_SystemTextFieldFieldEditor ptr=NO-SELECTION(not measurable here)
//     F1p PROXY: field focused, ⌘A in it; AX range set on the Text (no focus move); ⌘C goes to?: field=true,|field focused resp=_SystemTextFieldFieldEditor,|axSet resp=_SystemTextFieldFieldEditor,pb='fieldtext'
//     F1q PROXY: same, then the Text becomes first responder (what a click would do if it takes focus): field=false? ⌘C?: field=true,|focusing text,field=false,resp=AppKitTextInteractionView,pb='sel'
//     F1c CONTROL plain Text: field focused, click the Text: who is first responder: field=true,|fieldClicked resp=_SystemTextFieldFieldEditor,|textClicked resp=_SystemTextFieldFieldEditor
//     F2 Tab x4 / Shift-Tab x4 from the initial focus: [selectable Text, TextField a, TextField b]: fka=false start resp=_SystemTextFieldFieldEditor a=true b=false,|tab1 resp=_SystemTextFieldFieldEditor a=false b=true,|tab2 resp=_SystemTextFieldFieldEditor a=true b=false,|tab3 resp=_SystemTextFieldFieldEditor a=false b=true,|tab4 resp=_SystemTextFieldFieldEditor a=true b=false,|btab1 resp=_SystemTextFieldFieldEditor a=false b=true,|btab2 resp=_SystemTextFieldFieldEditor a=true b=false,|btab3 resp=_SystemTextFieldFieldEditor a=false b=true,|btab4 resp=_SystemTextFieldFieldEditor a=true b=false
//     F2c CONTROL the same with a plain Text: fka=false start resp=_SystemTextFieldFieldEditor a=true b=false,|tab1 resp=_SystemTextFieldFieldEditor a=false b=true,|tab2 resp=_SystemTextFieldFieldEditor a=true b=false,|tab3 resp=_SystemTextFieldFieldEditor a=false b=true,|tab4 resp=_SystemTextFieldFieldEditor a=true b=false,|btab1 resp=_SystemTextFieldFieldEditor a=false b=true,|btab2 resp=_SystemTextFieldFieldEditor a=true b=false,|btab3 resp=_SystemTextFieldFieldEditor a=false b=true,|btab4 resp=_SystemTextFieldFieldEditor a=true b=false
//     F2b Tab x3 with a selectable Text and a Button only (nothing else focusable): tab1 resp=window,tab2 resp=window,tab3 resp=window,nextValidKeyView=nil previousValidKeyView=nil
//   --- C: what a click elsewhere does to a selection (the selection is SET by the accessibility API and the Text focused: the pointer cannot select here)
//     C0 baseline: A has range 0+7 and focus; ⌘C: field=true,field=false,range=0+7 pb='text A '
//     C1 synthetic click on empty space (bottom), then ⌘C: field=true,field=false,resp=AppKitTextInteractionView A=0+7,pb='text A '
//     C2 synthetic click on the TextField, then ⌘C (the field has no selection): field=true,field=false,field=true,resp=_SystemTextFieldFieldEditor A=none,pb='<untouched>'
//     C2b the same, then click back into the Text's frame: is A's range still there: field=true,field=false,field=true,field=false,refocused A=none,pb='<untouched>'
//     C3 PROXY: B becomes first responder (what a click on B would do): A's range, B's range, ⌘C: field=true,field=false,A=none B=none resp=AppKitTextInteractionView,pb='<untouched>'
//     C3b both A and B given ranges (A first, then B, by AX): is A's kept: field=true,field=false,A=0+7 B=0+4
//     C5 the window resigns key (didResignKey posted, and the window made non-key), A's range, ⌘C: field=true,field=false,A=0+7,pb='text A '
//     C5b the window really resigns key (NSWindow.resignKey()), A's range, ⌘C: field=true,field=false,resp=AppKitTextInteractionView A=0+7,pb='text A '
//     C6 the first responder is cleared (makeFirstResponder(nil)) while A has a range: field=true,field=false,resp=window A=none,pb='<untouched>'
//   --- M: right-click
//     M1 menu(for:) of the selection view, nothing selected: [Cut|Copy|Paste|Paste and Match Style|-|Font|-|Spelling and Grammar|Substitutions|Transformations|Speech|Writing Direction|Layout Orientation]
//     M1b menu(for:), range 0+5 set: [Look Up “alpha”|Translate “alpha”|-|Search With Google|-|Cut|Copy|Paste|Paste and Match Style|-|Share…|-|Font|-|Spelling and Grammar|Substitutions|Transformations|Speech|Writing Direction|Layout Orientation]
//     M1c menu(for:), range set, the Text NOT first responder: [Look Up “alpha”|Translate “alpha”|-|Search With Google|-|Cut|Copy|Paste|Paste and Match Style|-|Share…|-|Font|-|Spelling and Grammar|Substitutions|Transformations|Speech|Writing Direction|Layout Orientation]
//     M1d synthetic right-click on a word (nothing selected): the menu the window shows, then ranges: tracking=[(Cut)|(Copy)|(Paste)|(Paste and Match Style)|-|Font|-|Spelling and Grammar|Substitutions|Transformations|Speech|Writing Direction|Layout Orientation],ranges=none
//     M1e right-click, Text with .contextMenu { Button("Mine") } + selectable: views=1,tracking=[(Cut)|(Copy)|(Paste)|(Paste and Match Style)|-|Font|-|Spelling and Grammar|Substitutions|Transformations|Speech|Writing Direction|Layout Orientation],ranges=none
//     M1h synthetic right-click with range 0+5 set and focus: the menu the window shows (enabled items): tracking=[Look Up “alpha”|Translate “alpha”|-|Search With Google|-|(Cut)|Copy|(Paste)|(Paste and Match Style)|-|Share…|-|Font|-|Spelling and Grammar|Substitutions|Transformations|Speech|Writing Direction|Layout Orientation],ranges=0+5
//     M1f CONTROL right-click on a plain Text: menuFor=nil
//     M1g the Edit-menu actions the selection view validates (Cut, Copy, Paste, Select All) with range set + focus: Cut=off/Copy=on/Paste=off/Select All=on,copy:=true,selectAll:=true,cut:=false,paste:=false,validateMenuItem:=true,writeSelectionToPasteboard:types:=true
//   --- S, T: the string changes; a truncated Text
//     S1 range 0+7 set, the string changes to a same-length 'ALPHA BETA GAMMA': before=0+7,after=none sameView=true value='ALPHA BETA GAMMA' resp=AppKitTextInteractionView copyMenu=Copy=on/Select All=on,pb='ALPHA B'
//     S1b to a shorter 'ab' (range now out of bounds): before=0+7,after=none sameView=true value='ab' resp=AppKitTextInteractionView copyMenu=Copy=on/Select All=on,pb=(not run: this ⌘C aborts the process, see S1x)
//     S1c to a longer text with the same prefix: before=0+7,after=none sameView=true value='alpha beta gamma delta epsilon' resp=AppKitTextInteractionView copyMenu=Copy=on/Select All=on,pb='alpha b'
//     S1d to the empty string: before=0+7,after=none sameView=true value='' resp=AppKitTextInteractionView copyMenu=Copy=on/Select All=off,pb=(not run: this ⌘C aborts the process, see S1x)
//     S1e to a shorter 'alpha b' that still covers the range exactly: before=0+7,after=none sameView=true value='alpha b' resp=AppKitTextInteractionView copyMenu=Copy=on/Select All=on,pb='alpha b'
//     S1x the same change as S1b ('ab') WITH the ⌘C, in a child process: exit=6 reason=signal lastLine=(none)
//     S1y the same change as S1d ('') WITH the ⌘C, in a child process: exit=6 reason=signal lastLine=(none)
//     T1 lineLimit(1) at 60 pt: the selection view focused, ⌘A, ⌘C: range=0+35 n=35 pb='alpha beta gamma delta epsilon zeta' axValue='alpha beta gamma delta epsilon zeta'
//     T1b same: the range 0+35 set over the whole string by AX, ⌘C; and the AX visible range: range=0+35 pb='alpha beta gamma delta epsilon zeta' visible=NSRange: {0, 35}
//     T1c synthetic drag from the start across and beyond the right end: ptr=NO-SELECTION(not measurable here),pb='<untouched>'
//   --- G: tap gestures (the tap is a SwiftUI gesture, delivered by the same synthetic events as the link probe's; every click here waits 0.8 s for the system double-click interval)
//     G1 Text.onTapGesture + selectable: synthetic click: views=1 resp=window ptr=NO-SELECTION(not measurable here)
//     G1b same: synthetic drag 45 pt (does the tap fire after a drag): ptr=NO-SELECTION(not measurable here)
//     G1c same: synthetic double click: tap,ptr=NO-SELECTION(not measurable here)
//     G1d same: AX range set + focus; then ⌘C (selection still works under a tap): range=0+5 pb='alpha'
//     G1e order swapped: onTapGesture then .textSelection: click: views=1,resp=window
//     G1f CONTROL no selection: onTapGesture click: tap
//     G2 ancestor onTapGesture, selectable Text inside: click on the text: ptr=NO-SELECTION(not measurable here)
//     G2b same: click on the ancestor off the text (inside its 160 x 60 frame, right of the text): tap
//     G2c same: synthetic drag on the text: ptr=NO-SELECTION(not measurable here)
//     G2d .textSelection on the ANCESTOR with the tap: click on the text: -
//     G2e CONTROL no selection: ancestor tap, click on the text: tap
//     G3 hit-test: which view is hit over a selectable Text, over a plain Text, over a selectable Text with onTapGesture: hit=AppKitTextInteractionView
//   --- L: a link in a selectable Text (re-measures LK13; every click here waits 0.8 s, the link probe waited 0.15 s)
//     L1 click on the link run: pt=ax axLinks=1 views=1,ptr=NO-SELECTION(not measurable here)
//     L1b synthetic drag starting on the link run (25 pt): ptr=NO-SELECTION(not measurable here)
//     L1c synthetic drag from before the link across it: ptr=NO-SELECTION(not measurable here)
//     L1d double-click on the link: open https://x.org,ptr=NO-SELECTION(not measurable here)
//     L1e CONTROL (LK0) without .textSelection: click on the link: open https://x.org
//     L1f click on the text OFF the link (selectable): ptr=NO-SELECTION(not measurable here)
//     L1g the AX link element under a selectable Text: press path: axLinks=1 label='docs here' role=AXLink
//     L1h AX range over the link set (the selection a drag would make), ⌘C: range=4+9 pb='docs here'
//   --- X: accessibility
//     X1 tree before any selection: AXStaticText sub=nil label='nil' value='alpha beta gamma' w=119.0 h=17.0 range={9223372036854775807, 0} text='' n=16,>AXStaticText sub=nil label='nil' value='alpha beta gamma' w=119.0 h=17.0 range=(no accessibilitySelectedTextRange) text='(no accessibilitySelectedText)' n=(no accessibilityNumberOfCharacters)
//     X1b tree after the AX range 0+7 is set and the Text focused: AXStaticText sub=nil label='nil' value='alpha beta gamma' w=119.0 h=17.0 range={0, 7} text='alpha b' n=16,>AXStaticText sub=nil label='nil' value='alpha beta gamma' w=119.0 h=17.0 range=(no accessibilitySelectedTextRange) text='(no accessibilitySelectedText)' n=(no accessibilityNumberOfCharacters)
//     X1c tree after ⌘A on the focused Text: AXStaticText sub=nil label='nil' value='alpha beta gamma' w=119.0 h=17.0 range={0, 16} text='alpha beta gamma' n=16,>AXStaticText sub=nil label='nil' value='alpha beta gamma' w=119.0 h=17.0 range=(no accessibilitySelectedTextRange) text='(no accessibilitySelectedText)' n=(no accessibilityNumberOfCharacters)
//     X1d CONTROL plain Text (no modifier): AXStaticText sub=nil label='nil' value='alpha beta gamma' w=119.0 h=17.0 range=(no accessibilitySelectedTextRange) text='(no accessibilitySelectedText)' n=(no accessibilityNumberOfCharacters)
//     X1e selectors the selectable Text's element answers: accessibilitySelectedText=true,accessibilitySelectedTextRange=true,accessibilityNumberOfCharacters=true,accessibilityVisibleCharacterRange=true,accessibilitySelectedTextRanges=true,setAccessibilitySelectedTextRange:=true,accessibilityStringForRange:=true,accessibilityFrameForRange:=true,accessibilityRangeForLine:=true,accessibilityLineForIndex:=true,attrs=AXRole/AXRoleDescription/AXHelp/AXFocused/AXParent/AXChildren/AXChildrenInNavigationOrder/AXWindow/AXTopLevelUIElement/AXPosition/AXSize
//     X1f the element's string ranges: accessibilityStringForRange (0,5), FrameForRange, RangeForLine(0): string(0,5)='alpha',frame(0,5)=(0.0, 0.0, 0.0, 0.0),rangeForLine(0)={0, 16}
//
// READING (PROXY arms read "given a selection exists"; every ptr=NO-SELECTION arm is a human check, see INSTRUMENT 4).
//   E. EVERY `Text` below `.textSelection(.enabled)` owns a selection view: in a VStack, HStack, Group, ZStack, ScrollView, a
//   `Label`'s title, a styled (`.bold().padding()`) Text, a markdown-link Text, a concatenated `Text + Text` (one view), a List
//   row, a Form row, and a Text in `.overlay` and `.background` (E0, E0e). A `Button`'s label Text gets none (9 views for 10
//   Texts, E0: the button publishes as `AXButton`). An inner `.textSelection(.disabled)` removes the view (E1: 2 of 3); an inner
//   `.enabled` under an outer `.disabled` gives one (E1b). `.disabled(true)` on the Text, `.allowsHitTesting(false)` and
//   `.opacity(0)` leave the view in place (E1c-e): whether a pointer could still select is not measurable.
//   D / A. Copy needs the Text to be first responder: with a range set but the Text not focused, Edit > Copy is off and `⌘C`
//   copies nothing (D1q); focused with no range, Copy is off and Select All on (D1p); with a range, Copy on and `⌘C` puts exactly
//   the range's text on the pasteboard (D1p `'alpha bet'`). `⌘A` with Text A focused selects ALL of A and nothing in B (A1
//   0+12 / none); with nothing focused `⌘A` does nothing (A1b); with B focused it selects B (A1c). D1 D2 D3 and A1d: not measurable.
//   F. The selection view's `acceptsFirstResponder` and `canBecomeKeyView` are true, `needsPanelToBecomeKey` true (F0). It is NOT
//   a Tab stop with Full Keyboard Access off: Tab and Shift-Tab alternate field a / field b exactly as with a plain Text (F2 =
//   F2c), and with only a selectable Text and a Button nothing takes focus (F2b). F1p: a focused field keeps focus when the
//   Text's AX range is set, and `⌘C` copies the FIELD (`'fieldtext'`). F1q: when the Text IS made first responder the field's
//   `@FocusState` goes false (`field=false`) and `⌘C` copies the Text (`'sel'`). Whether a CLICK makes the Text first
//   responder (F1, A1d) is not measurable (the click is swallowed by the same gestures that do not select).
//   C. A Text that stops being first responder loses its selection: another field focused (C2), another Text focused (C3), or
//   the responder cleared (C6) each leave A's AX range at none, and refocusing A does not bring it back (C2b); `⌘C` then copies
//   nothing. CLEARED, not kept inactive. A synthetic click on empty space changes neither the responder nor the range (C1,
//   with the caveat that the Text's own click gesture is not driven); the window really resigning key keeps responder and range
//   (C5b). Two Texts given ranges by AX without a focus move both hold one (C3b). The grey/active colour is not measurable.
//   M. The right-click menu is the full text-editing menu of an `NSTextInteraction`, not a copy menu: with no selection
//   `[(Cut)|(Copy)|(Paste)|(Paste and Match Style)|-|Font|-|Spelling and Grammar|Substitutions|Transformations|Speech|Writing
//   Direction|Layout Orientation]` (parentheses: disabled); with a selection `[Look Up "alpha"|Translate "alpha"|-|Search With
//   Google|-|(Cut)|Copy|(Paste)|(Paste and Match Style)|-|Share...|-|Font|-|...]` (M1b, M1h; the synthetic right-click left the
//   range unchanged, M1d, M1h: whether a real one selects the word is a human check). A declared `.contextMenu { Button("Mine") }`
//   is NOT shown: the text menu replaces it (M1e). A plain Text has no menu at all (M1f). M1g: Cut and Paste are off, Copy and
//   Select All on, in the main Edit menu while the Text is focused with a range.
//   S. When the string changes under a selection the AX range reads none, the view is reused, and `⌘C` still copies the OLD
//   range applied to the NEW string (S1 `'ALPHA B'`, S1c `'alpha b'`), Edit > Copy stays on. A new string at least as long as the
//   old range is safe (S1e). A string SHORTER than the old range ('ab', '') makes `⌘C` abort the whole process (S1x, S1y: exit 6;
//   `NSRangeException` in `attributedSubstringFromRange:` under `-[NSTextInteraction copy:]`): SwiftUI does not drop the selection.
//   T. A truncated `lineLimit(1)` Text selects and copies its WHOLE string, not the visible part: `⌘A` then `⌘C` gives all 35
//   characters; the AX value and number of characters are the whole string; the AX visible range is {0, 35} (T1, T1b).
//   G. Hit testing returns the selection view over a selectable Text even with `onTapGesture` on it (G3). A single synthetic
//   click does NOT fire the Text's own tap (G1, G1e), nor an ancestor's tap when it lands on the text (G2, G2d), even 0.8 s later;
//   the unselectable controls fire (G1f, G2e); an ancestor tap off the text still fires (G2b); a double click fires the Text's
//   tap once (G1c). Whether a real click, as opposed to the synthetic one, fires the tap is a human check.
//   L. LK13 reproduces: a single click on a link run in a selectable Text does not open it, even after 0.8 s (L1); the control opens
//   (L1e); a double click opens once (L1d). The `AXLink` element is still published (L1g). The selection a drag over the link
//   would make, set by AX, copies the link's text (L1h `'docs here'`).
//   X. A selectable Text is one `AXStaticText` that carries the selection attributes (it IS the selection view) with an inner
//   `AXStaticText` child, same value, no selection attributes (X1). Before a selection: `AXSelectedTextRange` {NSNotFound, 0},
//   `AXSelectedText` '', `AXNumberOfCharacters` 16. After AX-set 0+7: {0, 7}, 'alpha b' (X1b); after `⌘A`: {0, 16}, the whole
//   string (X1c). A plain Text publishes none of the three (X1d). The element also answers `accessibilityRangeForLine:`,
//   `accessibilityLineForIndex:`, `accessibilityStringForRange:`; `accessibilityFrameForRange:` answered a zero rect (X1f).
//   The role stays `AXStaticText`; the attribute NAME list is unchanged (X1e).
//

import SwiftUI
import AppKit
import ObjectiveC.runtime

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = super.menu(for: event)
        Log.add("menuFor=" + (m.map { Log.titles($0) } ?? "nil"))
        return m
    }
}

final class FakeApp: NSApplication {
    nonisolated(unsafe) static var current: NSWindow?
    override var isActive: Bool { true }
    override var keyWindow: NSWindow? { FakeApp.current }
    override var mainWindow: NSWindow? { FakeApp.current }
}
final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
    static func titles(_ m: NSMenu) -> String {
        "[" + m.items.map { $0.isSeparatorItem ? "-" : ($0.isEnabled ? $0.title : "(\($0.title))") }.joined(separator: "|") + "]"
    }
}

@MainActor func spin(_ s: Double = 0.15) { pump(s) }

func esc(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") + "'"
}

// MARK: - Window, events

@MainActor func makeWindow<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                      styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let host = FirstMouseHost(rootView: view)
    w.contentView = host
    FakeApp.current = w
    host.layoutSubtreeIfNeeded()
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    spin(0.5)
    return w
}

typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void
let setWindowLocation = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation"), to: SetWindowLocation.self)

/// A mouse event with a CGEvent behind it (AppKit's gesture recognisers ignore events that have none), the window and the
/// window-relative location filled in by hand (`CGEventSetWindowLocation`, field 51), sent through `NSApplication.sendEvent`.
@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint, count: Int = 1) {
    let sp = w.convertPoint(toScreen: p)
    let cgPoint = CGPoint(x: sp.x, y: NSScreen.screens[0].frame.height - sp.y)
    let cgType: CGEventType = [.leftMouseDown: .leftMouseDown, .leftMouseUp: .leftMouseUp, .leftMouseDragged: .leftMouseDragged,
                               .rightMouseDown: .rightMouseDown, .rightMouseUp: .rightMouseUp][t]!
    let btn: CGMouseButton = (t == .rightMouseDown || t == .rightMouseUp) ? .right : .left
    let cg = CGEvent(mouseEventSource: nil, mouseType: cgType, mouseCursorPosition: cgPoint, mouseButton: btn)!
    cg.setIntegerValueField(.mouseEventClickState, value: Int64(count))
    cg.setIntegerValueField(CGEventField(rawValue: 51)!, value: Int64(w.windowNumber))
    setWindowLocation(cg, CGPoint(x: p.x, y: w.frame.height - p.y))
    guard let e = NSEvent(cgEvent: cg) else { Log.add("no-nsevent"); return }
    NSApp.postEvent(e, atStart: false); pump(0.03)
}

@MainActor func pump(_ s: Double) {
    let until = Date().addingTimeInterval(s)
    while let e = NSApp.nextEvent(matching: .any, until: until, inMode: .default, dequeue: true) {
        NSApp.sendEvent(e)
    }
}

nonisolated(unsafe) var settleTime = 0.15

@MainActor func click(_ w: NSWindow, at p: CGPoint, count: Int = 1) {
    for n in 1...count {
        mouse(w, .leftMouseDown, p, count: n); spin(0.03); mouse(w, .leftMouseUp, p, count: n); spin(n == count ? settleTime : 0.03)
    }
}

@MainActor func rightClick(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .rightMouseDown, p); spin(0.05); mouse(w, .rightMouseUp, p); spin()
}

/// Press at `a`, five intermediate drag events, release at `b`.
@MainActor func drag(_ w: NSWindow, _ a: CGPoint, _ b: CGPoint) {
    mouse(w, .leftMouseDown, a); spin(0.05)
    for i in 1...5 {
        let f = CGFloat(i) / 5
        mouse(w, .leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)); spin(0.03)
    }
    mouse(w, .leftMouseUp, b); spin()
}

@MainActor func key(_ w: NSWindow, _ chars: String, code: UInt16, mods: NSEvent.ModifierFlags = []) {
    for t in [NSEvent.EventType.keyDown, .keyUp] {
        let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: mods,
                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                 isARepeat: false, keyCode: code)!
        if mods.contains(.command) { NSApp.sendEvent(e) } else { w.sendEvent(e) }
    }
    spin(0.1)
}
@MainActor func cmdC(_ w: NSWindow) { key(w, "c", code: 8, mods: .command) }
@MainActor func cmdA(_ w: NSWindow) { key(w, "a", code: 0, mods: .command) }
@MainActor func tab(_ w: NSWindow) { key(w, "\t", code: 48) }

// MARK: - Pasteboard, menu, responder

let sentinel = "<untouched>"
func pbClear() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(sentinel, forType: .string) }
func pbRead() -> String { esc(NSPasteboard.general.string(forType: .string) ?? "<nil>") }

nonisolated(unsafe) var editMenu = NSMenu(title: "Edit")
@MainActor func installMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem(); main.addItem(appItem); appItem.submenu = NSMenu(title: "App")
    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); main.addItem(editItem)
    editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
    NSApp.mainMenu = main
}
/// Edit menu item states as validated against the key window's responder chain.
@MainActor func editState() -> String {
    editMenu.update()
    return editMenu.items.filter { $0.title == "Copy" || $0.title == "Select All" }
        .map { "\($0.title)=\($0.isEnabled ? "on" : "off")" }.joined(separator: "/")
}
@MainActor func responder(_ w: NSWindow) -> String {
    guard let r = w.firstResponder else { return "nil" }
    return r === w ? "window" : String(describing: type(of: r))
}

// MARK: - Accessibility

@MainActor func kv(_ o: NSObject, _ k: String) -> String {
    guard o.responds(to: Selector(k)) else { return "(no \(k))" }
    return String(describing: o.value(forKey: k) ?? "nil")
}

@MainActor func axChildren(_ o: NSObject) -> [NSObject] {
    guard o.responds(to: Selector("accessibilityChildren")) else { return [] }
    return ((o.value(forKey: "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject }
}

@MainActor func axAll(_ w: NSWindow, role: String) -> [NSObject] {
    @MainActor func walk(_ o: NSObject) -> [NSObject] {
        var found: [NSObject] = []
        if kv(o, "accessibilityRole") == role { found.append(o) }
        for c in axChildren(o) { found += walk(c) }
        return found
    }
    return walk(w.contentView!)
}
@MainActor func axTexts(_ w: NSWindow) -> [NSObject] { axAll(w, role: "AXStaticText") }

@MainActor func axFrame(_ o: NSObject) -> CGRect {
    (o.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
}
@MainActor func rect(_ w: NSWindow, _ o: NSObject) -> CGRect { w.convertFromScreen(axFrame(o)) }

@MainActor func axSel(_ o: NSObject) -> String {
    "range=\(kv(o, "accessibilitySelectedTextRange").replacingOccurrences(of: "NSRange: ", with: "")) text=\(esc(kv(o, "accessibilitySelectedText"))) n=\(kv(o, "accessibilityNumberOfCharacters"))"
}
/// Selection of the `i`th static text.
@MainActor func sel(_ w: NSWindow, _ i: Int = 0) -> String {
    let t = axTexts(w)
    return i < t.count ? axSel(t[i]) : "no-text\(i)"
}

/// Window-coordinate point on the `n`th visual line (0-based) of a text of line height `lh` at x offset `dx` from the left.
@MainActor func linePoint(_ w: NSWindow, _ i: Int, line n: Int = 0, dx: CGFloat = 1, lh: CGFloat = 17) -> CGPoint? {
    let t = axTexts(w)
    guard i < t.count else { return nil }
    let r = rect(w, t[i])
    return CGPoint(x: r.minX + dx, y: r.maxY - lh * (CGFloat(n) + 0.5))
}
/// Drag over the whole first line of text `i` (to well past its end) and report the pasteboard after ⌘C.
@MainActor func selectLineAndCopy(_ w: NSWindow, _ i: Int) -> String {
    guard let a = linePoint(w, i) else { return "no-text" }
    let r = rect(w, axTexts(w)[i])
    pbClear()
    drag(w, a, CGPoint(x: min(r.maxX + 15, 198), y: a.y))
    cmdC(w)
    return pbRead()
}

nonisolated(unsafe) var keep: AnyObject?
nonisolated(unsafe) var only: String? = nil

@MainActor func arm<V: View>(_ label: String, _ view: V, size: CGFloat = 200, _ act: @MainActor (NSWindow) -> Void) {
    if let only, !(only.hasPrefix("~") ? label == only : label.split(separator: " ")[0].hasPrefix(only)) { return }
    _ = Log.take()
    pbClear()
    let w = makeWindow(view, size: size)
    act(w)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
    w.contentView = nil
}

/// A top-leading text of 14 pt so the geometry is the same in every arm.
struct Subject<V: View>: View {
    let content: V
    var body: some View {
        content.font(.system(size: 14)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

func md(_ s: String) -> AttributedString { try! AttributedString(markdown: s) }

// MARK: - The selection views (SwiftUI's `AppKitTextInteractionView`, one per selectable Text)

@MainActor func ivs(_ w: NSWindow) -> [NSView] {
    var found: [NSView] = []
    func walk(_ v: NSView) {
        if String(describing: type(of: v)) == "AppKitTextInteractionView" { found.append(v) }
        v.subviews.forEach(walk)
    }
    walk(w.contentView!)
    return found.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
}
@MainActor func rng(_ v: NSView) -> String {
    guard let r = (v.value(forKey: "accessibilitySelectedTextRange") as? NSValue)?.rangeValue, r.location != NSNotFound else { return "none" }
    return "\(r.location)+\(r.length)"
}
@MainActor func rngs(_ w: NSWindow) -> String { ivs(w).map(rng).joined(separator: "/") }
@MainActor func val(_ v: NSView) -> String { esc(String(describing: v.value(forKey: "accessibilityValue") ?? "nil")) }
/// What an accessibility client does: set the selection range on the Text's own element.
@MainActor func setSel(_ v: NSView, _ loc: Int, _ len: Int) {
    v.setAccessibilitySelectedTextRange(NSRange(location: loc, length: len)); spin(0.05)
}
@MainActor func focus(_ w: NSWindow, _ v: NSView) -> Bool { let ok = w.makeFirstResponder(v); spin(0.05); return ok }
/// The viewport point (window coordinates) of the first line of the `i`th selection view.
@MainActor func pt(_ w: NSWindow, _ v: NSView, dx: CGFloat = 2, line: Int = 0, lh: CGFloat = 17) -> CGPoint {
    let r = v.convert(v.bounds, to: nil)
    return CGPoint(x: r.minX + dx, y: r.maxY - lh * (CGFloat(line) + 0.5))
}
/// `NOT-MEASURABLE` unless the synthetic pointer left a selection on any view (the instrument's limit, see the header).
@MainActor func ptr(_ w: NSWindow) -> String {
    let r = rngs(w)
    return r.split(separator: "/").contains { $0 != "none" } ? "ptr-selected=\(r)" : "ptr=NO-SELECTION(not measurable here)"
}
/// ⌘C and the pasteboard.
@MainActor func copied(_ w: NSWindow) -> String { pbClear(); cmdC(w); return pbRead() }

// MARK: - Arms

let multi = "aaa bbb ccc ddd eee fff ggg hhh\nzzz yyy"

@MainActor func armE() {
    print("--- E: inheritance and an inner .disabled (a Text is selectable iff it owns an AppKitTextInteractionView; each is focused, given an AX range 0+3, copied with the real ⌘C key)")
    @MainActor func report(_ w: NSWindow) {
        let views = ivs(w)
        let all = axAll(w, role: "AXStaticText").map { kv($0, "accessibilityValue") }
        Log.add("staticTexts=\(Set(all).count) selectionViews=\(views.count)")
        for v in views { setSel(v, 0, 3); _ = focus(w, v); Log.add("\(val(v))->copy \(copied(w))") }
    }
    struct Many: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("t1 direct")
                HStack { Text("t2 hstack") }
                Group { Text("t3 group") }
                ZStack { Text("t4 zstack") }
                ScrollView { Text("t5 scroll") }.frame(height: 22)
                Button(action: {}) { Text("t6 button") }.buttonStyle(.plain)
                Label("t7 label", systemImage: "star")
                Text("t8 styled").bold().padding(2)
                Text(md("t9 [link](https://x.org) md"))
                Text("t10 ") + Text("concat").bold()
            }.textSelection(.enabled)
        }
    }
    arm("E0 .textSelection(.enabled) on a VStack", Subject(content: Many()), size: 320) { w in report(w) }
    arm("E0c CONTROL no modifier", Subject(content: VStack(alignment: .leading) { Text("t1 direct"); HStack { Text("t2 hstack") } }), size: 320) { w in report(w) }
    arm("E0e containers: List row, Form row, a text in .overlay and .background", Subject(content: VStack(alignment: .leading) {
        List { Text("l1 list row") }.frame(height: 60)
        Form { Text("f1 form row") }.frame(height: 60)
        Text("o1 base").overlay(Text("o2 overlay")).background(Text("b1 background"))
    }.textSelection(.enabled)), size: 320) { w in report(w) }
    arm("E1 enabled ancestor, inner .disabled on the middle Text", Subject(content: VStack(alignment: .leading, spacing: 4) {
        Text("outer one"); Text("inner off").textSelection(.disabled); Text("outer two")
    }.textSelection(.enabled))) { w in report(w) }
    arm("E1b disabled ancestor, inner .enabled on the second Text", Subject(content: VStack(alignment: .leading, spacing: 4) {
        Text("outer off"); Text("inner on").textSelection(.enabled)
    }.textSelection(.disabled))) { w in report(w) }
    arm("E1c .enabled on an ancestor, .disabled(true) (the view modifier) on the Text", Subject(content: Text("view-disabled").disabled(true).textSelection(.enabled))) { w in report(w) }
    arm("E1d .enabled with .allowsHitTesting(false) on the Text", Subject(content: Text("no-hit").allowsHitTesting(false).textSelection(.enabled))) { w in report(w) }
    arm("E1e .textSelection(.enabled) on a Text that is then .opacity(0)", Subject(content: Text("hidden").textSelection(.enabled).opacity(0))) { w in report(w) }
}

@MainActor func armD() {
    print("--- D: drag, double click, triple click, select all")
    let one = Subject(content: Text("alpha beta gamma delta").frame(width: 170, alignment: .leading).textSelection(.enabled))
    arm("D1 synthetic drag from the start 59 pt along the line, then ⌘C", one) { w in
        let v = ivs(w)[0]
        drag(w, pt(w, v), CGPoint(x: pt(w, v).x + 59, y: pt(w, v).y)); Log.add(ptr(w)); Log.add("pb=" + copied(w))
    }
    arm("D1p PROXY: AX range 0+9 set, the Text is first responder: Edit>Copy before/after, ⌘C", one) { w in
        let v = ivs(w)[0]; _ = focus(w, v); Log.add("copy(no range)=" + editState())
        setSel(v, 0, 9); Log.add("copy(range)=" + editState() + " range=" + rng(v)); Log.add("pb=" + copied(w))
    }
    arm("D1q PROXY: AX range set but the Text is NOT first responder, ⌘C", one) { w in
        let v = ivs(w)[0]; setSel(v, 0, 9); Log.add("range=" + rng(v) + " resp=" + responder(w) + " copy=" + editState()); Log.add("pb=" + copied(w))
    }
    let m = Subject(content: Text(multi).frame(width: 70, alignment: .leading).textSelection(.enabled))
    arm("D2 synthetic double-click mid-word on visual line 1 of a wrapped text, ⌘C", m) { w in
        let v = ivs(w)[0]; click(w, at: pt(w, v, dx: 8, line: 1), count: 2); Log.add(ptr(w)); Log.add("pb=" + copied(w))
    }
    arm("D3 synthetic triple-click on visual line 1, ⌘C", m) { w in
        let v = ivs(w)[0]; click(w, at: pt(w, v, dx: 8, line: 1), count: 3); Log.add(ptr(w)); Log.add("pb=" + copied(w))
    }
    let ab = Subject(content: VStack(alignment: .leading, spacing: 8) { Text("first text A"); Text("second text B") }.textSelection(.enabled))
    arm("A1 PROXY: A is first responder, ⌘A, ⌘C (the whole of A only?)", ab) { w in
        let v = ivs(w); _ = focus(w, v[0]); Log.add("resp=" + responder(w)); cmdA(w)
        Log.add("ranges=" + rngs(w)); Log.add("pb=" + copied(w)); Log.add("editMenu=" + editState())
    }
    arm("A1b nothing focused: ⌘A, ⌘C", ab) { w in
        cmdA(w); Log.add("ranges=" + rngs(w) + " resp=" + responder(w)); Log.add("pb=" + copied(w))
    }
    arm("A1c B has a range and focus, ⌘A: does A also select", ab) { w in
        let v = ivs(w); setSel(v[1], 0, 3); _ = focus(w, v[1]); cmdA(w); Log.add("ranges=" + rngs(w)); Log.add("pb=" + copied(w))
    }
    arm("A1d synthetic click on A, then ⌘A, ⌘C", ab) { w in
        let v = ivs(w); click(w, at: pt(w, v[0], dx: 5)); Log.add("resp=" + responder(w)); cmdA(w); Log.add("ranges=" + rngs(w)); Log.add("pb=" + copied(w))
    }
}

struct FocusProbe: View {
    @State var text = "fieldtext"
    @FocusState var field: Bool
    @FocusState var other: Bool
    let selectable: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (selectable ? AnyView(Text("sel text one").textSelection(.enabled)) : AnyView(Text("plain text one")))
            TextField("f", text: $text).focused($field).frame(height: 24)
            Color.blue.frame(height: 20).focusable().focused($other)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: field) { _, v in Log.add("field=\(v)") }
        .onChange(of: other) { _, v in Log.add("other=\(v)") }
    }
}

@MainActor func armF() {
    print("--- F: focus")
    let fieldPt = CGPoint(x: 100, y: 200 - 32 - 12)
    arm("F0 the selection view's focus answers", FocusProbe(selectable: true).font(.system(size: 14))) { w in
        let v = ivs(w)[0]
        Log.add("acceptsFirstResponder=\(v.acceptsFirstResponder) canBecomeKeyView=\(v.canBecomeKeyView) needsPanelToBecomeKey=\(v.needsPanelToBecomeKey)")
    }
    arm("F1 synthetic: field focused (click), click the selectable Text: who is first responder, did the field lose @FocusState", FocusProbe(selectable: true).font(.system(size: 14))) { w in
        let v = ivs(w)[0]
        click(w, at: fieldPt); Log.add("|fieldClicked resp=" + responder(w))
        click(w, at: pt(w, v, dx: 5)); Log.add("|textClicked resp=" + responder(w) + " " + ptr(w))
    }
    arm("F1p PROXY: field focused, ⌘A in it; AX range set on the Text (no focus move); ⌘C goes to?", FocusProbe(selectable: true).font(.system(size: 14))) { w in
        let v = ivs(w)[0]
        click(w, at: fieldPt); cmdA(w); Log.add("|field focused resp=" + responder(w))
        setSel(v, 0, 3); Log.add("|axSet resp=" + responder(w)); Log.add("pb=" + copied(w))
    }
    arm("F1q PROXY: same, then the Text becomes first responder (what a click would do if it takes focus): field=false? ⌘C?", FocusProbe(selectable: true).font(.system(size: 14))) { w in
        let v = ivs(w)[0]
        click(w, at: fieldPt); cmdA(w); setSel(v, 0, 3); Log.add("|focusing text")
        _ = focus(w, v); Log.add("resp=" + responder(w)); Log.add("pb=" + copied(w))
    }
    arm("F1c CONTROL plain Text: field focused, click the Text: who is first responder", FocusProbe(selectable: false).font(.system(size: 14))) { w in
        click(w, at: fieldPt); Log.add("|fieldClicked resp=" + responder(w))
        click(w, at: CGPoint(x: 5, y: 191)); Log.add("|textClicked resp=" + responder(w))
    }
    Log.add("fullKeyboardAccess=\(NSApp.isFullKeyboardAccessEnabled)"); _ = Log.take()
    for (name, selectable) in [("F2 Tab x4 / Shift-Tab x4 from the initial focus: [selectable Text, TextField a, TextField b]", true),
                               ("F2c CONTROL the same with a plain Text", false)] {
        arm(name, TwoFields(selectable: selectable).font(.system(size: 14))) { w in
            Log.add("fka=\(NSApp.isFullKeyboardAccessEnabled) start resp=" + responder(w) + " a=\(TwoFields.state.a) b=\(TwoFields.state.b)")
            for i in 1...4 { tab(w); Log.add("|tab\(i) resp=" + responder(w) + " a=\(TwoFields.state.a) b=\(TwoFields.state.b)") }
            for i in 1...4 { key(w, "\u{19}", code: 48, mods: .shift); Log.add("|btab\(i) resp=" + responder(w) + " a=\(TwoFields.state.a) b=\(TwoFields.state.b)") }
        }
    }
    arm("F2b Tab x3 with a selectable Text and a Button only (nothing else focusable)", Subject(content: VStack(alignment: .leading) {
        Text("only selectable").textSelection(.enabled); Button("btn") {}
    })) { w in
        for i in 1...3 { tab(w); Log.add("tab\(i) resp=" + responder(w)) }
        Log.add("nextValidKeyView=\(String(describing: ivs(w)[0].nextValidKeyView.map { type(of: $0) })) previousValidKeyView=\(String(describing: ivs(w)[0].previousValidKeyView.map { type(of: $0) }))")
    }
}

struct TwoFields: View {
    nonisolated(unsafe) static var state = (a: false, b: false)
    @State var ta = "aaa"
    @State var tb = "bbb"
    @FocusState var a: Bool
    @FocusState var b: Bool
    let selectable: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (selectable ? AnyView(Text("sel text one").textSelection(.enabled)) : AnyView(Text("plain text one")))
            TextField("a", text: $ta).focused($a).frame(height: 24)
            TextField("b", text: $tb).focused($b).frame(height: 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: a) { _, v in TwoFields.state.a = v }
        .onChange(of: b) { _, v in TwoFields.state.b = v }
    }
}

struct ClearProbe: View {
    @State var text = ""
    @FocusState var field: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("text A first").textSelection(.enabled)
            Text("text B second").textSelection(.enabled)
            TextField("f", text: $text).focused($field).frame(height: 24)
            Spacer()
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: field) { _, v in Log.add("field=\(v)") }
    }
}

@MainActor func armC() {
    print("--- C: what a click elsewhere does to a selection (the selection is SET by the accessibility API and the Text focused: the pointer cannot select here)")
    func selectA(_ w: NSWindow) -> NSView { let v = ivs(w)[0]; setSel(v, 0, 7); _ = focus(w, v); return v }
    arm("C0 baseline: A has range 0+7 and focus; ⌘C", ClearProbe().font(.system(size: 14))) { w in
        let v = selectA(w); Log.add("range=" + rng(v) + " pb=" + copied(w))
    }
    arm("C1 synthetic click on empty space (bottom), then ⌘C", ClearProbe().font(.system(size: 14))) { w in
        let v = selectA(w); click(w, at: CGPoint(x: 150, y: 10)); Log.add("resp=" + responder(w) + " A=" + rng(v)); Log.add("pb=" + copied(w))
    }
    arm("C2 synthetic click on the TextField, then ⌘C (the field has no selection)", ClearProbe().font(.system(size: 14))) { w in
        let v = selectA(w); click(w, at: CGPoint(x: 100, y: 200 - 4 - 17 * 2 - 16 - 12)); Log.add("resp=" + responder(w) + " A=" + rng(v)); Log.add("pb=" + copied(w))
    }
    arm("C2b the same, then click back into the Text's frame: is A's range still there", ClearProbe().font(.system(size: 14))) { w in
        let v = selectA(w); click(w, at: CGPoint(x: 100, y: 200 - 4 - 17 * 2 - 16 - 12))
        _ = focus(w, v); Log.add("refocused A=" + rng(v)); Log.add("pb=" + copied(w))
    }
    arm("C3 PROXY: B becomes first responder (what a click on B would do): A's range, B's range, ⌘C", ClearProbe().font(.system(size: 14))) { w in
        let a = selectA(w); let b = ivs(w)[1]; _ = focus(w, b)
        Log.add("A=" + rng(a) + " B=" + rng(b) + " resp=" + responder(w)); Log.add("pb=" + copied(w))
    }
    arm("C3b both A and B given ranges (A first, then B, by AX): is A's kept", ClearProbe().font(.system(size: 14))) { w in
        let a = selectA(w); let b = ivs(w)[1]; setSel(b, 0, 4)
        Log.add("A=" + rng(a) + " B=" + rng(b))
    }
    arm("C5 the window resigns key (didResignKey posted, and the window made non-key), A's range, ⌘C", ClearProbe().font(.system(size: 14))) { w in
        let v = selectA(w); NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: w); spin(0.1)
        Log.add("A=" + rng(v)); Log.add("pb=" + copied(w))
    }
    arm("C5b the window really resigns key (NSWindow.resignKey()), A's range, ⌘C", ClearProbe().font(.system(size: 14))) { w in
        let v = selectA(w); w.resignKey(); spin(0.1)
        Log.add("resp=" + responder(w) + " A=" + rng(v)); Log.add("pb=" + copied(w))
    }
    arm("C6 the first responder is cleared (makeFirstResponder(nil)) while A has a range", ClearProbe().font(.system(size: 14))) { w in
        let v = selectA(w); _ = w.makeFirstResponder(nil); spin(0.1); Log.add("resp=" + responder(w) + " A=" + rng(v)); Log.add("pb=" + copied(w))
    }
}

nonisolated(unsafe) var menuObserver: NSObjectProtocol?
@MainActor func armM() {
    print("--- M: right-click")
    menuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { n in
        if let m = n.object as? NSMenu {
            m.update(); Log.add("tracking=" + Log.titles(m))
            RunLoop.main.add(Timer(timeInterval: 0.2, repeats: false) { _ in m.cancelTracking() }, forMode: .eventTracking)
        }
    }
    let t = Subject(content: Text("alpha beta gamma").textSelection(.enabled))
    func menuFor(_ w: NSWindow, _ v: NSView, _ p: CGPoint) -> String {
        let e = NSEvent.mouseEvent(with: .rightMouseDown, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        return v.menu(for: e).map { Log.titles($0) } ?? "nil"
    }
    arm("M1 menu(for:) of the selection view, nothing selected", t) { w in
        let v = ivs(w)[0]; _ = focus(w, v); Log.add(menuFor(w, v, pt(w, v, dx: 40)))
    }
    arm("M1b menu(for:), range 0+5 set", t) { w in
        let v = ivs(w)[0]; _ = focus(w, v); setSel(v, 0, 5); Log.add(menuFor(w, v, pt(w, v, dx: 40)))
    }
    arm("M1c menu(for:), range set, the Text NOT first responder", t) { w in
        let v = ivs(w)[0]; setSel(v, 0, 5); Log.add(menuFor(w, v, pt(w, v, dx: 40)))
    }
    arm("M1d synthetic right-click on a word (nothing selected): the menu the window shows, then ranges", t) { w in
        let v = ivs(w)[0]; rightClick(w, at: pt(w, v, dx: 40)); Log.add("ranges=" + rngs(w))
    }
    arm("M1e right-click, Text with .contextMenu { Button(\"Mine\") } + selectable", Subject(content: Text("alpha beta gamma").textSelection(.enabled).contextMenu { Button("Mine") {} })) { w in
        let v = ivs(w)[0]; Log.add("views=\(ivs(w).count)"); rightClick(w, at: pt(w, v, dx: 40)); Log.add("ranges=" + rngs(w))
    }
    arm("M1h synthetic right-click with range 0+5 set and focus: the menu the window shows (enabled items)", t) { w in
        let v = ivs(w)[0]; _ = focus(w, v); setSel(v, 0, 5); rightClick(w, at: pt(w, v, dx: 20)); Log.add("ranges=" + rngs(w))
    }
    arm("M1f CONTROL right-click on a plain Text", Subject(content: Text("alpha beta gamma"))) { w in
        rightClick(w, at: CGPoint(x: 40, y: 191))
    }
    arm("M1g the Edit-menu actions the selection view validates (Cut, Copy, Paste, Select All) with range set + focus", t) { w in
        let v = ivs(w)[0]; _ = focus(w, v); setSel(v, 0, 5)
        editMenu.update(); Log.add(editMenu.items.map { "\($0.title)=\($0.isEnabled ? "on" : "off")" }.joined(separator: "/"))
        for sel in ["copy:", "selectAll:", "cut:", "paste:", "validateMenuItem:", "writeSelectionToPasteboard:types:"] { Log.add("\(sel)=\(v.responds(to: Selector(sel)))") }
    }
}

final class Model: ObservableObject { @Published var s = "alpha beta gamma" }
nonisolated(unsafe) let model = Model()
struct Changing: View {
    @ObservedObject var m: Model
    var body: some View { Text(m.s).textSelection(.enabled) }
}

@MainActor func armST() {
    print("--- S, T: the string changes; a truncated Text")
    func changeArm(_ label: String, to s: String, copy: Bool = true) {
        arm(label, Subject(content: Changing(m: model))) { w in
            model.s = "alpha beta gamma"; spin(0.2)
            let v = ivs(w)[0]; setSel(v, 0, 7); _ = focus(w, v); Log.add("before=" + rng(v))
            model.s = s; spin(0.3)
            let v2 = ivs(w)
            Log.add("after=" + (v2.first.map(rng) ?? "no-view") + " sameView=\(v2.first === v) value=" + (v2.first.map(val) ?? "-") + " resp=" + responder(w) + " copyMenu=" + editState())
            if copy { Log.add("pb=" + copied(w)) } else { Log.add("pb=(not run: this ⌘C aborts the process, see S1x)") }
        }
    }
    changeArm("S1 range 0+7 set, the string changes to a same-length 'ALPHA BETA GAMMA'", to: "ALPHA BETA GAMMA")
    changeArm("S1b to a shorter 'ab' (range now out of bounds)", to: "ab", copy: false)
    changeArm("S1c to a longer text with the same prefix", to: "alpha beta gamma delta epsilon")
    changeArm("S1d to the empty string", to: "", copy: false)
    changeArm("S1e to a shorter 'alpha b' that still covers the range exactly", to: "alpha b")
    if only == "~S1x" || only == "~S1y" {
        // Hidden arms: the ⌘C after a shrinking change, run as a child process by S1x / S1y below.
        changeArm("~S1x", to: "ab")
        changeArm("~S1y", to: "")
    }
    for (id, child) in [("S1x", "~S1x"), ("S1y", "~S1y")] where only == nil || only == "S1x" || only == "S1y" {
        let p = Process(); p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); p.arguments = [child]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = out.split(separator: "\n").filter { $0.contains("pb=") || $0.contains("after=") }.map { String($0.suffix(120)) }
        print("  \(id) the same change as \(id == "S1x" ? "S1b ('ab')" : "S1d ('')") WITH the ⌘C, in a child process: exit=\(p.terminationStatus) reason=\(p.terminationReason == .uncaughtSignal ? "signal" : "exit") lastLine=\(lines.last ?? "(none)")")
    }
    let long = Subject(content: Text("alpha beta gamma delta epsilon zeta").lineLimit(1).frame(width: 60, alignment: .leading).textSelection(.enabled))
    arm("T1 lineLimit(1) at 60 pt: the selection view focused, ⌘A, ⌘C", long) { w in
        let v = ivs(w)[0]; _ = focus(w, v); cmdA(w)
        Log.add("range=" + rng(v) + " n=" + kv(axTexts(w)[0], "accessibilityNumberOfCharacters") + " pb=" + copied(w) + " axValue=" + val(v))
    }
    arm("T1b same: the range 0+35 set over the whole string by AX, ⌘C; and the AX visible range", long) { w in
        let v = ivs(w)[0]; _ = focus(w, v); setSel(v, 0, 35); Log.add("range=" + rng(v) + " pb=" + copied(w) + " visible=" + kv(v, "accessibilityVisibleCharacterRange"))
    }
    arm("T1c synthetic drag from the start across and beyond the right end", long) { w in
        let v = ivs(w)[0]; drag(w, pt(w, v, dx: 1), CGPoint(x: 190, y: pt(w, v).y)); Log.add(ptr(w)); Log.add("pb=" + copied(w))
    }
}

@MainActor func armG() {
    print("--- G: tap gestures (the tap is a SwiftUI gesture, delivered by the same synthetic events as the link probe's; every click here waits 0.8 s for the system double-click interval)")
    settleTime = 0.8; defer { settleTime = 0.15 }
    let own = Subject(content: Text("alpha beta gamma").textSelection(.enabled).onTapGesture { Log.add("tap") })
    arm("G1 Text.onTapGesture + selectable: synthetic click", own) { w in
        click(w, at: pt(w, ivs(w)[0], dx: 20)); Log.add("views=\(ivs(w).count) resp=" + responder(w) + " " + ptr(w))
    }
    arm("G1b same: synthetic drag 45 pt (does the tap fire after a drag)", own) { w in
        let v = ivs(w)[0]; drag(w, pt(w, v), CGPoint(x: pt(w, v).x + 45, y: pt(w, v).y)); Log.add(ptr(w))
    }
    arm("G1c same: synthetic double click", own) { w in click(w, at: pt(w, ivs(w)[0], dx: 20), count: 2); Log.add(ptr(w)) }
    arm("G1d same: AX range set + focus; then ⌘C (selection still works under a tap)", own) { w in
        let v = ivs(w)[0]; _ = focus(w, v); setSel(v, 0, 5); Log.add("range=" + rng(v) + " pb=" + copied(w))
    }
    arm("G1e order swapped: onTapGesture then .textSelection: click", Subject(content: Text("alpha beta gamma").onTapGesture { Log.add("tap") }.textSelection(.enabled))) { w in
        Log.add("views=\(ivs(w).count)"); click(w, at: CGPoint(x: 22, y: 191)); Log.add("resp=" + responder(w))
    }
    arm("G1f CONTROL no selection: onTapGesture click", Subject(content: Text("alpha beta gamma").onTapGesture { Log.add("tap") })) { w in
        click(w, at: CGPoint(x: 22, y: 191))
    }
    let anc = Subject(content: VStack(alignment: .leading) { Text("alpha beta gamma").textSelection(.enabled) }
        .frame(width: 160, height: 60, alignment: .topLeading).contentShape(Rectangle()).onTapGesture { Log.add("tap") })
    arm("G2 ancestor onTapGesture, selectable Text inside: click on the text", anc) { w in
        click(w, at: pt(w, ivs(w)[0], dx: 20)); Log.add(ptr(w))
    }
    arm("G2b same: click on the ancestor off the text (inside its 160 x 60 frame, right of the text)", anc) { w in click(w, at: CGPoint(x: 150, y: 190)) }
    arm("G2c same: synthetic drag on the text", anc) { w in
        let v = ivs(w)[0]; drag(w, pt(w, v), CGPoint(x: pt(w, v).x + 45, y: pt(w, v).y)); Log.add(ptr(w))
    }
    arm("G2d .textSelection on the ANCESTOR with the tap: click on the text", Subject(content: VStack(alignment: .leading) { Text("alpha beta gamma") }
        .frame(width: 160, height: 60, alignment: .topLeading).contentShape(Rectangle()).onTapGesture { Log.add("tap") }.textSelection(.enabled))) { w in
        click(w, at: pt(w, ivs(w)[0], dx: 20))
    }
    arm("G2e CONTROL no selection: ancestor tap, click on the text", Subject(content: VStack(alignment: .leading) { Text("alpha beta gamma") }
        .frame(width: 160, height: 60, alignment: .topLeading).contentShape(Rectangle()).onTapGesture { Log.add("tap") })) { w in
        click(w, at: CGPoint(x: 22, y: 191))
    }
    arm("G3 hit-test: which view is hit over a selectable Text, over a plain Text, over a selectable Text with onTapGesture", own) { w in
        let host = w.contentView!; let p = pt(w, ivs(w)[0], dx: 20)
        Log.add("hit=" + (host.hitTest(host.superview!.convert(p, from: nil)).map { "\(type(of: $0))" } ?? "nil"))
    }
}

@MainActor func armL() {
    print("--- L: a link in a selectable Text (re-measures LK13; every click here waits 0.8 s, the link probe waited 0.15 s)")
    settleTime = 0.8; defer { settleTime = 0.15 }
    let logging = OpenURLAction { url in Log.add("open \(url.absoluteString)"); return .handled }
    let md1 = "see [docs here](https://x.org) now"
    let t = Subject(content: Text(md(md1)).textSelection(.enabled).environment(\.openURL, logging))
    func linkPt(_ w: NSWindow) -> (CGPoint, String) {
        if let l = axAll(w, role: "AXLink").first { let r = rect(w, l); return (CGPoint(x: r.midX, y: r.midY), "ax") }
        return (pt(w, ivs(w)[0], dx: 50), "guess(no AXLink)")
    }
    arm("L1 click on the link run", t) { w in
        let (p, how) = linkPt(w); Log.add("pt=\(how) axLinks=\(axAll(w, role: "AXLink").count) views=\(ivs(w).count)")
        click(w, at: p); Log.add(ptr(w))
    }
    arm("L1b synthetic drag starting on the link run (25 pt)", t) { w in
        let (p, _) = linkPt(w); drag(w, CGPoint(x: p.x - 15, y: p.y), CGPoint(x: p.x + 10, y: p.y)); Log.add(ptr(w))
    }
    arm("L1c synthetic drag from before the link across it", t) { w in
        let v = ivs(w)[0]; drag(w, pt(w, v), CGPoint(x: pt(w, v).x + 120, y: pt(w, v).y)); Log.add(ptr(w))
    }
    arm("L1d double-click on the link", t) { w in let (p, _) = linkPt(w); click(w, at: p, count: 2); Log.add(ptr(w)) }
    arm("L1e CONTROL (LK0) without .textSelection: click on the link", Subject(content: Text(md(md1)).environment(\.openURL, logging))) { w in
        let (p, _) = linkPt(w); click(w, at: p)
    }
    arm("L1f click on the text OFF the link (selectable)", t) { w in click(w, at: pt(w, ivs(w)[0], dx: 5)); Log.add(ptr(w)) }
    arm("L1g the AX link element under a selectable Text: press path", t) { w in
        let links = axAll(w, role: "AXLink")
        Log.add("axLinks=\(links.count)" + (links.first.map { " label=" + esc(kv($0, "accessibilityLabel")) + " role=" + kv($0, "accessibilityRole") } ?? ""))
    }
    arm("L1h AX range over the link set (the selection a drag would make), ⌘C", t) { w in
        let v = ivs(w)[0]; _ = focus(w, v); setSel(v, 4, 9); Log.add("range=" + rng(v) + " pb=" + copied(w))
    }
}

@MainActor func armX() {
    print("--- X: accessibility")
    @MainActor func dump(_ w: NSWindow) {
        func walk(_ o: NSObject, _ d: Int) {
            let r = rect(w, o)
            Log.add("\(String(repeating: ">", count: d))\(kv(o, "accessibilityRole")) sub=\(kv(o, "accessibilitySubrole")) label=\(esc(kv(o, "accessibilityLabel"))) value=\(esc(kv(o, "accessibilityValue"))) w=\(r.width.rounded()) h=\(r.height.rounded()) \(axSel(o))")
            for c in axChildren(o) { walk(c, d + 1) }
        }
        for c in axChildren(w.contentView!) { walk(c, 0) }
    }
    let t = Subject(content: Text("alpha beta gamma").textSelection(.enabled))
    arm("X1 tree before any selection", t) { w in dump(w) }
    arm("X1b tree after the AX range 0+7 is set and the Text focused", t) { w in
        let v = ivs(w)[0]; _ = focus(w, v); setSel(v, 0, 7); dump(w)
    }
    arm("X1c tree after ⌘A on the focused Text", t) { w in let v = ivs(w)[0]; _ = focus(w, v); cmdA(w); dump(w) }
    arm("X1d CONTROL plain Text (no modifier)", Subject(content: Text("alpha beta gamma"))) { w in dump(w) }
    arm("X1e selectors the selectable Text's element answers", t) { w in
        guard let e = axTexts(w).first else { Log.add("no-text"); return }
        for s in ["accessibilitySelectedText", "accessibilitySelectedTextRange", "accessibilityNumberOfCharacters", "accessibilityVisibleCharacterRange",
                  "accessibilitySelectedTextRanges", "setAccessibilitySelectedTextRange:", "accessibilityStringForRange:", "accessibilityFrameForRange:", "accessibilityRangeForLine:", "accessibilityLineForIndex:"] {
            Log.add("\(s)=\(e.responds(to: Selector(s)))")
        }
        Log.add("attrs=" + e.accessibilityAttributeNames().map { $0.rawValue }.joined(separator: "/"))
    }
    arm("X1f the element's string ranges: accessibilityStringForRange (0,5), FrameForRange, RangeForLine(0)", t) { w in
        let v = ivs(w)[0]
        let s = v.accessibilityString(for: NSRange(location: 0, length: 5)); Log.add("string(0,5)=" + esc(s ?? "nil"))
        let f = v.accessibilityFrame(for: NSRange(location: 0, length: 5)); Log.add("frame(0,5)=\(f)")
        Log.add("rangeForLine(0)=\(v.accessibilityRange(forLine: 0))")
    }
}

setbuf(stdout, nil)
MainActor.assumeIsolated {
    let app = FakeApp.shared
    app.setActivationPolicy(.regular)
    installMenu()
    NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    NSApp.accessibilitySetValue(true as NSNumber, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
    if CommandLine.arguments.count > 1 { only = CommandLine.arguments[1] }
    armE(); armD(); armF(); armC(); armM(); armST(); armG(); armL(); armX()
}
