# C14b retained subtrees: instruments and readings

`phase-timing.patch` (against the commit that adds `Tests/MetalUITestingTests/BracketFixture.swift`)
adds, in the working tree only:

* `ivPhase` / `ivNow` in `Frame.swift`: per-phase wall seconds inside `Frame.renderOutsideDispatch`
  (record §104's instrument, re-cut for `e85cb07a`): `[0]` build (`requestLayout`), `[1]` strips and
  lowering checks, `[2]` `computeRootLayout`, `[3]` prepaint plus hover and focus, `[4]` paint,
  `[5]` end-of-frame sweeps, `[6]` the whole render, `[7]` here the content memo's `==` comparison;
* `sbSignatureSeconds` in `LayoutTree.swift`: the signature pass (`prepareMemo`);
* `sbCounts` in `ElementGroup.swift`: element `requestLayout`, `prepaint` and `paint` calls
  (the `Element` group defaults);
* `Tests/MetalUITestingTests/BracketPhaseTiming.swift`: `bracketPhaseTiming(arm:)` (three arms of the
  fixture), `bracketSlice1Costs(layoutMemo:contentMemo:)` (the four memo combinations).

**Wall clock is an instrument here; no pin in the suite may read it.** The Mac is shared with other
workflows: read shares and ranges, not single milliseconds.

    git apply docs/probes/retained-subtrees/phase-timing.patch
    swift build --build-system native --build-tests -c release -Xswiftc -enable-testing --scratch-path .build-rel
    SB_REPS=30 swift test --build-system native -c release -Xswiftc -enable-testing --scratch-path .build-rel \
        --skip-build --no-parallel --filter 'bracketPhaseTiming|bracketSlice1Costs'
    git checkout Sources Tests/MetalUITestingTests/BracketPhaseTiming.swift   # (the file is new: delete it)

The counted baseline is `swift test --build-system native --no-parallel --filter
theBracketNodeDragRebuildsTheWholeWindow` (prints the `SB baseline` lines).

@@READINGS@@
