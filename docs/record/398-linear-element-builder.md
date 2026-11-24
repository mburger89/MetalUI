# 398: `ElementBuilder` is linear: `buildBlock<each>` and `TupleGroup` (`PE-AB`, Sift gap G17, class A, no divergence)

Branch `feat/linear-element-builder`, base master `595c474a`. **Number 398**: 396 is taken twice on other branches
(`feat/code-style-faces`, `fix/typetext-newline`) and 397 may be too; the later merge renumbers and says so in its header.

## The bug

Sift (`~/Developer/Sift`, `MapToolbar.swift` at `91cd941`): an 11-child toolbar `HStack` in a debug build needed about 0.93 MB of stack and
overflowed the 1 MB Windows test-worker thread (Swift Testing runs every test, `@MainActor` ones included, on a non-main 1 MB thread there).
Cause, measured by `StackMeter` and the object-file frames: `ElementBuilder.buildPartialBlock(accumulated:next:)`. At `-Onone` each
intermediate `Pair<Pair<…>>` of the chain gets a stack slot holding the whole prefix, so a builder closure's frame is quadratic in its
child count.

## The change

- `ElementBuilder` and `ProposalContentBuilder` lose both `buildPartialBlock` overloads (the compiler prefers them whenever they exist) and gain
  `buildBlock<G>(_:) -> G` (one statement, no wrapper) and `buildBlock<each G: ElementGroup>(_:) -> TupleGroup<repeat each G>`;
  `buildBlock()` stays.
- `TupleGroup<each Member>` (`ElementGroup.swift`): the members in one inline tuple. `requestGroupLayout`, `prepaintGroup` and `paintGroup`
  visit them in source order with the **same** cursor, **mutating each member where the tuple stores it** (`TupleGroup.slot` finds it at the
  offset a struct's field would have, pinned by `theTupleGroupFindsEachMemberWhereTheTupleStoresIt` against the compiler's own tuple offsets). It also conforms to `ProposalElementGroup`, `LazyFlattenable`, `LazyTreeType`, `LazyTreeFlattenable`,
  `LazyStampable` and `ToolbarPickerOptions`, as `Pair` did (pack iteration, which has no `where`).
- `Pair` stays (the framework's own controls assemble it by hand); `Stepper` and `PullDownMenu` spell `TupleGroup` where their builder blocks'
  types are named.
- `StackMeter.sample()`: one sample per block (the chain sampled once per statement); the sample sees the same closure frame.

Not reachable from Swift 6.4.2 (swiftlang-6.4.2.1.9): `#expect(tree.content.members.0.count == 3)` on a tuple of a pack crashes SILGen
(`signal 11`, "silgen emitFunction"); four tests in `ComponentTests.swift` bind `let members = tree.content.members` first.

## The first version overflowed Windows at layout, and why the members are mutated in place

The PR's first push rebuilt the members tuple from a pack expansion of copies (`let steps = (repeat visit(each members))`, then
`members = (repeat (each steps).group)`). Debug frames then held two copies of each level's whole subtree besides its layouts, so the
layout recursion was deeper than `Pair`'s (whose `first` and `second` are mutated through `self`): `Build and replay (Windows x64, D3D12)`
died with `Stack overflow` in `DemoCapture.exe`, `Thread 0`, `TupleGroup.requestGroupLayout` repeated through `Column`, `Row` and `Box`
(the 1 MB main thread). Mutating the members in place through their addresses removes the copies. `stackHighWater` of production trees
(build, layout, prepaint and paint at 1200 by 800, bytes, debug, macOS arm64), `Pair` chain then in-place `TupleGroup`: demo 905 264 then
778 080, controls 1 880 256 then 1 549 168, looks 1 360 400 then 1 223 488, text input 177 632 then 129 520, menus 1 045 952 then 991 920,
drag and drop 415 712 then 368 288, services 359 808 then 364 336, native layout preview 94 032 then 96 256 (the last two are the only
rises, 1 to 2 percent); the `ComponentStackTests` pane 562 864 then 387 680.

