import Foundation
import MetalUITextSystem

// The line-layout cache of `CodeView` (`CV-M`). One entry per distinct line *content*: a 64-bit hash of
// the line's bytes (never a `String`), the foreground partition's digest, and every input the layout reads
// (face, scale, tab width, text system, long-line window). The value is origin-free: glyph keys and device
// pixel offsets from the line's top-left, so a hit is placed by a whole-device-pixel translation.
//
// **It holds glyph keys, never atlas slots**, so the atlas reclaim (`GL-A`) and the flattening re-key
// (`TZ-A`) have nothing to invalidate. **It is an idempotent memo**: a build computes the same value from
// the same key whenever it runs, so no `rollbackBuild` is owed and a redone frame loses nothing.

/// What a cached line layout depends on.
struct CodeLineKey: Hashable {
    var textHash: UInt64
    var byteCount: Int
    var styleDigest: UInt64
    var font: FontKey
    var scaleBits: UInt32
    var tabColumns: Int
    var system: ObjectIdentifier
    /// The byte window of a long line that was shaped (`0..<0` for a whole line).
    var windowStart: Int
    var windowEnd: Int
}

/// A laid-out line, relative to its own top-left (`CV-M`).
final class CodeLineLayout {
    /// The glyphs at pixel offsets from the line's top-left (the baseline included).
    let glyphs: [TextGlyph]
    /// The foreground part (`LineStyling.foreground` index) of each glyph.
    let glyphParts: [UInt16]
    /// The UTF-8 offset, from the line's start, of every grapheme boundary of the shaped text.
    let boundaries: [Int]
    /// The x of every boundary, in points from the line's text origin.
    let caretX: [Double]
    /// The line's advance, in points.
    let width: Double
    /// Where the shaped text starts inside the line (a long line's window); 0 otherwise.
    let windowStart: Int
    /// The x of the window's first byte, in points.
    let windowX: Double

    init(glyphs: [TextGlyph], glyphParts: [UInt16], boundaries: [Int], caretX: [Double], width: Double,
         windowStart: Int, windowX: Double) {
        self.glyphs = glyphs
        self.glyphParts = glyphParts
        self.boundaries = boundaries
        self.caretX = caretX
        self.width = width
        self.windowStart = windowStart
        self.windowX = windowX
    }

    /// The x, in points from the text origin, of the boundary at `byte` (an offset in the line): the
    /// nearest boundary at or before it; outside a long line's window, `nil`.
    func x(ofByte byte: Int) -> Double? {
        let local = byte - windowStart
        guard local >= 0, let last = boundaries.last, local <= last else { return nil }
        var lo = 0, hi = boundaries.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if boundaries[mid] <= local { lo = mid } else { hi = mid - 1 }
        }
        return caretX[lo]
    }

    /// The byte offset (in the line) of the boundary nearest `x` points from the text origin.
    func byte(atX x: Double) -> Int {
        let local = x
        guard caretX.count > 1, local > caretX[0] else { return windowStart }
        var lo = 0, hi = caretX.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if caretX[mid] <= local { lo = mid } else { hi = mid - 1 }
        }
        let next = min(lo + 1, caretX.count - 1)
        let nearest = (caretX[next] - local) < (local - caretX[lo]) ? next : lo
        return windowStart + boundaries[nearest]
    }
}

/// The two-frame cache (`CV-M`): the entries used by the current frame, and those the previous one used.
@MainActor
final class CodeLineCache {
    private var current: [CodeLineKey: CodeLineLayout] = [:]
    private var previous: [CodeLineKey: CodeLineLayout] = [:]
    private weak var lastFrame: Frame?
    private var advances: [FontKey: (space: Double, digit: Double, height: Double)] = [:]
    /// Lines shaped since creation (a miss in both frames).
    private(set) var shapedTotal = 0
    /// The bytes of the lines shaped since creation (a long line counts its window only).
    private(set) var shapedBytesTotal = 0
    /// Gutter labels shaped since creation.
    private(set) var gutterShapedTotal = 0
    /// Hits that were laid out fresh and compared (verify mode).
    private(set) var verified = 0
    /// Whether every hit is re-laid-out and compared (`METALUI_VERIFY_CODE_CACHE=1`, read once).
    static let verifies: Bool = ProcessInfo.processInfo.environment["METALUI_VERIFY_CODE_CACHE"] == "1"

    /// The entries held (test observability).
    var count: Int { current.count + previous.count }

    /// Rotates the two frames when `frame` is not the one the last call served.
    func begin(_ frame: Frame) {
        guard lastFrame !== frame else { return }
        lastFrame = frame
        previous = current
        current = [:]
    }

    /// The layout for `key`: a hit in this frame or the previous one, else `build()` (counted).
    func layout(_ key: CodeLineKey, gutter: Bool = false, build: () -> CodeLineLayout) -> CodeLineLayout {
        if let hit = current[key] {
            if Self.verifies { verify(hit, build()) }
            return hit
        }
        if let old = previous[key] {
            if Self.verifies { verify(old, build()) }
            current[key] = old
            return old
        }
        let made = build()
        if gutter { gutterShapedTotal += 1 } else { shapedTotal += 1; shapedBytesTotal += key.byteCount }
        current[key] = made
        return made
    }

