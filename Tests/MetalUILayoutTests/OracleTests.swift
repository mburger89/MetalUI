import Testing
import Foundation
@testable import MetalUILayout

#if canImport(WebKit)
@MainActor
@Test func oracleMeasuresFlexboxFromAFixtureFile() async throws {
    let html = try String(contentsOf: fixtureURL(name: "flex_row_fixed_and_grow"), encoding: .utf8)
    let oracle = LayoutOracle(viewport: CGSize(width: 800, height: 600))
    let boxes = try await oracle.measure(html: html)

    let byID = Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0) })
    #expect(boxes.count == 4)

    // 700 wide, 100 fixed, 600 free split 1:2 -> 200 / 400.
    #expect(try #require(byID["root"]).width == 700)
    #expect(try #require(byID["a"]).width == 200)
    #expect(try #require(byID["b"]).width == 400)
    #expect(try #require(byID["c"]).width == 100)
    #expect(try #require(byID["a"]).x == 0)
    #expect(try #require(byID["b"]).x == 200)
    #expect(try #require(byID["c"]).x == 600)
}
#endif

#if canImport(WebKit)
@MainActor
@Test func oracleReportsSubPixelQuantization() async throws {
    // Documents WebKit's 1/64 quantisation, which is why comparisons are rounded.
    let html = """
    <!doctype html><html><head><style>
      * { box-sizing: border-box; margin: 0 } body { margin: 0 }
      #r { display: flex; width: 100px } #r > div { flex: 1 1 0 }
    </style></head><body><div id="r">\(String(repeating: "<div data-id=\"x\"></div>", count: 7))</div></body></html>
    """
    let oracle = LayoutOracle(viewport: CGSize(width: 400, height: 200))
    let boxes = try await oracle.measure(html: html)
    #expect(boxes.count == 7)
    // 100/7 = 14.2857…, quantised to 914/64 = 14.28125.
    #expect(boxes[0].width == 14.28125)
    // The row does NOT close on its parent — this is the compounding error.
    #expect(boxes[6].x + boxes[6].width == 99.96875)
}
#endif

@Test func goldenFileRoundTripsThroughJSON() throws {
    let g = GoldenFile(
        fixture: "demo",
        viewport: [800, 600],
        raw: [NodeBox(id: "root", x: 0, y: 0, width: 700, height: 100)],
        rounded: [NodeBox(id: "root", x: 0, y: 0, width: 700, height: 100)])
    let data = try JSONEncoder().encode(g)
    let back = try JSONDecoder().decode(GoldenFile.self, from: data)
    #expect(back == g)
}
