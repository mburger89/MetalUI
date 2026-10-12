import Testing
import MetalUIPlatform
@testable import MetalUI

// SL-A…SL-J: `TextSelection` and the pure half of the field's two-way
// selection (spec 4.1–4.9). The end-to-end arms live in
// `MetalUITestingTests/HarnessTextSelectionTests.swift`.

private func whole(_ text: String) -> TextSelection { TextSelection(range: text.startIndex..<text.endIndex) }

private func at(_ offset: Int, in text: String) -> TextSelection {
    TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset))
}

private func range(_ lower: Int, _ upper: Int, in text: String) -> TextSelection {
    TextSelection(range: text.index(text.startIndex, offsetBy: lower)..<text.index(text.startIndex, offsetBy: upper))
}

private func state(_ anchor: Int, _ head: Int) -> TextEditState {
    var s = TextEditState()
    s.anchor = anchor
    s.head = head
    return s
}

@Test func aTextSelectionHasSwiftUIsThreeShapes() throws {
    let text = "hello"
    let r = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 3)
    let ranged = TextSelection(range: r)
    #expect(ranged.indices == .selection(r))
    #expect(!ranged.isInsertion)
    let point = TextSelection(insertionPoint: r.lowerBound)
    #expect(point.indices == .selection(r.lowerBound..<r.lowerBound))
    #expect(point.isInsertion)
    var set = RangeSet<String.Index>()
    set.insert(contentsOf: r)
    let multi = TextSelection(ranges: set)
    #expect(multi.indices == .multiSelection(set))
    #expect(!multi.isInsertion)
    #expect(ranged == TextSelection(range: r))
    #expect(ranged != point)
    #expect(Set([ranged, ranged, point]).count == 2)
}

@Test func offsetsClampAndRoundDownToACharacterBoundary() throws {
    let text = "ab"
    let longer = "abcdefgh"
    let far = TextSelection(range: longer.index(longer.startIndex, offsetBy: 5)..<longer.endIndex)
    #expect(TextSelection.offsets(of: far, in: text) == 2..<2)
    #expect(TextSelection.offsets(of: whole(longer), in: text) == 0..<2)
    // A UTF-16 index inside a family emoji reads as the Character's start.
    let family = "a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}b"
    let inside = String.Index(utf16Offset: 3, in: family)
    #expect(TextSelection.offsets(of: TextSelection(insertionPoint: inside), in: family) == 1..<1)
    #expect(TextSelection.offsets(of: whole(family), in: family) == 0..<3)
    // Empty text.
    #expect(TextSelection.offsets(of: whole(""), in: "") == 0..<0)
    #expect(TextSelection.offsets(of: far, in: "") == 0..<0)
}

@Test func aMultiSelectionActsOnItsFirstRange() throws {
    let text = "abcdef"
    var set = RangeSet<String.Index>()
    set.insert(contentsOf: text.index(text.startIndex, offsetBy: 3)..<text.index(text.startIndex, offsetBy: 4))
    set.insert(contentsOf: text.startIndex..<text.index(text.startIndex, offsetBy: 1))
    #expect(TextSelection.offsets(of: TextSelection(ranges: set), in: text) == 0..<1)
    #expect(TextSelection.offsets(of: TextSelection(ranges: RangeSet<String.Index>()), in: text) == nil)
}

@Test func aRangeBecomesAnInsertionPointWhenEmptyAndASelectionOtherwise() {
    let text = "hello"
    let point = TextSelection(offsets: 2..<2, in: text)
    #expect(point.isInsertion)
    #expect(point == at(2, in: text))
    let span = TextSelection(offsets: 1..<4, in: text)
    #expect(!span.isInsertion)
    #expect(span == range(1, 4, in: text))
    // Offsets past the end clamp.
    #expect(TextSelection(offsets: 3..<99, in: text) == range(3, 5, in: text))
}

@Test func reconcileAppliesAValueTheFieldDidNotPublish() {
    let text = "hello"
    var s = state(0, 0)
    s.history.openGroup = .typing
    s.goalX = 4
    s.revealsCaret = false
    let value = range(1, 4, in: text)
    #expect(TextEditing.reconcile(binding: value, text: text, state: &s))
    #expect(s.anchor == 1 && s.head == 4)
    #expect(s.reported == 1..<4)
    #expect(s.seenBinding == value)
    #expect(s.history.openGroup == nil)
    #expect(s.goalX == nil)
    #expect(s.revealsCaret)
    // The same value again is not an instruction: moving away is kept.
    s.anchor = 2; s.head = 2
    #expect(!TextEditing.reconcile(binding: value, text: text, state: &s))
    #expect(s.anchor == 2 && s.head == 2)
    // A different value is.
    #expect(TextEditing.reconcile(binding: at(5, in: text), text: text, state: &s))
    #expect(s.anchor == 5 && s.head == 5)
}

@Test func reconcileIgnoresNilAndForgetsTheSeenValue() {
    let text = "hello"
    var s = state(0, 0)
    let value = range(1, 3, in: text)
    #expect(TextEditing.reconcile(binding: value, text: text, state: &s))
    s.anchor = 4; s.head = 4
    #expect(!TextEditing.reconcile(binding: nil, text: text, state: &s))
    #expect(s.anchor == 4 && s.head == 4)
    #expect(s.seenBinding == nil)
    // The earlier value written again applies again.
    #expect(TextEditing.reconcile(binding: value, text: text, state: &s))
    #expect(s.anchor == 1 && s.head == 3)
}

@Test func reconcileIsHeldBackWhileComposing() {
    let text = "hello"
    var s = state(2, 2)
    s.composition = TextComposition(text: "に", selection: 1..<1)
    let before = s
    #expect(!TextEditing.reconcile(binding: whole(text), text: text, state: &s))
    #expect(s == before)
    #expect(s.seenBinding == nil)
    // After the commit the held value applies.
    s.composition = .none
    #expect(TextEditing.reconcile(binding: whole(text), text: text, state: &s))
    #expect(s.anchor == 0 && s.head == 5)
}

@Test func reconcileNeverTouchesTheUndoStacks() {
    let text = "hello"
    var s = state(5, 5)
    s.history.undo = [.init(text: "hell", anchor: 4, head: 4)]
    s.history.redo = [.init(text: "hellox", anchor: 6, head: 6)]
    s.history.lastText = text
    s.history.openGroup = .typing
    let history = s.history
    #expect(TextEditing.reconcile(binding: at(1, in: text), text: text, state: &s))
    #expect(s.history.undo == history.undo)
    #expect(s.history.redo == history.redo)
    #expect(s.history.lastText == history.lastText)
    #expect(s.history.openGroup == nil)
}

@Test func publicationIsNilWhenNothingChangedOrWhileComposing() {
    let text = "hello"
    var s = state(1, 3)
    s.reported = 1..<3
    #expect(TextEditing.publication(state: s, text: text) == nil)
    s.head = 4
    #expect(TextEditing.publication(state: s, text: text) == 1..<4)
    // Backward selections publish their ordered range.
    s.anchor = 4; s.head = 1
    #expect(TextEditing.publication(state: s, text: text) == 1..<4)
    s.composition = TextComposition(text: "に", selection: 1..<1)
    #expect(TextEditing.publication(state: s, text: text) == nil)
    // Clamped to the text.
    s.composition = .none
    s.anchor = 9; s.head = 9
    #expect(TextEditing.publication(state: s, text: text) == 5..<5)
}
