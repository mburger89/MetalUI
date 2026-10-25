import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// C14-l (`AM-D`...`AM-G`, `AM-J`, record 146): a drag whose `updating` body sets `disablesAnimations` does not miss every `.equatable()`
// panel; the trace names the environment field that moved, cuts a path at a `/`, and says where a release build's fire came from.
// Counts and strings, never time.
//
// **Red before the change** (measured, record 146): `aSteadyDragCostsExactlyTheChangedPanelsMisses` read per drag frame
// `h0 m8, h0 m8, h7 m1, h7 m1, h7 m1, h7 m1`, release `h0 m8`, then `h0 m8` (the second frame of an ambient miss, `coverage.build,
// coverage.prepaint`); the other tests do not compile (`EnvironmentFingerprint.differences`, `writerCause(from:)`) or read the old text.

private func perFrame(_ frames: [FrameWork]) -> String { frames.map { "h\($0.retainedHits) m\($0.retainedMisses)" }.joined(separator: ", ") }

@Suite(.serialized) @MainActor
struct RetainedAmbientMissTests {
    /// 1 - a steady drag over eight `.equatable()` panels, one observed radius written per move, costs exactly the written panel's miss
    /// per frame: six drag frames h7 m1, the release frame (the gesture state resets: the transaction flips back) and two settle frames h8 m0,
    /// no `disablesAnimations`, `snappingTransaction` or `coverage` in any reason list.
    /// **Mutations:** `retainedKey` left real (reddens: the paint half names `key.ambient.disablesAnimations`), `retainedPrepaintKey` left real (the
    /// prepaint half names `ledgerKey.ambient.disablesAnimations`).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss")) func aSteadyDragCostsExactlyTheChangedPanelsMisses() throws {
        let (window, _) = try dragAmbientWindow()
        var frames: [FrameWork] = []
        let lines = try collectTrace { frames = try dragAmbientRun(window, steps: 6) }
        try #require(frames.count == 9, "press draws no frame: six moves, the release, two settles: \(frames.count)")
        for (k, f) in frames.enumerated() {
            let expected = k < 6 ? 1 : 0
            #expect(f.retainedMisses == expected && f.retainedHits == 8 - expected, "frame \(k): h\(f.retainedHits) m\(f.retainedMisses): \(perFrame(frames))")
        }
        let reasons = lines.filter { $0.contains(" miss ") }
        for line in reasons {
            #expect(!line.contains("disablesAnimations") && !line.contains("snappingTransaction") && !line.contains("coverage"), "\(line)")
        }
        #expect(reasons.count == 12, "six drag frames, one paint and one prepaint line each: \(reasons.count)")
    }

    /// 2 - the oracle (not the instrument): the same drag with retention off draws the same scene, hitboxes, accessibility, tallies and
    /// bounds after every frame of the script, so the key's two members decide nothing here.
    @Test func theDragFrameEqualsRetentionOff() throws {
        let (on, _) = try dragAmbientWindow()
        let (off, _) = try dragAmbientWindow(retain: false)
        _ = try dragAmbientRun(on, steps: 6)
        _ = try dragAmbientRun(off, steps: 6)
        let difference = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(difference.isEmpty, "\(difference)")
        // A second drag from the settled state: the gesture state starts again.
        _ = try dragAmbientRun(on, steps: 3)
        _ = try dragAmbientRun(off, steps: 3)
        let again = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(again.isEmpty, "\(again)")
    }

    /// 3 - the control: a drag whose `updating` body sets nothing on the transaction costs the same (the fix is the key, not the fixture).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss")) func aDragWithoutATransactionCostsTheSame() throws {
        let (window, _) = try dragAmbientWindow(setsDisablesAnimations: false)
        let frames = try dragAmbientRun(window, steps: 6)
        for (k, f) in frames.enumerated() {
            let expected = k < 6 ? 1 : 0
            #expect(f.retainedMisses == expected, "frame \(k): \(perFrame(frames))")
        }
    }

    /// 4 - an animation that **does** start inside a retained panel is not swallowed by the normalised key: a panel whose colour animates with
    /// `.animation(_:value:)` on its observed radius changes under a `withAnimation` write; the frame equals a retention-off twin at every
    /// tick of the animation. **Mutation:** normalise also `animation`-dependent state (not applicable: the value change moves the serial, so
    /// the panel misses on `observed`/`serial`; this arm pins that the miss still happens and the twin agrees).
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss")) func anAnimationStartedInsideAPanelStillRuns() throws {
        let (on, onModel) = try dragAmbientWindow(animated: true)
        let (off, offModel) = try dragAmbientWindow(retain: false, animated: true)
        for (window, model) in [(on, onModel), (off, offModel)] {
            withAnimation(.linear(duration: 0.3)) { model.params[2].radius = 4 }
            window.window.setNeedsRedraw(); window.tick()
        }
        for tick in 0..<8 {
            for window in [on, off] { window.advance(by: 0.05) }
            let difference = try RPSnapshot(on).differences(from: RPSnapshot(off))
            #expect(difference.isEmpty, "tick \(tick): \(difference)")
        }
    }

    /// 5 - one environment field flipped alone is named `key.ambient.environment.<field>`, for every field of the fingerprint. The `Mirror` count
    /// makes a new field owe a row in `EnvironmentFingerprint.differences`. **Mutation:** drop one row (reddens that field's arm).
    @Test func everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone() throws {
        let base = EnvironmentValues().retainedFingerprint
        try #require(Mirror(reflecting: base).children.count == 26, "a new EnvironmentFingerprint field owes a row in differences(from:) and here")
        var cases: [(String, (inout EnvironmentFingerprint) -> Void)] = [
            ("isEnabled", { $0.isEnabled.toggle() }), ("layoutDirection", { $0.layoutDirection = $0.layoutDirection == .leftToRight ? .rightToLeft : .leftToRight }),
            ("locale", { $0.locale = Locale(identifier: "xx_YY") }), ("dynamicTypeSize", { $0.dynamicTypeSize = .xxxLarge }),
            ("displayScale", { $0.displayScale += 1 }), ("controlActiveState", { $0.controlActiveState = .inactive }),
            ("accessibilityReduceMotion", { $0.accessibilityReduceMotion.toggle() }),
            ("accessibilityReduceTransparency", { $0.accessibilityReduceTransparency.toggle() }),
            ("titleBarInsets", { $0.titleBarInsets = Edges(top: Pixels(9), right: Pixels(0), bottom: Pixels(0), left: Pixels(0)) }),
            ("windowSize", { $0.windowSize = Size(width: Pixels(7), height: Pixels(7)) }), ("colorScheme", { $0.colorScheme = $0.colorScheme == .light ? .dark : .light }),
            ("controlSize", { $0.controlSize = .large }), ("font", { $0.font = .title }), ("lineLimit", { $0.lineLimit = 3 }),
            ("truncationMode", { $0.truncationMode = .head }), ("multilineTextAlignment", { $0.multilineTextAlignment = .trailing }),
            ("foregroundStyle", { $0.foregroundStyle = Color(red: 1, green: 0, blue: 0) }), ("fontWeight", { $0.fontWeight = .heavy }),
            ("italic", { $0.italic.toggle() }), ("textLineLimit", { $0.textLineLimit = TextLineLimit(min: nil, max: 4) }),
            ("fieldStyle", { $0.fieldStyle = .plain }), ("editorStyle", { $0.editorStyle = .plain }),
            ("theme", { $0.theme = Theme.dark }), ("hasTextSystem", { $0.hasTextSystem.toggle() }),
        ]
        cases.append(("objects", { $0.objects[ObjectIdentifier(AMEnvBox.self)] = ObjectIdentifier(AMEnvBox.self) }))
        cases.append(("custom", { $0.custom[ObjectIdentifier(AMEnvBox.self)] = EnvironmentReading.value(7) }))
        try #require(cases.count == 26)
        for (name, change) in cases {
            var other = base; change(&other)
            #expect(base != other, "\(name): the change changes the fingerprint")
            #expect(other.differences(from: base) == [name], "\(name): \(other.differences(from: base))")
        }
        #expect(base.differences(from: base).isEmpty)
    }

    /// 6 - the trace line names the field: a custom environment key written above the occurrences (the ambient-miss fixture) misses on
    /// `key.ambient.environment.custom`, not the bare `key.ambient.environment`. **Mutation:** print `environment` alone in `AmbientKey.differences`.
    @Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss")) func theTraceNamesTheDifferingEnvironmentField() throws {
        let (window, _, box) = try ambientMissWindow()
        let lines = collectTrace {
            box.n = 1
            window.window.setNeedsRedraw(); window.tick()
        }
        let reasons = lines.filter { $0.hasPrefix("retained paint miss") }.compactMap(traceReasons)
        try #require(!reasons.isEmpty)
        #expect(reasons.contains { $0.contains("key.ambient.environment.custom") }, "\(reasons)")
        #expect(!reasons.contains { $0.contains("key.ambient.environment") && !$0.contains("key.ambient.environment.") }, "\(reasons)")
    }
}
