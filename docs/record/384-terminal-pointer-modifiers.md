# 384 - Terminal pointer modifiers and drag frames (`TRM-BO`, `TRM-BP`)

Branch `feat/terminal-pointer-modifiers` on master `7b1a2253`. Class M, no divergence, no public API (`PointerAttachment.modifiersChanged` and the `pointerInput(modifiersChanged:)` parameter are `package`).

**(d) The path.** AppKit: `flagsChanged` and becoming key send `.modifiersChanged`. SDL: focus gained sends it, and every key down and up carries the modifier set (a modifier key is a key event). Headless: `TestWindow.pressModifiers`. `Window.currentModifiers` already took all of them; its `didSet` now tells the pointer attachments that asked (only when the last frame had a pointer-style region) and, for a flags report, key or scroll, resolves the style again at `lastMousePosition`. The terminal's link update runs in that hook (it asks `onLink`, sets the link, requests the surface redraw), so the provider (`model.pointer.link == nil ? nil : .link`) answers for the new modifiers in the same call; the platform cursor goes out only on a difference. The view no longer uses `.onModifierKeysChanged`, which cost a build per modifier change.

**Cost (counted).** Off a link 0 frames, 0 builds, 0 requests; over a link 1 frame, 1 surface draw, 0 builds, 0 requests; a window with no terminal 0 frames and no hitbox visited (steady requests 0 in the twin, the code path master has). Existing terminal, pointer, cursor and hover tests unchanged and green.

**(e) Drags.** Autoscroll steps are surface-only (0 builds, 0 requests, one surface draw). A selection drag event is NOT: one build and the steady 2 requests plus a one-row surface draw, because a claimed pointer event dirties the window (`FP-T` spares only an unclaimed move). Pinned, not fixed (a framework rule for claimed events).

**Mutations** (each shown red): no style resolve on a modifier change (`holdingPrimaryOverALinkShowsThePointingHand`); no `modifiersChanged:` in the view (that test and `aModifierChangeDrawsNoFrame`); a redraw on every change (`aModifierChangeDrawsNoFrame`, `aWindowWithoutATerminalPaysNothingForAModifierChange`). Not mutated: the `lastPointerStyleRegionCount` guard (no hitbox to visit without it, so unobservable here), the drag and autoscroll pins (counters only).

**Human check** TRM24.