## Numbers (macOS arm64, debug, `StackMeter` high-water of the component's getter)

| shape | `buildPartialBlock` chain | `buildBlock<each>` |
|---|---|---|
| 4 `Button`s | 195 KiB | 139 KiB |
| 8 `Button`s | 491 KiB | 277 KiB |
| 11 `Button`s | 802 KiB | 381 KiB |
| 16 `Button`s | 1472 KiB | 553 KiB |
| 16 over 8 | 3.0 | 2.0 |
| Sift toolbar shape (getter) | 926 KiB | 522 KiB |
| smallest passing thread for the shape | 1024 KiB (fails at 896) | 576 KiB (fails at 512) |

Release (`sub sp` of the toolbar component's getter in the object file, `-c release`): 3632 bytes before, 2000 after; the whole shape
is a few KB either way. The toy's 12, 28 and 40 KB for 4, 8 and 11 children measured the builder alone with tiny members; real children
are 4 KB values and `Button(…).keyboardShortcut(…).accessibilityIdentifier(…)` makes four per child in a debug frame, so the remainder is the
children's own expression temporaries (about 35 KiB per button), not the builder. **The cross-platform guard therefore builds on 768 KiB**, not the
512 KiB first proposed (it passes at 576).

## Identity and cost: nothing moved

- `elevenChildrenOfOneBlockKeepTheirFlatIdsAndTheirState` (`LinearBuilderTests.swift`): eleven native leaves, ids `.positional(0)` to
  `.positional(10)` under one container id in every frame, `@State` at position 7 survives three frames. **Passes unchanged at
  `595c474a`.** `elevenChildrenKeepTheirAccessibilityIdsAndTheirTabOrder` (`MetalUITestingTests`): node-id paths `/positional(0)/positional(i)`,
  tree order and the Tab walk; also unchanged at `595c474a`.
- Steady-frame cost: the first `requestGroupLayout` allocated two more per frame (`aNonAnimatableComponentAllocatesWhatItDid`: 399 for 397;
  a nested function capturing the node array boxed it, and `+=` on the empty array allocated where `Pair`'s `+` allocated once for two); a
  static helper taking `inout` parameters and taking the first member's array whole restored 397. No other count moved.

## Tests whose expectation changed (all concrete-type assertions, as the brief allowed)

- `theBuilderPreservesConcreteTypesRatherThanBoxing`: `contains("TupleGroup")`, `hasPrefix("Column<TupleGroup<")`.
- `aThreeChildBlockNestsPairsRatherThanFlattening` (name kept for citations; it now asserts one flat `Row<TupleGroup<…>>`).
- `proposalContentKeepsItsTypeAndLegacyContentIsAdopted` (a typecheck guard spelling `HStack<TupleGroup<…>>`).
- Typed spellings: `ProposalControlsTests` (`Picker<Int, TupleGroup<…>>`), `LayoutAuthorityTests` (`Stack<TupleGroup<…>>`), and `.first`/`.second`
  to `.members.0`/`.members.1` in four `ComponentTests`.

## Mutations (each restored, `git status` checked)

- The `buildPartialBlock` chain restored (a clean checkout of `595c474a` with the new tests added): `theSiftToolbarShapeBuildsOnA768KiBThread`
  crashes (`.signal(SIGBUS)`, reported by the exit test as a failure; it is its own test so the crash is attributable) and
  `aBuilderBlocksStackGrowsLinearlyWithItsChildren` fails both expectations (3.0 over 2.5; 802 KiB over 450).
- `TupleGroup` handing each member a fresh cursor: `elevenChildrenOfOneBlockKeepTheirFlatIdsAndTheirState` fails five expectations.

## Verification

See the PR. Docs: `PE-K` amended (`docs/rules/layout.md`, the decisions doc), ruling `PE-AB` (next `PE-AC`), `docs/api-overview.md`, `docs/migration.md`,
the inventory map (`buildPartialBlock` out of `ProposalContentBuilder`'s names; `TupleGroup` is claimed by `ElementGroup.swift`'s `builder` rule).
