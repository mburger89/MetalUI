import Testing
import MetalUICore
import MetalUITextSystem
@testable import MetalUIText
@testable import MetalUI

// R3-10 part 1 (`TM-A`, `TM-F`), the CoreText half: which seam calls a text under a view-level modifier
// makes (helpers `rtFrame`, `rtTopLeft`, `rtResolved`, `RichTextSpySystem` live in `RichTextTests.swift`).

private func note(_ message: String) -> Comment { Comment(rawValue: message) }

/// **TM-13** (`TM-A`, `RT-F` item 3, `RT-M`). A plain `Text` takes the plain calls byte for byte; under a
/// view-level underline, kerning (even `0`), tracking, baseline offset or monospaced it takes the styled
/// ones, as its own would; under a view-level `bold()` or `italic()` it stays plain (those are font
/// requests, not runs). **Mutation:** `viewLevel.isEmpty` dropped from `plainTextForm`'s guard (every
/// styled row reddens), or an `isBold` clause added to it (the plain rows).
@MainActor @Test func aTextUnderAViewLevelModifierTakesTheStyledPathExactlyWhenItsOwnWould() {
    let system = RichTextSpySystem()
    func calls<G: ElementGroup>(_ group: G) -> (plain: Set<String>, styled: Set<String>) {
        system.reset()
        _ = rtFrame(rtTopLeft(group), system: system)
        return (Set(system.plainCalls), Set(system.styledCalls))
    }
    let plainOnes: [(String, Set<String>, Set<String>)] = [
        ("no modifier", calls(Column { Text("a") }).plain, calls(Column { Text("a") }).styled),
        ("bold()", calls(Column { Text("a") }.bold()).plain, calls(Column { Text("a") }.bold()).styled),
        ("italic()", calls(Column { Text("a") }.italic()).plain, calls(Column { Text("a") }.italic()).styled),
    ]
    for (name, plain, styled) in plainOnes {
        #expect(styled.isEmpty && plain.isSuperset(of: ["measure", "placeGlyphs"]), note("\(name): plain \(plain), styled \(styled)"))
    }
    let styledOnes: [(String, (plain: Set<String>, styled: Set<String>))] = [
        ("underline()", calls(Column { Text("a") }.underline())),
        ("strikethrough(pattern:)", calls(Column { Text("a") }.strikethrough(pattern: .dash))),
        ("kerning(0)", calls(Column { Text("a") }.kerning(0))),
        ("tracking(1)", calls(Column { Text("a") }.tracking(1))),
        ("baselineOffset(1)", calls(Column { Text("a") }.baselineOffset(1))),
        ("monospaced()", calls(Column { Text("a") }.monospaced())),
    ]
    for (name, seen) in styledOnes {
        #expect(seen.plain.isEmpty && !seen.styled.isEmpty, note("\(name): plain \(seen.plain), styled \(seen.styled)"))
    }
}

/// **TM-14** (`TM-A`). A view-level `monospaced()` resolves the system face's monospaced design for the
/// text below, as the `Text`'s own does, and an own `monospaced(false)` wins; CoreText has the design, so
/// the face key tells. **Mutation:** drop `view.monospaced` from the request in `resolveRichText`.
@MainActor @Test func aViewLevelMonospacedResolvesTheMonospacedFace() {
    let system = CoreTextTextSystem()
    func key(_ text: Text, _ configure: (inout EnvironmentValues) -> Void = { _ in }) -> FontKey {
        var environment = EnvironmentValues()
        configure(&environment)
        return rtResolved(text, system, environment: environment).text.runs[0].style.font
    }
    let off = key(Text("a").underline(false))
    let own = key(Text("a").monospaced())
    #expect(own != off, "set up: the monospaced face is another face")
    #expect(key(Text("a").underline(false)) { $0.textMonospaced = true } == own, "the environment's is the Text's own")
    #expect(key(Text("a").monospaced(false)) { $0.textMonospaced = true } == off, "an own monospaced(false) wins")
}
