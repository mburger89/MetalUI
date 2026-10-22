#!/bin/zsh
# Compile-time arms for item BG (presentationBackground, windowBackgroundDragBehavior, PointerStyle.shape);
# companion to swiftui-presentation-extras.swift. Evidence for rulings BG-G, BG-K in
# docs/superpowers/2026-10-22-presentation-extras-decisions.md.
#
# HOW TO RUN:  zsh docs/probes/swiftui-presentation-extras-typecheck.sh
#
# ARMS. T0 positive control: PointerStyle.image compiles on macOS (so a refusal below is the API's, not the
# harness's). T1: PointerStyle.shape(_:eoFill:size:) on macOS. T2: windowBackgroundDragBehavior on a View
# (separating arm for T3). T3: on a Scene (WindowGroup). T4: presentationBackground(_:) and
# presentationBackground(alignment:content:) on a popover's content. Plus the interface census line for each.
#
# RECORDED 2026-10-22 (BG design session), macOS 27.0, Apple Swift 6.4 (swiftlang-6.4.0.33.1):
#   T0 .image(Image, hotSpot:): compiles
#   T1 .shape(Circle(), size:): error: 'shape(_:eoFill:size:)' is unavailable in macOS
#   T2 Color.windowBackgroundDragBehavior(.enabled): error: value of type 'Color' has no member 'windowBackgroundDragBehavior'
#   T3 WindowGroup { }.windowBackgroundDragBehavior(.enabled): compiles
#   T4 popover content .presentationBackground(.red) and (alignment:content:): compiles
#   census (SwiftUI.swiftinterface): `public static func shape(_ shape: some Shape, eoFill: Swift.Bool = false,
#     size: CoreFoundation.CGSize) -> SwiftUI.PointerStyle` under @available(visionOS 2.0, *) @available(macOS, unavailable);
#     `Scene.windowBackgroundDragBehavior(_ behavior: WindowInteractionBehavior)` (macOS 15), `WindowInteractionBehavior`
#     = automatic / enabled / disabled; `presentationBackground<S: ShapeStyle>(_:)` and
#     `presentationBackground<V: View>(alignment: Alignment = .center, @ContentBuilder content:)` (macOS 13.3).
set -u
dir=$(mktemp -d)
arm() { # name, source
  print -r -- "$2" > "$dir/$1.swift"
  out=$(xcrun swiftc -typecheck "$dir/$1.swift" 2>&1 | grep -m1 "error:")
  print "$1: ${out:-compiles}"
}
arm T0 'import SwiftUI
struct V: View { var body: some View { Color.red.pointerStyle(.image(Image(systemName: "star"), hotSpot: .center)) } }'
arm T1 'import SwiftUI
struct V: View { var body: some View { Color.red.pointerStyle(.shape(Circle(), size: CGSize(width: 16, height: 16))) } }'
arm T2 'import SwiftUI
struct V: View { var body: some View { Color.red.windowBackgroundDragBehavior(.enabled) } }'
arm T3 'import SwiftUI
struct A: App { var body: some Scene { WindowGroup { Color.red }.windowBackgroundDragBehavior(.enabled) } }'
arm T4 'import SwiftUI
struct V: View { @State var s = true; var body: some View { Color.red.popover(isPresented: $s) { Text("x").presentationBackground(.red); Text("y").presentationBackground(alignment: .leading) { Color.green } } } }'
rm -rf "$dir"
