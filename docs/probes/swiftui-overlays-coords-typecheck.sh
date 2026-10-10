#!/bin/zsh
# SwiftUI probe, compile-time half of swiftui-overlays-coords.swift (C15):
# which spellings SwiftUI's macOS SDK offers. Each arm is a one-file fixture
# type-checked with `xcrun swiftc -typecheck -target arm64-apple-macos15`;
# the line prints COMPILES or REFUSED (and the first error line).
#
# HOW TO RUN:  zsh docs/probes/swiftui-overlays-coords-typecheck.sh
#
# Positive controls: T0 (`\.displayScale` compiles) against T5–T8 (the
# window-size names); T1 (`onContinuousHover(perform:)`) against T2/T3 (the
# coordinate-space spellings); T9 a switch listing local/global/named
# (separating: T10 without `named` must refuse as non-exhaustive).
#
# RECORDED 2026-10-10 by the C15 design session; OUTPUT block at the end.

dir=$(mktemp -d)
arm() {
  local name=$1 body=$2
  print -r -- "import SwiftUI
struct Item: Identifiable { var id: Int }
@available(macOS 15, *)
struct V: View {
  @State var p: CGPoint = .zero
  var body: some View {
$body
  }
}" > $dir/f.swift
  local out
  if out=$(xcrun swiftc -typecheck -target arm64-apple-macos15 $dir/f.swift 2>&1); then
    print -r -- "$name: COMPILES"
  else
    print -r -- "$name: REFUSED -- $(print -r -- $out | grep -m1 'error:' | sed 's/.*error: //')"
  fi
}

arm "T0 control @Environment(\\.displayScale) read" '    let _ = EnvironmentValues().displayScale; return Color.clear'
arm "T1 control onContinuousHover(perform:)" '    Color.clear.onContinuousHover { _ in }'
arm "T2 onContinuousHover(coordinateSpace: .global)" '    Color.clear.onContinuousHover(coordinateSpace: .global) { _ in }'
arm "T3 onContinuousHover(coordinateSpace: .named(\"x\"))" '    Color.clear.onContinuousHover(coordinateSpace: .named("x")) { _ in }'
arm "T4 coordinateSpace(.named(\"x\")) and coordinateSpace(name:)" '    Color.clear.coordinateSpace(.named("x")).coordinateSpace(name: "y")'
arm "T5 EnvironmentValues().windowSize" '    let _ = EnvironmentValues().windowSize; return Color.clear'
arm "T6 EnvironmentValues().windowFrame" '    let _ = EnvironmentValues().windowFrame; return Color.clear'
arm "T7 EnvironmentValues().containerSize" '    let _ = EnvironmentValues().containerSize; return Color.clear'
arm "T8 EnvironmentValues().windowBounds" '    let _ = EnvironmentValues().windowBounds; return Color.clear'
arm "T9 switch CoordinateSpace { local, global, named } exhaustive" '    let s = CoordinateSpace.local
    switch s { case .local: break; case .global: break; case .named: break }
    return Color.clear'
arm "T10 switch CoordinateSpace { local, global } (separating)" '    let s = CoordinateSpace.local
    switch s { case .local: break; case .global: break }
    return Color.clear'
arm "T11 popover(isPresented:attachmentAnchor:arrowEdge:content:) with .point(.topLeading)" '    Color.clear.popover(isPresented: .constant(true), attachmentAnchor: .point(.topLeading), arrowEdge: .bottom) { Text("x") }'
arm "T12 popover(item:attachmentAnchor:arrowEdge:content:)" '    Color.clear.popover(item: Binding<Item?>.constant(nil), attachmentAnchor: .rect(.bounds), arrowEdge: .top) { (_: Item) in Text("x") }'
arm "T13 PopoverAttachmentAnchor.rect(.rect(CGRect))" '    let _: PopoverAttachmentAnchor = .rect(.rect(CGRect(x: 1, y: 2, width: 0, height: 0))); return Color.clear'
arm "T14 presentationBackground(.clear) on popover content" '    Color.clear.popover(isPresented: .constant(true)) { Text("x").presentationBackground(.clear) }'
arm "T15 a popoverStyle / presentationChrome modifier" '    Color.clear.popover(isPresented: .constant(true)) { Text("x").popoverStyle(.plain) }'
arm "T16 onGeometryChange frame(in: .named(\"x\"))" '    Color.clear.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("x")) }) { _ in }'
rm -rf $dir

# OUTPUT, recorded 2026-10-10, macOS 27.0 SDK, Apple Swift 6.4:
#
#   T0 control @Environment(\.displayScale) read: COMPILES
#   T1 control onContinuousHover(perform:): COMPILES
#   T2 onContinuousHover(coordinateSpace: .global): COMPILES
#   T3 onContinuousHover(coordinateSpace: .named("x")): COMPILES
#   T4 coordinateSpace(.named("x")) and coordinateSpace(name:): COMPILES
#   T5 EnvironmentValues().windowSize: REFUSED -- value of type 'EnvironmentValues' has no member 'windowSize'
#   T6 EnvironmentValues().windowFrame: REFUSED -- value of type 'EnvironmentValues' has no member 'windowFrame'
#   T7 EnvironmentValues().containerSize: REFUSED -- value of type 'EnvironmentValues' has no member 'containerSize'
#   T8 EnvironmentValues().windowBounds: REFUSED -- value of type 'EnvironmentValues' has no member 'windowBounds'
#   T9 switch CoordinateSpace { local, global, named } exhaustive: COMPILES
#   T10 switch CoordinateSpace { local, global } (separating): REFUSED -- switch must be exhaustive
#   T11 popover(isPresented:attachmentAnchor:arrowEdge:content:) with .point(.topLeading): COMPILES
#   T12 popover(item:attachmentAnchor:arrowEdge:content:): COMPILES
#   T13 PopoverAttachmentAnchor.rect(.rect(CGRect)): COMPILES
#   T14 presentationBackground(.clear) on popover content: COMPILES
#   T15 a popoverStyle / presentationChrome modifier: REFUSED -- value of type 'Text' has no member 'popoverStyle'
#   T16 onGeometryChange frame(in: .named("x")): COMPILES