    private func verify(_ cached: CodeLineLayout, _ fresh: CodeLineLayout) {
        verified += 1
        precondition(cached.glyphs == fresh.glyphs && cached.glyphParts == fresh.glyphParts
                     && cached.boundaries == fresh.boundaries && cached.caretX == fresh.caretX,
                     "METALUI_VERIFY_CODE_CACHE: a cached line layout differs from a fresh one (CV-M)")
    }

    /// The space advance, digit advance and line height of `font`, in points (cached per face).
    func metrics(of font: FontKey, system: any TextSystem) -> (space: Double, digit: Double, height: Double) {
        if let known = advances[font] { return known }
        let space = system.measure(" ", font: font, wrappingAt: nil)
        let digit = system.measure("0", font: font, wrappingAt: nil).widestLine
        let value = (space.widestLine, digit, space.totalHeight)
        advances[font] = value
        return value
    }
}

/// FNV-1a over a line's bytes.
@inline(__always)
func codeHash(_ bytes: some Sequence<UInt8>) -> UInt64 {
    var h: UInt64 = 0xCBF2_9CE4_8422_2325
    for b in bytes { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
    return h
}

/// Builds one line's layout (`CV-M`): `bytes` is the line (or its long-line window), split at tabs; each
/// segment is shaped through the styled seam with one run per foreground part, so a glyph's run says which
/// part colours it, and placed at the next tab stop (a multiple of `tabColumns` space advances, from the
/// pen's real end — never a glyph count).
@MainActor
func buildCodeLine(bytes: ArraySlice<UInt8>, windowStart: Int, windowX: Double, parts: [(bytes: Int, style: CodeStyleID?)],
                   partOffset: Int, font: FontKey, scale: Float, tabColumns: Int, spaceAdvance: Double,
                   system: any TextSystem) -> CodeLineLayout {
    var glyphs: [TextGlyph] = []
    var glyphParts: [UInt16] = []
    var boundaries = [0]
    var caretX = [windowX]
    var pen = windowX   // points, the true end of what is placed
    let stopWidth = max(spaceAdvance, 0.001) * Double(max(1, tabColumns))
    let runStyle = TextRunStyle(font: font)

    // The part cursor: which foreground part the next byte belongs to.
    var partIndex = partOffset
    var partLeft = parts.first?.bytes ?? 0
    var partCursor = 0
    func advancePart() {
        while partLeft == 0, partCursor + 1 < parts.count {
            partCursor += 1
            partIndex += 1
            partLeft = parts[partCursor].bytes
        }
    }

    var index = bytes.startIndex
    var segmentStart = index
    let end = bytes.endIndex
    while true {
        var atTab = false
        if index < end, bytes[index] == 0x09 { atTab = true }
        if index == end || atTab {
            let segment = bytes[segmentStart..<index]
            if !segment.isEmpty {
                let string = String(decoding: segment, as: UTF8.self)
                // Runs: one per foreground part the segment touches.
                var runs: [StyledTextRun] = []
                var runParts: [Int] = []
                var cursor = segment.startIndex
                var units = 0
                var lastPart = -1
                var consumed = 0
                while cursor < segment.endIndex {
                    advancePart()
                    let lead = segment[cursor]
                    let length = lead < 0x80 ? 1 : lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4
                    if partIndex != lastPart {
                        if lastPart >= 0 { runs.append(StyledTextRun(length: units, style: runStyle)); runParts.append(lastPart) }
                        units = 0
                        lastPart = partIndex
                    }
                    units += length == 4 ? 2 : 1
                    cursor += length
                    consumed += length
                    partLeft = max(0, partLeft - length)
                }
                if lastPart >= 0 { runs.append(StyledTextRun(length: units, style: runStyle)); runParts.append(lastPart) }
                // The segment's origin: a whole device pixel.
                let originPx = (pen * Double(scale)).rounded()
                let origin = originPx / Double(scale)
                let laid = system.layOut(StyledText(keepingNeighbours: string, runs: runs), wrappingAt: nil,
                                         options: TextLayoutOptions(), origin: (x: 0, y: 0), scaleFactor: scale)
                let shift = Int(originPx)
                for styled in laid.glyphs {
                    glyphs.append(TextGlyph(key: styled.glyph.key, pixelX: styled.glyph.pixelX + shift,
                                            baselineY: styled.glyph.baselineY))
                    glyphParts.append(UInt16(truncatingIfNeeded: runParts[min(styled.run, runParts.count - 1)]))
                }
                let offsets = system.caretOffsets(string, font: font)
                var byte = boundaries[boundaries.count - 1]
                var graphemeIndex = 1
                for character in string {
                    byte += character.utf8.count
                    boundaries.append(byte)
                    caretX.append(origin + offsets[min(graphemeIndex, offsets.count - 1)])
                    graphemeIndex += 1
                }
                pen = origin + laid.measurement.widestLine
            }
            if atTab {
                // The tab is one grapheme, as wide as the distance to the next stop.
                advancePart()
                partLeft = max(0, partLeft - 1)
                let stop = ((pen / stopWidth).rounded(.down) + 1) * stopWidth
                pen = stop
                boundaries.append(boundaries[boundaries.count - 1] + 1)
                caretX.append(pen)
                index += 1
                segmentStart = index
                continue
            }
            break
        }
        index += 1
    }
    return CodeLineLayout(glyphs: glyphs, glyphParts: glyphParts, boundaries: boundaries, caretX: caretX, width: pen,
                          windowStart: windowStart, windowX: windowX)
}
