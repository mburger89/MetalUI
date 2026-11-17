# 364 - The keys a code view takes, as claims (`KF-AJ`)

Branch `feat/codeview-key-bindings` on `feat/shortcut-claims` (record 363, PR #365). Class M, no divergence. PR 4 of the shortcut design.

**Change:** `CodeView.builtInKeyBindings(platform:)` (`Code/CodeKeyBindings.swift`): `[ClaimedShortcut]` with source `.codeView`, built by running `CodeEditing.command(for:platform:)` over every named key, `a`-`z`, `0`-`9` and ASCII punctuation times the 16 modifier combinations, titled by command in English, cached per platform family. Counts: macOS 63, Linux and Windows 46 (one list). Conditions (Alloy's answer 5): Escape "only with several selections", find next/previous "only with find matches", text-changing commands "editable only".

**Findings:** `CodeCommand` has no multi-caret case but `collapseSelections` (the rest of `CV-BK` is pointer gestures). `closeout-public-api.sh` reads `git ls-files`, so a new file must be `git add`ed before the closeout checks see it.

**Tests:** `CodeKeyBindingsTests` (8 functions, 3 of them over all three platforms). Mutations, each reddening tests: a dropped `case "y"` and a dropped Page Up (counts fall; Ctrl+Y missing), modifiers `0..<8`, a dropped letter `z`, the Mac list built with the `.other` table, Escape unconditional, Copy conditional, `.windows` mapped to the Mac list.
