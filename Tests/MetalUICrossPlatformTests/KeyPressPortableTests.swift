import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Key and focus scoping, lane A — the portable copies of A1, A3, A6, A18 and
// A42 (spec §5.1 A37), over `PortableFakeWindow`, so Linux and Windows CI run
// the key pipeline. Same scripts and mutations as `KeyPressTests` and
// `HoverKeyRegionTests` in `MetalUITests`.

private func kd(_ c: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, timestamp: 0))
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class PKLog {
    var log: [String] = []
    var text = ""
}

@MainActor private func square() -> some StyledElement { Box().frame(width: px(20), height: px(20)) }

/// **A37/A1** (portable). A focused element's `onKeyPress` hears a key.
@MainActor
@Test func portableAFocusedElementsOnKeyPressHearsAKeyDown() throws {
    let m = PKLog()
    let (window, platform) = try makePortableWindow {
        Box { square().focusable().onKeyPress("x") { m.log.append("x"); return .handled } }
    }
    window.drawFrameIfNeeded()
    window.focus(try #require(window.lastFocusRegistry.tabOrder.first))
    window.drawFrameIfNeeded()
    #expect(platform.simulateInput(kd("x")))
    #expect(m.log == ["x"], "\(m.log)")
}

/// **A37/A3** (portable). Outermost first along the focus chain.
@MainActor
@Test func portableOnKeyPressRunsOutermostFirstAlongTheFocusChain() throws {
    let m = PKLog()
    let (window, platform) = try makePortableWindow {
        Box {
            Box { square().focusable().onKeyPress { _ in m.log.append("inner"); return .ignored } }
                .onKeyPress { _ in m.log.append("mid"); return .ignored }
        }
        .onKeyPress { _ in m.log.append("root"); return .ignored }
    }
    window.drawFrameIfNeeded()
    window.focus(try #require(window.lastFocusRegistry.tabOrder.first))
    window.drawFrameIfNeeded()
    platform.simulateInput(kd("q"))
    #expect(m.log == ["root", "mid", "inner"], "\(m.log)")
}

/// **A37/A6** (portable). An `onKeyPress(.upArrow)` on a focused field claims
/// ↑ ahead of the field: Tab's whole-text selection survives, so `z` replaces
/// it.
@MainActor
@Test func portableOnKeyPressOnAFocusedTextFieldClaimsUpArrowAheadOfTheField() throws {
    let m = PKLog()
    m.text = "abc"
    let (window, platform) = try makePortableWindow {
        Box { TextField("t", text: m.text) { m.text = $0 }.onKeyPress(.upArrow) { .handled } }
    }
    window.drawFrameIfNeeded()
    platform.simulateInput(kd("\t"))
    window.drawFrameIfNeeded()
    #expect(platform.simulateInput(kd("\u{f700}")))
    platform.simulateInput(.textInput("z"))
    #expect(m.text == "z", "\(m.text)")
}

/// **A37/A18** (portable). With nothing focused the hovered key region hears
/// keys.
@MainActor
@Test func portableWithNothingFocusedTheHoveredKeyRegionReceivesKeys() throws {
    let m = PKLog()
    let (window, platform) = try makePortableWindow {
        Box().frame(width: px(100), height: px(100)).hoverKeyRegion()
            .onKeyPress { _ in m.log.append("region"); return .handled }
    }
    window.drawFrameIfNeeded()
    platform.simulateInput(.mouseMoved(MouseEvent(position: Point(x: px(100), y: px(100)))))
    #expect(platform.simulateInput(kd("x")))
    #expect(m.log == ["region"], "\(m.log)")
}

/// **A37/A42** (portable). A digit filter on a field keeps only digits.
@MainActor
@Test func portableADigitFilterOnAFieldKeepsOnlyDigits() throws {
    let m = PKLog()
    let (window, platform) = try makePortableWindow {
        Box {
            TextField("t", text: m.text) { m.text = $0 }
                .onKeyPress(characters: CharacterSet.decimalDigits.inverted) { _ in .handled }
        }
    }
    window.drawFrameIfNeeded()
    platform.simulateInput(kd("\t"))
    window.drawFrameIfNeeded()
    for c in ["a", "1", "b", "2"] { platform.simulateInput(.textInput(c)) }
    #expect(m.text == "12", "\(m.text)")
}
