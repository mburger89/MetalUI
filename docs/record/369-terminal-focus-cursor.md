# 369 - TerminalView click-to-focus and the default cursor style (`TRM-BE`, `TRM-BF`)

Numbered 369: 366, 368 and 362 are other branches' (open PRs #369, #370, #371); expect renumbering.

Branch `feat/terminal-view-focus-cursor`, on `feat/terminal-view-pointer` (#371), not rebased. Two Alloy gaps (2026-11-17).

**1. Click-to-focus.** #371 does not fix it (tests 1-3 red there): the pointer input's hitbox is an ancestor of the focusable's, so `Window.focusOnPress` never picks the focusable. A primary press now writes the view's `@FocusState` through the model's `requestFocus` (`TerminalViewModel+Pointer.swift`), before the press is handled, so plain, reported and ⌘-link presses all focus; a press elsewhere does not, a container's `.focused` binding sees it. Reordering the modifiers (pointer before focusable) was tried and breaks the pointer hitbox. Cost equals a press on a plain `.focusable()`.

**2. `cursorStyle:`.** Additive, defaulted init parameter of `TerminalView` (`TerminalCursorStyle`, default steady block = `TRM-F` power-on), part of `Equatable`. `TerminalEmulator.defaultCursorStyle` (public, additive) holds it; DECSCUSR 0, DECSTR and RIS restore it, DECSCUSR 1-6 and mode 12 override it. **`TRM-AD` item 3 is amended: DECSCUSR 0 is no longer a blinking block** (Alloy's new direction, 2026-11-17); fixture 34 changed. A default-valued view never calls `perform`; a runtime change redraws the cursor row only.

**Tests.** `Tests/MetalUITerminalUITests/TerminalFocusCursorTests.swift` (12). Mutations shown red: no press focus (1, 2, 3, 5), DECSCUSR 0 as a blinking block (8), applying the style on every build (12), style left out of `same` (10, 12), RIS keeping the program's style (9), DECSTR a steady block (9), no `perform` (7-11), the setter overwriting a program's style (10), the default's blink ignoring `cursorBlink` (11).

**Not done.** Human check `TRM15`.
