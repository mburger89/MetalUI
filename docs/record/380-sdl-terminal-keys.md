# 380 - SDL key coverage for the terminal (`TRM-BJ`)

Branch `feat/sdl-terminal-keys` on master `0327155d`. Plan item 4.2. No divergence, no public API beyond `KeyEvent.isKeypad`'s doc line (the field exists since `TRM-BC`).

**Gaps found.** Per key, on X11, Wayland and Win32 alike (the mapping is SDL's keycode and modifiers, identical on the three; only what the platform puts in the keycode differs):
- Insert: arrived with empty characters; now `\u{f727}`.
- Keypad (digits, `/ * - + .`, `=`, `,`, Enter): arrived with empty characters and no flag; now the AppKit character with `isKeypad`, from the scancode (the keycode may be `SDLK_KP_*` or the plain character, and is a navigation key with Num Lock off).
- F13-F20: already mapped (`KF-AH`); pinned by a table.
- ⌃Space, ⌃`: already keys with ⌃ and the encoder's NUL rows; pinned.

**Mechanism.** `MUIEvent.scancode` (appended; set by `translate`, injected by `mui_push_event`). `SDLKeys.keypadCharacter`, `SDLKeys.keyEvent` (the single key-to-`KeyEvent` function), `SDLWindow.producesText(keycode:modifiers:rawOptionKeys:scancode:)`.

**Double delivery.** A keypad character key is text while text input is on (SDL sends the text); keypad Enter and ⌃-modified keys stay keys. So under DECKPAM a keypad digit in a focused `TerminalView` still sends the digit, as on AppKit (`TRM-BC` item 2's accepted limitation). The AppKit side already sets the flag (`keypadKeyCodes`); the fix for both needs a platform hint, so it was left.

**Tests.** SDL package `SDLTerminalKeysTests` (6 tests: Insert and F13-F20, the keypad table in both keycode spellings, Num Lock off, ⌃Space and ⌃`, `producesText`, and a bridge test through SDL's queue). Root `TerminalSDLKeysTests` (3 tests: Insert and F13-F20 with ⇧ and ⌃, the keypad plain and under DECKPAM, NUL) through the focused view. Mutations are listed in each test's header.

**Human check.** `TRM16`: a real Linux (X11 and Wayland) and Windows keyboard.
