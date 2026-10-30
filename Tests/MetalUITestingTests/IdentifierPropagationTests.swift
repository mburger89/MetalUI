import MetalUI
import MetalUITesting
import Testing

// `DA-`: an accessibility identifier on a container never replaces a descendant's own, the
// container's stays findable, and a wrapper modifier written between the element and
// `.accessibilityIdentifier` does not lose it. Plain imports, as an app spells them.

private struct Screen: Component {
    let contain: Bool
    var content: some ElementGroup {
        if contain {
            VStack {
                Text("a").accessibilityIdentifier("a")
                Button("b") {}.accessibilityIdentifier("b")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen")
        } else {
            VStack {
                Text("a").accessibilityIdentifier("a")
                Button("b") {}.accessibilityIdentifier("b")
            }
            .accessibilityIdentifier("screen")
        }
    }
}

/// DA-A (refuted rule, aligned behaviour). Probe `swiftui-accessibility-identifier-nesting.swift`
/// X2: with `.accessibilityElement(children: .contain)` the container is one group with the
/// identifier and its children keep their own. Mutation DA-M8 (`ProposalElementGroup.accessibilityElement(children:)`
/// no longer writes `childBehavior`) reddens it.
@Test @MainActor func aContainedContainerIsAGroupWhoseChildrenKeepTheirIdentifiers() throws {
    let window = try harnessWindow { VStack { Screen(contain: true) } }
    let screen = try window.element(identifier: "screen")
    #expect(screen.role == AccessibilityRole.group)
    let a = try window.element(identifier: "a")
    let b = try window.element(identifier: "b")
    #expect(screen.children == [a.id, b.id])
    #expect(a.role == AccessibilityRole.staticText)
    #expect(b.role == AccessibilityRole.button)
}

/// DA-A. Probe X1, X3: without `.contain` SwiftUI overwrites, so does MetalUI (`IX-W` item 2,
/// N5): both children read "screen" and no element is "a" or "b". Mutation DA-M9
/// (distribution skips nodes that have an identifier) reddens it.
@Test @MainActor func withoutContainTheContainerIdentifierOverwritesTheChildrenAsInSwiftUI() throws {
    let window = try harnessWindow { VStack { Screen(contain: false) } }
    let identified = try window.elements(where: { $0.identifier == "screen" })
    #expect(identified.count == 2)
    #expect(Set(identified.map(\.role)) == [AccessibilityRole.staticText, AccessibilityRole.button])
    #expect(throws: (any Error).self) { try window.element(identifier: "a") }
    #expect(throws: (any Error).self) { try window.element(identifier: "b") }
}

/// The wrappers written between an element and `.accessibilityIdentifier`.
private enum Wrapper: String, CaseIterable, Sendable {
    case disabled, opacity, help, onHover, contextMenu, padding, frame, background
    case clipped, allowsHitTesting, shadow, blur, onTapGesture, onAppear, task, focusable, id
}

/// `Button` and `Text` under one wrapper, the identifier written AFTER it.
private struct Wrapped: Component {
    let wrapper: Wrapper
    var content: some ElementGroup {
        VStack {
            switch wrapper {
            case .disabled: Rectangle().fill(Color.red).frame(width: 40, height: 20).disabled(true).accessibilityIdentifier("x")
            case .opacity: Rectangle().fill(Color.red).frame(width: 40, height: 20).opacity(0.5).accessibilityIdentifier("x")
            case .help: Rectangle().fill(Color.red).frame(width: 40, height: 20).help("tip").accessibilityIdentifier("x")
            case .onHover: Rectangle().fill(Color.red).frame(width: 40, height: 20).onHover { _ in }.accessibilityIdentifier("x")
            case .contextMenu: Rectangle().fill(Color.red).frame(width: 40, height: 20).contextMenu { Button("m") {} }.accessibilityIdentifier("x")
            case .padding: Rectangle().fill(Color.red).frame(width: 40, height: 20).padding(4).accessibilityIdentifier("x")
            case .frame: Rectangle().fill(Color.red).frame(width: 40, height: 20).frame(width: 80, height: 30).accessibilityIdentifier("x")
            case .background: Rectangle().fill(Color.red).frame(width: 40, height: 20).background(Color.red).accessibilityIdentifier("x")
            case .clipped: Rectangle().fill(Color.red).frame(width: 40, height: 20).clipped().accessibilityIdentifier("x")
            case .allowsHitTesting: Rectangle().fill(Color.red).frame(width: 40, height: 20).allowsHitTesting(false).accessibilityIdentifier("x")
            case .shadow: Rectangle().fill(Color.red).frame(width: 40, height: 20).shadow(radius: 2).accessibilityIdentifier("x")
            case .blur: Rectangle().fill(Color.red).frame(width: 40, height: 20).blur(radius: 1).accessibilityIdentifier("x")
            case .onTapGesture: Rectangle().fill(Color.red).frame(width: 40, height: 20).onTapGesture {}.accessibilityIdentifier("x")
            case .onAppear: Rectangle().fill(Color.red).frame(width: 40, height: 20).onAppear {}.accessibilityIdentifier("x")
            case .task: Rectangle().fill(Color.red).frame(width: 40, height: 20).task {}.accessibilityIdentifier("x")
            case .focusable: Rectangle().fill(Color.red).frame(width: 40, height: 20).focusable(true).accessibilityIdentifier("x")
            case .id: Rectangle().fill(Color.red).frame(width: 40, height: 20).id("k").accessibilityIdentifier("x")
            }
        }
    }
}

/// DA-B. The identifier survives a wrapper written before it (no loss was reproducible, so
/// no mutation applies: this is a regression pin across 17 wrappers).
@Test(arguments: Wrapper.allCases) @MainActor
fileprivate func anIdentifierSurvivesAWrapperWrittenBeforeIt(wrapper: Wrapper) throws {
    let window = try harnessWindow { VStack { Wrapped(wrapper: wrapper) } }
    let element = try window.element(identifier: "x")
    #expect(element.frame.size.width.value > 0)
}

/// DA-B. `.disabled` and `.accessibilityIdentifier` in either order publish the same
/// identified, disabled elements (the report could not be reproduced as a loss; this pins
/// the reading). Mutation DA-M4 reddens it as a side effect (always-group changes who is identified).
@Test @MainActor func disabledThenIdentifierEqualsIdentifierThenDisabled() throws {
    let a = try harnessWindow { VStack { HStack { Text("a"); Button("b") {} }.disabled(true).accessibilityIdentifier("x") } }
    let b = try harnessWindow { VStack { HStack { Text("a"); Button("b") {} }.accessibilityIdentifier("x").disabled(true) } }
    for window in [a, b] {
        let identified = try window.elements(where: { $0.identifier == "x" })
        #expect(identified.count == 2)
        #expect(identified.allSatisfy { $0.isEnabled == false })
    }
}

private struct Fields: Component {
    @State var text = "hello"
    @State var long = "multi\nline"
    var content: some ElementGroup {
        VStack {
            TextField("Name", text: $text).accessibilityIdentifier("field")
            TextField("Plain", text: $text).accessibilityLabel("Labelled").accessibilityIdentifier("labelled")
            TextEditor(text: $long).accessibilityIdentifier("editor")
        }
    }
}

/// DA-C. An identifier on a text field is on the field's own element, whose value is its
/// text. Mutation DA-M6 (the `isEmpty` gate restored in `TextField.prepaint`) reddens the
/// field arms; DA-M7 (the same in `TextEditor.prepaint`) reddens the editor arm.
@Test @MainActor func anIdentifiedTextFieldPublishesItsTextAsValue() throws {
    let window = try harnessWindow { VStack { Fields() } }
    let field = try window.element(identifier: "field")
    #expect(field.role == AccessibilityRole.textField)
    #expect(field.value == "hello")
    #expect(field.label == "Name")
    let labelled = try window.element(identifier: "labelled")
    #expect(labelled.role == AccessibilityRole.textField)
    #expect(labelled.value == "hello")
    #expect(labelled.label == "Labelled")
    let editor = try window.element(identifier: "editor")
    #expect(editor.role == AccessibilityRole.textArea)
    #expect(editor.value == "multi\nline")
}
