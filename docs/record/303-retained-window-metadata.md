# 303. Window preferences ride the graft journal (`RW-X`)

Branch `fix/retained-window-metadata`. Ruling `RW-X`. Class `M`; no public API, no divergence.
Source: Alloy's warmed typing trace (20 keys into a `CodeView`, `METALUI_TRACE_RETAINED=1`): 40 decisions "because windowMetadata".

## Why

`BuildAudit` counted `openURLHandlers` and six `collected*` window preferences and refused a graft when a build moved either. Alloy registers none of `.navigationTitle`, `.navigationDocument` or `.onOpenURL`; the source is `.windowTitleBarMetrics` on `AlloyScreen` (`RootView.swift`) and `.containerBackground(.thinMaterial, for: .window)` in `WindowBackdropView`. Both report every build, the first report moves the audit, so the occurrence holding them and every `.equatable()` ancestor were ineligible every frame.

## Change

`Frame.reportWindowPreference(_:)` (`WindowShell.swift`) takes every report from `EnvironmentScope.reportingPreference`, journals it as `.windowPreference` inside a graft window and applies the first-wins (or append) rule; `reapply` calls it again for a graft. The audit fields and the `windowMetadata` refusal are removed.

## Numbers (`RetainedWindowMetadataTests`)

A plain root over a retained column holding an occurrence with title, subtitle, document, title-bar metrics, dismiss behavior and `.onOpenURL`: `windowMetadata` ineligibles **2 per steady frame before, 0 after**; the column grafts every frame, **2 element requests per frame**.

## Tests

Differentials against a retention-off window: what the platform was told (title, subtitle, document, dismiss, metrics) after grafts, an `app.open` reaching the grafted handler in order, a changed title, an earlier sibling's title beating a grafted one and yielding when it leaves. Mutations: the replay case emptied (title, subtitle, document, dismiss pins red); the title applied unconditionally (the sibling pin red). Before the change the count pin reads 2 (the behaviour pins already passed: the build ran).
