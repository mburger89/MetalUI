#!/bin/sh
# Does calling a `@available(*, deprecated)` method from inside a deprecated
# PROTOCOL WITNESS, or through a generic constraint, print a deprecation warning?
# Plan task 7, stage 6a, ruling LR-CV in
# docs/superpowers/2026-09-17-engine-replacement-decisions.md (record §30 §3).
#
# This is a probe of the Swift COMPILER, not of SwiftUI: no SwiftUI claim is
# made. Stage 6a deprecates `LayoutPass.requestNode`/`requestLeaf` under a
# 0-`warning:` gate, and five test fixtures plus the stage's exit test exist to
# exercise exactly those registrars (they record the trap a legacy-spelled
# custom element hits under the proposal authority). They cannot move, and they
# must not warn. The question is which spelling lets them call the deprecated
# registrar without a warning reaching the build log.
#
# THREE ARMS, one module boundary (the deprecated method is in `Lib`, as the
# registrars are in `MetalUI`; a same-module call warns the same way):
#   use.swift  `direct`            — a plain call.                 POSITIVE CONTROL: must warn.
#              `insideDeprecated`  — a call inside a function itself marked deprecated.
#              `viaWitness`        — a call through a generic constraint on a protocol
#                                    the deprecated method witnesses.
#   use2.swift `Fixture.requestLayout` — the fixture shape: an `Element`-like
#                                    requirement witnessed by a method marked
#                                    deprecated, called through a generic `render`.
#
# HOW TO RUN (Apple's toolchain; the swiftly `swift` first on PATH is a
# swift.org build, ruling SA-O):
#
#     sh docs/probes/swift-deprecated-witness-silence.sh
#
# RECORDED OUTPUT, 2026-09-23, Apple Swift version 6.4 (swiftlang-6.4.0.33.1
# clang-2100.3.33.1), macOS 27.0 — exactly one warning, on `direct` (line 12),
# and nothing for use2.swift under either language mode:
#
#     use.swift:12:46: warning: 'requestNode(style:children:)' is deprecated: use native [#DeprecatedDeclaration]
#     == use2 swift 5
#     == use2 swift 6
#
# RE-RUN 2026-09-23 by the stage-6a critic round (LR-DA), same toolchain: the three
# lines above byte for byte, plus the separating arm it added (use3.swift =
# use2.swift with the witness's attribute deleted), which warns in both modes —
# so use2's silence is the attribute's doing, not the fixture shape's:
#
#     == use3 (use2 without the witness attribute) swift 5
#     use3.swift:4:46: warning: 'requestNode(style:children:)' is deprecated: use native [#DeprecatedDeclaration]
#     == use3 (use2 without the witness attribute) swift 6
#     use3.swift:4:46: warning: 'requestNode(style:children:)' is deprecated: use native [#DeprecatedDeclaration]
#
# READING. The positive control warns, so the instrument can fail. A call
# inside a deprecated declaration does not warn, and a deprecated method used
# as a protocol witness does not warn at the conformance, nor at a generic call
# site that reaches it through the requirement. So a fixture whose
# `requestLayout` is marked `@available(*, deprecated, message: …)` calls the
# deprecated registrars silently, and `Frame.render` reaches that witness
# through `Element`'s requirement without a warning either. What this does NOT
# show: that a later toolchain keeps the behaviour — the 0-`warning:` gate on
# every build is what would notice.
set -e
DIR=$(mktemp -d)
cd "$DIR"
cat > lib.swift <<'EOF'
@MainActor
public struct Pass {
    public init() {}
    @available(*, deprecated, message: "use native")
    public func requestNode(style: Int, children: [Int]) -> Int { style + children.count }
}
EOF
cat > use.swift <<'EOF'
import Lib
@MainActor protocol LegacyRegistering {
    func requestNode(style: Int, children: [Int]) -> Int
}
extension Pass: LegacyRegistering {}
@MainActor func viaWitness(_ p: Pass) -> Int {
    func call<P: LegacyRegistering>(_ p: P) -> Int { p.requestNode(style: 1, children: []) }
    return call(p)
}
@available(*, deprecated)
@MainActor func insideDeprecated(_ p: Pass) -> Int { p.requestNode(style: 1, children: []) }
@MainActor func direct(_ p: Pass) -> Int { p.requestNode(style: 1, children: []) }
EOF
cat > use2.swift <<'EOF'
import Lib
@MainActor protocol Element { func requestLayout(_ p: Pass) -> Int }
struct Fixture: Element {
    @available(*, deprecated, message: "spelled with the deprecated registrar on purpose")
    func requestLayout(_ p: Pass) -> Int { p.requestNode(style: 1, children: []) }
}
@MainActor func render<E: Element>(_ e: E) -> Int { e.requestLayout(Pass()) }
@MainActor func use() -> Int { render(Fixture()) }
EOF
xcrun swiftc -emit-module -parse-as-library -module-name Lib lib.swift -o Lib.swiftmodule
xcrun swiftc -typecheck -swift-version 6 -diagnostic-style=llvm -I . use.swift 2>&1 | grep -E "warning:|error:" || true
for v in 5 6; do
    echo "== use2 swift $v"
    xcrun swiftc -typecheck -swift-version $v -diagnostic-style=llvm -I . use2.swift 2>&1 | grep -E "warning:|error:" || true
done
# Separating arm (added by the stage-6a critic round, LR-DA): use2.swift with the
# attribute on the witness removed. It MUST warn once, or use2's silence says
# nothing about the attribute.
sed '/@available(\*, deprecated, message: "spelled with/d' use2.swift > use3.swift
for v in 5 6; do
    echo "== use3 (use2 without the witness attribute) swift $v"
    xcrun swiftc -typecheck -swift-version $v -diagnostic-style=llvm -I . use3.swift 2>&1 | grep -E "warning:|error:" || true
done
