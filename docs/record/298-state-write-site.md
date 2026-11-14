# 298 - A `state` dirtying names its writer (`FP-S`)

Branch `feat/trace-state-site` from master `c3b22006`. Class M, no divergence label. Ruling `FP-S` in
`docs/superpowers/2026-11-07-frame-timing-decisions.md`.

**Why.** Alloy's glass trace (record 296 follow-up): with glass each key frame is dirtied by `state/7` rather than
`observation/6`, and a `dirty=state/1` tick follows most keys (181 against 57 without glass). Alloy's own `@State`
writes on those paths are `!=`-guarded `onGeometryChange` height writes, so which `@State` is written was the open question.

**Change.** `dirty=state@TypeName.property/count`. `StateBinder.bind` passes the element type to each wrapper
(`BindableState.bind(to:id:slot:owner:)`); `State.Box` and `FocusState.Box` keep `owner` and `ordinal`; `StateTable.write(_:_:by:)`
carries a `DirtyOwner` (metatype and number) in `StateTable.writer` for the duration of `onWrite`; `Window.markDirty`
forwards it only while tracing; `FrameTiming` keeps the first one per frame. Labels are recorded in the binder's cached
per-type `Shape` on its one `Mirror` pass and looked up only when a line is printed. `TimelineStore`'s wake sets
`TimelineSchedule`, `FocusState.Box.reconcile` sets `FocusReconcile`.

**Tests.** `FrameTimingWhyTests`: `aStateWriteIsTaggedState` (now `state@WhyStateBox.width`),
`anOnGeometryChangeWriteNamesItsOwner`, `anUnlabelledOwnerPrintsItsOrdinalAndInternalWritersTheirName`,
`withNoTraceNothingIsRecorded` (a state write with no sink records no owner).

**Step 2 reading (glass, material, backdrop, containerBackground, onGeometryChange).** `Glass.swift`, `GlassContainer.swift`,
`GlassLook.swift`, `Material.swift`, `Blur.swift` and `MaterialTransparency.swift` hold no `@State`, no `withState`, no
`setNeedsRedraw()`. Candidates that can fire per frame, ranked: (1) `Window.reconcileFocusStates` (`Window.swift:794`) writes
`@FocusState` slots whenever the stored value differs from the focused element, a `state` dirtying now named `FocusReconcile`;
(2) the accessibility publish asking for another frame when the tree changed (`Window.swift:1917`, `explicit`, already
site-named); (3) `reconcileWindowBackdrop` (`ContainerBackground.swift:102,109`), `explicit`, only while the backdrop is not honoured
(SDL, Reduce Transparency) and the fallback grey differs; (4) `TabStrip` (`TabStrip.swift:340`) writes `size` and `width(...)` from
`onGeometryChange` unguarded, but the action runs only when the measured width differs from the last build's (`Lifecycle.closeGeometry`,
`KF-J`), so a width that moves by a subpixel each frame would make it a per-frame writer; (5) `advanceGestures` (`Window.swift:3462`),
`explicit`, only while a gesture timer matures. Nothing proven; the new field is how the next Alloy trace decides.

**Observed while testing.** An `onGeometryChange` action runs inside the frame's lifecycle drain (`Window.drainLifecycle`), so its
`@State` write is counted for the *next* frame's `dirty=` (the headless test saw no follow-up frame of its own, only the
attribution on the next one a `setNeedsRedraw()` asked for). Whether the drain leaves the window dirty on the SDL/Metal path was not measured.
