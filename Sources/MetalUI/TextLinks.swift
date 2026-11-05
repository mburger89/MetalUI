import Foundation
import MetalUICore
import MetalUITextSystem

// Clickable text links (round 4 item R4-4 PR D; rulings `LI-A`…; divergence 150 retired). A `Text` with a link run
// registers one click region per laid-out piece of the run in prepaint, and one accessibility link per run. A text
// with no link run takes none of this (`RT-M`: it is one `contains` over its runs).

extension Text {
    /// Whether any run carries a destination: the one test a plain `Text`'s prepaint pays (`LI-A`).
    var hasLinkRun: Bool {
        guard case .runs(let runs) = content else { return false }
        return runs.contains { $0.link != nil }
    }
}

extension Frame {
    /// Registers the link regions of `resolved`, laid out exactly as paint lays it out (`origin`, `width`, `height` are
    /// paint's own; the layout call is the same one, so `RichTextPaint`'s segments and these agree, `LI-B`).
    ///
    /// - one hitbox per segment (a run wrapped over two lines, or a bidi run with two visual pieces, has several),
    ///   each the segment's `minX`..`maxX` by its **line's** box, under one numbered child id per resolved run
    ///   (`$link<n>`), so a press on one piece and a release on another of the same run still opens it;
    /// - each through `registerHandlers`, so the disabled, `allowsHitTesting`, clip and translation gates are the
    ///   ordinary ones (`LI-A`), with the pointing-hand style on the region (`LI-F`);
    /// - one accessibility link per run, labelled with the run's text, framed by the union of its pieces (probe
    ///   `LK12`: SwiftUI publishes one link element for a wrapped run), and only while a client collects.
    ///
    /// A destination `URL` cannot parse registers nothing (it could be neither opened nor handed to an action).
    @MainActor
    func registerTextLinks(_ resolved: ResolvedRichText, id: GlobalElementID, origin: Point<Pixels>,
                           width: Double, height: Double, action: OpenURLAction) {
        guard resolved.paints.contains(where: { $0.link != nil }) else { return }
        let laid = styledTextLines(resolved, system: textSystem, wrappingAt: width, height: height)
        let x = Double(origin.x.value), y = Double(origin.y.value)
        let layout = textSystem.layOut(resolved.text, wrappingAt: width, options: laid.options, origin: (x: x, y: y),
                                       scaleFactor: scaleFactor)
        let lines = layout.measurement.lines
        var unions: [Int: (id: GlobalElementID, minX: Double, minY: Double, maxX: Double, maxY: Double)] = [:]
        var order: [Int] = []
        for segment in layout.segments {
            guard let destination = resolved.paints[segment.run].link, let url = URL(string: destination) else { continue }
            let line = lines[segment.line]
            let top = y + line.top
            let runID = GlobalElementID.child(of: id, at: segment.run, name: ElementID("$link\(segment.run)"))
            var handlers = Handlers()
            handlers.onClick = { action(url) }
            handlers.pointer = PointerAttachment.style(.link, over: nil)
            let piece = Bounds(origin: Point(x: Pixels(Float(segment.minX)), y: Pixels(Float(top))),
                               size: Size(width: Pixels(Float(segment.maxX - segment.minX)),
                                          height: Pixels(Float(line.height))))
            registerHandlers(handlers, at: piece, id: runID, accessibleText: nil, synthesizesAccessibility: false)
            if var known = unions[segment.run] {
                known.minX = Swift.min(known.minX, segment.minX)
                known.maxX = Swift.max(known.maxX, segment.maxX)
                known.minY = Swift.min(known.minY, top)
                known.maxY = Swift.max(known.maxY, top + line.height)
                unions[segment.run] = known
            } else {
                unions[segment.run] = (runID, segment.minX, top, segment.maxX, top + line.height)
                order.append(segment.run)
            }
        }
        guard collectsAccessibility, !order.isEmpty else { return }
        // Each run's own text: its UTF-16 span of the whole string.
        var starts: [Int] = []
        var offset = 0
        for run in resolved.text.runs {
            starts.append(offset)
            offset += run.length
        }
        let units = Array(resolved.text.string.utf16)
        for run in order {
            guard let union = unions[run] else { continue }
            let lower = starts[run], upper = lower + resolved.text.runs[run].length
            let label = String(decoding: units[lower..<upper], as: UTF16.self)
            let bounds = Bounds(origin: Point(x: Pixels(Float(union.minX)), y: Pixels(Float(union.minY))),
                                size: Size(width: Pixels(Float(union.maxX - union.minX)),
                                           height: Pixels(Float(union.maxY - union.minY))))
            var node = AXNode(label: label)
            node.declarations.addedTraits.insert(.isLink)   // the published role is `.link` (`publishedRole`)
            recordAccessibility(text: nil, declared: node, at: bounds, id: union.id)
        }
    }
}
