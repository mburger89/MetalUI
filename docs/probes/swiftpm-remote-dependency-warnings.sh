#!/bin/zsh
# SwiftPM probe: does a consumer's `swift build` print the warnings a
# dependency's sources produce — by URL (a remote dependency) and by path (a
# local one)? (task-followups branch, ruling TF-B in
# docs/superpowers/2026-10-08-task-followups-decisions.md.) Test 1.7
# (`aCrossPlatformPackageBuildsItsSDLAppByURL`) builds MetalUI as a URL
# dependency; this measures what such a build can show.
#
# HOW TO RUN:  zsh docs/probes/swiftpm-remote-dependency-warnings.sh [scratch-dir]
#
# `Dep` holds three source warnings (an unused `let`, a never-mutated `var`,
# a deprecated call). Arms:
# - LOCAL (positive control): `.package(path:)` — the dependency's warnings
#   print.
# - URL (separating): `.package(url: "file://…", revision:)` at one commit —
#   the same sources.
# - URL-MANIFEST: the URL arm with the consumer's OWN source holding an unused
#   `let` — the consumer's warnings still print.
#
# RECORDED 2026-10-07 by the task-followups design session, macOS 27.0.1,
# Apple Swift 6.4 (swiftlang-6.4.0.33.1), default build system:
#   LOCAL warnings=6
#   URL warnings=0
#   URL-OWN warnings=2
# (URL-OWN's one unused `let` prints two `warning:` lines in Swift 6.4's
# diagnostic style — the summary line and the source excerpt's — each with
# ANSI colour codes around, not inside, "warning:".)
# Reading: SwiftPM suppresses every source warning of a remote (URL)
# dependency; a local one's print; the root package's own print. A filter on
# a URL consumer's output therefore never sees a MetalUI source warning — only
# SwiftPM's own diagnostics about the graph (e.g. PX-H item 3's "couldn't find
# pc file") and the consumer's own sources. Re-measured in CI's Linux image by
# the implementing lane (spec §5, measurement MT2.3).
set -e
S=${1:-$(mktemp -d)}
rm -rf $S/Dep $S/UrlConsumer $S/PathConsumer
mkdir -p $S/Dep/Sources/Dep $S/UrlConsumer/Sources/UrlConsumer $S/PathConsumer/Sources/PathConsumer
cat > $S/Dep/Package.swift <<'P'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Dep", products: [.library(name: "Dep", targets: ["Dep"])], targets: [.target(name: "Dep")])
P
cat > $S/Dep/Sources/Dep/Dep.swift <<'P'
public func dep() -> Int { let unused = 3; var never = 4; return 1 }
@available(*, deprecated) public func old() {}
public func callsOld() { old() }
P
(cd $S/Dep && git init -q && git add -A && git -c user.email=p@p -c user.name=p commit -qm dep)
C=$(cd $S/Dep && git rev-parse HEAD)
cat > $S/PathConsumer/Package.swift <<P
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PathConsumer", dependencies: [.package(path: "$S/Dep")],
  targets: [.executableTarget(name: "PathConsumer", dependencies: ["Dep"])])
P
echo 'import Dep; print(dep())' > $S/PathConsumer/Sources/PathConsumer/main.swift
cat > $S/UrlConsumer/Package.swift <<P
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "UrlConsumer", dependencies: [.package(url: "file://$S/Dep", revision: "$C")],
  targets: [.executableTarget(name: "UrlConsumer", dependencies: ["Dep"])])
P
echo 'import Dep; print(dep())' > $S/UrlConsumer/Sources/UrlConsumer/main.swift
echo "LOCAL warnings=$(cd $S/PathConsumer && swift build 2>&1 | grep -c 'warning:' || true)"
echo "URL warnings=$(cd $S/UrlConsumer && swift build 2>&1 | grep -c 'warning:' || true)"
echo 'import Dep; func own() { let unusedHere = 1 }; print(dep())' > $S/UrlConsumer/Sources/UrlConsumer/main.swift
echo "URL-OWN warnings=$(cd $S/UrlConsumer && swift build 2>&1 | grep -c 'warning:' || true)"
