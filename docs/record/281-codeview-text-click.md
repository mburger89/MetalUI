# 281. CodeView text click (Alloy gap G35 PR B, `CV-AL`)

Branch `feat/codeview-text-click` (master `ca5dce27`). Decision `CV-AL` in `docs/superpowers/2026-11-07-code-view-decisions.md`. Class `M`; no divergence added or retired (220 live, next label 241). Alloy's answer 5 is binding: the click is consumed only when `hit.region == .text`; past the line end, a virtual row and the gutter act as a normal click.

## 1. API

`CodeView.onTextClick(modifiers: EventModifiers = .primary, perform: @escaping @MainActor (CodeHit) -> Void) -> CodeView`. `EventModifiers` is the framework's `Modifiers` (the `.keyboardShortcut` convention); `.primary` is Command on Apple and Control elsewhere (`SG-B`). `Modifiers` has no caps-lock bit, so no masking is needed.

## 2. Structure

The window's text stage passes `mouse.modifiers` to `CodeEditSession.press`. A new `textClick` on the session is checked before the gutter-bar handler: modifiers `==` the handler's and `plan.hit(at:).region == .text` clears `dragging`, calls the action (already inside `StateDispatch.dispatching(to:)`, `ID-F`) and returns, so the caret, selection and composition are untouched and a later drag extends nothing. Everything else falls through unchanged.

## 3. Tests

`Tests/MetalUITestingTests/CodeViewTextClickTests.swift`: `aPrimaryClickReportsItsOffsetAndLeavesTheCaret`, `aShiftPrimaryClickIsNotAPrimaryClick`, `aPlainClickStillPlacesTheCaretWithAHandlerSet`, `aPrimaryClickPastTheLineEndPlacesTheCaret`, `aPrimaryClickInTheGutterOrOnAVirtualRowActsAsNormal`, `theDefaultModifierIsThePlatformsPrimary`. Mutations are named in each doc comment and were each shown to fail (section 4).

## 4. Mutations

Each was run on macOS against the mutated source and failed, then restored: `modifiers.contains(click.modifiers)` fails `aShiftPrimaryClickIsNotAPrimaryClick`; removing the `return` after the action fails `aPrimaryClickReportsItsOffsetAndLeavesTheCaret` (the caret moves); `if true` in place of the `.text` region test fails `aPrimaryClickPastTheLineEndPlacesTheCaret` and `aPrimaryClickInTheGutterOrOnAVirtualRowActsAsNormal`; the default `[]` fails `theDefaultModifierIsThePlatformsPrimary`. On Apple `.primary` is `.command`, so only the Linux and Windows jobs exercise the Control half.
