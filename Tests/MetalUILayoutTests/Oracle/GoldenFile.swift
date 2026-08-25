import Foundation
@testable import MetalUILayout

/// A fixture's browser-measured layout, raw and rounded.
///
/// `rounded` is what tests compare against; `raw` is kept for debugging a
/// disagreement, since it is what you would see in Safari's inspector.
public struct GoldenFile: Codable, Sendable, Equatable {
    public let fixture: String
    public let viewport: [Double]
    public let raw: [NodeBox]
    public let rounded: [NodeBox]
}

public func fixtureURL(name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "html")!
}

public func goldenURL(fixture: String) -> URL {
    Bundle.module.url(forResource: "Golden/\(fixture)", withExtension: "json")!
}

public func loadGolden(_ name: String) throws -> GoldenFile {
    try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: goldenURL(fixture: name)))
}

/// Apply the engine's rounding pass to browser output, so both sides are
/// compared in the same space.
public func roundBoxes(_ boxes: [NodeBox]) -> [NodeBox] {
    let rects = boxes.map { LayoutRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
    return zip(boxes, roundLayout(rects)).map { box, r in
        NodeBox(id: box.id, x: r.x, y: r.y, width: r.width, height: r.height)
    }
}
