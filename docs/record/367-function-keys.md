# 367 - Named function keys (`KF-AH`)

Branch `feat/function-keys` from master `a2979c32`. Class M, no divergence. PR 6 of the shortcut design (`KF-AI` is record 363; record 366 is the recorder branch).

**Change:** `KeyEquivalent.f1`...`.f20` (AppKit's `NSF1FunctionKey`...`NSF20FunctionKey`, `U+F704`...`U+F717`); `SDLKeys.named` maps SDL's F13 to F20 keycodes (`0x4000_0068`...`0x4000_006F`) to `U+F710`...`U+F717` (F1 to F12 were mapped already); `Keymap.namedKeys` gains `f13`...`f20`. The display text (`KF-AG`, F1 to F35) and the terminal encoder (`U+F704`...`U+F717`) already agreed with these codes and are unchanged. No Fn modifier.

**Probe:** `P1` arm `-D FKEYS` in `swiftui-shortcut-modifiers.swift`: `KeyEquivalent.f1` is refused by the compiler (recorded in its header).

**Tests:** `FunctionKeysTests` (5): each constant's code point; `.f12` + Shift against SDL-shaped and AppKit-shaped events; the keymap's `f13`...`f20`, `ctrl-shift-F20`, and `f21` refused; every key's display text on each platform; a `CommandMenu` item bound to `.f2` fires on F2 and not F3 or Shift+F2. SDL package: `sdlFunctionKeysMapToAppKitsCodes` (F1, F12, F13, F20, the whole range, F21 unmapped). Mutations (each reddened the named test, then reverted) are listed on the tests.
