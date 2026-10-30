# 166. MetalFlow dashboard (DA-, DX-)

Two lanes, **not plan tasks**, requested from the MetalFlow app session (a dashboard built on MetalUI), on `fix/metalflow-dashboard` from `feat/metalflow-gaps` (PR #152, record 165).

## 1. The lanes

| prefix | what | decisions doc | divergence |
|---|---|---|---|
| `DA-` | an identified `TextField`/`TextEditor` keeps its role and text (`AXNode.fillControl`, `DA-C`); container identifiers: `DA-A` **refuted**, `DA-B` no source change | `docs/superpowers/2026-10-30-dashboard-ax-decisions.md` | none |
| `DX-` | the harness timeline clock, so `advance(by:)` alone re-evaluates a periodic `TimelineView` (`DX-A`); SwiftUI's padding spellings on both vocabularies (`DX-B`); breaking options not taken (`DX-C`) | `docs/superpowers/2026-10-30-dashboard-text-timeline-decisions.md` | 208 (new) |

## 2. The refuted ruling

`DA-A` proposed that a container's identifier leave its children's alone. A probe (`docs/probes/swiftui-accessibility-identifier-nesting.swift`) showed SwiftUI overwrites a descendant's identifier with the container's, so MetalUI's distribution is already right; an app that wants both writes `.accessibilityElement(children: .contain)`. The rule went into `docs/rules/input-focus.md` as measured, and `DA-M9` pins the overwrite.

## 3. Divergences and counts

Divergence 208 added (record §04); 207 was never published and is unused. Header: 178 live, next label 209.

Root 4592 tests passed with `AppKitPresentationTests` skipped (the screen was locked), `--build-system native --no-parallel`, after `swift package clean`; an unfiltered figure was not measured (about 4601 if its 9 tests pass). Guards 281: record 165's 279 plus two in `TextModifierParityCompileGuards.swift`, counted from the diff; `FR-J no-argument frame: succeeded=true` printed. Both closeout scripts print nothing.

## 4. Rules added

`input-focus.md` (identifiers on containers, `DA-`), `tooling.md` (harness timeline clock, `DX-A`), `layout.md` (padding spellings, `DX-B`); prefix rows `DA-` (next `DA-D`) and `DX-` (next `DX-D`) in `decision-prefixes.md`. Mutation tables are in the decisions docs.
