// SwiftUI probe: when does a flexible frame's WIDTH answer not depend on its child (G48, MetalUI `HS-M`)?
//
// `HSplitView` reads each pane at three proposals along its axis (0, nil, infinity). When the pane is a flexible frame, some of
// those answers are the frame's own and the child cannot change them; measuring the child for them is wasted work. This probe
// measures one frame over a child that answers a fixed width (10, 500 or 1500, whatever the proposal) and prints, per frame and
// proposal, the two answers and whether they agree.
//
// HOW TO RUN (headless; no window; exits by itself):
//
//   xcrun swiftc -parse-as-library docs/probes/swiftui-flex-frame-determined.swift -o /tmp/ffd && /tmp/ffd
//
// RECORDED OUTPUT (macOS 27.2.1, 2026-11-24; "10 | 500 | 1500" are the frame's answers over a child of width 10, 500 and 1500; `=` agree,
// `!` the child shows through; inf is infinity):
//
//   (filled in below by the run)
//
// READ: see ruling `HS-M`. A frame is child-independent on an axis at a proposal when it has a fixed size, or a maximum AND a
// minimum with a non-nil proposal (clamp(proposal, min, max)), or a nil proposal with an ideal (clamp(ideal, min, max)). A
// maximum alone answers max(proposal, child) (the child shows through), a minimum alone or no bound answers the child.
import SwiftUI

struct Fixed: Layout {
    let width: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { CGSize(width: width, height: 20) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}

@MainActor func answer(_ frame: @escaping (AnyView) -> AnyView, child: CGFloat, proposal: ProposedViewSize) -> String {
    let host = ProposalHost(content: frame(AnyView(Fixed(width: child) { Color.clear })), proposal: proposal)
    host.run()
    return host.result ?? "?"
}

/// Asks a layout view for its size at a proposal through `NSHostingView`'s `sizeThatFits`-equivalent: `fittingSize` is for the
/// unspecified proposal only, so a custom root `Layout` is asked at each proposal by wrapping it in a second probing layout.
@MainActor final class ProposalHost {
    let content: AnyView
    let proposal: ProposedViewSize
    var result: String?
    init(content: AnyView, proposal: ProposedViewSize) { self.content = content; self.proposal = proposal }
    func run() {
        struct Asker: Layout {
            let proposal: ProposedViewSize
            let sink: (CGSize) -> Void
            func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
                let s = subviews[0].sizeThatFits(proposal); sink(s); return s
            }
            func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
        }
        var size = CGSize.zero
        let view = Asker(proposal: proposal, sink: { size = $0 }) { content }
        let renderer = ImageRenderer(content: view.frame(width: 1, height: 1))
        renderer.proposedSize = ProposedViewSize(width: 1, height: 1)
        _ = renderer.cgImage
        result = size.width.isInfinite ? "inf" : String(format: "%g", size.width)
    }
}

@main struct Main {
    @MainActor static func main() {
        let frames: [(String, (AnyView) -> AnyView)] = [
            ("min320 max inf        ", { AnyView($0.frame(minWidth: 320, maxWidth: .infinity)) }),
            ("min200 ideal250 max380", { AnyView($0.frame(minWidth: 200, idealWidth: 250, maxWidth: 380)) }),
            ("min240 max800         ", { AnyView($0.frame(minWidth: 240, maxWidth: 800)) }),
            ("max380 only           ", { AnyView($0.frame(maxWidth: 380)) }),
            ("max inf only          ", { AnyView($0.frame(maxWidth: .infinity)) }),
            ("min240 only           ", { AnyView($0.frame(minWidth: 240)) }),
            ("ideal250 only         ", { AnyView($0.frame(idealWidth: 250)) }),
            ("min100 ideal250       ", { AnyView($0.frame(minWidth: 100, idealWidth: 250)) }),
            ("fixed 150             ", { AnyView($0.frame(width: 150)) }),
            ("no frame              ", { $0 }),
        ]
        let proposals: [(String, ProposedViewSize)] = [
            ("0", ProposedViewSize(width: 0, height: 100)), ("nil", ProposedViewSize(width: nil, height: 100)),
            ("100", ProposedViewSize(width: 100, height: 100)), ("500", ProposedViewSize(width: 500, height: 100)),
            ("900", ProposedViewSize(width: 900, height: 100)), ("inf", ProposedViewSize(width: .infinity, height: 100)),
        ]
        print("frame                   proposal: answer over child 10 | 500 | 1500 (= child-independent, ! child shows through)")
        for (name, frame) in frames {
            var cells: [String] = []
            for (pname, p) in proposals {
                let a = answer(frame, child: 10, proposal: p), b = answer(frame, child: 500, proposal: p), c = answer(frame, child: 1500, proposal: p)
                cells.append("\(pname): \(a)|\(b)|\(c)\(a == b && b == c ? "=" : "!")")
            }
            print(name + "  " + cells.joined(separator: "  "))
        }
        exit(0)
    }
}
