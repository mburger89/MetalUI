#!/bin/zsh
# RUN WITH zsh OR EXECUTE DIRECTLY. Test-harness design (record §91, rulings
# HT-B, HT-F in docs/superpowers/2026-10-09-test-harness-decisions.md).
#
# Question: what does Apple give a SwiftUI app for testing its UI, so MetalUI's
# public harness (`MetalUITesting`) can take its spellings from it where one
# exists? Three groups of arms.
#
#   X  XCUITest's element vocabulary on macOS (out of process; XCUIElement).
#      X1 must typecheck: subscript/identifier queries, click, doubleClick,
#      rightClick, hover, typeText, typeKey(_:modifierFlags:),
#      scroll(byDeltaX:deltaY:), click(forDuration:thenDragTo:), frame,
#      identifier, label, isEnabled, menuBars, dialogs, sheets.
#      X2 (separating arm) must NOT typecheck: `rightTap()`, a member the SDK
#      does not declare — proves the typecheck reads XCUIElement's real
#      interface rather than accepting anything.
#   S  SwiftUI's own interface (SwiftUI + SwiftUICore .swiftinterface).
#      S0 (positive control) `class ImageRenderer` and `onGeometryChange`
#      are found — the grep reads the right files.
#      S1 an in-process input/test host: words `simulate`, `Simulat`,
#      `TestHost`, `func inject`, `ViewInspect` — counted.
#   R  Run: SwiftUI's headless surfaces. R1 ImageRenderer renders a view to a
#      CGImage with no window; R2 NSHostingView's fittingSize is the only
#      size read-back from outside the view; R3 a per-view frame is readable
#      only from inside the view (onGeometryChange) after a hosting view
#      lays out.
#
# RECORDED OUTPUT (2026-10-09, Xcode-beta, Apple Swift 6.4
# swiftlang-6.4.0.33.1, macOS 27):
#   X1 typecheck exit 0
#   X2 typecheck exit 1 (error: value of type 'XCUIElement' has no member 'rightTap')
#   S0 class ImageRenderer: 2  onGeometryChange: 10
#   S1 simulate: 0  Simulat: 0  TestHost: 0  func inject: 0  ViewInspect: 0
#   R1 ImageRenderer cgImage 80x24 (no window)
#   R2 NSHostingView fittingSize 80.0x24.0
#   R3 onGeometryChange frame (0.0, 0.0, 80.0, 24.0) read inside the view
# Reading: SwiftUI has no in-process input injection or element query (S1 0
# with S0 found); its offscreen surface is ImageRenderer (pixels) and a hosting
# view (one size); UI tests drive an app out of process through XCUITest,
# whose action vocabulary is X1. MetalUI's harness takes X1's names for its
# actions (HT-F) and gpui's TestAppContext/VisualTestContext shape for the
# in-process host (HT-B; gpui is not SwiftUI and was read, not probed).
set -u
DIR=$(mktemp -d)
FW=$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks
SDK=$(xcrun --show-sdk-path)

cat > $DIR/x1.swift <<'EOF'
import XCTest
@MainActor func arms(_ app: XCUIApplication, _ other: XCUIElement) {
    let e = app.buttons["save"]
    _ = app.descendants(matching: .any).matching(identifier: "save").firstMatch
    e.click(); e.doubleClick(); e.rightClick(); e.hover()
    e.typeText("abc"); e.typeKey("s", modifierFlags: .command)
    e.scroll(byDeltaX: 0, deltaY: -10)
    e.click(forDuration: 0.5, thenDragTo: other)
    _ = e.frame; _ = e.identifier; _ = e.label; _ = e.isEnabled; _ = e.exists
    _ = app.menuBars.menuBarItems["View"]; _ = app.dialogs.firstMatch; _ = app.sheets
}
EOF
cat > $DIR/x2.swift <<'EOF'
import XCTest
@MainActor func separating(_ e: XCUIElement) { e.rightTap() }
EOF
xcrun swiftc -typecheck -F $FW $DIR/x1.swift > $DIR/x1.log 2>&1; echo "X1 typecheck exit $?"
xcrun swiftc -typecheck -F $FW $DIR/x2.swift > $DIR/x2.log 2>&1; echo "X2 typecheck exit $? ($(grep -m1 'error:' $DIR/x2.log | sed 's/.*error: //'))"

UI=$(find $SDK/System/Library/Frameworks/SwiftUI.framework -name 'arm64e-apple-macos.swiftinterface' | head -1)
CORE=$(find $SDK/System/Library/Frameworks/SwiftUICore.framework -name 'arm64e-apple-macos.swiftinterface' | head -1)
count() { cat $UI $CORE | grep -c -- "$1" }
echo "S0 class ImageRenderer: $(count 'class ImageRenderer')  onGeometryChange: $(count onGeometryChange)"
echo "S1 simulate: $(count 'func simulate')  Simulat: $(count Simulat)  TestHost: $(count TestHost)  func inject: $(count 'func inject')  ViewInspect: $(count ViewInspect)"

cat > $DIR/r.swift <<'EOF'
import SwiftUI
import AppKit
@MainActor final class Box { var frame: CGRect = .zero }
struct Probe: View {
    let box: Box
    var body: some View {
        Color.red.frame(width: 80, height: 24)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { box.frame = $0 }
    }
}
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Color.red.frame(width: 80, height: 24))
    if let image = renderer.cgImage { print("R1 ImageRenderer cgImage \(image.width)x\(image.height) (no window)") }
    let box = Box()
    let host = NSHostingView(rootView: Probe(box: box))
    print("R2 NSHostingView fittingSize \(host.fittingSize.width)x\(host.fittingSize.height)")
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    print("R3 onGeometryChange frame \(box.frame) read inside the view")
}
EOF
xcrun swiftc -O $DIR/r.swift -o $DIR/r > $DIR/r.log 2>&1 && $DIR/r 2>/dev/null | grep '^R'
rm -rf $DIR
