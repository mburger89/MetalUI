import MetalUI
import MetalUITesting
import Testing

// `DA-`: an accessibility identifier on a container never replaces a descendant's own, the
// container's stays findable, and a wrapper modifier written between the element and
// `.accessibilityIdentifier` does not lose it. Plain imports, as an app spells them.

private struct ScreenWithOwnIDs: Component {
    var content: some ElementGroup {
        VStack {
            Text("a").accessibilityIdentifier("a")
            Button("b") {}.accessibilityIdentifier("b")
        }
        .accessibilityIdentifier("screen")
    }
}

private struct MixedScreen: Component {
    var content: some ElementGroup {
        VStack {
            Text("a").accessibilityIdentifier("a")
            Text("c")
        }
        .accessibilityIdentifier("screen")
    }
}

private struct PlainScreen: Component {
    var content: some ElementGroup {
        VStack {
            Text("a")
            Text("c")
        }
        .accessibilityIdentifier("screen")
    }
}

private struct NestedScreen: Component {
    var content: some ElementGroup {
        VStack {
            VStack {
                Text("a").accessibilityIdentifier("a")
            }
            .accessibilityElement(children: .contain)
            Text("c")
        }
        .accessibilityIdentifier("outer")
    }
}

/// DA-A 1. Descendants keep their own identifiers under an identified container. Mutation
/// DA-M1 (distribution overwrites a descendant's own identifier, the old rule) reddens it.
@Test @MainActor func aContainerIdentifierNeverReplacesADescendantsOwn() throws {
    let window = try harnessWindow { VStack { ScreenWithOwnIDs() } }
    #expect(try window.element(identifier: "a").role == AccessibilityRole.staticText)
    #expect(try window.element(identifier: "b").role == AccessibilityRole.button)
    #expect(try window.element(identifier: "b").label == "b")
}

/// DA-A 2. The container's own identifier stays findable, on a group holding both.
/// Mutation DA-M1 reddens it.
@Test @MainActor func theContainerIdentifierStaysFindableAsAGroupHoldingItsDescendants() throws {
    let window = try harnessWindow { VStack { ScreenWithOwnIDs() } }
    let screen = try window.element(identifier: "screen")
    #expect(screen.role == AccessibilityRole.group)
    #expect(screen.children == [try window.element(identifier: "a").id, try window.element(identifier: "b").id])
    let nested = try harnessWindow { VStack { NestedScreen() } }
    #expect(try nested.element(identifier: "outer").role == AccessibilityRole.group)   // exactly one
    #expect(try nested.element(identifier: "a").role == AccessibilityRole.staticText)
}

/// DA-A 3. One own identifier anywhere below makes the container a group: the sibling
/// without one does not inherit (it is inside the identified group). Mutation DA-M3
/// (subtree check looks at direct children only) reddens test 2's nested arm.
@Test @MainActor func aSiblingWithoutItsOwnIsContainedNotRelabelled() throws {
    let window = try harnessWindow { VStack { MixedScreen() } }
    let screen = try window.element(identifier: "screen")
    #expect(screen.role == AccessibilityRole.group)
    #expect(screen.children.count == 2)
    #expect(try window.element(identifier: "a").value == "a")
}

/// DA-A 4. SwiftUI's own reading is kept where no descendant declares one (probe N5): the
/// identifier distributes to each text. Mutation DA-M4 (always a group) reddens it.
@Test @MainActor func withoutDescendantIdentifiersTheContainerIdentifierStillDistributes() throws {
    let window = try harnessWindow { VStack { PlainScreen() } }
    let texts = try window.elements(role: .staticText)
    #expect(texts.count == 2)
    #expect(texts.allSatisfy { $0.identifier == "screen" })
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
