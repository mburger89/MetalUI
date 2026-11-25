# 410 - SwiftLint findings in the product source

Date: 2026-11-24. Branch `fix/lint-sources`. Scope: `Sources/` and `Backends/SDL/Sources/`
(`Tests/` and `Examples/` are the sibling lint pass).

## What changed

- **Crash risks.** 306 `force_unwrapping`, 23 `force_cast`, 7 `implicitly_unwrapped_optional`, 1
  `force_try` were each classified. One was a real crash on plausible input (a): an empty text
  into `BidiParagraph`, because SheenBidi's `SBAlgorithmCreate` answers NULL for a zero-length
  sequence and the wrapper stored it as non-optional (`BidiEdgeInputTests`, red before the fix,
  five tests). The rest were guaranteed by an invariant (b) or a system call that fails only on
  exhaustion (c); each now says so in code, at the cost of the `!` it replaced:
  `Dictionary[required:]` and `Optional.required` (in-place, no extra lookup), `scopeResult`
  for a value a scope helper's body stores, `trapCast` for `as!` on a value the code itself
  stored, `guard let ... preconditionFailure("<invariant>")`, or optional chaining/`compactMap`
  where absence was already tolerated. Empty-buffer `baseAddress!` sites (blur, atlas resize,
  renderer uploads, pty write, SDL GPU uploads) became no-ops on an empty buffer.
- **Mechanical rules** (no behaviour change): `empty_count`, `is_disjoint` (with
  `RasterRect.isDisjoint(with:)`), `duplicate_imports`, `lower_acl_than_parent`,
  `redundant_discardable_let` (`let _: Void =` in result builders, where `let _ =` is required),
  `unused_closure_parameter`, `unused_enumerated`, `orphaned_doc_comment`, `unused_setter_value`
  (`set { _ = newValue }`, writes dropped on purpose).
- **Delegates.** `DropDelegate` is not class-bound in SwiftUI and `onDrop(of:delegate:)` stores the
  value, so the strong `delegate` in `DragAndDrop.swift` and the `class_delegate_protocol` hit are
  by design (same-line `swiftlint:disable:this`, reason in the doc comment); the app delegate in
  `AppKitPlatform` is the owning reference. No retain cycle: the box owns the delegate and nothing
  it holds points back.

## Constraints kept

No public API change (the inventory scripts print nothing); no new allocation on a hot path.
`legacy_swiftui_aspect_ratio` hits were all in `Tests/`.
