# 167 — Decorations after transparent scopes (`ES-`)

2026-10-31, branch `fix/scope-decorations` from master `63cc5af1`. Requested by the MetalFlow app session: `Text("x").lineLimit(1).padding(…)` / `.accessibilityIdentifier(…)` did not compile, because `.lineLimit` returns a transparent `EnvironmentScope` (divergence 120). The same shape was behind its earlier `.disabled(true).accessibilityIdentifier(…)` report (record 166, `DA-B`).

## What changed

- `ES-A`: `EnvironmentScope`, `LifecycleScope`, `PresentationScope` and `ToolbarScope` gain `Element where Content: Element` and `StyledElement where Content: StyledElement`, forwarding `style`, `decoration`, `elementID` and `handlers` to the content. Every environment modifier (`lineLimit`, `disabled`, `environment`, `controlSize`, `theme`, the window preferences …), the lifecycle modifiers, the presentation modifiers and `toolbar`/`searchable` now take any decoration after them, and can be a window's root (the `AS-N` and `MD-S` container workarounds end).
- `ES-B`: `GeometryChangeScope` is left alone — it measures its content, so a forwarded decoration would fall inside the measured size where SwiftUI's is outside. Divergence 120 is narrowed to `.onGeometryChange` only (still 178 live).
- `ES-C`: the conformance made `StyledElement.id(_:) -> Self` name the content inside the scope; each scope now declares `id(_:) -> IdentifiedGroup<Self>` so `.id` wraps the scope as before. Caught by the first full run.

Rulings, the mutation table (two unobservable forwards: `style`, `elementID`) and the unconverted scopes are in `docs/superpowers/2026-10-31-scope-decorations-decisions.md`.

## Counts

`swift package clean`, native build, `swift test --build-system native --no-parallel --skip AppKitPresentationTests` (screen locked): **4601 tests passed**, `FR-J no-argument frame: succeeded=true`. Guards 283 (281 + the two in `ScopeDecorationCompileGuards.swift`, from the diff). Closeout scripts print nothing.
