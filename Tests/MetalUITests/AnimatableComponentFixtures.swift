import Observation
import MetalUICore
import MetalUILayout
@testable import MetalUI

// R4-3 PR E (`VA-I`, record 209): fixtures for `Component & Animatable`. `SplitCounter` is declared here and
// made `Animatable` in `AnimatableComponentSplit.swift`, a DIFFERENT file, to prove that the constrained witness
// is selected for a conformance written elsewhere (the guard `aWitnessDeclaredInAnotherFileIsSelected`).

/// What the fixtures' `content` getters saw, keyed by name (a test clears it first).
@MainActor var acSeen: [String: [Double]] = [:]

@MainActor func acNote(_ key: String, _ value: Double) { acSeen[key, default: []].append(value) }

/// The widths a proposal layout inside a fixture was asked to measure.
@MainActor let acWidths = ProposalWidthLog()

/// A counter whose `content` notes the value it sees and lays a width-recording child out at `100 + x`.
struct SplitCounter: Component {
    var x: Double
    var content: some ElementGroup {
        let _ = acNote("split", x)
        Box().frame(width: Pixels(Float(100 + x)), height: Pixels(20)).background(.accent)
    }
}
